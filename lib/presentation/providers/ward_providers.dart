import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local_ward_repository.dart';
import '../../data/mock/seeded_ward_data.dart';
import '../../domain/models/loop_enums.dart';
import '../../domain/projections/projections.dart';

/// Singleton in-memory local repository provider.
final localWardRepositoryProvider = Provider<LocalWardRepository>((ref) {
  return LocalWardRepository(seedInitialData: true);
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
