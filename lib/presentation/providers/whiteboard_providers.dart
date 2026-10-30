import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart';
import '../../data/database/database_provider.dart';
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

/// State for the Gertrude Whiteboard Bed Assignments with SQLite persistence
class WhiteboardAssignmentsNotifier extends Notifier<List<WhiteboardBedAssignment>> {
  @override
  List<WhiteboardBedAssignment> build() {
    _loadFromDatabase();
    return SeededGertrudeWhiteboardData.getInitialJacarandaAssignments();
  }

  Future<void> _loadFromDatabase() async {
    final db = ref.read(localDatabaseProvider);
    final rows = await db.getWhiteboardAssignments(
      DatabaseSeeder.defaultShiftDate,
      DatabaseSeeder.defaultShiftType,
    );
    if (rows.isNotEmpty) {
      state = rows.map((r) {
        final initials = r.patientName.split(' · ').first;
        final admNum = r.patientName.contains(' · ')
            ? r.patientName.split(' · ').last
            : 'ADM-${r.bedNumber}';
        return WhiteboardBedAssignment(
          bedNumber: r.bedNumber,
          patientInitials: initials,
          admissionNumber: admNum,
          admittingDoctor: r.diagnosis ?? 'Dr. Kamau',
          dayShiftNurseId: r.assignedNurse,
          nightShiftNurseId: 'Unassigned',
          status: 'accepted',
        );
      }).toList();
    }
  }

  void _persistToDatabase() {
    final db = ref.read(localDatabaseProvider);
    final companions = state.map((b) {
      String bay = 'Bay A';
      final bedNum = int.tryParse(b.bedNumber.replaceAll(RegExp(r'[^0-9]'), '')) ?? 21;
      if (bedNum >= 25 && bedNum <= 28) bay = 'Bay B';
      if (bedNum >= 29) bay = 'Side Rooms';

      return LocalWhiteboardAssignmentsCompanion.insert(
        bedNumber: b.bedNumber,
        patientName: '${b.patientInitials} · ${b.admissionNumber}',
        ageGender: const Value('Pediatric'),
        diagnosis: Value(b.admittingDoctor),
        assignedNurse: b.dayShiftNurseId ?? 'Unassigned',
        bay: bay,
        shiftDate: DatabaseSeeder.defaultShiftDate,
        shiftType: DatabaseSeeder.defaultShiftType,
      );
    }).toList();

    db.saveWhiteboardAssignments(companions);
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

    _persistToDatabase();
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

    _persistToDatabase();
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

    _persistToDatabase();
  }
}

final whiteboardAssignmentsProvider =
    NotifierProvider<WhiteboardAssignmentsNotifier, List<WhiteboardBedAssignment>>(
  WhiteboardAssignmentsNotifier.new,
);

/// Active shift support roster contacts with SQLite persistence
class WardSupportRosterNotifier extends Notifier<WardSupportRoster> {
  @override
  WardSupportRoster build() {
    _loadFromDatabase();
    return SeededGertrudeWhiteboardData.getGertrudeSupportRoster();
  }

  Future<void> _loadFromDatabase() async {
    final db = ref.read(localDatabaseProvider);
    final row = await db.getSupportRoster(
      DatabaseSeeder.defaultWardId,
      DatabaseSeeder.defaultShiftDate,
      DatabaseSeeder.defaultShiftType,
    );
    if (row != null) {
      try {
        final map = jsonDecode(row.hcasJson) as Map<String, dynamic>;
        state = WardSupportRoster.fromMap(map);
      } catch (_) {}
    }
  }

  void updateRoster(WardSupportRoster roster) {
    state = roster;
    _persistToDatabase(roster);
  }

  void _persistToDatabase(WardSupportRoster roster) {
    final db = ref.read(localDatabaseProvider);
    db.saveSupportRoster(LocalSupportRostersCompanion.insert(
      wardId: DatabaseSeeder.defaultWardId,
      shiftDate: DatabaseSeeder.defaultShiftDate,
      shiftType: DatabaseSeeder.defaultShiftType,
      inChargeName: roster.inchargeNurseDay,
      inChargePhone: const Value(''),
      inChargeRole: const Value('Sister In-Charge'),
      floatNurseName: roster.pcaDay,
      floatNursePhone: const Value(''),
      floatNurseRole: const Value('PCA'),
      hcasJson: jsonEncode(roster.toMap()),
      doctorsJson: '{}',
    ));
  }
}

final wardSupportRosterProvider = NotifierProvider<WardSupportRosterNotifier, WardSupportRoster>(
  WardSupportRosterNotifier.new,
);
