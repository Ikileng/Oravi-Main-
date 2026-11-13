import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/presentation/communications/personal_inbox.dart';

void main() {
  testWidgets('badge shows zero and received activity shows unread count', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalInboxProvider.overrideWith(
            (ref) async => {'items': <dynamic>[], 'unread_count': 0},
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Column(children: [InboxBadge(), ReceivedInbox()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0'), findsOneWidget);
    expect(find.text('No received messages or calls yet'), findsOneWidget);
  });

  testWidgets('clinical updates and missed calls appear with unread badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalInboxProvider.overrideWith(
            (ref) async => {
              'items': [
                {
                  'id': 'issue:1',
                  'kind': 'issue',
                  'title': 'Doctor X · Medical issue update',
                  'body': 'Please review',
                  'unread': true,
                },
                {
                  'id': 'call:C:missed',
                  'kind': 'call',
                  'title': 'Nurse Y',
                  'body': 'missed',
                  'status': 'missed',
                  'unread': true,
                },
              ],
              'unread_count': 2,
            },
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Column(children: [InboxBadge(), ReceivedInbox()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Doctor X · Medical issue update'), findsOneWidget);
    expect(find.text('missed'), findsOneWidget);
  });
}
