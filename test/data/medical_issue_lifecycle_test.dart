import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/data/database/database.dart';
import 'package:oravi_app/data/local_ward_repository.dart';
import 'package:oravi_app/domain/events/domain_events.dart';
import 'package:oravi_app/domain/models/loop_enums.dart';
import 'package:oravi_app/domain/state_machine/loop_state_machine.dart';

void main() {
  late OraviLocalDatabase database;
  late LocalWardRepository repository;

  setUp(() async {
    database = OraviLocalDatabase(NativeDatabase.memory());
    repository = LocalWardRepository(database: database);
    await repository.appendEvent(
      PatientAdmittedEvent(
        eventId: 'PATIENT-EVENT-01',
        patientId: 'PAT-TEST-01',
        authorId: 'NUR-401',
        deviceId: 'DEVICE-TEST',
        wardId: 'WARD-4B',
        bedNumber: 'Bed 1',
        patientInitials: 'J.K.',
        age: 50,
        sex: 'F',
        shortAdmittingNote: 'Test fixture',
      ),
    );
    await repository.initialize();
  });

  tearDown(() async => database.close());

  test(
    'Medical Issue lifecycle is validated, attributed, and survives restart',
    () async {
      await repository.openLoop(
        patientId: 'PAT-TEST-01',
        authorId: 'NUR-401',
        deviceId: 'DEVICE-TEST',
        title: 'Repeat potassium and notify the doctor',
        description: 'Repeat result after replacement.',
        loopType: LoopType.taskOrPendingResult,
        urgency: LoopUrgency.critical,
        initialOwnerId: 'NUR-401',
        initialOwnerRole: 'ward_nurse',
      );

      var issue = repository.getLoopsForPatient('PAT-TEST-01').single;
      final issueId = issue.loopId;
      expect(issue.state, LoopState.raised);
      expect(issue.openedByUserId, 'NUR-401');

      await repository.acknowledgeLoopForUser(
        patientId: issue.patientId,
        loopId: issueId,
        staffId: 'NUR-402',
        deviceId: 'DEVICE-TEST',
      );
      await repository.startLoopWork(
        patientId: issue.patientId,
        loopId: issueId,
        authorId: 'NUR-402',
        deviceId: 'DEVICE-TEST',
      );
      await repository.postMessage(
        patientId: issue.patientId,
        loopId: issueId,
        authorId: 'NUR-402',
        deviceId: 'DEVICE-TEST',
        content: 'Sample sent; awaiting result.',
      );
      await repository.logCallOutcome(
        patientId: issue.patientId,
        loopId: issueId,
        callerId: 'NUR-402',
        callerRole: 'charge_nurse',
        recipientId: 'DOC-401',
        recipientRole: 'doctor_on_call',
        outcomeNote: 'Doctor asked for the repeat result before review.',
        deviceId: 'DEVICE-TEST',
      );
      await repository.closeLoop(
        patientId: issue.patientId,
        loopId: issueId,
        authorId: 'NUR-402',
        deviceId: 'DEVICE-TEST',
        closureReason: 'The result was received and acted upon.',
        resolutionType: ClosureResolutionType.resolved,
      );

      issue = repository.getLoopsForPatient('PAT-TEST-01').single;
      expect(issue.state, LoopState.closedAwaitingConfirmation);
      final eventCountBeforeInvalidClose = repository.getAllEvents().length;
      await expectLater(
        repository.closeLoop(
          patientId: issue.patientId,
          loopId: issueId,
          authorId: 'NUR-402',
          deviceId: 'DEVICE-TEST',
          closureReason: 'The result was received.',
          resolutionType: ClosureResolutionType.resolved,
        ),
        throwsA(isA<InvalidLoopTransitionException>()),
      );
      expect(
        repository.getAllEvents(),
        hasLength(eventCountBeforeInvalidClose),
      );

      expect(
        () => repository.confirmCriticalClosure(
          patientId: issue.patientId,
          loopId: issueId,
          authorId: 'NUR-403',
          deviceId: 'DEVICE-TEST',
          confirmedByRole: 'ward_nurse',
          boardAssignedDoctorId: 'DOC-401',
        ),
        throwsA(isA<StateError>()),
      );
      await repository.confirmCriticalClosure(
        patientId: issue.patientId,
        loopId: issueId,
        authorId: 'DOC-401',
        deviceId: 'DEVICE-TEST',
        confirmedByRole: 'doctor_on_call',
        boardAssignedDoctorId: 'DOC-401',
      );
      await repository.reopenLoop(
        patientId: issue.patientId,
        loopId: issueId,
        authorId: 'NUR-402',
        deviceId: 'DEVICE-TEST',
        reopenReason: 'The repeat result was disputed; verify again.',
      );

      final restored = LocalWardRepository(database: database);
      await restored.initialize();
      final restoredIssue = restored.getLoopsForPatient('PAT-TEST-01').single;

      expect(restoredIssue.state, LoopState.raised);
      expect(restoredIssue.reopenCount, 1);
      expect(restoredIssue.openedByUserId, 'NUR-401');
      expect(restoredIssue.currentOwnerId, 'NUR-401');
      expect(restoredIssue.messages, hasLength(2));
      expect(
        restoredIssue.messages.first.content,
        'Sample sent; awaiting result.',
      );
      expect(restoredIssue.messages.last.isCallLog, isTrue);
      expect(restoredIssue.messages.last.callRecipientId, 'DOC-401');
      expect(
        restoredIssue.closureReasonText,
        'The result was received and acted upon.',
      );
      expect(restoredIssue.resolutionType, ClosureResolutionType.resolved);
      expect(restoredIssue.acknowledgedByUserIds.keys, contains('NUR-402'));
      expect(await database.getPendingOutboxEvents(), hasLength(9));
    },
  );

  test(
    'reads and acknowledgments are tracked independently per clinician',
    () async {
      await repository.openLoop(
        patientId: 'PAT-TEST-01',
        authorId: 'NUR-401',
        deviceId: 'DEVICE-TEST',
        title: 'Monitor oxygen saturation',
        description: '',
        loopType: LoopType.escalation,
        urgency: LoopUrgency.urgent,
        initialOwnerId: 'NUR-401',
        initialOwnerRole: 'ward_nurse',
      );
      final issueId = repository
          .getLoopsForPatient('PAT-TEST-01')
          .single
          .loopId;

      await repository.recordLoopRead(
        patientId: 'PAT-TEST-01',
        loopId: issueId,
        staffId: 'NUR-402',
        deviceId: 'DEVICE-TEST',
      );
      await repository.acknowledgeLoopForUser(
        patientId: 'PAT-TEST-01',
        loopId: issueId,
        staffId: 'NUR-402',
        deviceId: 'DEVICE-TEST',
      );
      await repository.recordLoopRead(
        patientId: 'PAT-TEST-01',
        loopId: issueId,
        staffId: 'DOC-401',
        deviceId: 'DEVICE-TEST',
      );

      final issue = repository.getLoopsForPatient('PAT-TEST-01').single;
      expect(issue.readByUserIds.keys, containsAll(['NUR-402', 'DOC-401']));
      expect(issue.acknowledgedByUserIds.keys, ['NUR-402']);
      expect(issue.state, LoopState.raised);
    },
  );

  test(
    'handoff transfers every open issue to the incoming nurse and preserves closed history',
    () async {
      for (final (title, urgency) in [
        ('Monitor oxygen saturation', LoopUrgency.urgent),
        ('Repeat potassium result', LoopUrgency.routine),
        ('Review completed medication dose', LoopUrgency.routine),
      ]) {
        await repository.openLoop(
          patientId: 'PAT-TEST-01',
          authorId: 'NUR-401',
          deviceId: 'DEVICE-TEST',
          title: title,
          description: 'Handoff test issue.',
          loopType: LoopType.taskOrPendingResult,
          urgency: urgency,
          initialOwnerId: 'NUR-401',
          initialOwnerRole: 'ward_nurse',
        );
      }

      final issues = repository.getLoopsForPatient('PAT-TEST-01');
      final openIssue = issues.firstWhere(
        (issue) => issue.title == 'Monitor oxygen saturation',
      );
      await repository.postMessage(
        patientId: 'PAT-TEST-01',
        loopId: openIssue.loopId,
        authorId: 'NUR-401',
        deviceId: 'DEVICE-TEST',
        content: 'The last observation showed a decline.',
      );
      final closedIssue = issues.firstWhere(
        (issue) => issue.title == 'Review completed medication dose',
      );
      await repository.closeLoop(
        patientId: 'PAT-TEST-01',
        loopId: closedIssue.loopId,
        authorId: 'NUR-401',
        deviceId: 'DEVICE-TEST',
        closureReason: 'The dose was reviewed.',
        resolutionType: ClosureResolutionType.resolved,
      );

      final openIssueIds = repository
          .getLoopsForPatient('PAT-TEST-01')
          .where((issue) => issue.isOpen)
          .map((issue) => issue.loopId)
          .toSet();
      await repository.acceptBedInHandoff(
        handoffSessionId: 'HANDOFF-TEST',
        wardId: 'WARD-4B',
        bedNumber: 'Bed 1',
        patientId: 'PAT-TEST-01',
        authorId: 'NUR-401',
        incomingNurseId: 'NUR-402',
        deviceId: 'DEVICE-TEST',
        nothingPendingConfirmed: false,
      );

      final transferred =
          repository.getAllEvents().singleWhere(
                (event) => event is HandoffBedAcceptedEvent,
              )
              as HandoffBedAcceptedEvent;
      expect(transferred.transferredLoopIds.toSet(), openIssueIds);
      final handedOffIssues = repository.getLoopsForPatient('PAT-TEST-01');
      for (final issue in handedOffIssues) {
        expect(issue.currentOwnerId, issue.isOpen ? 'NUR-402' : 'NUR-401');
      }
      expect(
        handedOffIssues
            .firstWhere((issue) => issue.loopId == openIssue.loopId)
            .messages
            .single
            .content,
        'The last observation showed a decline.',
      );
    },
  );

  test('a recent recurrence can be represented as a linked issue', () async {
    await repository.openLoop(
      patientId: 'PAT-TEST-01',
      authorId: 'NUR-401',
      deviceId: 'DEVICE-TEST',
      title: 'Monitor oxygen saturation',
      description: 'Initial concern.',
      loopType: LoopType.escalation,
      urgency: LoopUrgency.urgent,
      initialOwnerId: 'NUR-401',
      initialOwnerRole: 'ward_nurse',
    );
    final previousIssue = repository.getLoopsForPatient('PAT-TEST-01').single;
    await repository.closeLoop(
      patientId: 'PAT-TEST-01',
      loopId: previousIssue.loopId,
      authorId: 'NUR-401',
      deviceId: 'DEVICE-TEST',
      closureReason: 'Saturation returned to the documented target.',
      resolutionType: ClosureResolutionType.resolved,
    );
    await repository.openLoop(
      patientId: 'PAT-TEST-01',
      authorId: 'NUR-402',
      deviceId: 'DEVICE-TEST',
      title: previousIssue.title,
      description: 'Saturation has dropped again.',
      loopType: LoopType.escalation,
      urgency: LoopUrgency.critical,
      initialOwnerId: 'NUR-402',
      initialOwnerRole: 'ward_nurse',
      linkedLoopId: previousIssue.loopId,
    );

    final recurrence = repository
        .getLoopsForPatient('PAT-TEST-01')
        .singleWhere((issue) => issue.loopId != previousIssue.loopId);
    expect(recurrence.linkedLoopIds, contains(previousIssue.loopId));
  });

  test(
    'new issues cannot be assigned to a different patient by an update',
    () async {
      await repository.openLoop(
        patientId: 'PAT-TEST-01',
        authorId: 'NUR-401',
        deviceId: 'DEVICE-TEST',
        title: 'Review wound dressing',
        description: '',
        loopType: LoopType.taskOrPendingResult,
        urgency: LoopUrgency.routine,
        initialOwnerId: 'NUR-401',
        initialOwnerRole: 'ward_nurse',
      );
      final issueId = repository
          .getLoopsForPatient('PAT-TEST-01')
          .single
          .loopId;

      await expectLater(
        repository.postMessage(
          patientId: 'PAT-TEST-OTHER',
          loopId: issueId,
          authorId: 'NUR-401',
          deviceId: 'DEVICE-TEST',
          content: 'This must not attach to another patient.',
        ),
        throwsA(isA<StateError>()),
      );
      expect(repository.getAllEvents(), hasLength(2));
    },
  );
}
