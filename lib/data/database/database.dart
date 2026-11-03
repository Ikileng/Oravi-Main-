import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
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
  TextColumn get status => text().withDefault(
    const Constant('pending'),
  )(); // pending, in_flight, synced, failed
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Legacy local staff table retained for existing database upgrades.
class LocalStaff extends Table {
  TextColumn get staffId => text()();
  TextColumn get name => text()();
  TextColumn get role =>
      text()(); // ward_nurse, doctor_on_call, charge_nurse, admin
  TextColumn get wardId => text().withDefault(const Constant(''))();
  TextColumn get pin => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get avatarColor => text().withDefault(const Constant('#0284C7'))();
  TextColumn get initials => text()();
  TextColumn get email => text().nullable()();

  @override
  Set<Column> get primaryKey => {staffId};
}

/// Persistent digital whiteboard bed shift allocations.
class LocalWhiteboardAssignments extends Table {
  TextColumn get bedNumber => text()();
  TextColumn get patientName => text()();
  TextColumn get ageGender => text().nullable()();
  TextColumn get diagnosis => text().nullable()();
  TextColumn get assignedNurse => text()();
  TextColumn get bay => text()(); // Bay A, Bay B, Bay C, Side Rooms
  TextColumn get shiftDate => text()(); // YYYY-MM-DD
  TextColumn get shiftType => text()(); // day, night

  @override
  Set<Column> get primaryKey => {bedNumber, shiftDate, shiftType};
}

/// Persistent support roster contacts (In-Charge, Float Nurse, HCAs, Doctors).
class LocalSupportRosters extends Table {
  TextColumn get wardId => text()();
  TextColumn get shiftDate => text()();
  TextColumn get shiftType => text()();
  TextColumn get inChargeName => text()();
  TextColumn get inChargePhone => text().nullable()();
  TextColumn get inChargeRole => text().nullable()();
  TextColumn get floatNurseName => text()();
  TextColumn get floatNursePhone => text().nullable()();
  TextColumn get floatNurseRole => text().nullable()();
  TextColumn get hcasJson => text()(); // serialized List<SupportContact>
  TextColumn get doctorsJson => text()(); // serialized List<SupportContact>

  @override
  Set<Column> get primaryKey => {wardId, shiftDate, shiftType};
}

@DriftDatabase(
  tables: [
    LocalEvents,
    Outbox,
    LocalStaff,
    LocalWhiteboardAssignments,
    LocalSupportRosters,
  ],
)
class OraviLocalDatabase extends _$OraviLocalDatabase {
  OraviLocalDatabase(QueryExecutor? e, {String? encryptionKey})
    : super(e ?? _openConnection(encryptionKey));

  /// Converts a previous plaintext database to encrypted storage before Drift
  /// opens it. A recovery copy is restored on startup if conversion was
  /// interrupted, and removed only after the encrypted file is verified.
  static Future<void> prepareEncryptedDatabase(
    File file,
    String encryptionKey,
  ) async {
    if (!await file.exists() || await file.length() == 0) return;
    final backup = File('${file.path}.encryption-migration-backup');
    if (await backup.exists()) {
      await backup.copy(file.path);
      await backup.delete();
    }
    await file.copy(backup.path);

    sqlite3.Database? rawDb;
    try {
      rawDb = sqlite3.sqlite3.open(file.path);
      _ensureCipherAvailable(rawDb);
      try {
        rawDb.select('SELECT count(*) FROM sqlite_master');
        rawDb.execute("PRAGMA rekey = '$encryptionKey'");
      } on sqlite3.SqliteException {
        rawDb.execute("PRAGMA key = '$encryptionKey'");
        rawDb.select('SELECT count(*) FROM sqlite_master');
      }
      rawDb.close();
      rawDb = null;

      final verifyDb = sqlite3.sqlite3.open(file.path);
      try {
        _ensureCipherAvailable(verifyDb);
        verifyDb.execute("PRAGMA key = '$encryptionKey'");
        verifyDb.select('SELECT count(*) FROM sqlite_master');
      } finally {
        verifyDb.close();
      }
      await backup.delete();
    } catch (_) {
      rawDb?.close();
      if (await backup.exists()) {
        await backup.copy(file.path);
        await backup.delete();
      }
      rethrow;
    }
  }

  static void _ensureCipherAvailable(sqlite3.Database database) {
    if (database.select('PRAGMA cipher').isEmpty) {
      throw StateError('Encrypted SQLite support is unavailable.');
    }
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(localStaff);
        await m.createTable(localWhiteboardAssignments);
        await m.createTable(localSupportRosters);
      }
    },
  );

  // Insert one event to the local log and enqueue it for sync atomically.
  Future<void> appendEventWithOutbox(OraviEvent event) {
    return _insertEvents([event]);
  }

  /// Inserts a group of related events and queues them for sync as one unit.
  Future<void> appendEventsWithOutbox(List<OraviEvent> events) {
    return _insertEvents(events);
  }

  /// Removes only the fixed synthetic fixture records shipped by old debug
  /// builds. Patient and staff records created later are left untouched.
  Future<void> removeKnownDebugFixtures() async {
    const fixturePatientIds = [
      'PAT-4B-01',
      'PAT-4B-02',
      'PAT-4B-03',
      'PAT-4B-04',
      'PAT-4B-05',
    ];
    const fixtureStaffIds = [
      'NUR-401',
      'NUR-402',
      'NUR-403',
      'NUR-404',
      'NUR-405',
      'DOC-401',
      'DOC-499',
      'ADM-001',
    ];
    await transaction(() async {
      final fixtureEvents = await (select(
        localEvents,
      )..where((row) => row.patientId.isIn(fixturePatientIds))).get();
      final eventIds = fixtureEvents.map((row) => row.eventId).toList();
      if (eventIds.isNotEmpty) {
        await (delete(outbox)..where((row) => row.eventId.isIn(eventIds))).go();
        await (delete(
          localEvents,
        )..where((row) => row.eventId.isIn(eventIds))).go();
      }
      await (delete(
        localStaff,
      )..where((row) => row.staffId.isIn(fixtureStaffIds))).go();
      await (delete(localWhiteboardAssignments)..where(
            (row) =>
                row.shiftDate.equals('2026-10-30') &
                row.bedNumber.isIn(const [
                  '1',
                  '2',
                  '3',
                  '4',
                  '5',
                  '6',
                  '7',
                  '8',
                  '9',
                  '10',
                ]) &
                row.assignedNurse.isIn(const [
                  'Nurse A',
                  'Nurse B',
                  'Nurse C',
                  'Nurse D',
                  'Nurse E',
                ]) &
                row.patientName.isIn(const [
                  'J.N',
                  'M.G',
                  'R.A',
                  'M.M',
                  'G.W',
                  'A.K',
                  'A.M',
                  'T.M',
                  'Y.M',
                  '-',
                ]),
          ))
          .go();
      await (delete(localSupportRosters)..where(
            (row) =>
                row.wardId.equals('WARD-4B') &
                row.shiftDate.equals('2026-10-30') &
                row.hcasJson.contains('"team_leader":"Nurse A"'),
          ))
          .go();
    });
  }

  Future<void> _insertEvents(List<OraviEvent> events) {
    if (events.isEmpty) return Future<void>.value();

    return transaction(() async {
      for (final event in events) {
        final map = event.toMap();
        final rawPayload = map['payload'];
        final payload = rawPayload is Map
            ? Map<String, dynamic>.from(rawPayload)
            : <String, dynamic>{};

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
          mode: InsertMode.insertOrIgnore,
        );

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
      }
    });
  }

  /// Reads server-ordered events first, followed by still-local queued events.
  Future<List<OraviEvent>> getAllStoredEvents() async {
    final rows =
        await (select(localEvents)..orderBy([
              (t) => OrderingTerm(expression: t.serverSeq.isNull()),
              (t) => OrderingTerm(expression: t.serverSeq),
              (t) => OrderingTerm(expression: t.clientCreatedAt),
              (t) => OrderingTerm(expression: t.eventId),
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
    final query =
        select(outbox).join([
            innerJoin(
              localEvents,
              localEvents.eventId.equalsExp(outbox.eventId),
            ),
          ])
          ..where(
            outbox.status.equals('pending') | outbox.status.equals('failed'),
          )
          ..orderBy([
            OrderingTerm(expression: outbox.createdAt),
            OrderingTerm(expression: outbox.id),
          ])
          ..limit(limit);

    final results = await query.get();
    return results.map((row) => row.readTable(localEvents)).toList();
  }

  Future<OutboxData?> getOutboxStatus(String eventId) => (select(
    outbox,
  )..where((t) => t.eventId.equals(eventId))).getSingleOrNull();

  /// Marks outbox items as in-flight during an active network sync push.
  Future<void> markOutboxInFlight(List<String> eventIds) {
    return (update(outbox)..where((t) => t.eventId.isIn(eventIds))).write(
      OutboxCompanion(
        status: const Value('in_flight'),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );
  }

  /// Returns interrupted requests to the retry queue after a process crash.
  Future<int> resetStaleInFlightOutbox({
    Duration staleAfter = const Duration(minutes: 2),
  }) {
    final cutoff = DateTime.now().subtract(staleAfter);
    return (update(outbox)..where(
          (t) =>
              t.status.equals('in_flight') &
              t.lastAttemptAt.isSmallerThanValue(cutoff),
        ))
        .write(const OutboxCompanion(status: Value('pending')));
  }

  /// Marks outbox items as acknowledged by the server with authoritative server sequence.
  Future<void> markOutboxAcknowledged(Map<String, int> eventIdToServerSeq) {
    return transaction(() async {
      final now = DateTime.now();
      for (final entry in eventIdToServerSeq.entries) {
        // 1. Update serverSeq in local event log
        await (update(
          localEvents,
        )..where((t) => t.eventId.equals(entry.key))).write(
          LocalEventsCompanion(
            serverSeq: Value(entry.value),
            serverReceivedAt: Value(now),
          ),
        );

        // 2. Remove or mark synced in outbox
        await (update(outbox)..where((t) => t.eventId.equals(entry.key))).write(
          const OutboxCompanion(status: Value('synced')),
        );
      }
    });
  }

  /// Marks outbox items as failed with error details and increments retry counter.
  Future<void> markOutboxFailed(List<String> eventIds, String error) {
    if (eventIds.isEmpty) return Future<void>.value();
    final placeholders = List.filled(eventIds.length, '?').join(', ');
    return customUpdate(
      'UPDATE outbox SET status = ?, retry_count = retry_count + 1, error_message = ?, last_attempt_at = ? WHERE event_id IN ($placeholders)',
      variables: [
        Variable.withString('failed'),
        Variable.withString(error),
        Variable.withDateTime(DateTime.now()),
        ...eventIds.map(Variable.withString),
      ],
      updates: {outbox},
    );
  }

  /// Returns the highest server sequence stored in the local SQLite database.
  /// Ignores any legacy epoch-millisecond mock sequences (>= 1,000,000,000).
  Future<int> getHighestServerSeq() async {
    final query = selectOnly(localEvents)
      ..where(localEvents.serverSeq.isSmallerThanValue(1000000000))
      ..addColumns([localEvents.serverSeq.max()]);
    final result = await query
        .map((row) => row.read(localEvents.serverSeq.max()))
        .getSingleOrNull();
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
        final clientCreatedAt = DateTime.parse(
          raw['client_created_at'] as String,
        );
        final loopId = raw['loop_id'] as String?;
        final serverSeq = raw['server_seq'] as int?;
        final serverReceivedAt = raw['server_received_at'] != null
            ? DateTime.parse(raw['server_received_at'] as String)
            : null;
        final schemaVersion = raw['schema_version'] as int? ?? 1;
        final rawPayload = raw['payload'];
        final payload = rawPayload is Map
            ? Map<String, dynamic>.from(rawPayload)
            : <String, dynamic>{};

        final existing = await (select(
          localEvents,
        )..where((t) => t.eventId.equals(eventId))).getSingleOrNull();
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
        } else if ((existing.serverSeq == null ||
                existing.serverSeq! >= 1000000000) &&
            serverSeq != null) {
          // Update serverSeq and serverReceivedAt if previously local-only or mock timestamp
          await (update(
            localEvents,
          )..where((t) => t.eventId.equals(eventId))).write(
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

  // ==========================================
  // STAFF DIRECTORY PERSISTENCE
  // ==========================================
  Future<List<LocalStaffData>> getAllStaff() {
    return select(localStaff).get();
  }

  Stream<List<LocalStaffData>> watchAllStaff() {
    return select(localStaff).watch();
  }

  Future<void> upsertStaff(LocalStaffCompanion entry) {
    return into(localStaff).insertOnConflictUpdate(entry);
  }

  Future<int> deleteStaff(String staffId) {
    return (delete(localStaff)..where((t) => t.staffId.equals(staffId))).go();
  }

  Future<int> updateStaffPin(String staffId, String newPin) {
    return (update(localStaff)..where((t) => t.staffId.equals(staffId))).write(
      LocalStaffCompanion(pin: Value(newPin)),
    );
  }

  Future<void> toggleStaffActive(String staffId) async {
    final user = await (select(
      localStaff,
    )..where((t) => t.staffId.equals(staffId))).getSingleOrNull();
    if (user != null) {
      await (update(localStaff)..where((t) => t.staffId.equals(staffId))).write(
        LocalStaffCompanion(isActive: Value(!user.isActive)),
      );
    }
  }

  // ==========================================
  // WHITEBOARD ALLOCATIONS PERSISTENCE
  // ==========================================
  Future<List<LocalWhiteboardAssignment>> getWhiteboardAssignments(
    String shiftDate,
    String shiftType,
  ) {
    return (select(localWhiteboardAssignments)..where(
          (t) => t.shiftDate.equals(shiftDate) & t.shiftType.equals(shiftType),
        ))
        .get();
  }

  Stream<List<LocalWhiteboardAssignment>> watchWhiteboardAssignments(
    String shiftDate,
    String shiftType,
  ) {
    return (select(localWhiteboardAssignments)..where(
          (t) => t.shiftDate.equals(shiftDate) & t.shiftType.equals(shiftType),
        ))
        .watch();
  }

  Future<void> saveWhiteboardAssignments(
    List<LocalWhiteboardAssignmentsCompanion> entries,
  ) {
    return transaction(() async {
      for (final entry in entries) {
        await into(localWhiteboardAssignments).insertOnConflictUpdate(entry);
      }
    });
  }

  // ==========================================
  // SUPPORT ROSTER PERSISTENCE
  // ==========================================
  Future<LocalSupportRoster?> getSupportRoster(
    String wardId,
    String shiftDate,
    String shiftType,
  ) {
    return (select(localSupportRosters)..where(
          (t) =>
              t.wardId.equals(wardId) &
              t.shiftDate.equals(shiftDate) &
              t.shiftType.equals(shiftType),
        ))
        .getSingleOrNull();
  }

  Stream<LocalSupportRoster?> watchSupportRoster(
    String wardId,
    String shiftDate,
    String shiftType,
  ) {
    return (select(localSupportRosters)..where(
          (t) =>
              t.wardId.equals(wardId) &
              t.shiftDate.equals(shiftDate) &
              t.shiftType.equals(shiftType),
        ))
        .watchSingleOrNull();
  }

  Future<void> saveSupportRoster(LocalSupportRostersCompanion roster) {
    return into(localSupportRosters).insertOnConflictUpdate(roster);
  }
}

LazyDatabase _openConnection(String? encryptionKey) {
  return LazyDatabase(() async {
    if (encryptionKey == null && !kDebugMode) {
      throw StateError('An encrypted database key is required.');
    }
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'oravi_offline.sqlite'));
    return NativeDatabase.createInBackground(
      file,
      setup: encryptionKey == null
          ? null
          : (rawDb) {
              OraviLocalDatabase._ensureCipherAvailable(rawDb);
              rawDb.execute("PRAGMA key = '$encryptionKey'");
              rawDb.select('SELECT count(*) FROM sqlite_master');
            },
    );
  });
}
