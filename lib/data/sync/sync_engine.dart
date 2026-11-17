import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../api_configuration.dart';
import '../database/database.dart';

enum SyncState { idle, syncing, offline, error }

class SyncStatus extends Equatable {
  final SyncState state;
  final int pendingCount;
  final DateTime? lastSyncedAt;
  final String? lastError;
  final bool? networkAvailable;

  const SyncStatus({
    this.state = SyncState.idle,
    this.pendingCount = 0,
    this.lastSyncedAt,
    this.lastError,
    this.networkAvailable,
  });

  SyncStatus copyWith({
    SyncState? state,
    int? pendingCount,
    DateTime? lastSyncedAt,
    String? lastError,
    bool? networkAvailable,
  }) {
    return SyncStatus(
      state: state ?? this.state,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: lastError,
      networkAvailable: networkAvailable ?? this.networkAvailable,
    );
  }

  @override
  List<Object?> get props => [
    state,
    pendingCount,
    lastSyncedAt,
    lastError,
    networkAvailable,
  ];
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
  static List<String> get defaultCandidateUrls =>
      OraviApiConfiguration.candidateUrls;

  final List<String> candidateUrls;
  String _activeBaseUrl;
  String get baseUrl => _activeBaseUrl;
  final String wardId;
  final String deviceId;
  final String? Function()? getAccessToken;
  final Duration timeout;

  // Optional mock handlers for offline unit testing
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> pushPayload)?
  mockPushHandler;
  final Future<Map<String, dynamic>> Function(int sinceSeq)? mockPullHandler;
  final Future<void> Function()? onRemoteEventsReceived;

  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();

  SyncStatus _currentStatus = const SyncStatus();
  Timer? _periodicTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isSyncing = false;
  bool? _hasNetwork;

  SyncEngine(
    this._db, {
    String? baseUrl,
    List<String>? candidateUrls,
    this.wardId = '',
    this.deviceId = '',
    this.getAccessToken,
    this.timeout = const Duration(seconds: 10),
    this.mockPushHandler,
    this.mockPullHandler,
    this.onRemoteEventsReceived,
  }) : candidateUrls =
           candidateUrls ??
           (baseUrl != null
               ? [baseUrl, ...defaultCandidateUrls]
               : defaultCandidateUrls),
       _activeBaseUrl =
           baseUrl ??
           ((candidateUrls ?? defaultCandidateUrls).isEmpty
               ? ''
               : (candidateUrls ?? defaultCandidateUrls).first) {
    for (final url in this.candidateUrls) {
      OraviApiConfiguration.validateBaseUrl(url);
    }
    _statusController.add(_currentStatus);
  }

  Stream<SyncStatus> get statusStream => _statusController.stream;
  SyncStatus get currentStatus => _currentStatus;

  Future<T> _executeWithFallback<T>(
    Future<T> Function(String base) request,
  ) async {
    final ordered = [
      _activeBaseUrl,
      ...candidateUrls.where((u) => u != _activeBaseUrl),
    ];
    dynamic lastError;
    for (final base in ordered) {
      try {
        final result = await request(base);
        _activeBaseUrl = base;
        return result;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('All candidate servers unreachable');
  }

  /// Starts the periodic background sync loop (every 10 seconds by default).
  void startPeriodicSync({Duration interval = const Duration(seconds: 10)}) {
    _periodicTimer?.cancel();
    unawaited(_restoreLastSyncTime());
    unawaited(_startConnectivityMonitoring());
    _periodicTimer = Timer.periodic(interval, (_) => syncAll());
  }

  Future<void> _restoreLastSyncTime() async {
    try {
      final lastSyncedAt = await _db.getLastSuccessfulSyncAt();
      if (lastSyncedAt == null || _statusController.isClosed) return;
      _updateStatus(_currentStatus.copyWith(lastSyncedAt: lastSyncedAt));
    } catch (_) {
      // The regular sync loop remains available if a checkpoint cannot load.
    }
  }

  Future<void> _startConnectivityMonitoring() async {
    try {
      final connectivity = Connectivity();
      _connectivitySubscription = connectivity.onConnectivityChanged.listen(
        _handleConnectivityChange,
      );
      _handleConnectivityChange(await connectivity.checkConnectivity());
    } catch (_) {
      // Periodic sync remains the fallback if the platform monitor is unavailable.
    }
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final available = results.any(
      (result) => result != ConnectivityResult.none,
    );
    final wasAvailable = _hasNetwork;
    _hasNetwork = available;
    _updateStatus(
      _currentStatus.copyWith(
        networkAvailable: available,
        state: !available && !_isSyncing ? SyncState.offline : null,
      ),
    );
    if (available && wasAvailable != true) unawaited(syncAll());
  }

  void stopPeriodicSync() {
    _periodicTimer?.cancel();
  }

  /// Pushes pending outbox events over HTTP to the ward server (Tech Arch Section 9).
  Future<int> pushOutbox() async {
    final accessToken = getAccessToken?.call();
    if (mockPushHandler == null && accessToken == null) return 0;
    await _db.resetStaleInFlightOutbox();
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
        data = await _executeWithFallback((base) async {
          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 2);
          try {
            final cleanBase = base.endsWith('/')
                ? base.substring(0, base.length - 1)
                : base;
            final uri = Uri.parse('$cleanBase/api/v1/sync/push');

            final request = await client.postUrl(uri).timeout(timeout);
            request.headers.contentType = ContentType.json;
            request.headers.set(
              HttpHeaders.authorizationHeader,
              'Bearer $accessToken',
            );
            request.write(jsonEncode(payload));

            final response = await request.close().timeout(timeout);
            if (response.statusCode == 200) {
              final body = await response.transform(utf8.decoder).join();
              return jsonDecode(body) as Map<String, dynamic>;
            } else {
              throw Exception(
                'Server rejected sync push: HTTP ${response.statusCode}',
              );
            }
          } finally {
            client.close();
          }
        });
      }

      final acks = (data['acks'] as List<dynamic>?) ?? [];
      final rejected = (data['rejected'] as List<dynamic>?) ?? [];
      final serverSeqMap = <String, int>{};
      final pendingIds = eventIds.toSet();
      final rejectedIds = <String>{};
      for (final item in rejected) {
        final id = item['event_id'] as String;
        final reason =
            item['reason'] as String? ?? 'The server rejected this event.';
        if (!pendingIds.contains(id) || !rejectedIds.add(id)) {
          throw const FormatException(
            'Sync response contains an invalid rejection.',
          );
        }
        await _db.markOutboxRejected([id], reason);
      }
      for (final ack in acks) {
        final id = ack['event_id'] as String;
        final seq = ack['server_seq'] as int;
        if (!pendingIds.contains(id) ||
            serverSeqMap.containsKey(id) ||
            seq <= 0) {
          throw const FormatException(
            'Sync response contains an invalid acknowledgement.',
          );
        }
        serverSeqMap[id] = seq;
      }

      await _db.markOutboxAcknowledged(serverSeqMap);
      final notAcknowledged = eventIds
          .where(
            (eventId) =>
                !serverSeqMap.containsKey(eventId) &&
                !rejectedIds.contains(eventId),
          )
          .toList();
      if (notAcknowledged.isNotEmpty) {
        await _db.markOutboxFailed(
          notAcknowledged,
          'Server response omitted acknowledgement; event will be retried.',
        );
      }
      return acks.length;
    } catch (e) {
      await _db.markOutboxFailed(eventIds, e.toString());
      rethrow;
    }
  }

  /// Replays queued, explicitly supported API operations after reconnecting.
  Future<int> pushQueuedApiOperations() async {
    final accessToken = getAccessToken?.call();
    if (accessToken == null || accessToken.isEmpty) return 0;
    await _db.resetStaleApiOperations();
    final pending = await _db.getPendingApiOperations();
    var pushed = 0;
    String? blockedError;
    for (final operation in pending) {
      if (operation.method != 'POST' ||
          operation.path != '/api/v1/allocations/publish') {
        final error =
            'This queued operation is not supported for automatic sync.';
        await _db.markApiOperationFailed(
          operation.operationId,
          error,
          blocked: true,
        );
        blockedError ??= error;
        continue;
      }
      await _db.markApiOperationInFlight(operation.operationId);
      try {
        await _executeWithFallback((base) async {
          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 2);
          try {
            final cleanBase = base.endsWith('/')
                ? base.substring(0, base.length - 1)
                : base;
            final request = await client
                .postUrl(Uri.parse('$cleanBase${operation.path}'))
                .timeout(timeout);
            request.headers.contentType = ContentType.json;
            request.headers.set(
              HttpHeaders.authorizationHeader,
              'Bearer $accessToken',
            );
            request.headers.set('Idempotency-Key', operation.operationId);
            request.write(jsonEncode(operation.payload));
            final response = await request.close().timeout(timeout);
            final body = await response.transform(utf8.decoder).join();
            if (response.statusCode >= 200 && response.statusCode < 300) {
              return body;
            }
            if (response.statusCode == 401) {
              await _db.markApiOperationFailed(
                operation.operationId,
                'The saved Oravi session expired. Sign in while online to resume sync.',
                blocked: false,
              );
              throw const _AuthenticationRequiredException();
            }
            if (response.statusCode >= 400 && response.statusCode < 500) {
              await _db.markApiOperationFailed(
                operation.operationId,
                'The server rejected this saved change (HTTP ${response.statusCode}). $body',
                blocked: true,
              );
              throw _BlockedOperationException(
                'Saved change needs review (HTTP ${response.statusCode}).',
              );
            }
            throw HttpException('Server returned HTTP ${response.statusCode}.');
          } finally {
            client.close();
          }
        });
        await _db.markApiOperationSynced(operation.operationId);
        pushed++;
      } on _BlockedOperationException catch (error) {
        blockedError ??= error.message;
      } on _AuthenticationRequiredException {
        rethrow;
      } catch (error) {
        await _db.markApiOperationFailed(
          operation.operationId,
          error.toString(),
          blocked: false,
        );
        rethrow;
      }
    }
    if (blockedError != null) throw StateError(blockedError);
    return pushed;
  }

  Future<int> _totalPendingCount() async =>
      (await _db.getPendingOutboxEvents()).length +
      await _db.getPendingApiOperationCount();

  /// Pulls new events created by other ward devices since highest serverSeq stored.
  Future<int> pullEvents({String? wardIdOverride}) async {
    final requestedWardId = wardIdOverride ?? wardId;
    if (requestedWardId.isEmpty) return 0;
    final accessToken = getAccessToken?.call();
    if (mockPullHandler == null && accessToken == null) return 0;
    final sinceSeq = await _db.getHighestServerSeq();

    Map<String, dynamic> data;

    if (mockPullHandler != null) {
      data = await mockPullHandler!(sinceSeq);
    } else {
      data = await _executeWithFallback((base) async {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 2);
        try {
          final cleanBase = base.endsWith('/')
              ? base.substring(0, base.length - 1)
              : base;
          final uri = Uri.parse(
            '$cleanBase/api/v1/sync/pull?ward_id=${Uri.encodeQueryComponent(requestedWardId)}&since_seq=$sinceSeq&limit=100',
          );

          final request = await client.getUrl(uri).timeout(timeout);
          request.headers.set(HttpHeaders.acceptHeader, 'application/json');
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $accessToken',
          );

          final response = await request.close().timeout(timeout);
          if (response.statusCode == 200) {
            final body = await response.transform(utf8.decoder).join();
            return jsonDecode(body) as Map<String, dynamic>;
          } else if (response.statusCode == 401) {
            throw const _AuthenticationRequiredException();
          } else {
            throw Exception(
              'Server rejected sync pull: HTTP ${response.statusCode}',
            );
          }
        } finally {
          client.close();
        }
      });
    }

    final rawEvents = (data['events'] as List<dynamic>?) ?? [];
    if (rawEvents.isEmpty) return 0;

    final typedList = rawEvents.map((e) => e as Map<String, dynamic>).toList();
    final inserted = await _db.insertRemoteEvents(typedList);
    return inserted;
  }

  /// Complete bidirectional sync cycle: flushes outbox, then pulls remote events.
  Future<SyncResult> syncAll({String? wardIdOverride}) async {
    if (mockPushHandler == null &&
        mockPullHandler == null &&
        getAccessToken?.call() == null) {
      final pending = await _totalPendingCount();
      _updateStatus(
        _currentStatus.copyWith(
          state: SyncState.offline,
          pendingCount: pending,
          lastError: 'Sign in to synchronize pending changes.',
        ),
      );
      return const SyncResult(
        pushedCount: 0,
        pulledCount: 0,
        success: false,
        error: 'An authenticated session is required to synchronize.',
      );
    }
    if (_isSyncing) {
      return const SyncResult(pushedCount: 0, pulledCount: 0, success: true);
    }

    _isSyncing = true;
    final initialPending = await _totalPendingCount();
    _updateStatus(
      _currentStatus.copyWith(
        state: SyncState.syncing,
        pendingCount: initialPending,
      ),
    );

    int pushed = 0;
    int pulled = 0;

    try {
      pushed = await pushOutbox();
      final pushedOperations = await pushQueuedApiOperations();
      pulled = await pullEvents(wardIdOverride: wardIdOverride);
      if (pulled > 0 || pushedOperations > 0) {
        await onRemoteEventsReceived?.call();
      }

      final remainingPending = await _totalPendingCount();
      final syncedAt = DateTime.now();
      await _db.saveLastSuccessfulSyncAt(syncedAt);
      _updateStatus(
        _currentStatus.copyWith(
          state: SyncState.idle,
          pendingCount: remainingPending,
          lastSyncedAt: syncedAt,
          lastError: null,
        ),
      );

      return SyncResult(
        pushedCount: pushed,
        pulledCount: pulled,
        success: true,
      );
    } catch (e) {
      final remainingPending = await _totalPendingCount();
      final isOffline =
          e.toString().contains('SocketException') ||
          e.toString().contains('TimeoutException') ||
          e.toString().contains('Failed host lookup');

      _updateStatus(
        _currentStatus.copyWith(
          state: isOffline ? SyncState.offline : SyncState.error,
          pendingCount: remainingPending,
          lastError: e.toString(),
        ),
      );

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
    _connectivitySubscription?.cancel();
    _statusController.close();
  }
}

class _BlockedOperationException implements Exception {
  final String message;
  const _BlockedOperationException(this.message);

  @override
  String toString() => message;
}

class _AuthenticationRequiredException implements Exception {
  const _AuthenticationRequiredException();

  @override
  String toString() =>
      'The saved Oravi session expired. Sign in while online to resume sync.';
}
