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

    test('Critical (STAT) loop transitions to closedAwaitingConfirmation on close', () {
      // PRD Section 6 & FR-51
      final next = LoopStateMachine.transitionOnClose(
        currentState: LoopState.raised,
        urgency: LoopUrgency.critical,
        reasonCode: ClosureReasonCode.actionTaken,
        freeTextNote: 'Heparin infusion paused and verified with lab',
      );
      expect(next, LoopState.closedAwaitingConfirmation);
    });

    test('Critical loop moves from closedAwaitingConfirmation to closed on confirmation', () {
      final confirmed = LoopStateMachine.transitionOnConfirmClosure(
        currentState: LoopState.closedAwaitingConfirmation,
      );
      expect(confirmed, LoopState.closed);
    });

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
  });

  group('M0: Pure Domain Core - Event Reducer & Conformance Fixture', () {
    test('Folds canonical event stream into exact expected LoopStateProjection', () {
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
      expect(projection.messages.first.content, 'Normal saline running at 100ml/hr. MAP is 68.');
    });

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
  });
}
