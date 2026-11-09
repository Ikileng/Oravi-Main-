import 'package:uuid/uuid.dart';

import 'database/database.dart';
import '../domain/events/domain_events.dart';
import '../domain/events/oravi_event.dart';
import '../domain/models/loop_enums.dart';
import '../domain/projections/projections.dart';
import '../domain/reducers/oravi_domain_reducer.dart';
import '../domain/search/ward_search_engine.dart';
import '../domain/timeline/ask_oravi_engine.dart';
import '../domain/timeline/patient_timeline_entry.dart';

int _compareEventsByAuthority(OraviEvent a, OraviEvent b) {
  if (a.serverSeq != null && b.serverSeq != null) {
    final bySequence = a.serverSeq!.compareTo(b.serverSeq!);
    if (bySequence != 0) return bySequence;
  } else if (a.serverSeq != null) {
    return -1;
  } else if (b.serverSeq != null) {
    return 1;
  }
  final byClientTime = a.clientCreatedAt.compareTo(b.clientCreatedAt);
  return byClientTime != 0 ? byClientTime : a.eventId.compareTo(b.eventId);
}

/// In-memory offline event-sourced repository implementing the client event-store pattern.
///
/// Tech Arch Section 3 & Section 6:
/// - Every state mutation appends an immutable [OraviEvent].
/// - The phone is a full working offline copy.
/// - Current patient and loop projections are deterministically computed on-the-fly.
class LocalWardRepository {
  static String _newId(String prefix) => '$prefix-${const Uuid().v7()}';

  final List<OraviEvent> _events = [];
  final OraviLocalDatabase? database;

  LocalWardRepository({this.database});

  /// Restores saved events from the local database.
  Future<void> initialize() async {
    if (database != null) {
      final stored = await database!.getAllStoredEvents();
      _events
        ..clear()
        ..addAll(stored);
      _events.sort(_compareEventsByAuthority);
    }
  }

  /// Appends an event to the local immutable event log and queues to SQLite outbox.
  Future<void> appendEvent(OraviEvent event) => appendEvents([event]);

  /// Persists related events atomically before exposing them to the UI.
  Future<void> appendEvents(List<OraviEvent> events) async {
    _validateEvents(events);
    if (database != null) {
      await database!.appendEventsWithOutbox(events);
    }
    _events.addAll(events);
  }

  void _validateEvents(List<OraviEvent> pendingEvents) {
    final affectedLoopIds = pendingEvents
        .map((event) => event.loopId)
        .whereType<String>()
        .toSet();

    for (final loopId in affectedLoopIds) {
      final existingEvents = _events
          .where((event) => event.loopId == loopId)
          .toList();
      final newEvents = pendingEvents
          .where((event) => event.loopId == loopId)
          .toList();
      final allEvents = [...existingEvents, ...newEvents];
      final patientIds = allEvents.map((event) => event.patientId).toSet();
      if (patientIds.length != 1) {
        throw StateError('A medical issue cannot move between patients.');
      }

      final projection = OraviDomainReducer.reduceLoopEvents(allEvents);
      if (projection == null) {
        throw StateError(
          'A medical issue must be raised before it is updated.',
        );
      }
    }
  }

  /// Reloads events from SQLite storage (e.g. after remote pull sync).
  Future<void> reloadFromDatabase() async {
    if (database != null) {
      final stored = await database!.getAllStoredEvents();
      _events.clear();
      _events.addAll(stored);
    }
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
      if (projection != null &&
          projection.wardId == wardId &&
          !projection.isDischarged) {
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

  Future<void> recordLoopRead({
    required String patientId,
    required String loopId,
    required String staffId,
    required String deviceId,
  }) async {
    final loop = getLoopsForPatient(
      patientId,
    ).where((candidate) => candidate.loopId == loopId).firstOrNull;
    if (loop == null) return;
    await appendEvent(
      LoopReadEvent(
        patientId: patientId,
        loopId: loopId,
        authorId: staffId,
        deviceId: deviceId,
      ),
    );
  }

  Future<void> acknowledgeLoopForUser({
    required String patientId,
    required String loopId,
    required String staffId,
    required String deviceId,
  }) async {
    final loop = getLoopsForPatient(
      patientId,
    ).where((candidate) => candidate.loopId == loopId).firstOrNull;
    if (loop == null || loop.acknowledgedByUserIds.containsKey(staffId)) return;
    await appendEvent(
      LoopUserAcknowledgedEvent(
        patientId: patientId,
        loopId: loopId,
        authorId: staffId,
        deviceId: deviceId,
      ),
    );
  }

  /// Appends a new message to a loop thread.
  Future<void> postMessage({
    required String patientId,
    required String loopId,
    required String authorId,
    required String deviceId,
    required String content,
    List<String> mentionedStaffIds = const [],
  }) {
    final event = MessagePostedEvent(
      patientId: patientId,
      loopId: loopId,
      authorId: authorId,
      deviceId: deviceId,
      messageId: _newId('MSG'),
      content: content,
      mentionedStaffIds: mentionedStaffIds,
    );
    return appendEvent(event);
  }

  Future<void> acknowledgeLoop({
    required String patientId,
    required String loopId,
    required String authorId,
    required String deviceId,
  }) {
    return appendEvent(
      LoopAcknowledgedEvent(
        patientId: patientId,
        loopId: loopId,
        authorId: authorId,
        deviceId: deviceId,
      ),
    );
  }

  Future<void> startLoopWork({
    required String patientId,
    required String loopId,
    required String authorId,
    required String deviceId,
  }) {
    final matchingLoops = getLoopsForPatient(
      patientId,
    ).where((loop) => loop.loopId == loopId);
    if (matchingLoops.isNotEmpty &&
        matchingLoops.first.state == LoopState.inProgress) {
      return Future<void>.value();
    }

    return appendEvent(
      LoopWorkStartedEvent(
        patientId: patientId,
        loopId: loopId,
        authorId: authorId,
        deviceId: deviceId,
      ),
    );
  }

  Future<void> changeLoopOwner({
    required String patientId,
    required String loopId,
    required String authorId,
    required String deviceId,
    required String newOwnerId,
    required String newOwnerRole,
    required String transferReason,
  }) {
    if (newOwnerId.trim().isEmpty || transferReason.trim().isEmpty) {
      throw ArgumentError('An owner and reassignment reason are required.');
    }
    return appendEvent(
      LoopOwnerChangedEvent(
        patientId: patientId,
        loopId: loopId,
        authorId: authorId,
        deviceId: deviceId,
        newOwnerId: newOwnerId,
        newOwnerRole: newOwnerRole,
        transferReason: transferReason.trim(),
      ),
    );
  }

  /// Creates a new open loop for a patient.
  Future<void> openLoop({
    required String patientId,
    required String authorId,
    required String deviceId,
    required String title,
    required String description,
    required LoopType loopType,
    required LoopUrgency urgency,
    required String initialOwnerId,
    required String initialOwnerRole,
    String? linkedLoopId,
  }) {
    final event = LoopOpenedEvent(
      patientId: patientId,
      loopId: _newId('LOOP'),
      authorId: authorId,
      deviceId: deviceId,
      title: title,
      description: description,
      loopType: loopType,
      urgency: urgency,
      initialOwnerId: initialOwnerId,
      initialOwnerRole: initialOwnerRole,
      linkedLoopId: linkedLoopId,
    );
    return appendEvent(event);
  }

  /// Closes an open loop with mandatory reason code & free-text validation.
  Future<void> closeLoop({
    required String patientId,
    required String loopId,
    required String authorId,
    required String deviceId,
    required String closureReason,
    required ClosureResolutionType resolutionType,
    ClosureReasonCode? reasonCode,
    String? freeTextNote,
  }) {
    final event = LoopClosedEvent(
      patientId: patientId,
      loopId: loopId,
      authorId: authorId,
      deviceId: deviceId,
      reasonCode: reasonCode,
      closureReason: closureReason.trim(),
      freeTextNote: freeTextNote,
      resolutionType: resolutionType,
    );
    return appendEvent(event);
  }

  /// Confirms closure of a Critical (STAT) loop (PRD FR-51).
  Future<void> confirmCriticalClosure({
    required String patientId,
    required String loopId,
    required String authorId,
    required String deviceId,
    required String confirmedByRole,
    required String boardAssignedDoctorId,
  }) {
    LoopStateProjection? loop;
    for (final candidate in getLoopsForPatient(patientId)) {
      if (candidate.loopId == loopId) {
        loop = candidate;
        break;
      }
    }
    if (loop == null ||
        boardAssignedDoctorId.trim().isEmpty ||
        authorId != boardAssignedDoctorId) {
      throw StateError(
        'Only the board-assigned doctor can confirm this closure. Assign a doctor before confirming.',
      );
    }

    final event = LoopClosureConfirmedEvent(
      patientId: patientId,
      loopId: loopId,
      authorId: authorId,
      deviceId: deviceId,
      confirmedByRole: confirmedByRole,
    );
    return appendEvent(event);
  }

  /// Reopens a closed loop with mandatory reason (PRD FR-50).
  Future<void> reopenLoop({
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
    return appendEvent(event);
  }

  /// Logs telephone contact and mandatory verbal outcome note (PRD FR-54).
  Future<void> logCallOutcome({
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
      callId: _newId('CALL'),
      callerId: callerId,
      callerRole: callerRole,
      recipientId: recipientId,
      recipientRole: recipientRole,
      outcomeNote: outcomeNote,
      durationSeconds: durationSeconds,
    );
    return appendEvent(event);
  }

  // ==========================================
  // Shift Handoff Operations (PRD Section 7.3)
  // ==========================================

  /// Initiates a shift handoff session pairing outgoing and incoming nurse (PRD FR-11).
  Future<HandoffSessionProjection> startHandoffSession({
    required String wardId,
    required String outgoingNurseId,
    required String incomingNurseId,
    required String authorId,
    required String deviceId,
  }) async {
    final sessionId = _newId('HANDOFF');
    final event = HandoffStartedEvent(
      patientId: wardId,
      authorId: authorId,
      deviceId: deviceId,
      handoffSessionId: sessionId,
      wardId: wardId,
      outgoingNurseId: outgoingNurseId,
      incomingNurseId: incomingNurseId,
    );
    await appendEvent(event);
    return getActiveHandoffSession(wardId)!;
  }

  /// Accepts a bed during a handoff session and transfers open loops (PRD FR-12 & FR-14).
  Future<void> acceptBedInHandoff({
    required String handoffSessionId,
    required String wardId,
    required String bedNumber,
    required String patientId,
    required String authorId,
    required String incomingNurseId,
    required String deviceId,
    required bool nothingPendingConfirmed,
  }) {
    final transferredLoopIds = getLoopsForPatient(
      patientId,
    ).where((loop) => loop.isOpen).map((loop) => loop.loopId).toList();
    if (nothingPendingConfirmed && transferredLoopIds.isNotEmpty) {
      throw StateError(
        'Open Medical Issues must be transferred to the incoming nurse.',
      );
    }
    if (!nothingPendingConfirmed && transferredLoopIds.isEmpty) {
      throw StateError(
        'Confirm that nothing is pending when there are no open Medical Issues.',
      );
    }
    final event = HandoffBedAcceptedEvent(
      patientId: patientId,
      authorId: authorId,
      deviceId: deviceId,
      handoffSessionId: handoffSessionId,
      bedNumber: bedNumber,
      nothingPendingConfirmed: nothingPendingConfirmed,
      transferredLoopIds: transferredLoopIds,
    );
    final events = <OraviEvent>[event];

    // Every unfinished issue moves with the patient to the incoming nurse.
    for (final loopId in transferredLoopIds) {
      events.add(
        LoopOwnerChangedEvent(
          patientId: patientId,
          loopId: loopId,
          authorId: authorId,
          deviceId: deviceId,
          newOwnerId: incomingNurseId,
          newOwnerRole: 'ward_nurse',
          transferReason: 'Shift handoff transfer to $incomingNurseId',
          handoffSessionId: handoffSessionId,
        ),
      );
    }
    return appendEvents(events);
  }

  /// Finalizes and cryptographically locks a handoff session (PRD FR-14 & FR-16).
  Future<void> completeHandoffSession({
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
    return appendEvent(event);
  }

  /// Returns the current active (unlocked) handoff session for the ward, if one exists.
  HandoffSessionProjection? getActiveHandoffSession(String wardId) {
    // Find all handoff events
    final handoffEvents = _events.where(
      (e) =>
          e is HandoffStartedEvent ||
          e is HandoffBedAcceptedEvent ||
          e is HandoffCompletedEvent,
    );

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

  // ==========================================
  // Milestone 4: Ask Oravi Timeline & Search
  // ==========================================

  /// Returns the complete chronological verbatim timeline for a patient (PRD Section 8A FR-35).
  List<PatientTimelineEntry> getPatientTimeline(String patientId) {
    final loops = getLoopsForPatient(patientId);
    return AskOraviEngine.buildPatientTimeline(
      events: _events,
      patientId: patientId,
      loops: loops,
    );
  }

  /// Executes an Ask Oravi query for a patient (PRD Section 8A FR-34 to FR-44).
  AskOraviResult askOravi({
    required String patientId,
    required String queryString,
    DateTime? since,
  }) {
    final patientEvents = _events
        .where((e) => e.patientId == patientId)
        .toList();
    final patient = OraviDomainReducer.reducePatientEvents(patientEvents);
    if (patient == null) {
      throw StateError('Patient not found for id $patientId');
    }
    final loops = getLoopsForPatient(patientId);

    return AskOraviEngine.query(
      events: _events,
      patient: patient,
      loops: loops,
      queryString: queryString,
      since: since,
    );
  }

  /// Searches across all patients, loops, and timeline entries in a ward (PRD Section 7.1 / 8A).
  List<WardSearchResult> searchWard({
    required String wardId,
    required String query,
    Set<String>? allowedPatientIds,
  }) {
    final patients = getPatientsForWard(wardId)
        .where(
          (patient) =>
              allowedPatientIds == null ||
              allowedPatientIds.contains(patient.patientId),
        )
        .toList();
    final patientLoopsMap = <String, List<LoopStateProjection>>{};
    final patientTimelineMap = <String, List<PatientTimelineEntry>>{};

    for (final p in patients) {
      final loops = getLoopsForPatient(p.patientId);
      patientLoopsMap[p.patientId] = loops;
      patientTimelineMap[p.patientId] = AskOraviEngine.buildPatientTimeline(
        events: _events,
        patientId: p.patientId,
        loops: loops,
      );
    }

    return WardSearchEngine.searchWard(
      patients: patients,
      patientLoopsMap: patientLoopsMap,
      patientTimelineMap: patientTimelineMap,
      query: query,
    );
  }
}
