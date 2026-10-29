import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../domain/events/domain_events.dart';
import '../../domain/events/oravi_event.dart';

part 'database.g.dart';

/// Immutable event log table stored locally on device.
/// Tech Arch Section 4.1 & Section 9:
/// "Every change is an immutable event. Current state is computed from events."
class LocalEvents extends Table {
  TextColumn get eventId => text()(); // UUIDv7
  TextColumn get patientId => text()();
  TextColumn get loopId => text().nullable()();
  TextColumn get eventType => text()();
  TextColumn get authorId => text()();
  TextColumn get deviceId => text()();
  DateTimeColumn get clientCreatedAt => dateTime()();
  IntColumn get serverSeq => integer().nullable()();
  DateTimeColumn get serverReceivedAt => dateTime().nullable()();
  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();
  TextColumn get payloadJson => text()();

  @override
  Set<Column> get primaryKey => {eventId};
}

/// Outbox table holding un-synchronized local events.
/// Tech Arch Section 3 & Section 9:
/// "The phone is a full working copy... It never waits for the server to record an event.
/// Outbox queues pending events with retries."
class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get eventId => text().unique()();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending, in_flight, synced, failed
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

@DriftDatabase(tables: [LocalEvents, Outbox])
class OraviLocalDatabase extends _$OraviLocalDatabase {
  OraviLocalDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

  // Insert event to local log and enqueue to outbox in single atomic transaction
  Future<void> appendEventWithOutbox(OraviEvent event) {
    return transaction(() async {
      final map = event.toMap();
      final payload = map['payload'] as Map<String, dynamic>? ?? {};

      await into(localEvents).insert(
        LocalEventsCompanion.insert(
          eventId: event.eventId,
          patientId: event.patientId,
          loopId: Value(event.loopId),
          eventType: event.type,
          authorId: event.authorId,
          deviceId: event.deviceId,
          clientCreatedAt: event.clientCreatedAt,
          serverSeq: Value(event.serverSeq),
          serverReceivedAt: Value(event.serverReceivedAt),
          schemaVersion: Value(event.schemaVersion),
          payloadJson: jsonEncode(payload),
        ),
        mode: InsertMode.insertOrReplace,
      );

      // Only enqueue to outbox if event has not yet been acknowledged by server
      if (event.serverSeq == null) {
        await into(outbox).insert(
          OutboxCompanion.insert(
            eventId: event.eventId,
            status: const Value('pending'),
            createdAt: DateTime.now(),
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// Fetches all stored events in insertion/timestamp order to recompute projections.
  Future<List<OraviEvent>> getAllStoredEvents() async {
    final rows = await (select(localEvents)
          ..orderBy([
            (t) => OrderingTerm(expression: t.clientCreatedAt),
            (t) => OrderingTerm(expression: t.serverSeq),
          ]))
        .get();

    return rows.map((row) {
      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      final map = {
        'event_id': row.eventId,
        'type': row.eventType,
        'patient_id': row.patientId,
        'loop_id': row.loopId,
        'author_id': row.authorId,
        'device_id': row.deviceId,
        'client_created_at': row.clientCreatedAt.toIso8601String(),
        'server_seq': row.serverSeq,
        'server_received_at': row.serverReceivedAt?.toIso8601String(),
        'schema_version': row.schemaVersion,
        'payload': payload,
      };
      return deserializeOraviEvent(map);
    }).toList();
  }

  /// Returns pending outbox events ready to be pushed to the backend.
  Future<List<LocalEvent>> getPendingOutboxEvents({int limit = 50}) async {
    final query = select(outbox).join([
      innerJoin(localEvents, localEvents.eventId.equalsExp(outbox.eventId)),
    ])
      ..where(outbox.status.equals('pending') | outbox.status.equals('failed'))
      ..limit(limit);

    final results = await query.get();
    return results.map((row) => row.readTable(localEvents)).toList();
  }

  /// Marks outbox items as in-flight during an active network sync push.
  Future<void> markOutboxInFlight(List<String> eventIds) {
    return (update(outbox)..where((t) => t.eventId.isIn(eventIds))).write(
      OutboxCompanion(
        status: const Value('in_flight'),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );
  }

  /// Marks outbox items as acknowledged by the server with authoritative server sequence.
  Future<void> markOutboxAcknowledged(Map<String, int> eventIdToServerSeq) {
    return transaction(() async {
      final now = DateTime.now();
      for (final entry in eventIdToServerSeq.entries) {
        // 1. Update serverSeq in local event log
        await (update(localEvents)..where((t) => t.eventId.equals(entry.key))).write(
          LocalEventsCompanion(
            serverSeq: Value(entry.value),
            serverReceivedAt: Value(now),
          ),
        );

        // 2. Remove or mark synced in outbox
        await (update(outbox)..where((t) => t.eventId.equals(entry.key))).write(
          const OutboxCompanion(
            status: Value('synced'),
          ),
        );
      }
    });
  }

  /// Marks outbox items as failed with error details and increments retry counter.
  Future<void> markOutboxFailed(List<String> eventIds, String error) {
    return customUpdate(
      'UPDATE outbox SET status = ?, retry_count = retry_count + 1, error_message = ?, last_attempt_at = ? WHERE event_id IN (${eventIds.map((e) => "'$e'").join(',')})',
      variables: [
        Variable.withString('failed'),
        Variable.withString(error),
        Variable.withDateTime(DateTime.now()),
      ],
      updates: {outbox},
    );
  }

  /// Returns the highest server sequence stored in the local SQLite database.
  Future<int> getHighestServerSeq() async {
    final query = selectOnly(localEvents)..addColumns([localEvents.serverSeq.max()]);
    final result = await query.map((row) => row.read(localEvents.serverSeq.max())).getSingleOrNull();
    return result ?? 0;
  }

  /// Inserts or updates events pulled from the server into the local SQLite database.
  /// Remote events are NOT enqueued to the outbox because they already originate from the server.
  Future<int> insertRemoteEvents(List<Map<String, dynamic>> remoteEvents) {
    return transaction(() async {
      int inserted = 0;
      for (final raw in remoteEvents) {
        final eventId = raw['event_id'] as String;
        final type = raw['type'] as String;
        final patientId = raw['patient_id'] as String;
        final authorId = raw['author_id'] as String;
        final deviceId = raw['device_id'] as String;
        final clientCreatedAt = DateTime.parse(raw['client_created_at'] as String);
        final loopId = raw['loop_id'] as String?;
        final serverSeq = raw['server_seq'] as int?;
        final serverReceivedAt = raw['server_received_at'] != null
            ? DateTime.parse(raw['server_received_at'] as String)
            : null;
        final schemaVersion = raw['schema_version'] as int? ?? 1;
        final payload = raw['payload'] as Map<String, dynamic>? ?? {};

        final existing = await (select(localEvents)..where((t) => t.eventId.equals(eventId))).getSingleOrNull();
        if (existing == null) {
          await into(localEvents).insert(
            LocalEventsCompanion(
              eventId: Value(eventId),
              eventType: Value(type),
              patientId: Value(patientId),
              loopId: Value(loopId),
              authorId: Value(authorId),
              deviceId: Value(deviceId),
              clientCreatedAt: Value(clientCreatedAt),
              serverSeq: Value(serverSeq),
              serverReceivedAt: Value(serverReceivedAt),
              schemaVersion: Value(schemaVersion),
              payloadJson: Value(jsonEncode(payload)),
            ),
          );
          inserted++;
        } else if (existing.serverSeq == null && serverSeq != null) {
          // Update serverSeq and serverReceivedAt if previously local-only
          await (update(localEvents)..where((t) => t.eventId.equals(eventId))).write(
            LocalEventsCompanion(
              serverSeq: Value(serverSeq),
              serverReceivedAt: Value(serverReceivedAt),
            ),
          );
        }
      }
      return inserted;
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'oravi_offline.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
