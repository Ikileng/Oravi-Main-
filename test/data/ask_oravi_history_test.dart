import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/data/ask_oravi_history_store.dart';
import 'package:oravi_app/data/database/database.dart';
import 'package:oravi_app/data/database/database_provider.dart';
import 'package:oravi_app/data/local_ward_repository.dart';
import 'package:oravi_app/domain/models/staff_profile.dart';
import 'package:oravi_app/presentation/providers/auth_providers.dart';
import 'package:oravi_app/presentation/providers/ward_providers.dart';
import 'package:oravi_app/presentation/widgets/ask_oravi_view.dart';
import '../fixtures/seeded_ward_data.dart';

void main() {
  test(
    'History survives reopening SQLite, preserves snapshots, and isolates staff and patients',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'oravi_history_test',
      );
      final file = File('${directory.path}/history.sqlite');
      var db = OraviLocalDatabase(NativeDatabase(file));
      try {
        final repository = LocalWardRepository();
        await repository.appendEvents(SeededWardData.getInitialEvents());
        final result = repository.askOravi(
          patientId: 'PAT-4B-01',
          queryString: 'oxygen',
        );
        final message = OraviChatMessage(
          id: 'answer',
          sender: ChatSender.oravi,
          text: 'Recorded oxygen observations',
          timestamp: DateTime.utc(2026, 11, 18),
          result: result,
        );
        final store = AskOraviHistoryStore(db);
        await Future.wait([
          store.save('nurse-a', 'PAT-4B-01', {
            'id': 'one',
            'messages': [message.toJson()],
          }),
          store.save('nurse-a', 'PAT-4B-01', {'id': 'two', 'messages': []}),
        ]);
        await db.close();
        db = OraviLocalDatabase(NativeDatabase(file));
        final reopened = AskOraviHistoryStore(db);
        final history = await reopened.load('nurse-a', 'PAT-4B-01');
        expect(history.map((c) => c['id']), ['two', 'one']);
        final restored = OraviChatMessage.fromJson(
          Map<String, dynamic>.from((history.last['messages'] as List).single),
        );
        expect(restored.text, message.text);
        expect(restored.timestamp, message.timestamp);
        expect(restored.result!.verbatimQuotes, result.verbatimQuotes);
        expect(
          restored.result!.coverage.formattedLine,
          result.coverage.formattedLine,
        );
        expect(await reopened.load('nurse-b', 'PAT-4B-01'), isEmpty);
        expect(await reopened.load('nurse-a', 'PAT-4B-02'), isEmpty);
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'Reopening restores chats; New chat retains older conversations in History',
    (tester) async {
      final db = OraviLocalDatabase(NativeDatabase.memory());
      final repository = LocalWardRepository();
      await repository.appendEvents(SeededWardData.getInitialEvents());
      final patient = repository
          .getPatientsForWard(SeededWardData.wardId)
          .first;
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(db),
          localWardRepositoryProvider.overrideWithValue(repository),
        ],
      );
      container
          .read(authenticatedStaffProvider.notifier)
          .setStaff(
            const StaffProfile(
              staffId: 'nurse-a',
              name: 'Nurse A',
              role: 'ward_nurse',
              wardId: 'WARD-4B',
              avatarColor: '#0284C7',
              initials: 'NA',
            ),
          );
      Future<void> open() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(body: AskOraviView(patient: patient)),
            ),
          ),
        );
        await tester.runAsync(
          () => container
              .read(askOraviHistoryStoreProvider)
              .load('nurse-a', patient.patientId),
        );
        await tester.pumpAndSettle();
      }

      try {
        await open();
        await tester.enterText(find.byType(TextField), 'hello');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => container
              .read(askOraviHistoryStoreProvider)
              .load('nurse-a', patient.patientId),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await open();
        expect(find.text('hello'), findsOneWidget);
        expect(find.textContaining('Saved conversation.'), findsOneWidget);
        await tester.tap(find.text('New chat'));
        await tester.pumpAndSettle();
        expect(find.text('hello'), findsNothing);
        await tester.tap(find.text('History'));
        await tester.runAsync(
          () => container
              .read(askOraviHistoryStoreProvider)
              .load('nurse-a', patient.patientId),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('hello'));
        await tester.pumpAndSettle();
        expect(find.text('hello'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.runAsync(db.close);
      }
    },
  );
}
