import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/data/ward_board_service.dart';
import 'package:oravi_app/domain/models/staff_profile.dart';
import 'package:oravi_app/presentation/providers/auth_providers.dart';
import 'package:oravi_app/presentation/providers/clinical_assignment_provider.dart';
import 'package:oravi_app/presentation/providers/ward_context_providers.dart';
import 'package:oravi_app/presentation/providers/whiteboard_providers.dart';

class AssignmentApi extends WardBoardService {
  AssignmentApi() : super(getAccessToken: () => 'token');
  final shifts = <String, String>{};
  bool fail = false;
  Completer<Map<String, dynamic>?>? delayed;
  final requested = <String>[];
  @override
  Future<Map<String, dynamic>?> getActiveAssignment({
    required String date,
    required String shiftType,
  }) async {
    requested.add(shiftType);
    if (delayed != null) return delayed!.future;
    if (fail) throw StateError('offline');
    final ward = shifts[shiftType];
    return ward == null
        ? null
        : {
            'ward_id': ward,
            'ward_name': 'Ward $ward',
            'date': date,
            'shift_type': shiftType,
          };
  }
}

StaffProfile person(String id, {String role = 'ward_nurse'}) => StaffProfile(
  staffId: id,
  name: id,
  role: role,
  wardId: '',
  avatarColor: '#059669',
  initials: id,
);

void main() {
  test('afternoon greeting remains independent of a night assignment', () {
    expect(clinicalGreeting(DateTime(2026, 11, 13, 15)), 'Good afternoon');
    expect(clinicalShiftLabel('night', hasWard: true), 'Night shift');
    expect(clinicalGreeting(DateTime(2026, 11, 13, 9)), 'Good morning');
    expect(clinicalGreeting(DateTime(2026, 11, 13, 20)), 'Good evening');
    expect(clinicalShiftLabel('day', hasWard: false), 'No shift assigned');
  });

  test(
    'a nurse with no ward discovers a newly published night allocation',
    () async {
      final api = AssignmentApi();
      final container = ProviderContainer(
        overrides: [wardBoardServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      container.read(authenticatedStaffProvider.notifier).setStaff(person('Y'));
      container.read(authAccessTokenProvider.notifier).setToken('Y-token');
      final refresher = container.read(
        clinicalAssignmentRefreshProvider.notifier,
      );
      await refresher.refresh();
      expect(container.read(selectedWardProvider).wardId, isEmpty);
      api.shifts['night'] = 'A';
      await refresher.refresh();
      expect(container.read(selectedWardProvider).wardId, 'A');
      expect(container.read(selectedShiftTypeProvider), 'night');
      // A correction on the board moves the personal dashboard back to day.
      api.shifts
        ..clear()
        ..['day'] = 'A';
      await refresher.refresh();
      expect(container.read(selectedShiftTypeProvider), 'day');
      api.fail = true;
      await refresher.refresh();
      expect(container.read(selectedWardProvider).wardId, 'A');
      expect(container.read(wardContextErrorProvider), isNotNull);
      api.fail = false;
      api.shifts.clear();
      await refresher.refresh();
      expect(container.read(selectedWardProvider).wardId, isEmpty);
    },
  );

  test(
    'late responses from a previous user cannot change the current account',
    () async {
      final api = AssignmentApi()..delayed = Completer<Map<String, dynamic>?>();
      final container = ProviderContainer(
        overrides: [wardBoardServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      container.read(authenticatedStaffProvider.notifier).setStaff(person('X'));
      container.read(authAccessTokenProvider.notifier).setToken('X-token');
      final pending = container
          .read(clinicalAssignmentRefreshProvider.notifier)
          .refresh();
      container.read(authenticatedStaffProvider.notifier).setStaff(person('Y'));
      container.read(authAccessTokenProvider.notifier).setToken('Y-token');
      api.delayed!.complete({
        'ward_id': 'J',
        'ward_name': 'Ward J',
        'shift_type': 'night',
      });
      await pending;
      expect(container.read(selectedWardProvider).wardId, isEmpty);
      expect(container.read(selectedShiftTypeProvider), 'day');
    },
  );

  test(
    'confirmed double shifts preserve selection and charge context is untouched',
    () async {
      final api = AssignmentApi()..shifts.addAll({'day': 'A', 'night': 'J'});
      final container = ProviderContainer(
        overrides: [wardBoardServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      container.read(authenticatedStaffProvider.notifier).setStaff(person('X'));
      container.read(authAccessTokenProvider.notifier).setToken('token');
      container.read(selectedShiftTypeProvider.notifier).select('night');
      await container
          .read(clinicalAssignmentRefreshProvider.notifier)
          .refresh();
      expect(container.read(selectedWardProvider).wardId, 'J');
      expect(container.read(selectedShiftTypeProvider), 'night');
      api.requested.clear();
      container
          .read(authenticatedStaffProvider.notifier)
          .setStaff(person('C', role: 'charge_nurse'));
      await container
          .read(clinicalAssignmentRefreshProvider.notifier)
          .refresh();
      expect(api.requested, isEmpty);
      expect(container.read(selectedWardProvider).wardId, 'J');
    },
  );
}
