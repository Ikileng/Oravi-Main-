import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/data/local_ward_repository.dart';
import 'package:oravi_app/presentation/providers/ward_providers.dart';
import 'package:oravi_app/presentation/widgets/ask_oravi_view.dart';
import 'package:oravi_app/presentation/widgets/log_call_outcome_dialog.dart';
import '../fixtures/seeded_ward_data.dart';

void main() {
  testWidgets(
    'Issue Call invokes real-call callback once with the raiser and issue',
    (tester) async {
      final repository = LocalWardRepository();
      await repository.appendEvents(SeededWardData.getInitialEvents());
      final patient = repository
          .getPatientsForWard(SeededWardData.wardId)
          .firstWhere((p) => p.patientId == 'PAT-4B-01');
      final finished = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localWardRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AskOraviView(
                patient: patient,
                onCall: (loop, recipientId, role) async {
                  calls++;
                  expect(loop.patientId, patient.patientId);
                  expect(loop.loopId, 'LOOP-4B-01-A');
                  expect(recipientId, SeededWardData.testNurseId);
                  await finished.future;
                },
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Active medical issues');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Call').first);
      await tester.pump();
      await tester.tap(find.text('Call').first);
      expect(calls, 1);
      expect(find.byType(LogCallOutcomeDialog), findsNothing);
      finished.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Call invitation failure is shown without opening an outcome form',
    (tester) async {
      final repository = LocalWardRepository();
      await repository.appendEvents(SeededWardData.getInitialEvents());
      final patient = repository
          .getPatientsForWard(SeededWardData.wardId)
          .first;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localWardRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AskOraviView(
                patient: patient,
                onCall: (loop, recipientId, role) async =>
                    throw StateError('Offline'),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Active medical issues');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Call').first);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Could not start the call. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.byType(LogCallOutcomeDialog), findsNothing);
    },
  );
}
