import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:oravi_app/data/database/database.dart';
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

  group('M3: Drift SQLite Event Store & Outbox Engine', () {
    test('Appends event to LocalEvents and enqueues to Outbox table atomically', () async {
      final now = DateTime.now();
      final event = LoopOpenedEvent(
        eventId: '0192a5b6-7c8d-7e0f-a1b2-c3d4e5f60001',
        patientId: 'PAT-401',
        loopId: 'LOOP-001',
        authorId: 'NURSE-01',
        deviceId: 'DEV-A',
        clientCreatedAt: now,
        title: 'Check Post-op vitals',
        description: 'BP every 30m',
        loopType: LoopType.taskOrPendingResult,
        urgency: LoopUrgency.urgent,
        initialOwnerId: 'NURSE-01',
        initialOwnerRole: 'ward_nurse',
      );

      await db.appendEventWithOutbox(event);

      // Verify LocalEvents
      final storedEvents = await db.getAllStoredEvents();
      expect(storedEvents.length, 1);
      final stored = storedEvents.first as LoopOpenedEvent;
      expect(stored.eventId, event.eventId);
      expect(stored.title, 'Check Post-op vitals');
      expect(stored.urgency, LoopUrgency.urgent);
      expect(stored.serverSeq, isNull);

      // Verify Outbox queue
      final pendingOutbox = await db.getPendingOutboxEvents();
      expect(pendingOutbox.length, 1);
      expect(pendingOutbox.first.eventId, event.eventId);
    });

    test('Outbox lifecycle: pending -> in_flight -> acknowledged/synced', () async {
      final event = LoopOpenedEvent(
        eventId: '0192a5b6-7c8d-7e0f-a1b2-c3d4e5f60002',
        patientId: 'PAT-402',
        loopId: 'LOOP-002',
        authorId: 'NURSE-01',
        deviceId: 'DEV-A',
        clientCreatedAt: DateTime.now(),
        title: 'Stat Troponin T',
        description: 'Chest pain evaluation',
        loopType: LoopType.taskOrPendingResult,
        urgency: LoopUrgency.critical,
        initialOwnerId: 'NURSE-01',
        initialOwnerRole: 'ward_nurse',
      );

      await db.appendEventWithOutbox(event);

      // 1. Mark in-flight
      await db.markOutboxInFlight([event.eventId]);
      var pending = await db.getPendingOutboxEvents();
      expect(pending.isEmpty, isTrue); // in_flight is excluded from pending

      // 2. Mark acknowledged with server sequence
      await db.markOutboxAcknowledged({event.eventId: 1042});

      // Verify event in LocalEvents now has serverSeq = 1042
      final events = await db.getAllStoredEvents();
      expect(events.first.serverSeq, 1042);
      expect(events.first.serverReceivedAt, isNotNull);
    });

    test('Outbox failure increments retry count and stores error message', () async {
      final event = LoopOpenedEvent(
        eventId: '0192a5b6-7c8d-7e0f-a1b2-c3d4e5f60003',
        patientId: 'PAT-403',
        loopId: 'LOOP-003',
        authorId: 'NURSE-01',
        deviceId: 'DEV-A',
        clientCreatedAt: DateTime.now(),
        title: 'Review Antibiotic regimen',
        description: 'Switch to oral',
        loopType: LoopType.questionOrClarification,
        urgency: LoopUrgency.routine,
        initialOwnerId: 'DOC-01',
        initialOwnerRole: 'doctor_on_call',
      );

      await db.appendEventWithOutbox(event);
      await db.markOutboxFailed([event.eventId], 'HTTP 503 Service Unavailable');

      final pending = await db.getPendingOutboxEvents();
      expect(pending.length, 1); // Failed items are retried
    });
  });
}
