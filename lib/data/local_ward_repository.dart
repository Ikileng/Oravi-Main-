import 'database/database.dart';
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
  final OraviLocalDatabase? database;

  LocalWardRepository({
    this.database,
    bool seedInitialData = true,
  }) {
    if (seedInitialData) {
      _events.addAll(SeededWardData.getInitialEvents());
    }
  }

  /// Initializes repository from SQLite database, seeding initial ward if empty.
  Future<void> initialize({bool seedInitialData = true}) async {
    if (database != null) {
      final stored = await database!.getAllStoredEvents();
      if (stored.isEmpty && seedInitialData) {
        final initial = SeededWardData.getInitialEvents();
        for (final event in initial) {
          await database!.appendEventWithOutbox(event);
          _events.add(event);
        }
      } else {
        _events.clear();
        _events.addAll(stored);
      }
    }
  }

  /// Appends an event to the local immutable event log and queues to SQLite outbox.
  void appendEvent(OraviEvent event) {
    _events.add(event);
    database?.appendEventWithOutbox(event);
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

  // ==========================================
  // Shift Handoff Operations (PRD Section 7.3)
  // ==========================================

  /// Initiates a shift handoff session pairing outgoing and incoming nurse (PRD FR-11).
  HandoffSessionProjection startHandoffSession({
    required String wardId,
    required String outgoingNurseId,
    required String incomingNurseId,
    required String authorId,
    required String deviceId,
  }) {
    final sessionId = 'HANDOFF-${DateTime.now().millisecondsSinceEpoch}';
    final event = HandoffStartedEvent(
      patientId: wardId,
      authorId: authorId,
      deviceId: deviceId,
      handoffSessionId: sessionId,
      wardId: wardId,
      outgoingNurseId: outgoingNurseId,
      incomingNurseId: incomingNurseId,
    );
    appendEvent(event);
    return getActiveHandoffSession(wardId)!;
  }

  /// Accepts a bed during a handoff session and transfers open loops (PRD FR-12 & FR-14).
  void acceptBedInHandoff({
    required String handoffSessionId,
    required String wardId,
    required String bedNumber,
    required String patientId,
    required String authorId,
    required String incomingNurseId,
    required String deviceId,
    required bool nothingPendingConfirmed,
    required List<String> transferredLoopIds,
  }) {
    final event = HandoffBedAcceptedEvent(
      patientId: patientId,
      authorId: authorId,
      deviceId: deviceId,
      handoffSessionId: handoffSessionId,
      bedNumber: bedNumber,
      nothingPendingConfirmed: nothingPendingConfirmed,
      transferredLoopIds: transferredLoopIds,
    );
    appendEvent(event);

    // PRD FR-12 & FR-17: Incoming nurse accepts ownership of all transferred loops
    for (final loopId in transferredLoopIds) {
      appendEvent(
        LoopOwnerChangedEvent(
          patientId: patientId,
          loopId: loopId,
          authorId: authorId,
          deviceId: deviceId,
          newOwnerId: incomingNurseId,
          newOwnerRole: 'ward_nurse',
          transferReason: 'Shift handoff transfer to $incomingNurseId',
        ),
      );
    }
  }

  /// Finalizes and cryptographically locks a handoff session (PRD FR-14 & FR-16).
  void completeHandoffSession({
    required String handoffSessionId,
    required String wardId,
    required String authorId,
    required String deviceId,
    required int totalBedsHandedOver,
    required int totalLoopsTransferred,
  }) {
    final event = HandoffCompletedEvent(
      patientId: wardId,
      authorId: authorId,
      deviceId: deviceId,
      handoffSessionId: handoffSessionId,
      totalBedsHandedOver: totalBedsHandedOver,
      totalLoopsTransferred: totalLoopsTransferred,
    );
    appendEvent(event);
  }

  /// Returns the current active (unlocked) handoff session for the ward, if one exists.
  HandoffSessionProjection? getActiveHandoffSession(String wardId) {
    // Find all handoff events
    final handoffEvents = _events.where((e) =>
        e is HandoffStartedEvent ||
        e is HandoffBedAcceptedEvent ||
        e is HandoffCompletedEvent);

    // Group events by sessionId
    final sessionMap = <String, List<OraviEvent>>{};
    for (final event in handoffEvents) {
      String? sessionId;
      if (event is HandoffStartedEvent) sessionId = event.handoffSessionId;
      if (event is HandoffBedAcceptedEvent) sessionId = event.handoffSessionId;
      if (event is HandoffCompletedEvent) sessionId = event.handoffSessionId;
      if (sessionId != null) {
        sessionMap.putIfAbsent(sessionId, () => []).add(event);
      }
    }

    for (final entry in sessionMap.entries.toList().reversed) {
      final session = OraviDomainReducer.reduceHandoffEvents(entry.value);
      if (session != null && session.wardId == wardId && !session.isLocked) {
        return session;
      }
    }
    return null;
  }
}
