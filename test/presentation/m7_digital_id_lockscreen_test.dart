import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oravi_app/data/auth/staff_auth_service.dart';
import 'package:oravi_app/presentation/lockscreen/digital_id_lockscreen.dart';
import 'package:oravi_app/presentation/providers/auth_providers.dart';
import 'package:oravi_app/presentation/ward_board_screen.dart';

void main() {
  group('M7: Digital ID Lockscreen & Quick PIN Authentication', () {
    late StaffAuthService mockAuthService;

    setUp(() {
      mockAuthService = StaffAuthService(
        mockGetStaffHandler: (wardId) async => kDefaultWardStaff,
        mockVerifyPinHandler: (staffId, pin) async {
          if (staffId == 'NUR-401' && pin == '1234') {
            return AuthResult(
              success: true,
              staff: kDefaultWardStaff[0], // Mary Wanjiku
              token: 'mock_token_123',
            );
          } else if (staffId == 'NUR-402' && pin == '5678') {
            return AuthResult(
              success: true,
              staff: kDefaultWardStaff[1], // Grace Achieng
              token: 'mock_token_456',
            );
          }
          return const AuthResult(
            success: false,
            error: 'Invalid PIN. 4 attempt(s) remaining.',
          );
        },
      );
    });

    Widget createWidgetUnderTest() {
      return ProviderScope(
        overrides: [
          staffAuthServiceProvider.overrideWithValue(mockAuthService),
        ],
        child: const MaterialApp(
          home: DigitalIdLockscreen(),
        ),
      );
    }

    testWidgets('1. Lockscreen displays Ward 4B header and staff Digital ID badges', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Verify Header
      expect(find.text('ORAVI CLINICAL STATION'), findsOneWidget);
      expect(find.text('Ward 4B'), findsOneWidget);
      expect(find.text('Active Shift'), findsOneWidget);

      // Verify staff badges visible
      expect(find.text('Mary Wanjiku, RN'), findsOneWidget);
      expect(find.text('Grace Achieng, RN'), findsOneWidget);
      expect(find.text('NUR-401'), findsOneWidget);
      expect(find.text('NUR-402'), findsOneWidget);
    });

    testWidgets('2. Search filter narrows down staff cards by name or initials', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Search for "Grace"
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'Grace');
      await tester.pumpAndSettle();

      // Grace should be visible, Mary filtered out
      expect(find.text('Grace Achieng, RN'), findsOneWidget);
      expect(find.text('Mary Wanjiku, RN'), findsNothing);

      // Clear search
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(find.text('Mary Wanjiku, RN'), findsOneWidget);
      expect(find.text('Grace Achieng, RN'), findsOneWidget);
    });

    testWidgets('3. Tapping staff badge opens 4-Digit Quick PIN Keypad', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap Mary Wanjiku
      await tester.tap(find.text('Mary Wanjiku, RN'));
      await tester.pumpAndSettle();

      // Verify modal opened
      expect(find.text('Enter 4-Digit Quick PIN'), findsOneWidget);
      expect(find.text('Ward Nurse • NUR-401'), findsOneWidget);

      // Keypad numbers 1 to 9 and 0 visible
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('4. Invalid PIN displays clinical error and remains locked', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mary Wanjiku, RN'));
      await tester.pumpAndSettle();

      // Punch wrong PIN: 9999
      await tester.tap(find.text('9'));
      await tester.pump();
      await tester.tap(find.text('9'));
      await tester.pump();
      await tester.tap(find.text('9'));
      await tester.pump();
      await tester.tap(find.text('9'));
      await tester.pumpAndSettle();

      // Should show error message
      expect(find.textContaining('Invalid PIN'), findsOneWidget);
      expect(find.byType(WardBoardScreen), findsNothing);
    });

    testWidgets('5. Correct PIN unlocks and routes seamlessly to WardBoardScreen', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mary Wanjiku, RN'));
      await tester.pumpAndSettle();

      // Punch correct PIN: 1234
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pumpAndSettle();

      // Should route to WardBoardScreen!
      expect(find.byType(WardBoardScreen), findsOneWidget);
      expect(find.text('ORAVI — WARD BOARD'), findsOneWidget);
      expect(find.text('MW'), findsOneWidget); // Lock icon initials on Ward Board
    });
  });
}
