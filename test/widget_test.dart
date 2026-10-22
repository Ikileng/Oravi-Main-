import 'package:oravi_app/presentation/widgets/ward_search_sheet.dart';
import 'package:flutter/material.dart';
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

  testWidgets('M4: Tapping Ask Oravi & Timeline tab renders search, suggested chips, and queries', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: OraviApp(),
      ),
    );

    // Tap Bed 1
    await tester.tap(find.text('Bed 1'));
    await tester.pumpAndSettle();

    // Verify TabBar with 'Loops' and 'Ask Oravi & Timeline'
    expect(find.text('Ask Oravi & Timeline'), findsOneWidget);

    // Switch to Ask Oravi & Timeline Tab
    await tester.tap(find.text('Ask Oravi & Timeline'));
    await tester.pumpAndSettle();

    // Verify search bar and suggested chips
    expect(find.textContaining('Ask Oravi or search record'), findsOneWidget);
    expect(find.text('SpO2 / Oxygen'), findsOneWidget);
    expect(find.text('Urine / Mkojo'), findsOneWidget);
    expect(find.text('Blood / Cross-match'), findsOneWidget);

    // Tap 'SpO2 / Oxygen' chip to run query
    await tester.tap(find.text('SpO2 / Oxygen'));
    await tester.pumpAndSettle();

    // Verify verbatim quote appears in search results
    expect(find.textContaining('SpO2 stable at 94% on 2L nasal prongs'), findsOneWidget);
    expect(find.text('Message'), findsWidgets);
    expect(find.text('Call'), findsWidgets);

    // Drag up to view coverage line and feedback action
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.textContaining('Searched:'), findsOneWidget);
    expect(find.text('Something is missing?'), findsOneWidget);
  });

  testWidgets('M4: Ward Search Sheet filters beds by term and navigates to patient', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: OraviApp(),
      ),
    );

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
      matching: find.text('P.O. (ADM-2026-8834)'),
    );
    expect(patientInSheet, findsOneWidget);

    // Tap Bed 2 search result
    await tester.tap(patientInSheet);
    await tester.pumpAndSettle();

    // Verify navigated to Bed 2 detail screen
    expect(find.textContaining('Bed 2 — P.O. (ADM-2026-8834)'), findsOneWidget);
  });
}
