import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/data/ward_board_service.dart';
import 'package:oravi_app/domain/models/hospital_ward.dart';
import 'package:oravi_app/domain/models/staff_profile.dart';
import 'package:oravi_app/domain/models/whiteboard_models.dart';
import 'package:oravi_app/presentation/providers/auth_providers.dart';
import 'package:oravi_app/presentation/providers/ward_context_providers.dart';
import 'package:oravi_app/presentation/providers/whiteboard_providers.dart';
import 'package:oravi_app/presentation/whiteboard/ward_transfer_screen.dart';

const nurse = StaffProfile(
  staffId: 'N',
  name: 'Nurse Nina',
  role: 'ward_nurse',
  wardId: 'A',
  avatarColor: '#059669',
  initials: 'NN',
);

class TransferApi extends WardBoardService {
  TransferApi() : super(getAccessToken: () => 'token');
  List<Map<String, dynamic>> assignments = [];
  final writes = <Map<String, dynamic>>[];
  @override
  Future<Object?> communicationRequest(
    String method,
    String path, {
    Map<String, dynamic>? payload,
  }) async {
    if (method == 'GET') return assignments;
    writes.add({'path': path, ...?payload});
    return {'id': 'transfer'};
  }
}

class EditorHarness extends ConsumerWidget {
  final WhiteboardBedAssignment bed;
  const EditorHarness(this.bed, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () =>
            showNurseAssignmentEditor(context, ref, bed, [nurse], true),
        child: const Text('Edit day'),
      ),
    ),
  );
}

class HandoffApi extends TransferApi {
  @override
  Future<Object?> communicationRequest(
    String method,
    String path, {
    Map<String, dynamic>? payload,
  }) async {
    if (method == 'GET' && path == '/ward-transfers') {
      return [
        {
          'id': 'T',
          'nurse_id': 'N',
          'nurse_name': 'Nurse Nina',
          'source_ward': 'A',
          'source_name': 'Ward A',
          'target_ward': 'J',
          'target_name': 'Ward J',
          'date': '2026-11-13',
          'shift_type': 'day',
          'status': 'handoff',
          'replacement_id': 'R',
        },
      ];
    }
    if (method == 'GET' && path.endsWith('/handoff')) {
      return {
        'beds': [
          {'bed_number': '1', 'patient_initials': 'AB', 'issues': []},
        ],
        'revision': 'reviewed-revision',
        'notes': 'Follow up results',
      };
    }
    return super.communicationRequest(method, path, payload: payload);
  }
}

Future<void> mount(
  WidgetTester tester,
  TransferApi api,
  WhiteboardBedAssignment bed,
) async {
  final container = ProviderContainer(
    overrides: [wardBoardServiceProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  container
      .read(authenticatedStaffProvider.notifier)
      .setStaff(nurse.copyWith(role: 'charge_nurse'));
  container
      .read(selectedWardProvider.notifier)
      .selectWard(
        const HospitalWard(
          wardId: 'A',
          name: 'Ward A',
          bedCount: 1,
          bedNumbers: ['1'],
          department: '',
          description: '',
        ),
      );
  // Editing the day column must remain day even while the global selector is night.
  container.read(selectedShiftTypeProvider.notifier).select('night');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: EditorHarness(bed)),
    ),
  );
  await tester.tap(find.text('Edit day'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'receiving nurse must explicitly accept before transfer completes',
    (tester) async {
      final api = HandoffApi();
      final container = ProviderContainer(
        overrides: [wardBoardServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      container
          .read(authenticatedStaffProvider.notifier)
          .setStaff(nurse.copyWith(staffId: 'R'));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: WardTransferScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Prepare patient handoff'), findsNothing);
      await tester.tap(find.text('Review and accept handoff'));
      await tester.pumpAndSettle();
      expect(find.text('Bed 1 · AB'), findsOneWidget);
      expect(find.text('Handoff notes: Follow up results'), findsOneWidget);
      final accept = find.widgetWithText(
        FilledButton,
        'Accept and complete transfer',
      );
      expect(tester.widget<FilledButton>(accept).onPressed, isNull);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(api.writes.single['path'], '/ward-transfers/T/accept');
      expect(api.writes.single['revision'], 'reviewed-revision');
    },
  );
  const bed = WhiteboardBedAssignment(
    bedNumber: '1',
    patientId: 'P',
    patientInitials: 'XX',
    admittingDoctor: '',
  );
  testWidgets('opposite shift needs confirmation and day edits target day', (
    tester,
  ) async {
    final api = TransferApi()
      ..assignments = [
        {'ward_id': 'A', 'ward_name': 'Ward A', 'shift_type': 'night'},
      ];
    await mount(tester, api, bed);
    await tester.tap(find.text('Nurse Nina'));
    await tester.pumpAndSettle();
    expect(find.text('Assign both shifts?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    await tester.tap(find.text('Edit day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nurse Nina'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm both shifts'));
    await tester.pumpAndSettle();
    expect(api.writes.single['shift_type'], 'day');
    expect(api.writes.single['confirm_both_shifts'], true);
  });
  testWidgets('another ward offers transfer and never assigns directly', (
    tester,
  ) async {
    final api = TransferApi()
      ..assignments = [
        {'ward_id': 'J', 'ward_name': 'Ward J', 'shift_type': 'day'},
      ];
    await mount(tester, api, bed);
    await tester.tap(find.text('Nurse Nina'));
    await tester.pumpAndSettle();
    expect(find.text('Already in Ward J'), findsOneWidget);
    await tester.tap(find.text('Continue to transfer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Request transfer'));
    await tester.pumpAndSettle();
    expect(api.writes.single['path'], '/ward-transfers');
    expect(api.writes.single['source_ward'], 'J');
    expect(api.writes.single['target_ward'], 'A');
  });
  testWidgets('move corrects the explicit column with an expected old value', (
    tester,
  ) async {
    final api = TransferApi();
    await mount(tester, api, bed.copyWith(dayShiftNurseId: 'N'));
    await tester.tap(find.text('Move to night'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm move'));
    await tester.pumpAndSettle();
    expect(api.writes.single['shift_type'], 'night');
    expect(api.writes.single['move_from_other_shift'], true);
    expect(api.writes.single['expected_nurse_id'], null);
    expect(api.writes.single['nurse_id'], 'N');
  });
}
