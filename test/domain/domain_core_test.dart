import 'dart:io';
import 'package:oravi_app/domain/projections/projections.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/domain/events/domain_events.dart';
import 'package:oravi_app/domain/models/loop_enums.dart';
import 'package:oravi_app/domain/reducers/oravi_domain_reducer.dart';
import 'package:oravi_app/domain/state_machine/loop_state_machine.dart';

void main() {
  group('M0: Pure Domain Core - Loop State Machine', () {
    test('Routine loop closes immediately with valid reason', () {
      final next = LoopStateMachine.transitionOnClose(
        currentState: LoopState.raised,
        urgency: LoopUrgency.routine,
        reasonCode: ClosureReasonCode.resultReceived,
        freeTextNote: null,
      );
      expect(next, LoopState.closed);
    });

    test(
      'Critical (STAT) loop transitions to closedAwaitingConfirmation on close',
      () {
        // PRD Section 6 & FR-51
        final next = LoopStateMachine.transitionOnClose(
          currentState: LoopState.raised,
          urgency: LoopUrgency.critical,
          reasonCode: ClosureReasonCode.actionTaken,
          freeTextNote: 'Heparin infusion paused and verified with lab',
        );
        expect(next, LoopState.closedAwaitingConfirmation);
      },
    );

    test(
      'Critical loop moves from closedAwaitingConfirmation to closed on confirmation',
      () {
        final confirmed = LoopStateMachine.transitionOnConfirmClosure(
          currentState: LoopState.closedAwaitingConfirmation,
        );
        expect(confirmed, LoopState.closed);
      },
    );

    test('Closure requiring free-text note throws when note is omitted', () {
      // PRD FR-46: 'medication given', 'action taken', 'other' require note
      expect(
        () => LoopStateMachine.transitionOnClose(
          currentState: LoopState.raised,
          urgency: LoopUrgency.routine,
          reasonCode: ClosureReasonCode.medicationGiven,
          freeTextNote: '', // Missing note
        ),
        throwsA(isA<InvalidLoopTransitionException>()),
      );
    });

    test('Reopening closed loop requires non-empty reason', () {
      final reopened = LoopStateMachine.transitionOnReopen(
        currentState: LoopState.closed,
        reopenReason: 'Symptoms recurred after 4 hours',
      );
      expect(reopened, LoopState.raised);

      expect(
        () => LoopStateMachine.transitionOnReopen(
          currentState: LoopState.closed,
          reopenReason: '   ',
        ),
        throwsA(isA<InvalidLoopTransitionException>()),
      );
    });

    test('Starting work again on an in-progress loop is idempotent', () {
      expect(
        LoopStateMachine.transitionOnStartWork(
          currentState: LoopState.inProgress,
        ),
        LoopState.inProgress,
      );
    });
  });

  group('M0: Pure Domain Core - Event Reducer & Conformance Fixture', () {
    test(
      'Folds canonical event stream into exact expected LoopStateProjection',
      () {
        final openedAt = DateTime.parse('2026-10-20T08:00:00Z');
        final messageAt = DateTime.parse('2026-10-20T08:15:00Z');
        final closedAt = DateTime.parse('2026-10-20T09:00:00Z');

        final events = [
          LoopOpenedEvent(
            eventId: '0192a5b6-7c8d-7e0f-a1b2-c3d4e5f60001',
            patientId: 'PAT-101',
            loopId: 'LOOP-001',
            authorId: 'NURSE-01',
            deviceId: 'DEV-A',
            clientCreatedAt: openedAt,
            title: 'Titrate IV fluids',
            description: 'Target MAP > 65',
            loopType: LoopType.taskOrPendingResult,
            urgency: LoopUrgency.routine,
            initialOwnerId: 'NURSE-01',
            initialOwnerRole: 'ward_nurse',
          ),
          LoopAcknowledgedEvent(
            eventId: '0192a5b6-7c8d-7e0f-a1b2-c3d4e5f60002',
            patientId: 'PAT-101',
            loopId: 'LOOP-001',
            authorId: 'NURSE-02',
            deviceId: 'DEV-B',
            clientCreatedAt: openedAt.add(const Duration(minutes: 5)),
          ),
          MessagePostedEvent(
            eventId: '0192a5b6-7c8d-7e0f-a1b2-c3d4e5f60003',
            patientId: 'PAT-101',
            loopId: 'LOOP-001',
            authorId: 'NURSE-02',
            deviceId: 'DEV-B',
            clientCreatedAt: messageAt,
            messageId: 'MSG-001',
            content: 'Normal saline running at 100ml/hr. MAP is 68.',
          ),
          LoopClosedEvent(
            eventId: '0192a5b6-7c8d-7e0f-a1b2-c3d4e5f60004',
            patientId: 'PAT-101',
            loopId: 'LOOP-001',
            authorId: 'NURSE-02',
            deviceId: 'DEV-B',
            clientCreatedAt: closedAt,
            reasonCode: ClosureReasonCode.actionTaken,
            freeTextNote: 'Target MAP achieved and stable',
            resolutionType: ClosureResolutionType.resolved,
          ),
        ];

        final projection = OraviDomainReducer.reduceLoopEvents(events);

        expect(projection, isNotNull);
        expect(projection!.loopId, 'LOOP-001');
        expect(projection.patientId, 'PAT-101');
        expect(projection.state, LoopState.closed);
        expect(projection.closureReason, ClosureReasonCode.actionTaken);
        expect(projection.closureNote, 'Target MAP achieved and stable');
        expect(projection.messages.length, 1);
        expect(
          projection.messages.first.content,
          'Normal saline running at 100ml/hr. MAP is 68.',
        );
      },
    );

    test(
      'FR-54: CallLoggedEvent reduces into ThreadMessage with isCallLog and outcome note',
      () {
        final events = [
          LoopOpenedEvent(
            eventId: '0192a5b6-7c8d-7e0f-a1b2-c3d4e5f60010',
            patientId: 'PAT-404',
            loopId: 'LOOP-404',
            authorId: 'NURSE-MWANGI',
            deviceId: 'DEV-A',
            title: 'Check Hemoglobin',
            description: 'Post-op drop',
            loopType: LoopType.escalation,
            urgency: LoopUrgency.urgent,
            initialOwnerId: 'NURSE-MWANGI',
            initialOwnerRole: 'ward_nurse',
          ),
          CallLoggedEvent(
            eventId: '0192a5b6-7c8d-7e0f-a1b2-c3d4e5f60011',
            patientId: 'PAT-404',
            loopId: 'LOOP-404',
            authorId: 'NURSE-MWANGI',
            deviceId: 'DEV-A',
            callId: 'CALL-001',
            callerId: 'Nurse Mwangi, RN',
            callerRole: 'ward_nurse',
            recipientId: 'Dr. Kimani',
            recipientRole: 'gynaecologist',
            outcomeNote: 'Agreed to hold dose until repeat Hb at 16:00',
          ),
        ];

        final projection = OraviDomainReducer.reduceLoopEvents(events);
        expect(projection, isNotNull);
        expect(projection!.messages.length, 1);
        final msg = projection.messages.first;
        expect(msg.isCallLog, isTrue);
        expect(msg.callRecipientId, 'Dr. Kimani');
        expect(
          msg.content,
          contains('Agreed to hold dose until repeat Hb at 16:00'),
        );
      },
    );

    test('Verifies Event Serialization & Deserialization round-trip', () {
      final original = LoopOpenedEvent(
        eventId: '0192a5b6-7c8d-7e0f-a1b2-c3d4e5f60009',
        patientId: 'PAT-202',
        loopId: 'LOOP-009',
        authorId: 'DOC-01',
        deviceId: 'DEV-C',
        title: 'Review Blood Gas',
        description: 'Check pO2 after extubation',
        loopType: LoopType.questionOrClarification,
        urgency: LoopUrgency.critical,
        initialOwnerId: 'DOC-01',
        initialOwnerRole: 'doctor_on_call',
      );

      final map = original.toMap();
      final jsonStr = jsonEncode(map);
      final decodedMap = jsonDecode(jsonStr) as Map<String, dynamic>;

      final restored = deserializeOraviEvent(decodedMap) as LoopOpenedEvent;

      expect(restored.eventId, original.eventId);
      expect(restored.title, original.title);
      expect(restored.urgency, LoopUrgency.critical);
      expect(restored.loopType, LoopType.questionOrClarification);
      expect(restored.initialOwnerRole, 'doctor_on_call');
    });

    test('Recovers a legacy LoopOpened event with missing required fields', () {
      final original = LoopOpenedEvent(
        eventId: '0192a5b6-7c8d-7e0f-a1b2-c3d4e5f60010',
        patientId: 'PAT-203',
        loopId: 'LOOP-010',
        authorId: 'NURSE-01',
        deviceId: 'DEV-C',
        title: 'Review observations',
        description: 'Check the repeat observations',
        loopType: LoopType.taskOrPendingResult,
        urgency: LoopUrgency.routine,
        initialOwnerId: 'NURSE-01',
        initialOwnerRole: 'ward_nurse',
      );
      final map = original.toMap()
        ..['loop_id'] = null
        ..['payload'] = {
          'title': null,
          'description': null,
          'loop_type': null,
          'urgency': null,
          'initial_owner_id': null,
          'initial_owner_role': null,
        };

      final restored = deserializeOraviEvent(map) as LoopOpenedEvent;

      expect(restored.loopId, 'recovered-${original.eventId}');
      expect(restored.title, 'Recovered medical issue');
      expect(restored.description, isEmpty);
      expect(restored.loopType, LoopType.taskOrPendingResult);
      expect(restored.urgency, LoopUrgency.routine);
      expect(restored.initialOwnerId, original.authorId);
      expect(restored.initialOwnerRole, 'unknown');
    });

    test('Recovers a message whose stored medical-issue id is missing', () {
      final message = MessagePostedEvent(
        eventId: '0192a5b6-7c8d-7e0f-a1b2-c3d4e5f60011',
        patientId: 'PAT-204',
        loopId: 'LOOP-011',
        authorId: 'NURSE-01',
        deviceId: 'DEV-C',
        messageId: 'MSG-011',
        content: 'Observations reviewed.',
      );
      final map = message.toMap()..['loop_id'] = null;

      final restored = deserializeOraviEvent(map) as MessagePostedEvent;

      expect(restored.loopId, 'recovered-${message.eventId}');
      expect(restored.content, message.content);
    });

    test('Patient records accept initials only and mask legacy full names', () {
      final newEvent = PatientAdmittedEvent(
        patientId: 'PAT-NEW',
        authorId: 'NURSE-01',
        deviceId: 'DEVICE-01',
        wardId: 'WARD-4B',
        bedNumber: 'Bed 1',
        patientInitials: 'j.k',
        age: 42,
        sex: 'F',
        shortAdmittingNote: 'Observation',
      );
      final newPayload = newEvent.toMap()['payload'] as Map<String, dynamic>;
      expect(newEvent.patientInitials, 'J.K.');
      expect(newPayload.containsKey('admission_number'), isFalse);

      expect(
        () => PatientAdmittedEvent(
          patientId: 'PAT-INVALID',
          authorId: 'NURSE-01',
          deviceId: 'DEVICE-01',
          wardId: 'WARD-4B',
          bedNumber: 'Bed 2',
          patientInitials: 'Jane Kamau',
          age: 42,
          sex: 'F',
          shortAdmittingNote: 'Observation',
        ),
        throwsArgumentError,
      );

      final legacyEvent = PatientAdmittedEvent.fromMap({
        'event_id': 'legacy-patient-event',
        'type': PatientAdmittedEvent.eventType,
        'patient_id': 'PAT-LEGACY',
        'author_id': 'NURSE-01',
        'device_id': 'DEVICE-01',
        'client_created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        'payload': {
          'ward_id': 'WARD-4B',
          'bed_number': 'Bed 3',
          'admission_number': 'ADM-PRIVATE-01',
          'name_or_initials': 'Kamau, Jane',
          'age': 42,
          'sex': 'F',
          'short_admitting_note': 'Observation',
        },
      });
      final legacyProjection = OraviDomainReducer.reducePatientEvents([
        legacyEvent,
      ])!;

      expect(legacyProjection.patientInitials, 'K.J.');
      expect(legacyProjection.toString(), isNot(contains('Kamau')));
      expect(legacyProjection.toString(), isNot(contains('ADM-PRIVATE-01')));
    });

    test(
      'Cross-platform JSON Conformance Fixture validation (Tech Arch Section 4.3)',
      () {
        final file = File('test/fixtures/conformance_fixture.json');
        expect(file.existsSync(), isTrue);

        final jsonStr = file.readAsStringSync();
        final fixture = jsonDecode(jsonStr) as Map<String, dynamic>;
        final rawEvents = fixture['events'] as List<dynamic>;

        final events = rawEvents
            .map((e) => deserializeOraviEvent(e as Map<String, dynamic>))
            .toList();

        final projection = OraviDomainReducer.reduceLoopEvents(events);
        expect(projection, isNotNull);

        final expected =
            fixture['expected_final_state'] as Map<String, dynamic>;
        expect(projection!.loopId, expected['loop_id']);
        expect(projection.state.name, expected['state']);
        expect(projection.messages.length, expected['total_messages']);
        expect(projection.closureReason?.name, expected['closure_reason']);
        expect(projection.isOpen, expected['is_open']);
      },
    );
  });

  group('M2: Shift Handoff & Kardex SBAR', () {
    final testPatient = PatientStateProjection(
      patientId: 'PAT-401',
      wardId: 'WARD-4B',
      bedNumber: '1',
      patientInitials: 'K.J.',
      age: 58,
      sex: 'M',
      shortAdmittingNote: 'Decompensated Heart Failure',
      keyAlerts: const ['Penicillin Allergy', 'Fall Risk'],
      admittedAt: DateTime.parse('2026-10-18T10:00:00Z'),
      updatedAt: DateTime.parse('2026-10-18T10:00:00Z'),
    );

    test(
      'SBAR auto-compilation handles patients with Critical and Routine loops',
      () {
        final loops = [
          LoopStateProjection(
            loopId: 'LOOP-01',
            patientId: 'PAT-401',
            title: 'Repeat Serum Potassium STAT',
            description: 'Last K+ was 2.8 mmol/L',
            loopType: LoopType.taskOrPendingResult,
            urgency: LoopUrgency.critical,
            state: LoopState.raised,
            currentOwnerId: 'NURSE-01',
            currentOwnerRole: 'ward_nurse',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          LoopStateProjection(
            loopId: 'LOOP-02',
            patientId: 'PAT-401',
            title: 'Daily morning weight chart',
            description: 'Assess fluid retention',
            loopType: LoopType.taskOrPendingResult,
            urgency: LoopUrgency.routine,
            state: LoopState.raised,
            currentOwnerId: 'NURSE-01',
            currentOwnerRole: 'ward_nurse',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];

        final sbar = SbarSummary.fromPatientAndLoops(
          patient: testPatient,
          loops: loops,
        );

        // Situation
        expect(sbar.situation, contains('1 — K.J., 58y M'));
        expect(sbar.situation, isNot(contains('IP-2026-0891')));
        expect(sbar.situation, contains('Decompensated Heart Failure'));

        // Background
        expect(sbar.background, contains('Penicillin Allergy, Fall Risk'));

        // Assessment
        expect(sbar.assessment, contains('1 CRITICAL/STAT'));
        expect(sbar.assessment, contains('1 Routine'));
        expect(sbar.assessment, contains('Repeat Serum Potassium STAT'));

        // Recommendation
        expect(sbar.recommendation, contains('ACTION STAT'));
      },
    );

    test('SBAR auto-compilation handles ALL CLEAR patients', () {
      final sbar = SbarSummary.fromPatientAndLoops(
        patient: testPatient,
        loops: const [],
      );

      expect(
        sbar.assessment,
        contains('ALL CLEAR: No open clinical loops pending.'),
      );
      expect(
        sbar.recommendation,
        contains('Maintain routine baseline monitoring'),
      );
    });

    test(
      'Reducer folds Handoff lifecycle into locked HandoffSessionProjection',
      () {
        final startedAt = DateTime.parse('2026-10-21T07:00:00Z');
        final bed1At = DateTime.parse('2026-10-21T07:05:00Z');
        final bed2At = DateTime.parse('2026-10-21T07:10:00Z');
        final completedAt = DateTime.parse('2026-10-21T07:15:00Z');

        final events = [
          HandoffStartedEvent(
            patientId: 'WARD-4B',
            authorId: 'NURSE-MWANGI',
            deviceId: 'DEV-A',
            clientCreatedAt: startedAt,
            handoffSessionId: 'SESSION-001',
            wardId: 'WARD-4B',
            outgoingNurseId: 'Nurse Mwangi, RN',
            incomingNurseId: 'Nurse Achieng, RN',
          ),
          HandoffBedAcceptedEvent(
            patientId: 'PAT-401',
            authorId: 'NURSE-ACHIENG',
            deviceId: 'DEV-B',
            clientCreatedAt: bed1At,
            handoffSessionId: 'SESSION-001',
            bedNumber: '1',
            nothingPendingConfirmed: false,
            transferredLoopIds: ['LOOP-01', 'LOOP-02'],
          ),
          HandoffBedAcceptedEvent(
            patientId: 'PAT-402',
            authorId: 'NURSE-ACHIENG',
            deviceId: 'DEV-B',
            clientCreatedAt: bed2At,
            handoffSessionId: 'SESSION-001',
            bedNumber: '2',
            nothingPendingConfirmed: true,
            transferredLoopIds: const [],
          ),
          HandoffCompletedEvent(
            patientId: 'WARD-4B',
            authorId: 'NURSE-ACHIENG',
            deviceId: 'DEV-B',
            clientCreatedAt: completedAt,
            handoffSessionId: 'SESSION-001',
            totalBedsHandedOver: 2,
            totalLoopsTransferred: 2,
          ),
        ];

        final session = OraviDomainReducer.reduceHandoffEvents(events);

        expect(session, isNotNull);
        expect(session!.handoffSessionId, 'SESSION-001');
        expect(session.outgoingNurseId, 'Nurse Mwangi, RN');
        expect(session.incomingNurseId, 'Nurse Achieng, RN');
        expect(session.bedReviews.length, 2);
        expect(session.bedReviews['1']!.transferredLoopIds.length, 2);
        expect(session.bedReviews['2']!.nothingPendingConfirmed, isTrue);
        expect(session.isLocked, isTrue);
        expect(session.totalBedsHandedOver, 2);
        expect(session.totalLoopsTransferred, 2);
      },
    );
  });
}
