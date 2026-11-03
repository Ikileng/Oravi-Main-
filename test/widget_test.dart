import 'package:oravi_app/presentation/widgets/ward_search_sheet.dart';
import 'package:oravi_app/presentation/ward_board_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oravi_app/main.dart';
import 'package:drift/native.dart';
import 'package:oravi_app/data/database/database.dart';
import 'package:oravi_app/data/database/database_provider.dart';
import 'package:oravi_app/data/local_ward_repository.dart';
import 'package:oravi_app/data/ward_board_service.dart';
import 'package:oravi_app/domain/models/hospital_ward.dart';
import 'package:oravi_app/domain/models/staff_profile.dart';
import 'package:oravi_app/data/auth/staff_auth_service.dart';
import 'package:oravi_app/presentation/providers/whiteboard_providers.dart';
import 'package:oravi_app/presentation/providers/ward_context_providers.dart';
import 'package:oravi_app/presentation/providers/auth_providers.dart';
import 'package:oravi_app/presentation/providers/ward_providers.dart';
import 'fixtures/seeded_ward_data.dart';

const _testStaff = [
  StaffProfile(
    staffId: 'NUR-401',
    name: 'Mary Wanjiku, RN',
    role: 'ward_nurse',
    wardId: '',
    avatarColor: '#059669',
    initials: 'MW',
  ),
  StaffProfile(
    staffId: 'NUR-402',
    name: 'Grace Achieng, RN',
    role: 'ward_nurse',
    wardId: '',
    avatarColor: '#2563EB',
    initials: 'GA',
  ),
];

class _TestWardBoardService extends WardBoardService {
  _TestWardBoardService()
    : super(getAccessToken: () => 'test-token', candidateUrls: const []);

  @override
  Future<Map<String, dynamic>> getBoard({
    required String wardId,
    required String date,
    required String shiftType,
  }) async {
    return {
      'allocation_id': 'ALLOC-TEST',
      'bed_assignments': [
        for (var index = 1; index <= 5; index++)
          {
            'bed_number': 'Bed $index',
            'patient_id': 'PAT-4B-0$index',
            'patient_initials': const [
              'J.K.',
              'P.O.',
              'D.M.',
              'S.W.',
              'J.K.',
            ][index - 1],
            'admitting_doctor': '',
            'day_shift_nurse_id': index == 1 ? 'NUR-401' : 'NUR-402',
            'night_shift_nurse_id': null,
            'status': 'pending',
          },
      ],
      'responsibilities': const <String, dynamic>{},
    };
  }

  @override
  Future<List<StaffProfile>> getStaffForWard(
    String wardId, {
    required String date,
    required String shiftType,
  }) async => _testStaff;

  @override
  Future<void> acceptHandoffBeds({
    required String allocationId,
    required String outgoingStaffId,
    required String incomingAccessToken,
    required List<String> bedNumbers,
  }) async {}
}

Future<void> _pumpWardBoard(WidgetTester tester) async {
  final database = OraviLocalDatabase(NativeDatabase.memory());
  final repository = LocalWardRepository(database: database);
  await repository.initialize();
  await repository.appendEvents(SeededWardData.getInitialEvents());
  addTearDown(database.close);
  final container = ProviderContainer(
    overrides: [
      localDatabaseProvider.overrideWithValue(database),
      localWardRepositoryProvider.overrideWithValue(repository),
      localDeviceIdProvider.overrideWithValue('DEVICE-test-install'),
      wardBoardServiceProvider.overrideWithValue(_TestWardBoardService()),
      staffAuthServiceProvider.overrideWithValue(
        StaffAuthService(
          mockVerifyPinHandler: (staffId, pin) async => AuthResult(
            success: staffId == 'NUR-402' && pin == '5678',
            staff: _testStaff.last,
            token: 'incoming-test-token',
            error: 'Invalid test PIN.',
          ),
        ),
      ),
    ],
  );
  container.read(authenticatedStaffProvider);
  container.read(authAccessTokenProvider);
  container.read(selectedWardProvider);
  container
      .read(authenticatedStaffProvider.notifier)
      .setStaff(
        const StaffProfile(
          staffId: 'NUR-401',
          name: 'Mary Wanjiku, RN',
          role: 'ward_nurse',
          wardId: '',
          avatarColor: '#059669',
          initials: 'MW',
        ),
      );
  container
      .read(authAccessTokenProvider.notifier)
      .setToken('outgoing-test-token');
  container
      .read(selectedWardProvider.notifier)
      .selectWard(
        const HospitalWard(
          wardId: 'WARD-4B',
          name: 'Test Ward',
          bedCount: 5,
          bedNumbers: ['Bed 1', 'Bed 2', 'Bed 3', 'Bed 4', 'Bed 5'],
          department: 'Testing',
          description: '',
        ),
      );
  expect(container.read(selectedWardProvider).wardId, 'WARD-4B');
  expect(container.read(authAccessTokenProvider), 'outgoing-test-token');
  expect(
    (await container.read(wardBoardProvider.future)).assignments,
    hasLength(5),
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const OraviApp(home: WardBoardScreen()),
    ),
  );
}

void main() {
  testWidgets('Oravi Ward Board loads beds and displays patient identifiers', (
    WidgetTester tester,
  ) async {
    await _pumpWardBoard(tester);

    // Verify AppBar
    expect(find.textContaining('ORAVI'), findsOneWidget);

    // Verify the bedside identifiers are bed number and initials only.
    expect(find.text('01'), findsOneWidget);
    expect(find.text('J.K.'), findsNWidgets(2));
    expect(find.text('ADM-2026-8812'), findsNothing);

    expect(find.text('02'), findsOneWidget);
    expect(find.text('P.O.'), findsOneWidget);
    expect(find.text('ADM-2026-8834'), findsNothing);

    // Verify the open Medical Issue count on Bed 1.
    expect(find.text('1 pending'), findsWidgets);

    // Beds without open Medical Issues are identified as clear.
    expect(find.text('All clear'), findsWidgets);
  });

  testWidgets('Tapping a bed row opens PatientDetailScreen with loops', (
    WidgetTester tester,
  ) async {
    await _pumpWardBoard(tester);

    // Open Bed 1 using the visible patient identity.
    await tester.tap(find.text('01'));
    await tester.pumpAndSettle();

    // Verify detail screen loaded with loop title
    expect(find.textContaining('Bed 1 — J.K.'), findsOneWidget);
    expect(find.text('ADM-2026-8812'), findsNothing);
    expect(find.text('Maintain SpO2 > 92% on nasal cannula'), findsOneWidget);
    expect(find.text('Thread History (Append-Only):'), findsOneWidget);
    expect(
      find.text('Normal saline running at 100ml/hr. MAP is 68.'),
      findsNothing,
    ); // Bed 1 message was SpO2
    expect(
      find.textContaining('SpO2 stable at 94% on 2L nasal prongs'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Tapping Start Shift Handoff opens HandoffWizardScreen and walks through beds',
    (WidgetTester tester) async {
      await _pumpWardBoard(tester);

      // Verify the handoff banner on the current ward board.
      final handoffBtn = find.text('Shift Handoff');
      expect(handoffBtn, findsOneWidget);

      // Tap Handoff button
      await tester.ensureVisible(handoffBtn);
      await tester.pumpAndSettle();
      await tester.tap(handoffBtn);
      await tester.pumpAndSettle();

      // Verify Step 1: Pairing view
      expect(find.text('SHIFT HANDOFF SESSION'), findsOneWidget);
      expect(find.text('Shift Handover Protocol'), findsOneWidget);
      expect(find.text('Begin Bed-by-Bed Walkthrough'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grace Achieng, RN · NUR-402').last);
      await tester.pumpAndSettle();

      // Start walkthrough
      await tester.tap(find.text('Begin Bed-by-Bed Walkthrough'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '5678');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      // Verify Step 2: Bed 1 Walkthrough with SBAR
      expect(find.textContaining('Bed 1 of 5: Bed 1'), findsOneWidget);
      expect(find.text('ADM-2026-8812'), findsNothing);
      expect(find.text('SBAR SUMMARY (Compiled without AI)'), findsOneWidget);
      expect(find.text('S (Situation)'), findsOneWidget);
      expect(find.text('B (Background)'), findsOneWidget);
      expect(find.text('A (Assessment)'), findsOneWidget);
      expect(find.text('R (Recommendation)'), findsOneWidget);

      // Verify bed confirmation button
      expect(find.textContaining('Confirm: Transfer'), findsOneWidget);
    },
  );

  testWidgets(
    'M4: Tapping Ask Oravi & Timeline tab renders search, suggested chips, and queries',
    (WidgetTester tester) async {
      await _pumpWardBoard(tester);

      // Open Bed 1 using the visible patient identity.
      await tester.tap(find.text('01'));
      await tester.pumpAndSettle();

      // Verify TabBar with 'Loops' and 'Ask Oravi & Timeline'
      expect(find.text('Ask Oravi'), findsOneWidget);

      // Switch to Ask Oravi & Timeline Tab
      await tester.tap(find.text('Ask Oravi'));
      await tester.pumpAndSettle();

      // Verify search bar and suggested chips
      expect(
        find.textContaining('Message Oravi about this patient'),
        findsOneWidget,
      );
      expect(find.text('SpO2 / Oxygen'), findsOneWidget);
      expect(find.text('Urine / Mkojo'), findsOneWidget);
      expect(find.text('Blood / Cross-match'), findsOneWidget);

      // Tap 'SpO2 / Oxygen' chip to run query
      await tester.tap(find.text('SpO2 / Oxygen'));
      await tester.pumpAndSettle();

      // Verify verbatim quote appears in search results
      expect(
        find.textContaining('SpO2 stable at 94% on 2L nasal prongs'),
        findsOneWidget,
      );
      expect(find.text('Message'), findsWidgets);
      expect(find.text('Call'), findsWidgets);

      // Drag up to view coverage line and feedback action
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.textContaining('Searched:'), findsOneWidget);
      expect(find.text('Something is missing?'), findsOneWidget);
    },
  );

  testWidgets(
    'M4: Ward Search Sheet filters beds by term and navigates to patient',
    (WidgetTester tester) async {
      await _pumpWardBoard(tester);

      // Tap search icon in Ward Board AppBar
      final searchIconFinder = find.byIcon(Icons.search);
      expect(searchIconFinder, findsOneWidget);
      await tester.tap(searchIconFinder);
      await tester.pumpAndSettle();

      // Verify Ward Search sheet is open
      expect(find.text('WARD SEARCH'), findsOneWidget);

      // Enter 'cross-match' in search field
      final textFieldFinder = find.byType(TextField);
      await tester.enterText(textFieldFinder, 'cross-match');
      await tester.pumpAndSettle();

      // Verify Bed 2 (STAT repeat Hb & cross-match) appears in Ward Search sheet
      final patientInSheet = find.descendant(
        of: find.byType(WardSearchSheet),
        matching: find.text('P.O.'),
      );
      expect(patientInSheet, findsOneWidget);
      expect(find.text('ADM-2026-8834'), findsNothing);

      // Tap Bed 2 search result
      await tester.tap(patientInSheet);
      await tester.pumpAndSettle();

      // Verify navigated to Bed 2 detail screen
      expect(find.textContaining('Bed 2 — P.O.'), findsOneWidget);
    },
  );
}
