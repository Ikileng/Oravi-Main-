import 'package:oravi_app/domain/events/domain_events.dart';
import 'package:oravi_app/domain/events/oravi_event.dart';
import 'package:oravi_app/domain/models/loop_enums.dart';

/// Seeded realistic clinical dataset representing a Kenyan hospital inpatient ward
/// (e.g. Ward 4B - Male Medical & Surgical Ward).
///
/// Designed to validate PRD Section 7.1, 7.2, and 7.6 requirements:
/// - Distinct beds matching ward round order (Bed 1 to Bed 6).
/// - Nurse-facing patient identifiers are bed number and initials.
/// - Routine, Urgent, and STAT/Critical loops.
/// - Unanswered escalations and recently closed loops.
class SeededWardData {
  static const String wardId = 'WARD-4B';
  static const String wardName = 'Ward 4B (Inpatient Medical/Surgical)';
  static const String testNurseId = 'NURSE-MWANGI';
  static const String testNurseName = 'Nurse Mwangi, RN';
  static const String testDeviceId = 'PHONE-WARD4B-SHARED';

  static List<OraviEvent> getInitialEvents() {
    final now = DateTime.now().toUtc();
    final tMinus4h = now.subtract(const Duration(hours: 4));
    final tMinus2h = now.subtract(const Duration(hours: 2));
    final tMinus30m = now.subtract(const Duration(minutes: 30));

    return [
      // Bed 1: John K. (Admitted with severe pneumonia, oxygen requirements)
      PatientAdmittedEvent(
        eventId: '0192a5b6-0001-7000-8000-000000000001',
        patientId: 'PAT-4B-01',
        authorId: testNurseId,
        deviceId: testDeviceId,
        clientCreatedAt: tMinus4h,
        wardId: wardId,
        bedNumber: 'Bed 1',
        patientInitials: 'J.K.',
        age: 58,
        sex: 'M',
        shortAdmittingNote:
            'Severe CAP; bilateral crackles, SpO2 88% on room air on arrival.',
        keyAlerts: ['Penicillin allergy', 'Fall risk'],
      ),
      LoopOpenedEvent(
        eventId: '0192a5b6-0001-7000-8000-000000000002',
        patientId: 'PAT-4B-01',
        loopId: 'LOOP-4B-01-A',
        authorId: testNurseId,
        deviceId: testDeviceId,
        clientCreatedAt: tMinus4h,
        title: 'Maintain SpO2 > 92% on nasal cannula',
        description:
            'Currently on 2L/min. If dropping below 90, notify medical officer.',
        loopType: LoopType.taskOrPendingResult,
        urgency: LoopUrgency.urgent,
        initialOwnerId: testNurseId,
        initialOwnerRole: 'ward_nurse',
      ),
      MessagePostedEvent(
        eventId: '0192a5b6-0001-7000-8000-000000000003',
        patientId: 'PAT-4B-01',
        loopId: 'LOOP-4B-01-A',
        authorId: testNurseId,
        deviceId: testDeviceId,
        clientCreatedAt: tMinus2h,
        messageId: 'MSG-01-01',
        content:
            'SpO2 stable at 94% on 2L nasal prongs. Patient resting comfortably.',
      ),

      // Bed 2: Peter O. (Post-op Day 1 Laparotomy, STAT repeat hemoglobin needed)
      PatientAdmittedEvent(
        eventId: '0192a5b6-0002-7000-8000-000000000001',
        patientId: 'PAT-4B-02',
        authorId: testNurseId,
        deviceId: testDeviceId,
        clientCreatedAt: tMinus4h,
        wardId: wardId,
        bedNumber: 'Bed 2',
        patientInitials: 'P.O.',
        age: 42,
        sex: 'M',
        shortAdmittingNote:
            'POD 1 exploratory laparotomy for perforated ulcer. Abdominal drain in situ.',
        keyAlerts: ['NPO', 'Strict fluid balance'],
      ),
      LoopOpenedEvent(
        eventId: '0192a5b6-0002-7000-8000-000000000002',
        patientId: 'PAT-4B-02',
        loopId: 'LOOP-4B-02-STAT',
        authorId: 'DOC-OTIENO',
        deviceId: testDeviceId,
        clientCreatedAt: tMinus2h,
        title: 'STAT: Draw urgent Hb and cross-match 2 units PRBC',
        description: 'Drain output 250ml serosanguinous in 2 hrs, BP 90/60.',
        loopType: LoopType.escalation,
        urgency:
            LoopUrgency.critical, // STAT: Triggers confirmation gate on close
        initialOwnerId: testNurseId,
        initialOwnerRole: 'ward_nurse',
      ),
      EscalationRaisedEvent(
        eventId: '0192a5b6-0002-7000-8000-000000000003',
        patientId: 'PAT-4B-02',
        loopId: 'LOOP-4B-02-STAT',
        authorId: testNurseId,
        deviceId: testDeviceId,
        clientCreatedAt: tMinus30m,
        escalationId: 'ESC-4B-02-1',
        targetRole: 'doctor_on_call',
        initialTargetUserId: 'DOC-OTIENO',
        escalationReason:
            'Lab called: Hb is 7.1 g/dL. Requesting urgent blood bank release confirmation.',
        timeoutMinutes: 15,
      ),

      // Bed 3: David M. (Diabetic Ketoacidosis resolution, regular insulin sliding scale)
      PatientAdmittedEvent(
        eventId: '0192a5b6-0003-7000-8000-000000000001',
        patientId: 'PAT-4B-03',
        authorId: testNurseId,
        deviceId: testDeviceId,
        clientCreatedAt: tMinus4h,
        wardId: wardId,
        bedNumber: 'Bed 3',
        patientInitials: 'D.M.',
        age: 29,
        sex: 'M',
        shortAdmittingNote:
            'DKA on resolution. Transitioned to subQ sliding scale insulin.',
        keyAlerts: ['Type 1 Diabetes Mellitus'],
      ),
      LoopOpenedEvent(
        eventId: '0192a5b6-0003-7000-8000-000000000002',
        patientId: 'PAT-4B-03',
        loopId: 'LOOP-4B-03-A',
        authorId: testNurseId,
        deviceId: testDeviceId,
        clientCreatedAt: tMinus4h,
        title: 'Check 2-hourly blood glucose & record in counter-book',
        description:
            'Notify MO if random blood sugar > 14 mmol/L or < 4 mmol/L.',
        loopType: LoopType.taskOrPendingResult,
        urgency: LoopUrgency.routine,
        initialOwnerId: testNurseId,
        initialOwnerRole: 'ward_nurse',
      ),

      // Bed 4: Samuel W. (Cellulitis - Loop recently closed to test audit history)
      PatientAdmittedEvent(
        eventId: '0192a5b6-0004-7000-8000-000000000001',
        patientId: 'PAT-4B-04',
        authorId: testNurseId,
        deviceId: testDeviceId,
        clientCreatedAt: tMinus4h,
        wardId: wardId,
        bedNumber: 'Bed 4',
        patientInitials: 'S.W.',
        age: 63,
        sex: 'M',
        shortAdmittingNote:
            'Right lower limb cellulitis. Day 3 IV Ceftriaxone.',
        keyAlerts: ['Hypertension'],
      ),
      LoopOpenedEvent(
        eventId: '0192a5b6-0004-7000-8000-000000000002',
        patientId: 'PAT-4B-04',
        loopId: 'LOOP-4B-04-A',
        authorId: testNurseId,
        deviceId: testDeviceId,
        clientCreatedAt: tMinus4h,
        title: 'Administer IV Ceftriaxone 2g daily dose',
        description: 'Due at 14:00 after cannula patency check.',
        loopType: LoopType.taskOrPendingResult,
        urgency: LoopUrgency.routine,
        initialOwnerId: testNurseId,
        initialOwnerRole: 'ward_nurse',
      ),
      LoopClosedEvent(
        eventId: '0192a5b6-0004-7000-8000-000000000003',
        patientId: 'PAT-4B-04',
        loopId: 'LOOP-4B-04-A',
        authorId: testNurseId,
        deviceId: testDeviceId,
        clientCreatedAt: tMinus30m,
        reasonCode: ClosureReasonCode.medicationGiven,
        freeTextNote:
            '2g Ceftriaxone in 100ml NS infused over 30 mins. Site clean.',
        resolutionType: ClosureResolutionType.resolved,
      ),

      // Bed 5: Joseph K. (Routine post-reduction fracture - All clear / zero pending)
      PatientAdmittedEvent(
        eventId: '0192a5b6-0005-7000-8000-000000000001',
        patientId: 'PAT-4B-05',
        authorId: testNurseId,
        deviceId: testDeviceId,
        clientCreatedAt: tMinus4h,
        wardId: wardId,
        bedNumber: 'Bed 5',
        patientInitials: 'J.K.',
        age: 71,
        sex: 'M',
        shortAdmittingNote:
            'Closed right Colles fracture post-cast application. Limb elevated.',
        keyAlerts: ['No known allergies'],
      ),
    ];
  }
}
