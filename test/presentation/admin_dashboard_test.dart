import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/data/auth/staff_auth_service.dart';
import 'package:oravi_app/domain/models/staff_profile.dart';
import 'package:oravi_app/domain/models/hospital_ward.dart';
import 'package:oravi_app/main.dart';
import 'package:oravi_app/presentation/admin/dev_admin_dashboard_screen.dart';
import 'package:oravi_app/presentation/providers/auth_providers.dart';

const admin = StaffProfile(
  staffId: 'ADMIN',
  name: 'Test Admin',
  role: 'dev_admin',
  wardId: '',
  avatarColor: '#475569',
  initials: 'TA',
);
StaffProfile account(String id, String role, {bool active = true}) =>
    StaffProfile(
      staffId: id,
      name: 'Staff $id',
      role: role,
      wardId: 'PRIVATE-WARD',
      avatarColor: '#059669',
      initials: 'ST',
      isActive: active,
    );

class _StaffApi extends StaffAuthService {
  _StaffApi() : super(candidateUrls: const []);
  final users = [
    account('N1', 'ward_nurse'),
    account('D1', 'doctor_on_call'),
    account('C1', 'charge_nurse', active: false),
  ];
  String? changedId;
  bool? activeStatus;
  List<String>? savedExpectedBeds;
  final wards = [
    const HospitalWard(
      wardId: 'A',
      name: 'Ward A',
      bedCount: 0,
      bedNumbers: [],
      department: 'General',
      description: 'Existing',
    ),
    const HospitalWard(
      wardId: 'B',
      name: 'Ward B',
      bedCount: 1,
      bedNumbers: ['B01'],
      department: 'General',
      description: 'Existing',
    ),
  ];
  @override
  Future<List<HospitalWard>> getConfiguredWards(String token) async =>
      List.of(wards);
  @override
  Future<void> saveConfiguredWard(
    String token,
    HospitalWard ward, {
    List<String>? expectedBeds,
  }) async {
    savedExpectedBeds = expectedBeds;
    final index = wards.indexWhere((item) => item.wardId == ward.wardId);
    if (index < 0) {
      wards.add(ward);
    } else {
      wards[index] = ward;
    }
  }

  @override
  Future<List<StaffProfile>> getProvisionedStaff(String token) async =>
      List.of(users);
  @override
  Future<StaffProfile> createClinicalStaff({
    required String token,
    required String staffId,
    required String name,
    required String role,
    required String pin,
  }) async {
    final user = account(staffId, role);
    users.add(user);
    return user;
  }

  @override
  Future<void> setStaffActive({
    required String token,
    required String staffId,
    required bool active,
  }) async {
    changedId = staffId;
    activeStatus = active;
    final index = users.indexWhere((user) => user.staffId == staffId);
    users[index] = account(staffId, users[index].role, active: active);
  }

  @override
  Future<void> deleteStaff({
    required String token,
    required String staffId,
  }) async {
    changedId = staffId;
    users.removeWhere((user) => user.staffId == staffId);
  }
}

Future<_StaffApi> _pumpAdmin(WidgetTester tester) async {
  tester.view.physicalSize = const Size(384, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = _StaffApi();
  final container = ProviderContainer(
    overrides: [staffAuthServiceProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  container.read(authAccessTokenProvider.notifier).setToken('test-admin-token');
  container.read(authenticatedStaffProvider.notifier).setStaff(admin);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const OraviApp()),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('admin edits existing empty ward without replacing other wards', (
    tester,
  ) async {
    final api = await _pumpAdmin(tester);
    await tester.tap(find.text('Configure wards'));
    await tester.pumpAndSettle();
    expect(find.text('Ward A'), findsOneWidget);
    expect(find.text('Ward B'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit Ward A'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Bed labels'),
      '01, 02',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.wards[0].wardId, 'A');
    expect(api.wards[0].bedNumbers, ['01', '02']);
    expect(api.savedExpectedBeds, isEmpty);
    expect(api.wards[1].bedNumbers, ['B01']);
    expect(find.text('2 beds · General\n01, 02'), findsOneWidget);
  });
  testWidgets('root routes admin to staff management without clinical data', (
    tester,
  ) async {
    await _pumpAdmin(tester);
    expect(find.byType(DevAdminDashboardScreen), findsOneWidget);
    expect(find.text('Create new user'), findsOneWidget);
    expect(find.text('Oravi Hospital'), findsOneWidget);
    expect(find.textContaining('PRIVATE-WARD'), findsNothing);
    expect(find.textContaining('Jaramanda'), findsNothing);
    expect(find.text('Medical Issues'), findsNothing);
  });

  testWidgets('directory filters by role and search', (tester) async {
    await _pumpAdmin(tester);
    await tester.tap(find.text('All roles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doctor').last);
    await tester.pumpAndSettle();
    expect(find.text('Staff D1'), findsOneWidget);
    expect(find.text('Staff N1'), findsNothing);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('0 staff shown'), findsOneWidget);
  });

  testWidgets('admin creates a staff account through the form', (tester) async {
    final api = await _pumpAdmin(tester);
    await tester.tap(find.text('Create new user'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'New Nurse');
    await tester.enterText(find.byType(TextFormField).at(1), 'N2');
    await tester.enterText(find.byType(TextFormField).at(2), '5678');
    await tester.tap(find.text('Create user'));
    await tester.pumpAndSettle();
    expect(api.users.any((user) => user.staffId == 'N2'), isTrue);
    expect(find.text('Staff N2'), findsOneWidget);
  });

  testWidgets('deactivate and delete require confirmation and reach backend', (
    tester,
  ) async {
    final api = await _pumpAdmin(tester);
    await tester.tap(find.byTooltip('Manage N1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();
    expect(api.changedId, isNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pumpAndSettle();
    expect(api.changedId, 'N1');
    expect(api.activeStatus, isFalse);
    await tester.tap(find.byTooltip('Manage N1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.users.any((user) => user.staffId == 'N1'), isTrue);
    await tester.tap(find.byTooltip('Manage N1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete permanently'));
    await tester.pumpAndSettle();
    expect(api.users.any((user) => user.staffId == 'N1'), isFalse);
  });
}
