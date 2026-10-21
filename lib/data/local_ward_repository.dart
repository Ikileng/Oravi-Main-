import '../domain/events/domain_events.dart';
import '../domain/events/oravi_event.dart';
import '../domain/models/loop_enums.dart';
import '../domain/projections/projections.dart';
import '../domain/reducers/oravi_domain_reducer.dart';
import 'mock/seeded_ward_data.dart';

/// In-memory offline event-sourced repository implementing the client event-store pattern.
///
/// Tech Arch Section 3 & Section 6:
/// - Every state mutation appends an immutable [OraviEvent].
/// - The phone is a full working offline copy.
/// - Current patient and loop projections are deterministically computed on-the-fly.
class LocalWardRepository {
  final List<OraviEvent> _events = [];

  LocalWardRepository({bool seedInitialData = true}) {
    if (seedInitialData) {
      _events.addAll(SeededWardData.getInitialEvents());
    }
  }

  /// Appends an event to the local immutable event log and returns the reduced projections.
  void appendEvent(OraviEvent event) {
    _events.add(event);
  }

  /// Returns an unmodifiable list of all local events in insertion order.
  List<OraviEvent> getAllEvents() => List.unmodifiable(_events);

  /// Computes all current patient projections for a given ward.
  List<PatientStateProjection> getPatientsForWard(String wardId) {
    // Group events by patientId
    final patientEventsMap = <String, List<OraviEvent>>{};
    for (final event in _events) {
      patientEventsMap.putIfAbsent(event.patientId, () => []).add(event);
    }

    final patients = <PatientStateProjection>[];
    for (final entry in patientEventsMap.entries) {
      final projection = OraviDomainReducer.reducePatientEvents(entry.value);
      if (projection != null && projection.wardId == wardId && !projection.isDischarged) {
        patients.add(projection);
      }
    }

    // Sort beds in natural ward round order (Bed 1, Bed 2, Bed 3...)
    patients.sort((a, b) => a.bedNumber.compareTo(b.bedNumber));
    return patients;
  }

  /// Computes all loop projections for a specific patient.
  List<LoopStateProjection> getLoopsForPatient(String patientId) {
    // Group events for this patient by loopId
    final loopEventsMap = <String, List<OraviEvent>>{};
    for (final event in _events) {
      if (event.patientId == patientId && event.loopId != null) {
        loopEventsMap.putIfAbsent(event.loopId!, () => []).add(event);
      }
    }

    final loops = <LoopStateProjection>[];
    for (final entry in loopEventsMap.entries) {
      final projection = OraviDomainReducer.reduceLoopEvents(entry.value);
      if (projection != null) {
        loops.add(projection);
      }
    }

    // Sort loops: open loops first, then by urgency (critical > urgent > routine), then newest
    loops.sort((a, b) {
      if (a.isOpen && !b.isOpen) return -1;
      if (!a.isOpen && b.isOpen) return 1;

      final urgencyCompare = b.urgency.index.compareTo(a.urgency.index);
      if (urgencyCompare != 0) return urgencyCompare;

      return b.createdAt.compareTo(a.createdAt);
    });

    return loops;
  }

  /// Appends a new message to a loop thread.
  void postMessage({
    required String patientId,
    required String loopId,
    required String authorId,
    required String deviceId,
    required String content,
  }) {
    final event = MessagePostedEvent(
      patientId: patientId,
      loopId: loopId,
      authorId: authorId,
      deviceId: deviceId,
      messageId: 'MSG-${DateTime.now().millisecondsSinceEpoch}',
      content: content,
    );
    appendEvent(event);
  }

  /// Creates a new open loop for a patient.
  void openLoop({
    required String patientId,
    required String authorId,
    required String deviceId,
    required String title,
    required String description,
    required LoopType loopType,
    required LoopUrgency urgency,
    required String initialOwnerId,
    required String initialOwnerRole,
  }) {
    final event = LoopOpenedEvent(
      patientId: patientId,
      loopId: 'LOOP-${DateTime.now().millisecondsSinceEpoch}',
      authorId: authorId,
      deviceId: deviceId,
      title: title,
      description: description,
      loopType: loopType,
      urgency: urgency,
      initialOwnerId: initialOwnerId,
      initialOwnerRole: initialOwnerRole,
    );
    appendEvent(event);
  }

  /// Closes an open loop with mandatory reason code & free-text validation.
  void closeLoop({
    required String patientId,
    required String loopId,
    required String authorId,
    required String deviceId,
    required ClosureReasonCode reasonCode,
    String? freeTextNote,
    ClosureResolutionType resolutionType = ClosureResolutionType.resolved,
  }) {
    final event = LoopClosedEvent(
      patientId: patientId,
      loopId: loopId,
      authorId: authorId,
      deviceId: deviceId,
      reasonCode: reasonCode,
      freeTextNote: freeTextNote,
      resolutionType: resolutionType,
    );
    appendEvent(event);
  }

  /// Confirms closure of a Critical (STAT) loop (PRD FR-51).
  void confirmCriticalClosure({
    required String patientId,
    required String loopId,
    required String authorId,
    required String deviceId,
    required String confirmedByRole,
  }) {
    final event = LoopClosureConfirmedEvent(
      patientId: patientId,
      loopId: loopId,
      authorId: authorId,
      deviceId: deviceId,
      confirmedByRole: confirmedByRole,
    );
    appendEvent(event);
  }

  /// Reopens a closed loop with mandatory reason (PRD FR-50).
  void reopenLoop({
    required String patientId,
    required String loopId,
    required String authorId,
    required String deviceId,
    required String reopenReason,
  }) {
    final event = LoopReopenedEvent(
      patientId: patientId,
      loopId: loopId,
      authorId: authorId,
      deviceId: deviceId,
      reopenReason: reopenReason,
    );
    appendEvent(event);
  }

  /// Logs telephone contact and mandatory verbal outcome note (PRD FR-54).
  void logCallOutcome({
    required String patientId,
    required String loopId,
    required String callerId,
    required String callerRole,
    required String recipientId,
    required String recipientRole,
    required String outcomeNote,
    required String deviceId,
    int durationSeconds = 0,
  }) {
    final event = CallLoggedEvent(
      patientId: patientId,
      loopId: loopId,
      authorId: callerId,
      deviceId: deviceId,
      callId: 'CALL-${DateTime.now().millisecondsSinceEpoch}',
      callerId: callerId,
      callerRole: callerRole,
      recipientId: recipientId,
      recipientRole: recipientRole,
      outcomeNote: outcomeNote,
      durationSeconds: durationSeconds,
    );
    appendEvent(event);
  }
}
