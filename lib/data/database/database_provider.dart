import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database.dart';
import '../mock/seeded_gertrude_whiteboard_data.dart';

/// Global provider for the SQLite Drift local database instance.
final localDatabaseProvider = Provider<OraviLocalDatabase>((ref) {
  final db = OraviLocalDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// Seeds the SQLite database on first launch if empty.
class DatabaseSeeder {
  static const String defaultWardId = 'WARD-4B';
  static const String defaultShiftDate = '2026-10-30';
  static const String defaultShiftType = 'day';

  static Future<void> seedIfEmpty(OraviLocalDatabase db) async {
    // 1. Seed Staff Table
    final staffCount = (await db.getAllStaff()).length;
    if (staffCount == 0) {
      final initialStaff = [
        LocalStaffCompanion.insert(
          staffId: 'NUR-401',
          name: 'Mary Wanjiku, RN',
          role: 'ward_nurse',
          wardId: const Value('WARD-4B'),
          pin: '1234',
          isActive: const Value(true),
          avatarColor: const Value('#059669'),
          initials: 'MW',
          email: const Value('nurse.y@oravi.dev'),
        ),
        LocalStaffCompanion.insert(
          staffId: 'NUR-402',
          name: 'Grace Achieng, RN',
          role: 'charge_nurse',
          wardId: const Value('WARD-4B'),
          pin: '5678',
          isActive: const Value(true),
          avatarColor: const Value('#2563EB'),
          initials: 'GA',
          email: const Value('manager@oravi.dev'),
        ),
        LocalStaffCompanion.insert(
          staffId: 'NUR-403',
          name: 'Faith Njeri, RN',
          role: 'ward_nurse',
          wardId: const Value('WARD-4B'),
          pin: '1111',
          isActive: const Value(true),
          avatarColor: const Value('#0D9488'),
          initials: 'FN',
          email: const Value('nurse.x@oravi.dev'),
        ),
        LocalStaffCompanion.insert(
          staffId: 'DOC-401',
          name: 'Dr. James Kamau',
          role: 'doctor_on_call',
          wardId: const Value('WARD-4B'),
          pin: '9090',
          isActive: const Value(true),
          avatarColor: const Value('#7C3AED'),
          initials: 'JK',
          email: const Value('doctor.a@oravi.dev'),
        ),
        LocalStaffCompanion.insert(
          staffId: 'NUR-404',
          name: 'Sarah Otieno, RN',
          role: 'ward_nurse',
          wardId: const Value('WARD-4B'),
          pin: '2222',
          isActive: const Value(true),
          avatarColor: const Value('#D97706'),
          initials: 'SO',
          email: const Value('sarah.o@oravi.dev'),
        ),
        LocalStaffCompanion.insert(
          staffId: 'NUR-405',
          name: 'Jane Muthoni, RN',
          role: 'ward_nurse',
          wardId: const Value('WARD-4B'),
          pin: '3333',
          isActive: const Value(true),
          avatarColor: const Value('#E11D48'),
          initials: 'JM',
          email: const Value('jane.m@oravi.dev'),
        ),
        LocalStaffCompanion.insert(
          staffId: 'DOC-499',
          name: 'Dr. Lucy Wangari',
          role: 'doctor_on_call',
          wardId: const Value('WARD-4B'),
          pin: '8080',
          isActive: const Value(true),
          avatarColor: const Value('#7C3AED'),
          initials: 'LW',
          email: const Value('lucy.w@oravi.dev'),
        ),
        LocalStaffCompanion.insert(
          staffId: 'ADM-001',
          name: 'Admin',
          role: 'admin',
          wardId: const Value('N/A'),
          pin: '0000',
          isActive: const Value(true),
          avatarColor: const Value('#475569'),
          initials: 'AD',
          email: const Value('admin@oravi.dev'),
        ),
      ];

      for (final staff in initialStaff) {
        await db.upsertStaff(staff);
      }
    }

    // 2. Seed Whiteboard Bed Assignments
    final existingAssignments = await db.getWhiteboardAssignments(defaultShiftDate, defaultShiftType);
    if (existingAssignments.isEmpty) {
      final initialBeds = SeededGertrudeWhiteboardData.getInitialJacarandaAssignments();
      final companions = initialBeds.map((bed) {
        String bay = 'Bay A';
        final bedNum = int.tryParse(bed.bedNumber.replaceAll(RegExp(r'[^0-9]'), '')) ?? 21;
        if (bedNum >= 25 && bedNum <= 28) bay = 'Bay B';
        if (bedNum >= 29) bay = 'Side Rooms';

        return LocalWhiteboardAssignmentsCompanion.insert(
          bedNumber: bed.bedNumber,
          patientName: '${bed.patientInitials} · ${bed.admissionNumber}',
          ageGender: const Value('Pediatric'),
          diagnosis: Value(bed.admittingDoctor),
          assignedNurse: bed.dayShiftNurseId ?? 'Unassigned',
          bay: bay,
          shiftDate: defaultShiftDate,
          shiftType: defaultShiftType,
        );
      }).toList();

      await db.saveWhiteboardAssignments(companions);
    }

    // 3. Seed Support Roster
    final existingRoster = await db.getSupportRoster(defaultWardId, defaultShiftDate, defaultShiftType);
    if (existingRoster == null) {
      final initialRoster = SeededGertrudeWhiteboardData.getGertrudeSupportRoster();
      final rosterCompanion = LocalSupportRostersCompanion.insert(
        wardId: defaultWardId,
        shiftDate: defaultShiftDate,
        shiftType: defaultShiftType,
        inChargeName: initialRoster.inchargeNurseDay,
        inChargePhone: const Value(''),
        inChargeRole: const Value('Sister In-Charge'),
        floatNurseName: initialRoster.pcaDay,
        floatNursePhone: const Value(''),
        floatNurseRole: const Value('PCA'),
        hcasJson: jsonEncode(initialRoster.toMap()),
        doctorsJson: '{}',
      );

      await db.saveSupportRoster(rosterCompanion);
    }
  }
}
