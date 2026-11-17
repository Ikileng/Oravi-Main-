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
  Future<List<Map<String, dynamic>>> getCarriedForwardIssues() async => [];

  @override
  Future<void> acceptHandoffBeds({
    required String allocationId,
    required String outgoingStaffId,
    required String incomingAccessToken,
    required List<String> bedNumbers,
    required String handoffSessionId,
    required String patientId,
    required List<String> transferredLoopIds,
  }) async {}
}

Future<ProviderContainer> _pumpWardBoard(
  WidgetTester tester, {
  bool emptyPatients = false,
}) async {
  final database = OraviLocalDatabase(NativeDatabase.memory());
  final repository = LocalWardRepository(database: database);
  await repository.initialize();
  await repository.appendEvents(SeededWardData.getInitialEvents());
  addTearDown(database.close);
  final container = ProviderContainer(
    overrides: [
      if (emptyPatients)
        personallyAssignedPatientIdsProvider.overrideWithValue(<String>{}),
      localDatabaseProvider.overrideWithValue(database),
      localWardRepositoryProvider.overrideWithValue(repository),
      localDeviceIdProvider.overrideWithValue('DEVICE-test-install'),
      wardBoardServiceProvider.overrideWithValue(_TestWardBoardService()),
      patientStaffListProvider('PAT-4B-01').overrideWith(
        (ref) async => const [
          StaffProfile(
            staffId: SeededWardData.testNurseId,
            name: 'Nurse A',
            role: 'ward_nurse',
            wardId: '',
            avatarColor: '#059669',
            initials: 'NA',
          ),
        ],
      ),
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
  if (!emptyPatients) addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const OraviApp(home: WardBoardScreen()),
    ),
  );
  return container;
}

void main() {
  testWidgets('Home prioritizes the highest assigned clinical issue', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = await _pumpWardBoard(tester);
    await tester.pumpAndSettle();

    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Maintain SpO2 > 92% on nasal cannula'), findsOneWidget);
    expect(find.text('At a glance'), findsOneWidget);
    expect(find.text('Shift workflow'), findsOneWidget);

    // Patient Detail has a separate responsive-refinement phase.
    tester.view.physicalSize = const Size(800, 600);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View issue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bed 1 — J.K.'), findsOneWidget);
    expect(find.text('Maintain SpO2 > 92% on nasal cannula'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets(
    'Home and Patients have distinct empty states and real navigation',
    (tester) async {
      final container = await _pumpWardBoard(tester, emptyPatients: true);
      await tester.pump();
      expect(find.text('Nothing on your Home page yet'), findsOneWidget);
      expect(find.text('You have no patients'), findsNothing);
      await tester.tap(find.text('Patients').last);
      await tester.pump();
      expect(find.text('You have no patients'), findsOneWidget);
      expect(find.text('Nothing on your Home page yet'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.text('Home').last);
      await tester.pump();
      expect(find.text('Nothing on your Home page yet'), findsOneWidget);
      expect(find.text('You have no patients'), findsNothing);
      await tester.tap(find.text('More').last);
      await tester.pumpAndSettle();
      expect(find.text('Switch Active Hospital Ward'), findsNothing);
      expect(find.text('Lock Station'), findsOneWidget);
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      expect(find.text('Nothing on your Home page yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump();
    },
  );

  testWidgets('Oravi Ward Board loads beds and displays patient identifiers', (
    WidgetTester tester,
  ) async {
    await _pumpWardBoard(tester);

    // Verify AppBar
    expect(find.textContaining('ORAVI'), findsOneWidget);

    await tester.tap(find.text('Patients').last);
    await tester.pumpAndSettle();

    // Verify the bedside identifiers are bed number and initials only.
    expect(find.text('01'), findsOneWidget);
    expect(find.text('J.K.'), findsOneWidget);
    expect(find.text('ADM-2026-8812'), findsNothing);

    expect(find.text('02'), findsNothing);
    expect(find.text('P.O.'), findsNothing);
    expect(find.text('ADM-2026-8834'), findsNothing);

    // Verify the open Medical Issue count on Bed 1.
    expect(find.text('1 pending'), findsWidgets);

    expect(find.text('All clear'), findsNothing);
  });

  testWidgets('Tapping a bed row opens PatientDetailScreen with loops', (
    WidgetTester tester,
  ) async {
    final container = await _pumpWardBoard(tester);

    // Open Bed 1 using the visible patient identity.
    await tester.tap(find.text('Patients').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('01'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open issue thread (1)'));
    await tester.pumpAndSettle();

    // Verify detail screen and explicitly opened Medical Issue thread.
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

    await tester.ensureVisible(find.text('Reply').first);
    await tester.tap(find.text('Reply').first);
    await tester.pumpAndSettle();
    final replyField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Add note or update...',
    );
    expect(tester.widget<TextField>(replyField).controller!.text, '@Nurse A: ');
    // Repeated taps must not duplicate the mention or its recipient.
    await tester.tap(find.text('Reply').first);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(replyField).controller!.text, '@Nurse A: ');
    await tester.ensureVisible(find.byIcon(Icons.send));
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    final reply = container
        .read(patientLoopsProvider('PAT-4B-01'))
        .expand((loop) => loop.messages)
        .singleWhere((message) => message.content == '@Nurse A:');
    expect(reply.mentionedStaffIds, [SeededWardData.testNurseId]);
    await tester.pumpWidget(const SizedBox.shrink());
    container.invalidate(syncEngineProvider);
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

      // The outgoing nurse only hands over patients currently assigned to them.
      expect(find.textContaining('Bed 1 of 1: Bed 1'), findsOneWidget);
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

      // Open Bed 1 from the Patients destination.
      await tester.tap(find.text('Patients').last);
      await tester.pumpAndSettle();
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

      // Search is available from the Patients destination.
      await tester.tap(find.text('Patients').last);
      await tester.pumpAndSettle();
      final searchIconFinder = find.byIcon(Icons.search);
      expect(searchIconFinder, findsOneWidget);
      await tester.tap(searchIconFinder);
      await tester.pumpAndSettle();

      // Verify Ward Search sheet is open
      expect(find.text('WARD SEARCH'), findsOneWidget);

      // Search within the patient's assignment scope.
      final textFieldFinder = find.byType(TextField);
      await tester.enterText(textFieldFinder, 'SpO2');
      await tester.pumpAndSettle();

      // Verify the assigned Bed 1 Medical Issue appears in search.
      final patientInSheet = find.descendant(
        of: find.byType(WardSearchSheet),
        matching: find.text('J.K.'),
      );
      expect(patientInSheet, findsOneWidget);
      expect(find.text('ADM-2026-8834'), findsNothing);

      // Tap Bed 1 search result
      await tester.tap(patientInSheet);
      await tester.pumpAndSettle();

      // Verify navigated to Bed 1 detail screen
      expect(find.textContaining('Bed 1 — J.K.'), findsOneWidget);
    },
  );
}
