import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:equatable/equatable.dart';
import '../database/database.dart';

enum SyncState { idle, syncing, offline, error }

class SyncStatus extends Equatable {
  final SyncState state;
  final int pendingCount;
  final DateTime? lastSyncedAt;
  final String? lastError;

  const SyncStatus({
    this.state = SyncState.idle,
    this.pendingCount = 0,
    this.lastSyncedAt,
    this.lastError,
  });

  SyncStatus copyWith({
    SyncState? state,
    int? pendingCount,
    DateTime? lastSyncedAt,
    String? lastError,
  }) {
    return SyncStatus(
      state: state ?? this.state,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: lastError,
    );
  }

  @override
  List<Object?> get props => [state, pendingCount, lastSyncedAt, lastError];
}

class SyncResult {
  final int pushedCount;
  final int pulledCount;
  final bool success;
  final String? error;

  const SyncResult({
    required this.pushedCount,
    required this.pulledCount,
    required this.success,
    this.error,
  });
}

/// Outbox & Inbound Pull Sync Engine implementing:
/// - PRD Section 3: Offline-First Reliability & Outbox Engine
/// - Tech Arch Section 9: Sync Protocol (Mobile <-> Backend)
/// - Tech Arch Section 10: Multi-Device Synchronization & Idempotency
class SyncEngine {
  final OraviLocalDatabase _db;
  final String baseUrl;
  final String wardId;
  final String deviceId;
  final Duration timeout;

  // Optional mock handlers for offline unit testing
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> pushPayload)? mockPushHandler;
  final Future<Map<String, dynamic>> Function(int sinceSeq)? mockPullHandler;
  final Future<void> Function()? onRemoteEventsReceived;

  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();

  SyncStatus _currentStatus = const SyncStatus();
  Timer? _periodicTimer;
  bool _isSyncing = false;

  SyncEngine(
    this._db, {
    this.baseUrl = 'http://10.0.96.95:8000',
    this.wardId = 'WARD-4B',
    this.deviceId = 'PHONE-WARD4B-SHARED',
    this.timeout = const Duration(seconds: 10),
    this.mockPushHandler,
    this.mockPullHandler,
    this.onRemoteEventsReceived,
  }) {
    _statusController.add(_currentStatus);
  }

  Stream<SyncStatus> get statusStream => _statusController.stream;
  SyncStatus get currentStatus => _currentStatus;

  /// Starts the periodic background sync loop (every 10 seconds by default).
  void startPeriodicSync({Duration interval = const Duration(seconds: 10)}) {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) => syncAll());
  }

  void stopPeriodicSync() {
    _periodicTimer?.cancel();
  }

  /// Pushes pending outbox events over HTTP to the ward server (Tech Arch Section 9).
  Future<int> pushOutbox() async {
    final pending = await _db.getPendingOutboxEvents();
    if (pending.isEmpty) return 0;

    final eventIds = pending.map((e) => e.eventId).toList();
    await _db.markOutboxInFlight(eventIds);

    try {
      final payload = {
        'device_id': deviceId,
        'events': pending.map((e) {
          final payloadMap = jsonDecode(e.payloadJson) as Map<String, dynamic>;
          return {
            'event_id': e.eventId,
            'type': e.eventType,
            'patient_id': e.patientId,
            'author_id': e.authorId,
            'device_id': e.deviceId,
            'client_created_at': e.clientCreatedAt.toUtc().toIso8601String(),
            'loop_id': e.loopId,
            'schema_version': e.schemaVersion,
            'payload': payloadMap,
          };
        }).toList(),
      };

      Map<String, dynamic> data;

      if (mockPushHandler != null) {
        data = await mockPushHandler!(payload);
      } else {
        final client = HttpClient()..connectionTimeout = timeout;
        final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
        final uri = Uri.parse('$cleanBase/api/v1/sync/push');

        final request = await client.postUrl(uri).timeout(timeout);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(payload));

        final response = await request.close().timeout(timeout);
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          data = jsonDecode(body) as Map<String, dynamic>;
          client.close();
        } else {
          client.close();
          throw Exception('Server rejected sync push: HTTP ${response.statusCode}');
        }
      }

      final acks = (data['acks'] as List<dynamic>?) ?? [];
      final serverSeqMap = <String, int>{};
      for (final ack in acks) {
        final id = ack['event_id'] as String;
        final seq = ack['server_seq'] as int;
        serverSeqMap[id] = seq;
      }

      await _db.markOutboxAcknowledged(serverSeqMap);
      return acks.length;
    } catch (e) {
      await _db.markOutboxFailed(eventIds, e.toString());
      rethrow;
    }
  }

  /// Pulls new events created by other ward devices since highest serverSeq stored.
  Future<int> pullEvents() async {
    final sinceSeq = await _db.getHighestServerSeq();

    Map<String, dynamic> data;

    if (mockPullHandler != null) {
      data = await mockPullHandler!(sinceSeq);
    } else {
      final client = HttpClient()..connectionTimeout = timeout;
      final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final uri = Uri.parse('$cleanBase/api/v1/sync/pull?ward_id=$wardId&since_seq=$sinceSeq&limit=100');

      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(timeout);
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        data = jsonDecode(body) as Map<String, dynamic>;
        client.close();
      } else {
        client.close();
        throw Exception('Server rejected sync pull: HTTP ${response.statusCode}');
      }
    }

    final rawEvents = (data['events'] as List<dynamic>?) ?? [];
    if (rawEvents.isEmpty) return 0;

    final typedList = rawEvents.map((e) => e as Map<String, dynamic>).toList();
    final inserted = await _db.insertRemoteEvents(typedList);
    return inserted;
  }

  /// Complete bidirectional sync cycle: flushes outbox, then pulls remote events.
  Future<SyncResult> syncAll() async {
    if (_isSyncing) {
      return const SyncResult(
        pushedCount: 0,
        pulledCount: 0,
        success: true,
      );
    }

    _isSyncing = true;
    final initialPending = await _db.getPendingOutboxEvents();
    _updateStatus(_currentStatus.copyWith(
      state: SyncState.syncing,
      pendingCount: initialPending.length,
    ));

    int pushed = 0;
    int pulled = 0;

    try {
      pushed = await pushOutbox();
      pulled = await pullEvents();
      if (pulled > 0) {
        await onRemoteEventsReceived?.call();
      }

      final remainingPending = await _db.getPendingOutboxEvents();
      _updateStatus(_currentStatus.copyWith(
        state: SyncState.idle,
        pendingCount: remainingPending.length,
        lastSyncedAt: DateTime.now(),
        lastError: null,
      ));

      return SyncResult(
        pushedCount: pushed,
        pulledCount: pulled,
        success: true,
      );
    } catch (e) {
      final remainingPending = await _db.getPendingOutboxEvents();
      final isOffline = e.toString().contains('SocketException') ||
          e.toString().contains('TimeoutException') ||
          e.toString().contains('Failed host lookup');

      _updateStatus(_currentStatus.copyWith(
        state: isOffline ? SyncState.offline : SyncState.error,
        pendingCount: remainingPending.length,
        lastError: e.toString(),
      ));

      return SyncResult(
        pushedCount: pushed,
        pulledCount: pulled,
        success: false,
        error: e.toString(),
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Compatibility wrapper for existing callers.
  Future<int> syncOutbox() async {
    final result = await syncAll();
    return result.pushedCount;
  }

  void _updateStatus(SyncStatus newStatus) {
    _currentStatus = newStatus;
    if (!_statusController.isClosed) {
      _statusController.add(_currentStatus);
    }
  }

  void dispose() {
    _periodicTimer?.cancel();
    _statusController.close();
  }
}
