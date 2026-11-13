import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/data/ward_board_service.dart';
import 'package:oravi_app/domain/models/staff_profile.dart';
import 'package:oravi_app/domain/models/hospital_ward.dart';
import 'package:oravi_app/main.dart';
import 'package:oravi_app/presentation/communications/staff_communications_screen.dart';
import 'package:oravi_app/presentation/providers/auth_providers.dart';
import 'package:oravi_app/presentation/providers/ward_context_providers.dart';
import 'package:oravi_app/presentation/providers/whiteboard_providers.dart';
import 'package:oravi_app/presentation/widgets/ward_responsibilities.dart';

class FakeCommunications extends WardBoardService {
  FakeCommunications() : super(getAccessToken: () => 'token');
  final requests = <String>[];
  String? assigned;
  final messages = <Map<String, dynamic>>[];
  @override
  Future<Object?> communicationRequest(
    String method,
    String path, {
    Map<String, dynamic>? payload,
  }) async {
    requests.add('$method $path');
    if (path == '/inbox') return {'items': <dynamic>[], 'unread_count': 0};
    if (path == '/inbox/read') return {'success': true};
    if (path.contains('responsibility-candidates')) {
      return [
        {'staff_id': 'H', 'name': 'Jane Housekeeper', 'role': 'housekeeper'},
      ];
    }
    if (path.contains('responsibilities') && method == 'PUT') {
      assigned = payload!['staff_id'] as String;
      return {};
    }
    if (path.contains('responsibilities')) {
      return [
        {
          'key': 'housekeeper',
          'label': 'Housekeeper',
          'staff': {
            'staff_id': 'H',
            'name': 'Jane Housekeeper',
            'role': 'housekeeper',
          },
        },
      ];
    }
    if (path == '/direct/threads' || path == '/direct/calls') return [];
    if (method == 'POST') {
      messages.add({
        'sender_id': 'N',
        'recipient_id': 'H',
        'body': payload!['body'],
      });
      return {'success': true};
    }
    return messages;
  }
}

Future<ProviderContainer> mount(
  WidgetTester tester,
  FakeCommunications api,
  String role, {
  Widget? home,
}) async {
  tester.view.physicalSize = const Size(384, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [wardBoardServiceProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  container.read(authAccessTokenProvider.notifier).setToken('token');
  container
      .read(authenticatedStaffProvider.notifier)
      .setStaff(
        StaffProfile(
          staffId: 'N',
          name: 'Test Staff',
          role: role,
          wardId: '',
          avatarColor: '#059669',
          initials: 'TS',
        ),
      );
  container
      .read(selectedWardProvider.notifier)
      .selectWard(
        const HospitalWard(
          wardId: 'A',
          name: 'A',
          bedCount: 0,
          bedNumbers: [],
          department: '',
          description: '',
        ),
      );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: OraviApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'support root loads only messages and calls, without patient providers',
    (tester) async {
      final api = FakeCommunications();
      await mount(tester, api, 'housekeeper');
      expect(find.byType(StaffCommunicationsScreen), findsOneWidget);
      expect(find.text('No messages yet'), findsOneWidget);
      expect(find.text('No calls yet'), findsOneWidget);
      expect(find.text('Ward Responsibilities'), findsNothing);
      expect(
        api.requests.every((r) => r.contains('/direct/') || r == 'GET /inbox'),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('nurse can message a responsibility contact but cannot edit it', (
    tester,
  ) async {
    final api = FakeCommunications();
    await mount(
      tester,
      api,
      'ward_nurse',
      home: const Scaffold(body: WardResponsibilities()),
    );
    expect(find.byTooltip('Assign Housekeeper'), findsNothing);
    await tester.tap(find.text('Jane Housekeeper'));
    await tester.pumpAndSettle();
    expect(find.text('Call'), findsOneWidget);
    await tester.tap(find.text('Message'));
    await tester.pumpAndSettle();
    expect(find.byType(StaffChatScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Please arrange supplies');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(api.messages.single['body'], 'Please arrange supplies');
    expect(api.requests.any((r) => r.startsWith('PUT')), isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('charge nurse searches and assigns a provisioned person', (
    tester,
  ) async {
    final api = FakeCommunications();
    await mount(
      tester,
      api,
      'charge_nurse',
      home: const Scaffold(body: WardResponsibilities()),
    );
    await tester.tap(find.byTooltip('Assign Housekeeper'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Jane');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Jane Housekeeper'),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.assigned, 'H');
  });
}
