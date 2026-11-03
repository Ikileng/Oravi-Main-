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

      await repository.acknowledgeLoop(
        patientId: issue.patientId,
        loopId: issueId,
        authorId: 'NUR-402',
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
        reasonCode: ClosureReasonCode.resultReceived,
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
          reasonCode: ClosureReasonCode.resultReceived,
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
        ),
        throwsA(isA<StateError>()),
      );
      await repository.confirmCriticalClosure(
        patientId: issue.patientId,
        loopId: issueId,
        authorId: 'NUR-CHARGE',
        deviceId: 'DEVICE-TEST',
        confirmedByRole: 'charge_nurse',
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
      expect(await database.getPendingOutboxEvents(), hasLength(9));
    },
  );

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
