import 'auth_providers.dart';
import '../../domain/search/ward_search_engine.dart';
import '../../domain/timeline/patient_timeline_entry.dart';
import '../../data/sync/sync_engine.dart';
import '../../data/ask_oravi_model_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local_ward_repository.dart';
import '../../data/database/database_provider.dart';
import '../../domain/models/staff_profile.dart';
import '../../domain/models/loop_enums.dart';
import '../../domain/projections/projections.dart';
import 'whiteboard_providers.dart';
import 'ward_context_providers.dart';

/// Outbox Sync Engine provider.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final db = ref.watch(localDatabaseProvider);
  final repo = ref.watch(localWardRepositoryProvider);
  final engine = SyncEngine(
    db,
    wardId: ref.watch(selectedWardProvider).wardId,
    deviceId: ref.read(localDeviceIdProvider),
    getAccessToken: () => ref.read(authAccessTokenProvider),
    onRemoteEventsReceived: () async {
      await repo.reloadFromDatabase();
      ref.read(wardControllerProvider.notifier).refresh();
      ref.invalidate(wardBoardProvider);
      ref.invalidate(carriedForwardIssuesProvider('owned'));
    },
  );
  engine.startPeriodicSync(interval: const Duration(seconds: 10));
  ref.onDispose(() => engine.dispose());
  return engine;
});

/// Reactive stream provider for sync state and pending outbox count.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  return ref.watch(syncEngineProvider).statusStream;
});

/// Offline-first event-sourced repository backed by SQLite.
final localWardRepositoryProvider = Provider<LocalWardRepository>((ref) {
  final db = ref.watch(localDatabaseProvider);
  return LocalWardRepository(database: db);
});

/// Notifier that manages ward state versioning and triggers UI updates on mutations.
class WardController extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() {
    state++;
  }

  StaffProfile get _currentStaff =>
      ref.read(authenticatedStaffProvider) ??
      (throw StateError('A signed-in staff member is required.'));

  String get _currentDeviceId => ref.read(localDeviceIdProvider);

  Future<void> postMessage({
    required String patientId,
    required String loopId,
    required String content,
    List<String> mentionedStaffIds = const [],
  }) async {
    await ref
        .read(localWardRepositoryProvider)
        .postMessage(
          patientId: patientId,
          loopId: loopId,
          authorId: _currentStaff.staffId,
          deviceId: _currentDeviceId,
          content: content,
          mentionedStaffIds: mentionedStaffIds,
        );
    refresh();
  }

  Future<void> openLoop({
    required String patientId,
    required String title,
    required String description,
    required LoopType loopType,
    required LoopUrgency urgency,
    String? linkedLoopId,
  }) async {
    await ref
        .read(localWardRepositoryProvider)
        .openLoop(
          patientId: patientId,
          authorId: _currentStaff.staffId,
          deviceId: _currentDeviceId,
          title: title,
          description: description,
          loopType: loopType,
          urgency: urgency,
          initialOwnerId: _currentStaff.staffId,
          initialOwnerRole: _currentStaff.role,
          linkedLoopId: linkedLoopId,
        );
    refresh();
  }

  Future<void> acknowledgeLoop({
    required String patientId,
    required String loopId,
  }) async {
    final staff = _currentStaff;
    await ref
        .read(localWardRepositoryProvider)
        .acknowledgeLoopForUser(
          patientId: patientId,
          loopId: loopId,
          staffId: staff.staffId,
          deviceId: _currentDeviceId,
        );
    refresh();
  }

  Future<void> recordLoopRead({
    required String patientId,
    required String loopId,
  }) async {
    final staff = _currentStaff;
    await ref
        .read(localWardRepositoryProvider)
        .recordLoopRead(
          patientId: patientId,
          loopId: loopId,
          staffId: staff.staffId,
          deviceId: _currentDeviceId,
        );
    refresh();
  }

  Future<void> startLoopWork({
    required String patientId,
    required String loopId,
  }) async {
    final staff = _currentStaff;
    await ref
        .read(localWardRepositoryProvider)
        .startLoopWork(
          patientId: patientId,
          loopId: loopId,
          authorId: staff.staffId,
          deviceId: _currentDeviceId,
        );
    refresh();
  }

  Future<void> changeLoopOwner({
    required String patientId,
    required String loopId,
    required String newOwnerId,
    required String newOwnerRole,
  }) async {
    final staff = _currentStaff;
    await ref
        .read(localWardRepositoryProvider)
        .changeLoopOwner(
          patientId: patientId,
          loopId: loopId,
          authorId: staff.staffId,
          deviceId: _currentDeviceId,
          newOwnerId: newOwnerId,
          newOwnerRole: newOwnerRole,
          transferReason: 'Assigned by ${staff.staffId}',
        );
    refresh();
  }

  Future<void> closeLoop({
    required String patientId,
    required String loopId,
    required String closureReason,
    required ClosureResolutionType resolutionType,
    String? freeTextNote,
  }) async {
    await ref
        .read(localWardRepositoryProvider)
        .closeLoop(
          patientId: patientId,
          loopId: loopId,
          authorId: _currentStaff.staffId,
          deviceId: _currentDeviceId,
          closureReason: closureReason,
          resolutionType: resolutionType,
          freeTextNote: freeTextNote,
        );
    refresh();
  }

  Future<void> confirmCriticalClosure({
    required String patientId,
    required String loopId,
  }) async {
    final staff = _currentStaff;
    final repo = ref.read(localWardRepositoryProvider);
    LoopStateProjection? loop;
    for (final candidate in repo.getLoopsForPatient(patientId)) {
      if (candidate.loopId == loopId) {
        loop = candidate;
        break;
      }
    }
    final boardAssignedDoctorId = ref
        .read(whiteboardAssignmentsProvider)
        .where((bed) => bed.patientId == patientId)
        .map((bed) => bed.admittingDoctor)
        .where((doctorId) => doctorId.isNotEmpty && doctorId != '-')
        .firstOrNull;
    if (loop == null ||
        boardAssignedDoctorId == null ||
        staff.staffId != boardAssignedDoctorId) {
      throw StateError(
        'Only the board-assigned doctor can confirm this closure. Assign a doctor before confirming.',
      );
    }

    await repo.confirmCriticalClosure(
      patientId: patientId,
      loopId: loopId,
      authorId: staff.staffId,
      deviceId: _currentDeviceId,
      confirmedByRole: staff.role,
      boardAssignedDoctorId: boardAssignedDoctorId,
    );
    refresh();
  }

  Future<void> reopenLoop({
    required String patientId,
    required String loopId,
    required String reopenReason,
  }) async {
    await ref
        .read(localWardRepositoryProvider)
        .reopenLoop(
          patientId: patientId,
          loopId: loopId,
          authorId: _currentStaff.staffId,
          deviceId: _currentDeviceId,
          reopenReason: reopenReason,
        );
    refresh();
  }

  Future<void> logCallOutcome({
    required String patientId,
    required String loopId,
    required String recipientId,
    required String recipientRole,
    required String outcomeNote,
    int durationSeconds = 0,
  }) async {
    await ref
        .read(localWardRepositoryProvider)
        .logCallOutcome(
          patientId: patientId,
          loopId: loopId,
          callerId: _currentStaff.staffId,
          callerRole: _currentStaff.role,
          recipientId: recipientId,
          recipientRole: recipientRole,
          outcomeNote: outcomeNote,
          deviceId: _currentDeviceId,
          durationSeconds: durationSeconds,
        );
    refresh();
  }

  Future<void> startHandoffSession({
    required String outgoingNurseId,
    required String incomingNurseId,
  }) async {
    final wardId = ref.read(selectedWardProvider).wardId;
    if (wardId.isEmpty) throw StateError('Select an assigned ward first.');
    await ref
        .read(localWardRepositoryProvider)
        .startHandoffSession(
          wardId: wardId,
          outgoingNurseId: outgoingNurseId,
          incomingNurseId: incomingNurseId,
          authorId: _currentStaff.staffId,
          deviceId: _currentDeviceId,
        );
    refresh();
  }

  Future<void> acceptBedInHandoff({
    required String handoffSessionId,
    required String bedNumber,
    required String patientId,
    required String incomingNurseId,
    required bool nothingPendingConfirmed,
  }) async {
    final wardId = ref.read(selectedWardProvider).wardId;
    if (wardId.isEmpty) throw StateError('Select an assigned ward first.');
    await ref
        .read(localWardRepositoryProvider)
        .acceptBedInHandoff(
          handoffSessionId: handoffSessionId,
          wardId: wardId,
          bedNumber: bedNumber,
          patientId: patientId,
          authorId: _currentStaff.staffId,
          incomingNurseId: incomingNurseId,
          deviceId: _currentDeviceId,
          nothingPendingConfirmed: nothingPendingConfirmed,
        );
    refresh();
  }

  Future<void> completeHandoffSession({
    required String handoffSessionId,
    required String authorId,
    required int totalBedsHandedOver,
    required int totalLoopsTransferred,
  }) async {
    final wardId = ref.read(selectedWardProvider).wardId;
    if (wardId.isEmpty) throw StateError('Select an assigned ward first.');
    await ref
        .read(localWardRepositoryProvider)
        .completeHandoffSession(
          handoffSessionId: handoffSessionId,
          wardId: wardId,
          authorId: _currentStaff.staffId,
          deviceId: _currentDeviceId,
          totalBedsHandedOver: totalBedsHandedOver,
          totalLoopsTransferred: totalLoopsTransferred,
        );
    refresh();
  }
}

final wardControllerProvider = NotifierProvider<WardController, int>(
  WardController.new,
);

/// Reactive provider yielding active patient projections for the ward.
final wardPatientsProvider = Provider<List<PatientStateProjection>>((ref) {
  ref.watch(wardControllerProvider);
  final wardId = ref.watch(selectedWardProvider).wardId;
  if (wardId.isEmpty) return const [];
  final boardBeds = ref.watch(whiteboardAssignmentsProvider);
  final now = DateTime.now();
  return boardBeds
      .where(
        (bed) =>
            bed.patientId != null &&
            bed.patientId!.isNotEmpty &&
            bed.patientInitials.trim().isNotEmpty,
      )
      .map(
        (bed) => PatientStateProjection(
          patientId: bed.patientId!,
          wardId: wardId,
          bedNumber: bed.bedNumber,
          patientInitials: bed.patientInitials,
          age: 0,
          sex: '',
          shortAdmittingNote: '',
          admittedAt: now,
          updatedAt: now,
        ),
      )
      .toList();
});

final currentUserPatientIdsProvider = Provider<Set<String>>((ref) {
  final staff = ref.watch(authenticatedStaffProvider);
  if (staff == null) return const {};
  if (staff.role == 'charge_nurse' &&
      ref.watch(wardContextNeedsConfirmationProvider)) {
    return const {};
  }
  final isDayShift = ref.watch(selectedShiftTypeProvider) == 'day';
  return ref
      .watch(whiteboardAssignmentsProvider)
      .where((bed) {
        if (staff.role == 'charge_nurse') return true;
        if (staff.role == 'doctor_on_call') {
          return bed.admittingDoctor == staff.staffId;
        }
        return staff.role == 'ward_nurse' &&
            (isDayShift ? bed.dayShiftNurseId : bed.nightShiftNurseId) ==
                staff.staffId;
      })
      .map((bed) => bed.patientId)
      .whereType<String>()
      .toSet();
});

final currentNurseShiftPatientsProvider =
    Provider<List<PatientStateProjection>>((ref) {
      final staff = ref.watch(authenticatedStaffProvider);
      if (staff == null) return const [];
      final isDayShift = ref.watch(selectedShiftTypeProvider) == 'day';
      final assignedPatientIds = ref
          .watch(whiteboardAssignmentsProvider)
          .where(
            (bed) =>
                (isDayShift ? bed.dayShiftNurseId : bed.nightShiftNurseId) ==
                staff.staffId,
          )
          .map((bed) => bed.patientId)
          .whereType<String>()
          .toSet();
      return ref
          .watch(wardPatientsProvider)
          .where((patient) => assignedPatientIds.contains(patient.patientId))
          .toList();
    });

/// Reactive family provider yielding loops for a specific patient.
final patientLoopsProvider = Provider.family<List<LoopStateProjection>, String>(
  (ref, patientId) {
    ref.watch(wardControllerProvider); // re-evaluate on mutations
    final repo = ref.watch(localWardRepositoryProvider);
    return repo.getLoopsForPatient(patientId);
  },
);

/// Reactive provider yielding the active handoff session for the ward, if any.
final activeHandoffSessionProvider = Provider<HandoffSessionProjection?>((ref) {
  ref.watch(wardControllerProvider);
  final repo = ref.watch(localWardRepositoryProvider);
  final wardId = ref.watch(selectedWardProvider).wardId;
  if (wardId.isEmpty) return null;
  return repo.getActiveHandoffSession(wardId);
});

/// Reactive provider yielding the chronological timeline for a specific patient.
final patientTimelineProvider =
    Provider.family<List<PatientTimelineEntry>, String>((ref, patientId) {
      ref.watch(wardControllerProvider);
      final repo = ref.watch(localWardRepositoryProvider);
      return repo.getPatientTimeline(patientId);
    });

/// Reactive provider yielding ward-wide search results across beds, loops, and notes.
class WardSearchQueryController extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }

  void clear() {
    state = '';
  }
}

final wardSearchQueryProvider =
    NotifierProvider<WardSearchQueryController, String>(
      WardSearchQueryController.new,
    );

final wardSearchResultsProvider = Provider<List<WardSearchResult>>((ref) {
  ref.watch(wardControllerProvider);
  final query = ref.watch(wardSearchQueryProvider);
  if (query.trim().isEmpty) return [];

  final repo = ref.watch(localWardRepositoryProvider);
  final wardId = ref.watch(selectedWardProvider).wardId;
  if (wardId.isEmpty) return [];
  return repo.searchWard(
    wardId: wardId,
    query: query,
    allowedPatientIds: ref.watch(currentUserPatientIdsProvider),
  );
});

/// Provider for model-assisted Ask Oravi backend service (Milestone 5).
final askOraviModelServiceProvider = Provider<AskOraviModelService>((ref) {
  return AskOraviModelService(
    getAccessToken: () => ref.read(authAccessTokenProvider),
  );
});
