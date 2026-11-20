import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:oravi_app/data/database/database.dart';
import 'package:oravi_app/data/sync/sync_engine.dart';
import 'package:oravi_app/domain/events/domain_events.dart';
import 'package:oravi_app/domain/models/loop_enums.dart';

void main() {
  late OraviLocalDatabase db;

  setUp(() {
    db = OraviLocalDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('M6: Multi-Device Sync Pipeline (Tech Arch Section 9 & 10)', () {
    test(
      'recovers date rejection once and reports other rejections honestly',
      () async {
        for (final id in ['date-rejected', 'wrong-author']) {
          await db.appendEventWithOutbox(
            LoopOpenedEvent(
              eventId: id,
              patientId: 'PAT-N',
              loopId: id,
              authorId: 'NURSE-X',
              deviceId: 'PHONE-X',
              title: 'Review',
              description: '',
              loopType: LoopType.taskOrPendingResult,
              urgency: LoopUrgency.urgent,
              initialOwnerId: 'NURSE-X',
              initialOwnerRole: 'ward_nurse',
            ),
          );
        }
        await db.markOutboxRejected([
          'date-rejected',
        ], 'The patient was not assigned to this account for the event date.');
        await db.markOutboxRejected([
          'wrong-author',
        ], 'Event author does not match the signed-in account.');
        final engine = SyncEngine(
          db,
          wardId: 'WARD',
          mockPushHandler: (payload) async {
            expect((payload['events'] as List).map((e) => e['event_id']), [
              'date-rejected',
            ]);
            return {
              'acks': [
                {'event_id': 'date-rejected', 'server_seq': 1},
              ],
            };
          },
          mockPullHandler: (_) async => {'events': []},
        );
        try {
          final result = await engine.syncAll();
          expect(result.success, isFalse);
          expect(result.pushedCount, 1);
          expect(engine.currentStatus.lastError, contains('not been shared'));
          expect(engine.currentStatus.lastSyncedAt, isNull);
          expect((await db.getOutboxStatus('date-rejected'))!.status, 'synced');
          expect(
            (await db.getOutboxStatus('wrong-author'))!.status,
            'rejected',
          );
          await db.markOutboxRejected(
            ['date-rejected'],
            'The patient was not assigned to this account for the event date.',
          );
          await db.recoverAssignmentDateRejections();
          expect(
            (await db.getOutboxStatus('date-rejected'))!.status,
            'rejected',
          );
        } finally {
          engine.dispose();
        }
      },
    );

    test(
      'failed upload still downloads and refreshes the other clinician issue',
      () async {
        await db.appendEventWithOutbox(
          LoopOpenedEvent(
            eventId: 'local',
            patientId: 'PAT-N',
            loopId: 'local',
            authorId: 'NURSE-X',
            deviceId: 'PHONE-X',
            title: 'Review',
            description: '',
            loopType: LoopType.taskOrPendingResult,
            urgency: LoopUrgency.urgent,
            initialOwnerId: 'NURSE-X',
            initialOwnerRole: 'ward_nurse',
          ),
        );
        var refreshed = false;
        final engine = SyncEngine(
          db,
          wardId: 'WARD',
          mockPushHandler: (_) async =>
              throw StateError('Server rejected sync push: HTTP 409'),
          mockPullHandler: (_) async => {
            'events': [
              {
                'event_id': 'doctor-issue',
                'patient_id': 'PAT-N',
                'loop_id': 'doctor-issue',
                'type': 'LoopOpened',
                'author_id': 'DOC-B',
                'device_id': 'PHONE-B',
                'client_created_at': '2026-11-18T22:30:00Z',
                'server_seq': 1,
                'payload': {
                  'title': 'Doctor review',
                  'description': '',
                  'loop_type': 'task_or_pending_result',
                  'urgency': 'urgent',
                  'initial_owner_id': 'DOC-B',
                  'initial_owner_role': 'doctor_on_call',
                },
              },
            ],
          },
          onRemoteEventsReceived: () async {
            refreshed = true;
          },
        );
        try {
          final result = await engine.syncAll();
          expect(result.success, isFalse);
          expect(result.pulledCount, 1);
          expect(refreshed, isTrue);
          expect(
            (await db.getAllStoredEvents()).map((e) => e.eventId),
            contains('doctor-issue'),
          );
          expect(engine.currentStatus.lastSyncedAt, isNull);
        } finally {
          engine.dispose();
        }
      },
    );

    test(
      'doctor recovers older nurse history despite a newer local event, across pages',
      () async {
        Map<String, dynamic> event(int seq) => {
          'event_id': 'nurse-event-$seq',
          'patient_id': 'PAT-N',
          'type': 'LoopOpened',
          'author_id': 'NURSE-X',
          'device_id': 'PHONE-X',
          'client_created_at': DateTime(2026, 11, 19).toIso8601String(),
          'loop_id': 'ISSUE-$seq',
          'server_seq': seq,
          'payload': {
            'title': 'Issue $seq',
            'description': 'Review needed',
            'loop_type': 'escalation',
            'urgency': 'urgent',
            'initial_owner_id': 'DOC-B',
            'initial_owner_role': 'doctor_on_call',
          },
        };
        await db.insertRemoteEvents([event(200)]);
        final cursors = <int>[];
        final engine = SyncEngine(
          db,
          wardId: 'WARD',
          mockPullHandler: (cursor) async {
            cursors.add(cursor);
            final history = List.generate(101, (i) => event(i + 1));
            return {
              'events': history
                  .where((e) => (e['server_seq'] as int) > cursor)
                  .take(100)
                  .toList(),
              'latest_seq': 200,
            };
          },
        );
        try {
          expect(await engine.pullEvents(), 101);
          expect(cursors, [0, 100]);
          expect((await db.getAllStoredEvents()).length, 102);
          expect(await engine.pullEvents(), 0);
          expect(await db.getPendingOutboxEvents(), isEmpty);
        } finally {
          engine.dispose();
        }
      },
    );

    test(
      '1. pushOutbox flushes pending events and updates local serverSeq with server ack',
      () async {
        final now = DateTime.now();
        final event = LoopOpenedEvent(
          eventId: '0192a5b6-0001-7000-8000-000000000001',
          patientId: 'PAT-4B-01',
          loopId: 'LOOP-01',
          authorId: 'NURSE-MWANGI',
          deviceId: 'PHONE-A',
          clientCreatedAt: now,
          title: 'Check SpO2 on nasal cannula',
          description: 'Target > 92%',
          loopType: LoopType.taskOrPendingResult,
          urgency: LoopUrgency.urgent,
          initialOwnerId: 'NURSE-MWANGI',
          initialOwnerRole: 'ward_nurse',
        );

        await db.appendEventWithOutbox(event);

        // Verify 1 pending in outbox
        final initialPending = await db.getPendingOutboxEvents();
        expect(initialPending.length, 1);

        // Setup SyncEngine with mock push handler
        Map<String, dynamic>? receivedPayload;
        final engine = SyncEngine(
          db,
          mockPushHandler: (payload) async {
            receivedPayload = payload;
            return {
              'status': 'success',
              'acknowledged_count': 1,
              'acks': [
                {
                  'event_id': event.eventId,
                  'server_seq': 105,
                  'server_received_at': now.toIso8601String(),
                  'hash': 'a' * 64,
                },
              ],
            };
          },
        );

        final pushedCount = await engine.pushOutbox();
        expect(pushedCount, 1);
        expect(receivedPayload, isNotNull);
        expect((receivedPayload!['events'] as List).length, 1);

        // Verify Outbox is now empty (synced)
        final remainingPending = await db.getPendingOutboxEvents();
        expect(remainingPending.isEmpty, isTrue);

        // Verify LocalEvents row has authoritative serverSeq = 105
        final storedEvents = await db.getAllStoredEvents();
        expect(storedEvents.first.serverSeq, 105);

        engine.dispose();
      },
    );

    test(
      '2. pullEvents inserts remote events from other ward devices into local SQLite',
      () async {
        final now = DateTime.now();

        // Setup SyncEngine with mock pull handler returning remote event from Doctor Otieno
        final engine = SyncEngine(
          db,
          wardId: 'WARD-4B',
          mockPullHandler: (sinceSeq) async {
            expect(sinceSeq, 0); // Initially no server events stored
            return {
              'ward_id': 'WARD-4B',
              'latest_seq': 201,
              'events': [
                {
                  'event_id': '0192a5b6-0002-7000-8000-000000000001',
                  'patient_id': 'PAT-4B-02',
                  'type': 'LoopOpened',
                  'author_id': 'DOC-OTIENO',
                  'device_id': 'PHONE-DOCTOR',
                  'client_created_at': now.toIso8601String(),
                  'loop_id': 'LOOP-STAT-02',
                  'server_seq': 201,
                  'server_received_at': now.toIso8601String(),
                  'schema_version': 1,
                  'payload': {
                    'title':
                        'STAT: Draw urgent Hb and cross-match 2 units PRBC',
                    'description': 'Drain output 250ml',
                    'loop_type': 'escalation',
                    'urgency': 'critical',
                    'initial_owner_id': 'NURSE-MWANGI',
                    'initial_owner_role': 'ward_nurse',
                  },
                },
              ],
            };
          },
        );

        final pulledCount = await engine.pullEvents();
        expect(pulledCount, 1);

        // Verify local database now contains Doctor Otieno's remote event
        final storedEvents = await db.getAllStoredEvents();
        expect(storedEvents.length, 1);
        final stored = storedEvents.first as LoopOpenedEvent;
        expect(stored.patientId, 'PAT-4B-02');
        expect(stored.authorId, 'DOC-OTIENO');
        expect(stored.urgency, LoopUrgency.critical);
        expect(stored.serverSeq, 201);

        // Verify that pulled remote events do NOT get added to local Outbox
        final outboxEvents = await db.getPendingOutboxEvents();
        expect(outboxEvents.isEmpty, isTrue);

        engine.dispose();
      },
    );

    test(
      '3. syncAll executes bidirectional push then pull and updates status to idle',
      () async {
        final now = DateTime.now();
        final localEvent = LoopOpenedEvent(
          eventId: 'evt-local-01',
          patientId: 'PAT-4B-01',
          loopId: 'LOOP-01',
          authorId: 'NURSE-MWANGI',
          deviceId: 'PHONE-A',
          clientCreatedAt: now,
          title: 'Check vitals',
          description: 'Every 4h',
          loopType: LoopType.taskOrPendingResult,
          urgency: LoopUrgency.routine,
          initialOwnerId: 'NURSE-MWANGI',
          initialOwnerRole: 'ward_nurse',
        );
        await db.appendEventWithOutbox(localEvent);

        final statuses = <SyncStatus>[];

        final engine = SyncEngine(
          db,
          mockPushHandler: (payload) async => {
            'status': 'success',
            'acknowledged_count': 1,
            'acks': [
              {
                'event_id': 'evt-local-01',
                'server_seq': 301,
                'server_received_at': now.toIso8601String(),
                'hash': 'b' * 64,
              },
            ],
          },
          mockPullHandler: (sinceSeq) async => {
            'ward_id': 'WARD-4B',
            'latest_seq': 301,
            'events': [],
          },
        );

        final sub = engine.statusStream.listen(statuses.add);

        final result = await engine.syncAll();
        expect(result.success, isTrue);
        expect(result.pushedCount, 1);
        expect(result.pulledCount, 0);

        expect(engine.currentStatus.state, SyncState.idle);
        expect(engine.currentStatus.pendingCount, 0);
        expect(engine.currentStatus.lastSyncedAt, isNotNull);

        await sub.cancel();
        engine.dispose();
      },
    );

    test(
      '4. Offline resilience: Socket/Timeout exception safely flags status offline without throwing',
      () async {
        final event = LoopOpenedEvent(
          eventId: 'evt-offline-01',
          patientId: 'PAT-4B-01',
          loopId: 'LOOP-01',
          authorId: 'NURSE-MWANGI',
          deviceId: 'PHONE-A',
          clientCreatedAt: DateTime.now(),
          title: 'Elevate limb',
          description: 'Post cast',
          loopType: LoopType.taskOrPendingResult,
          urgency: LoopUrgency.routine,
          initialOwnerId: 'NURSE-MWANGI',
          initialOwnerRole: 'ward_nurse',
        );
        await db.appendEventWithOutbox(event);

        final engine = SyncEngine(
          db,
          mockPushHandler: (_) async => throw Exception(
            'SocketException: Connection refused (OS Error: Connection refused, errno = 111)',
          ),
        );

        final result = await engine.syncAll();
        expect(result.success, isFalse);
        expect(engine.currentStatus.state, SyncState.offline);
        expect(engine.currentStatus.pendingCount, 1);

        // Event is still safely preserved in outbox
        final pending = await db.getPendingOutboxEvents();
        expect(pending.length, 1);

        engine.dispose();
      },
    );

    test(
      'unacknowledged and interrupted events return to the ordered retry queue',
      () async {
        final event = LoopOpenedEvent(
          eventId: 'evt-retry-01',
          patientId: 'PAT-4B-03',
          loopId: 'LOOP-RETRY-01',
          authorId: 'NURSE-01',
          deviceId: 'PHONE-A',
          title: 'Repeat observation',
          description: '',
          loopType: LoopType.taskOrPendingResult,
          urgency: LoopUrgency.routine,
          initialOwnerId: 'NURSE-01',
          initialOwnerRole: 'ward_nurse',
        );
        await db.appendEventWithOutbox(event);

        final engine = SyncEngine(
          db,
          mockPushHandler: (_) async => {'acks': <dynamic>[]},
        );
        expect(await engine.pushOutbox(), 0);
        var retry = await db.getPendingOutboxEvents();
        expect(retry.single.eventId, event.eventId);
        expect((await db.getOutboxStatus(event.eventId))?.status, 'failed');

        await db.markOutboxInFlight([event.eventId]);
        await db.resetStaleInFlightOutbox(
          staleAfter: const Duration(seconds: -1),
        );
        retry = await db.getPendingOutboxEvents();
        expect(retry.single.eventId, event.eventId);
        expect((await db.getOutboxStatus(event.eventId))?.status, 'pending');
        engine.dispose();
      },
    );

    test(
      'network sync does not send queued clinical events without a session token',
      () async {
        final event = LoopOpenedEvent(
          eventId: 'evt-no-session-01',
          patientId: 'PAT-4B-04',
          loopId: 'LOOP-NO-SESSION-01',
          authorId: 'NURSE-01',
          deviceId: 'PHONE-A',
          title: 'Queued offline',
          description: '',
          loopType: LoopType.taskOrPendingResult,
          urgency: LoopUrgency.routine,
          initialOwnerId: 'NURSE-01',
          initialOwnerRole: 'ward_nurse',
        );
        await db.appendEventWithOutbox(event);
        final engine = SyncEngine(db);

        final result = await engine.syncAll();
        expect(result.success, isFalse);
        expect(engine.currentStatus.state, SyncState.offline);
        expect(
          (await db.getPendingOutboxEvents()).single.eventId,
          event.eventId,
        );
        expect((await db.getOutboxStatus(event.eventId))?.status, 'pending');
        engine.dispose();
      },
    );
  });
}
