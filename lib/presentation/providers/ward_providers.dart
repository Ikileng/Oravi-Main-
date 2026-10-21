import '../../data/database/database.dart';
import '../../data/sync/sync_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local_ward_repository.dart';
import '../../data/mock/seeded_ward_data.dart';
import '../../domain/models/loop_enums.dart';
import '../../domain/projections/projections.dart';

/// Persistent Drift SQLite local database provider.
final oraviLocalDatabaseProvider = Provider<OraviLocalDatabase>((ref) {
  final db = OraviLocalDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// Outbox Sync Engine provider.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(ref.watch(oraviLocalDatabaseProvider));
  ref.onDispose(() => engine.dispose());
  return engine;
});

/// Reactive stream provider for sync state and pending outbox count.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  return ref.watch(syncEngineProvider).statusStream;
});

/// Offline-first event-sourced repository backed by SQLite.
final localWardRepositoryProvider = Provider<LocalWardRepository>((ref) {
  final db = ref.watch(oraviLocalDatabaseProvider);
  return LocalWardRepository(database: db, seedInitialData: true);
});

/// Notifier that manages ward state versioning and triggers UI updates on mutations.
class WardController extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() {
    state++;
  }

  void postMessage({
    required String patientId,
    required String loopId,
    required String content,
  }) {
    ref.read(localWardRepositoryProvider).postMessage(
      patientId: patientId,
      loopId: loopId,
      authorId: SeededWardData.testNurseId,
      deviceId: SeededWardData.testDeviceId,
      content: content,
    );
    refresh();
  }

  void openLoop({
    required String patientId,
    required String title,
    required String description,
    required LoopType loopType,
    required LoopUrgency urgency,
  }) {
    ref.read(localWardRepositoryProvider).openLoop(
      patientId: patientId,
      authorId: SeededWardData.testNurseId,
      deviceId: SeededWardData.testDeviceId,
      title: title,
      description: description,
      loopType: loopType,
      urgency: urgency,
      initialOwnerId: SeededWardData.testNurseId,
      initialOwnerRole: 'ward_nurse',
    );
    refresh();
  }

  void closeLoop({
    required String patientId,
    required String loopId,
    required ClosureReasonCode reasonCode,
    String? freeTextNote,
    ClosureResolutionType resolutionType = ClosureResolutionType.resolved,
  }) {
    ref.read(localWardRepositoryProvider).closeLoop(
      patientId: patientId,
      loopId: loopId,
      authorId: SeededWardData.testNurseId,
      deviceId: SeededWardData.testDeviceId,
      reasonCode: reasonCode,
      freeTextNote: freeTextNote,
      resolutionType: resolutionType,
    );
    refresh();
  }

  void confirmCriticalClosure({
    required String patientId,
    required String loopId,
  }) {
    ref.read(localWardRepositoryProvider).confirmCriticalClosure(
      patientId: patientId,
      loopId: loopId,
      authorId: SeededWardData.testNurseId,
      deviceId: SeededWardData.testDeviceId,
      confirmedByRole: 'ward_in_charge',
    );
    refresh();
  }

  void reopenLoop({
    required String patientId,
    required String loopId,
    required String reopenReason,
  }) {
    ref.read(localWardRepositoryProvider).reopenLoop(
      patientId: patientId,
      loopId: loopId,
      authorId: SeededWardData.testNurseId,
      deviceId: SeededWardData.testDeviceId,
      reopenReason: reopenReason,
    );
    refresh();
  }

  void logCallOutcome({
    required String patientId,
    required String loopId,
    required String recipientId,
    required String recipientRole,
    required String outcomeNote,
    int durationSeconds = 0,
  }) {
    ref.read(localWardRepositoryProvider).logCallOutcome(
      patientId: patientId,
      loopId: loopId,
      callerId: SeededWardData.testNurseId,
      callerRole: 'ward_nurse',
      recipientId: recipientId,
      recipientRole: recipientRole,
      outcomeNote: outcomeNote,
      deviceId: SeededWardData.testDeviceId,
      durationSeconds: durationSeconds,
    );
    refresh();
  }
  void startHandoffSession({
    required String outgoingNurseId,
    required String incomingNurseId,
  }) {
    ref.read(localWardRepositoryProvider).startHandoffSession(
      wardId: SeededWardData.wardId,
      outgoingNurseId: outgoingNurseId,
      incomingNurseId: incomingNurseId,
      authorId: outgoingNurseId,
      deviceId: SeededWardData.testDeviceId,
    );
    refresh();
  }

  void acceptBedInHandoff({
    required String handoffSessionId,
    required String bedNumber,
    required String patientId,
    required String incomingNurseId,
    required bool nothingPendingConfirmed,
    required List<String> transferredLoopIds,
  }) {
    ref.read(localWardRepositoryProvider).acceptBedInHandoff(
      handoffSessionId: handoffSessionId,
      wardId: SeededWardData.wardId,
      bedNumber: bedNumber,
      patientId: patientId,
      authorId: incomingNurseId,
      incomingNurseId: incomingNurseId,
      deviceId: SeededWardData.testDeviceId,
      nothingPendingConfirmed: nothingPendingConfirmed,
      transferredLoopIds: transferredLoopIds,
    );
    refresh();
  }

  void completeHandoffSession({
    required String handoffSessionId,
    required String authorId,
    required int totalBedsHandedOver,
    required int totalLoopsTransferred,
  }) {
    ref.read(localWardRepositoryProvider).completeHandoffSession(
      handoffSessionId: handoffSessionId,
      wardId: SeededWardData.wardId,
      authorId: authorId,
      deviceId: SeededWardData.testDeviceId,
      totalBedsHandedOver: totalBedsHandedOver,
      totalLoopsTransferred: totalLoopsTransferred,
    );
    refresh();
  }
}

final wardControllerProvider = NotifierProvider<WardController, int>(WardController.new);

/// Reactive provider yielding active patient projections for the ward.
final wardPatientsProvider = Provider<List<PatientStateProjection>>((ref) {
  ref.watch(wardControllerProvider); // re-evaluate on mutations
  final repo = ref.watch(localWardRepositoryProvider);
  return repo.getPatientsForWard(SeededWardData.wardId);
});

/// Reactive family provider yielding loops for a specific patient.
final patientLoopsProvider = Provider.family<List<LoopStateProjection>, String>((ref, patientId) {
  ref.watch(wardControllerProvider); // re-evaluate on mutations
  final repo = ref.watch(localWardRepositoryProvider);
  return repo.getLoopsForPatient(patientId);
});


/// Reactive provider yielding the active handoff session for the ward, if any.
final activeHandoffSessionProvider = Provider<HandoffSessionProjection?>((ref) {
  ref.watch(wardControllerProvider);
  final repo = ref.watch(localWardRepositoryProvider);
  return repo.getActiveHandoffSession(SeededWardData.wardId);
});
