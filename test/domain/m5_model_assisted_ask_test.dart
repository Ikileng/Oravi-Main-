import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oravi_app/data/ask_oravi_model_service.dart';
import 'package:oravi_app/data/local_ward_repository.dart';
import '../fixtures/seeded_ward_data.dart';
import 'package:oravi_app/presentation/providers/ward_providers.dart';
import 'package:oravi_app/presentation/widgets/ask_oravi_view.dart';

void main() {
  group(
    'M5: Model-Assisted Answers with Verification (PRD Section 8A & Tech Arch Section 11)',
    () {
      late LocalWardRepository repository;

      setUp(() async {
        repository = LocalWardRepository();
        await repository.appendEvents(SeededWardData.getInitialEvents());
      });

      test(
        '1. ModelAskResponse deserializes valid verified backend response',
        () {
          final json = {
            'patient_id': 'PAT-4B-01',
            'query': 'urine',
            'observation_note':
                'Urine output was 30ml at 06:00 draining dark amber.',
            'is_refusal': false,
            'refusal_message': null,
            'is_absence': false,
            'absence_message': null,
            'doctor_in_charge': 'DOC-OTIENO',
            'verification_passed': true,
            'model_provider': 'ollama',
            'model_name': 'qwen2.5:7b',
            'verbatim_quotes': [
              {
                'quote_id': 'evt-1',
                'author_id': 'NURSE-WANJIKU',
                'timestamp': '2026-10-23T06:00:00Z',
                'verbatim_text':
                    'Urine output 30ml in last 2 hours. Foley draining dark amber.',
              },
            ],
          };

          final resp = ModelAskResponse.fromJson(json);

          expect(resp.patientId, 'PAT-4B-01');
          expect(resp.query, 'urine');
          expect(resp.observationNote, contains('Urine output was 30ml'));
          expect(resp.verificationPassed, isTrue);
          expect(resp.modelName, 'qwen2.5:7b');
          expect(resp.modelProvider, 'ollama');
          expect(resp.verbatimQuotes.length, 1);
        },
      );

      test(
        '2. Silent Fallback: AskOraviModelService returns null on failure without throwing',
        () async {
          final failingService = AskOraviModelService(
            baseUrl: 'http://127.0.0.1:54321', // Unreachable
            timeout: const Duration(milliseconds: 100),
          );

          final result = await failingService.askPatient(
            patientId: 'PAT-4B-01',
            query: 'urine',
          );

          expect(result, isNull);
        },
      );

      test(
        'Ask Oravi does not send patient queries without an authenticated session',
        () async {
          final service = AskOraviModelService(getAccessToken: () => null);
          final result = await service.askPatient(
            patientId: 'PAT-4B-01',
            query: 'Show recent observations',
          );

          expect(result, isNull);
        },
      );

      testWidgets(
        '3. AskOraviView renders Model Observation Card with mandatory disclaimer and quotes',
        (tester) async {
          final patient = repository
              .getPatientsForWard(SeededWardData.wardId)
              .first;

          final mockModelService = AskOraviModelService(
            mockHandler: (patientId, query, timeWindow) async {
              return const ModelAskResponse(
                patientId: 'PAT-4B-01',
                query: 'urine',
                observationNote:
                    'Urine output was 30ml at 06:00 draining dark amber.',
                verificationPassed: true,
                modelProvider: 'ollama',
                modelName: 'qwen2.5:7b',
              );
            },
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                localWardRepositoryProvider.overrideWithValue(repository),
                askOraviModelServiceProvider.overrideWithValue(
                  mockModelService,
                ),
              ],
              child: MaterialApp(
                home: Scaffold(body: AskOraviView(patient: patient)),
              ),
            ),
          );

          await tester.pumpAndSettle();

          // Enter query
          final textField = find.byType(TextField);
          expect(textField, findsOneWidget);

          await tester.enterText(textField, 'urine');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();

          // Mandatory M5 visual verification:
          // 1. Mandatory disclaimer badge: "Note from Oravi, not from the record"
          expect(
            find.text('Note from Oravi, not from the record'),
            findsOneWidget,
          );

          // 2. Observation content
          expect(
            find.text('Urine output was 30ml at 06:00 draining dark amber.'),
            findsOneWidget,
          );

          // 3. Model indicator badge
          expect(find.text('qwen2.5:7b (ollama)'), findsOneWidget);

          // 4. Verification statement
          expect(
            find.text(
              'All numbers verified against patient event log quotes below',
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        '4. Silent Fallback in UI: when model service fails, deterministic quotes are still rendered without error dialogs',
        (tester) async {
          final patient = repository
              .getPatientsForWard(SeededWardData.wardId)
              .first;

          // Model service returns null (simulating offline / model timeout)
          final failingModelService = AskOraviModelService(
            mockHandler: (patientId, query, timeWindow) async {
              return null;
            },
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                localWardRepositoryProvider.overrideWithValue(repository),
                askOraviModelServiceProvider.overrideWithValue(
                  failingModelService,
                ),
              ],
              child: MaterialApp(
                home: Scaffold(body: AskOraviView(patient: patient)),
              ),
            ),
          );

          await tester.pumpAndSettle();

          final textField = find.byType(TextField);
          await tester.enterText(textField, 'oxygen');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();

          // Model observation card should NOT appear
          expect(
            find.text('Note from Oravi, not from the record'),
            findsNothing,
          );

          // No error dialog or snackbar should appear
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.byType(SnackBar), findsNothing);

          // Deterministic quotes and coverage line must still be present
          expect(find.textContaining('Searched:'), findsOneWidget);
        },
      );
    },
  );
}
