import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/data/ward_board_service.dart';
import 'package:oravi_app/domain/models/staff_profile.dart';
import 'package:oravi_app/domain/models/whiteboard_models.dart';
import 'package:oravi_app/presentation/notebook/personal_notebook_screen.dart';
import 'package:oravi_app/presentation/providers/auth_providers.dart';
import 'package:oravi_app/presentation/providers/ward_context_providers.dart';
import 'package:oravi_app/presentation/providers/ward_providers.dart';
import 'package:oravi_app/presentation/providers/whiteboard_providers.dart';

StaffProfile staff(String id, String role) => StaffProfile(
  staffId: id,
  name: id,
  role: role,
  wardId: 'A',
  avatarColor: '#059669',
  initials: id,
);

class NotebookApi extends WardBoardService {
  NotebookApi() : super(getAccessToken: () => 'token');
  final rows = <String, Map<String, dynamic>>{};
  @override
  Future<Object?> communicationRequest(
    String method,
    String path, {
    Map<String, dynamic>? payload,
  }) async {
    if (method == 'GET') return rows.values.toList();
    final id = path.split('/').last;
    if (method == 'DELETE') {
      rows.remove(id);
      return {};
    }
    rows[id] = {
      'id': id,
      'created_at':
          rows[id]?['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
      ...payload!,
      'completed_at': payload['completed'] == true
          ? DateTime.now().toUtc().toIso8601String()
          : null,
    };
    return rows[id];
  }
}

void main() {
  test(
    'charge nurse personal workload differs from ward access for both shifts',
    () {
      final container = ProviderContainer(
        overrides: [
          whiteboardAssignmentsProvider.overrideWithValue(const [
            WhiteboardBedAssignment(
              bedNumber: '1',
              patientId: 'P1',
              patientInitials: 'AB',
              admittingDoctor: 'D',
              dayShiftNurseId: 'N',
              nightShiftNurseId: 'C',
            ),
            WhiteboardBedAssignment(
              bedNumber: '2',
              patientId: 'P2',
              patientInitials: 'CD',
              admittingDoctor: 'D',
              dayShiftNurseId: 'C',
              nightShiftNurseId: 'N',
            ),
          ]),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(authenticatedStaffProvider.notifier)
          .setStaff(staff('C', 'charge_nurse'));
      expect(container.read(currentUserPatientIdsProvider), {'P1', 'P2'});
      expect(container.read(personallyAssignedPatientIdsProvider), {'P2'});
      container.read(selectedShiftTypeProvider.notifier).select('night');
      expect(container.read(personallyAssignedPatientIdsProvider), {'P1'});
      container
          .read(authenticatedStaffProvider.notifier)
          .setStaff(staff('OTHER', 'charge_nurse'));
      expect(container.read(personallyAssignedPatientIdsProvider), isEmpty);
      expect(container.read(currentUserPatientIdsProvider), {'P1', 'P2'});
      container
          .read(authenticatedStaffProvider.notifier)
          .setStaff(staff('N', 'ward_nurse'));
      expect(container.read(personallyAssignedPatientIdsProvider), {'P2'});
      container
          .read(authenticatedStaffProvider.notifier)
          .setStaff(staff('D', 'doctor_on_call'));
      expect(container.read(personallyAssignedPatientIdsProvider), {
        'P1',
        'P2',
      });
      container
          .read(authenticatedStaffProvider.notifier)
          .setStaff(staff('H', 'housekeeper'));
      expect(container.read(personallyAssignedPatientIdsProvider), isEmpty);
    },
  );

  testWidgets('tasks count, complete history and notes stay distinct', (
    tester,
  ) async {
    final api = NotebookApi();
    final container = ProviderContainer(
      overrides: [wardBoardServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    container
        .read(authenticatedStaffProvider.notifier)
        .setStaff(staff('N', 'ward_nurse'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PersonalNotebookScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No pending tasks.'), findsOneWidget);
    await tester.tap(find.text('Add entry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Prepare handover');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(container.read(pendingPersonalTasksProvider), 1);
    expect(api.rows.values.single['reminder_at'], isNull);
    await tester.tap(find.text('Mark done'));
    await tester.pumpAndSettle();
    expect(container.read(pendingPersonalTasksProvider), 0);
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('Prepare handover'), findsOneWidget);
    await tester.tap(find.text('Add entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Note'));
    await tester.enterText(find.byType(TextField), 'Remember next meeting');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Remember next meeting'), findsOneWidget);
    expect(container.read(pendingPersonalTasksProvider), 0);
    // Simulate leaving the screen and returning: API-backed history remains.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PersonalNotebookScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('Prepare handover'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('due reminder can be snoozed without completing its task', (
    tester,
  ) async {
    final api = NotebookApi();
    api.rows['one'] = {
      'id': 'one',
      'body': 'Ward rounds',
      'kind': 'task',
      'completed': false,
      'created_at': '2025-01-01T00:00:00Z',
      'reminder_at': '2025-01-01T00:00:00Z',
    };
    final container = ProviderContainer(
      overrides: [wardBoardServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    container
        .read(authenticatedStaffProvider.notifier)
        .setStaff(staff('N', 'ward_nurse'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: NotebookReminderBanner()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A gentle reminder'), findsOneWidget);
    await tester.tap(find.text('Snooze 15 min'));
    await tester.pumpAndSettle();
    expect(find.text('A gentle reminder'), findsNothing);
    expect(api.rows['one']!['completed'], false);
    expect(
      DateTime.parse(
        api.rows['one']!['reminder_at'] as String,
      ).isAfter(DateTime.now()),
      true,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
