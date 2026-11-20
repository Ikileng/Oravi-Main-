import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/domain/models/loop_enums.dart';
import 'package:oravi_app/domain/projections/projections.dart';
import 'package:oravi_app/presentation/theme/clinical_theme.dart';
import 'package:oravi_app/presentation/widgets/log_call_outcome_dialog.dart';

void main() {
  testWidgets('call outcome workflow remains usable at 360px', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final loop = LoopStateProjection(
      loopId: 'LOOP-1',
      patientId: 'PAT-1',
      title: 'Review falling haemoglobin and agree the immediate plan',
      description: 'Awaiting clinical review',
      loopType: LoopType.consultRequest,
      urgency: LoopUrgency.urgent,
      state: LoopState.raised,
      currentOwnerId: 'DOC-1',
      currentOwnerRole: 'doctor_on_call',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ClinicalTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => LogCallOutcomeDialog(
                      loop: loop,
                      recipientId: 'DOC-1',
                      recipientName: 'Dr Alexandra Long Clinician Name',
                      recipientRole: 'doctor_on_call',
                      durationSeconds: 125,
                    ),
                  ),
                  child: const Text('Open outcome'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open outcome'));
    await tester.pumpAndSettle();

    expect(find.text('Document call outcome'), findsOneWidget);
    expect(find.text('What was agreed?'), findsOneWidget);
    expect(find.text('Save to thread'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Save to thread'));
    await tester.pump();
    expect(
      find.text('Add the agreed outcome before saving to the thread.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
