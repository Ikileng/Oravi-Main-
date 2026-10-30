import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:oravi_app/data/database/database.dart';
import 'package:oravi_app/data/database/database_provider.dart';

void main() {
  late OraviLocalDatabase db;

  setUp(() async {
    db = OraviLocalDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('DatabaseSeeder seeds default staff and whiteboard when empty', () async {
    await DatabaseSeeder.seedIfEmpty(db);

    final staff = await db.getAllStaff();
    expect(staff.length, greaterThanOrEqualTo(8));
    expect(staff.any((s) => s.staffId == 'NUR-403'), isTrue);

    final beds = await db.getWhiteboardAssignments(
      DatabaseSeeder.defaultShiftDate,
      DatabaseSeeder.defaultShiftType,
    );
    expect(beds.length, equals(10));
    expect(beds.first.bedNumber, equals('1'));

    final roster = await db.getSupportRoster(
      DatabaseSeeder.defaultWardId,
      DatabaseSeeder.defaultShiftDate,
      DatabaseSeeder.defaultShiftType,
    );
    expect(roster, isNotNull);
    expect(roster!.inChargeName, equals('Nurse E'));
  });

  test('Staff CRUD, PIN update and active toggle persists in SQLite', () async {
    await DatabaseSeeder.seedIfEmpty(db);

    // 1. Insert new staff
    await db.upsertStaff(LocalStaffCompanion.insert(
      staffId: 'DEV-TEST',
      name: 'Nurse Test, RN',
      role: 'ward_nurse',
      pin: '9999',
      initials: 'NT',
    ));

    var staff = await db.getAllStaff();
    expect(staff.any((s) => s.staffId == 'DEV-TEST' && s.pin == '9999'), isTrue);

    // 2. Update PIN
    await db.updateStaffPin('DEV-TEST', '5555');
    staff = await db.getAllStaff();
    expect(staff.firstWhere((s) => s.staffId == 'DEV-TEST').pin, equals('5555'));

    // 3. Toggle active
    await db.toggleStaffActive('DEV-TEST');
    staff = await db.getAllStaff();
    expect(staff.firstWhere((s) => s.staffId == 'DEV-TEST').isActive, isFalse);

    // 4. Delete staff
    await db.deleteStaff('DEV-TEST');
    staff = await db.getAllStaff();
    expect(staff.any((s) => s.staffId == 'DEV-TEST'), isFalse);
  });

  test('Whiteboard bed allocation update persists in SQLite', () async {
    await DatabaseSeeder.seedIfEmpty(db);

    // Reallocate Bed 21 to Nurse X
    final updated = [
      LocalWhiteboardAssignmentsCompanion.insert(
        bedNumber: 'Bed 21',
        patientName: 'K.M. · ADM-4089',
        assignedNurse: 'Nurse X (Faith Njeri)',
        bay: 'Bay A',
        shiftDate: DatabaseSeeder.defaultShiftDate,
        shiftType: DatabaseSeeder.defaultShiftType,
      ),
    ];
    await db.saveWhiteboardAssignments(updated);

    final beds = await db.getWhiteboardAssignments(
      DatabaseSeeder.defaultShiftDate,
      DatabaseSeeder.defaultShiftType,
    );
    final bed21 = beds.firstWhere((b) => b.bedNumber == 'Bed 21');
    expect(bed21.assignedNurse, equals('Nurse X (Faith Njeri)'));
  });
}
