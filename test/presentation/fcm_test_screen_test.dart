import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/data/notifications/medical_issue_push_service.dart';
import 'package:oravi_app/presentation/fcm_test_screen.dart';
import 'package:oravi_app/presentation/providers/auth_providers.dart';

class _TestPushService extends MedicalIssuePushService {
  bool fail = false;

  @override
  Future<String> getConsoleTestToken() async {
    if (fail) throw StateError('Allow notifications in Android settings.');
    return 'test-console-registration-token';
  }
}

void main() {
  testWidgets('generates a Console token without staff authentication', (
    tester,
  ) async {
    final service = _TestPushService();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [medicalIssuePushServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: FcmTestScreen()),
      ),
    );
    expect(find.text('test-console-registration-token'), findsNothing);
    await tester.tap(find.text('Generate / refresh token'));
    await tester.pumpAndSettle();
    expect(find.text('test-console-registration-token'), findsOneWidget);
    expect(find.text('Copy token'), findsOneWidget);
  });

  testWidgets('shows permission errors and lets the user retry', (
    tester,
  ) async {
    final service = _TestPushService()..fail = true;
    addTearDown(service.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [medicalIssuePushServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: FcmTestScreen()),
      ),
    );
    await tester.tap(find.text('Generate / refresh token'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Allow notifications in Android settings.'),
      findsOneWidget,
    );
    expect(find.text('Copy token'), findsNothing);
    service.fail = false;
    await tester.tap(find.text('Generate / refresh token'));
    await tester.pumpAndSettle();
    expect(find.text('test-console-registration-token'), findsOneWidget);
    expect(
      find.textContaining('Allow notifications in Android settings.'),
      findsNothing,
    );
  });
}
