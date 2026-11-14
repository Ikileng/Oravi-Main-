import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/data/database/database.dart';

void main() {
  late OraviLocalDatabase db;
  const testDate = '2026-03-19';

  setUp(() async {
    db = OraviLocalDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'a new local database contains no demo staff or board allocations',
    () async {
      expect(await db.getAllStaff(), isEmpty);
      expect(await db.getWhiteboardAssignments(testDate, 'day'), isEmpty);
      expect(await db.getSupportRoster('WARD-TEST', testDate, 'day'), isNull);
    },
  );

  test('explicit test staff CRUD persists in SQLite', () async {
    await db.upsertStaff(
      LocalStaffCompanion.insert(
        staffId: 'DEV-TEST',
        name: 'Test Nurse',
        role: 'ward_nurse',
        wardId: const Value('WARD-TEST'),
        pin: '9999',
        initials: 'TN',
      ),
    );

    var staff = await db.getAllStaff();
    expect(staff.single.staffId, 'DEV-TEST');
    expect(staff.single.pin, '9999');

    await db.updateStaffPin('DEV-TEST', '5555');
    staff = await db.getAllStaff();
    expect(staff.single.pin, '5555');

    await db.toggleStaffActive('DEV-TEST');
    staff = await db.getAllStaff();
    expect(staff.single.isActive, isFalse);

    await db.deleteStaff('DEV-TEST');
    expect(await db.getAllStaff(), isEmpty);
  });

  test('explicit test board allocation persists in SQLite', () async {
    final allocation = [
      LocalWhiteboardAssignmentsCompanion.insert(
        bedNumber: '1',
        patientName: 'Patient Test',
        assignedNurse: 'NUR-TEST',
        bay: 'Bay A',
        shiftDate: testDate,
        shiftType: 'day',
      ),
    ];
    await db.saveWhiteboardAssignments(allocation);

    final beds = await db.getWhiteboardAssignments(testDate, 'day');
    expect(beds.single.bedNumber, '1');
    expect(beds.single.assignedNurse, 'NUR-TEST');
  });
}
