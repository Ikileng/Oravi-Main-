import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oravi_app/main.dart';

void main() {
  testWidgets('Oravi Ward Board loads beds and displays patient identifiers', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: OraviApp(),
      ),
    );

    // Verify AppBar
    expect(find.text('ORAVI — WARD BOARD'), findsOneWidget);

    // Verify beds and 2 required patient identifiers (PRD FR-3: Bed + Admission Number)
    expect(find.text('Bed 1'), findsOneWidget);
    expect(find.text('J.K.'), findsOneWidget);
    expect(find.text('(ADM-2026-8812)'), findsOneWidget);

    expect(find.text('Bed 2'), findsOneWidget);
    expect(find.text('P.O.'), findsOneWidget);
    expect(find.text('(ADM-2026-8834)'), findsOneWidget);

    // Verify open loop count badge on Bed 1
    expect(find.text('1 OPEN'), findsWidgets);

    // Verify "ALL CLEAR" on Beds with 0 open loops (Bed 4 and Bed 5)
    expect(find.text('ALL CLEAR'), findsNWidgets(2));
  });

  testWidgets('Tapping a bed row opens PatientDetailScreen with loops', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: OraviApp(),
      ),
    );

    // Tap Bed 1
    await tester.tap(find.text('Bed 1'));
    await tester.pumpAndSettle();

    // Verify detail screen loaded with loop title
    expect(find.text('Maintain SpO2 > 92% on nasal cannula'), findsOneWidget);
    expect(find.text('Thread History (Append-Only):'), findsOneWidget);
    expect(find.text('Normal saline running at 100ml/hr. MAP is 68.'), findsNothing); // Bed 1 message was SpO2
    expect(find.textContaining('SpO2 stable at 94% on 2L nasal prongs'), findsOneWidget);
  });

  testWidgets('Tapping Start Shift Handoff opens HandoffWizardScreen and walks through beds', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: OraviApp(),
      ),
    );

    // Verify Handoff button on ward board
    final handoffBtn = find.text('Start Shift Handoff (PRD FR-11)');
    expect(handoffBtn, findsOneWidget);

    // Tap Handoff button
    await tester.tap(handoffBtn);
    await tester.pumpAndSettle();

    // Verify Step 1: Pairing view
    expect(find.text('SHIFT HANDOFF SESSION'), findsOneWidget);
    expect(find.text('Shift Handover Protocol'), findsOneWidget);
    expect(find.text('Begin Bed-by-Bed Walkthrough'), findsOneWidget);

    // Start walkthrough
    await tester.tap(find.text('Begin Bed-by-Bed Walkthrough'));
    await tester.pumpAndSettle();

    // Verify Step 2: Bed 1 Walkthrough with SBAR
    expect(find.textContaining('Bed 1 of 5: Bed 1'), findsOneWidget);
    expect(find.text('SBAR SUMMARY (Compiled without AI)'), findsOneWidget);
    expect(find.text('S (Situation)'), findsOneWidget);
    expect(find.text('B (Background)'), findsOneWidget);
    expect(find.text('A (Assessment)'), findsOneWidget);
    expect(find.text('R (Recommendation)'), findsOneWidget);

    // Verify bed confirmation button
    expect(find.textContaining('Confirm: Transfer'), findsOneWidget);
  });
}
