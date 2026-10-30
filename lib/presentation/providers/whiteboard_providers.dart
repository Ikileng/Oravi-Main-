import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/hospital_ward.dart';
import '../../domain/models/whiteboard_models.dart';
import '../../data/mock/seeded_gertrude_whiteboard_data.dart';

/// Currently selected active hospital ward. Defaults to Jacaranda Ward (Pediatrics).
class SelectedWardNotifier extends Notifier<HospitalWard> {
  @override
  HospitalWard build() {
    return kDefaultHospitalWards.firstWhere(
      (w) => w.wardId == SeededGertrudeWhiteboardData.jacarandaWardId,
      orElse: () => kDefaultHospitalWards[0],
    );
  }

  void selectWard(HospitalWard ward) {
    state = ward;
  }
}

final selectedWardProvider = NotifierProvider<SelectedWardNotifier, HospitalWard>(
  SelectedWardNotifier.new,
);

/// State for the Gertrude Whiteboard Bed Assignments
class WhiteboardAssignmentsNotifier extends Notifier<List<WhiteboardBedAssignment>> {
  @override
  List<WhiteboardBedAssignment> build() {
    return SeededGertrudeWhiteboardData.getInitialJacarandaAssignments();
  }

  void updateAssignment(String bedNumber, {String? nurseId, String? doctor, String? status}) {
    state = state.map((b) {
      if (b.bedNumber == bedNumber) {
        return WhiteboardBedAssignment(
          bedNumber: b.bedNumber,
          patientInitials: b.patientInitials,
          admissionNumber: b.admissionNumber,
          admittingDoctor: doctor ?? b.admittingDoctor,
          dayShiftNurseId: nurseId ?? b.dayShiftNurseId,
          nightShiftNurseId: b.nightShiftNurseId,
          status: status ?? b.status,
        );
      }
      return b;
    }).toList();
  }

  void batchAssignBeds(List<String> bedNumbers, String nurseId) {
    state = state.map((b) {
      if (bedNumbers.contains(b.bedNumber)) {
        return WhiteboardBedAssignment(
          bedNumber: b.bedNumber,
          patientInitials: b.patientInitials,
          admissionNumber: b.admissionNumber,
          admittingDoctor: b.admittingDoctor,
          dayShiftNurseId: nurseId,
          nightShiftNurseId: b.nightShiftNurseId,
          status: 'pending',
        );
      }
      return b;
    }).toList();
  }

  void acceptBeds(List<String> bedNumbers, String nurseId) {
    state = state.map((b) {
      if (bedNumbers.contains(b.bedNumber) && b.dayShiftNurseId == nurseId) {
        return WhiteboardBedAssignment(
          bedNumber: b.bedNumber,
          patientInitials: b.patientInitials,
          admissionNumber: b.admissionNumber,
          admittingDoctor: b.admittingDoctor,
          dayShiftNurseId: b.dayShiftNurseId,
          nightShiftNurseId: b.nightShiftNurseId,
          status: 'accepted',
        );
      }
      return b;
    }).toList();
  }
}

final whiteboardAssignmentsProvider =
    NotifierProvider<WhiteboardAssignmentsNotifier, List<WhiteboardBedAssignment>>(
  WhiteboardAssignmentsNotifier.new,
);

/// Active shift support roster contacts
class WardSupportRosterNotifier extends Notifier<WardSupportRoster> {
  @override
  WardSupportRoster build() {
    return SeededGertrudeWhiteboardData.getGertrudeSupportRoster();
  }

  void updateRoster(WardSupportRoster roster) {
    state = roster;
  }
}

final wardSupportRosterProvider = NotifierProvider<WardSupportRosterNotifier, WardSupportRoster>(
  WardSupportRosterNotifier.new,
);
