import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/data/ward_board_service.dart';
import 'package:oravi_app/domain/models/hospital_ward.dart';
import 'package:oravi_app/domain/models/staff_profile.dart';
import 'package:oravi_app/presentation/providers/auth_providers.dart';
import 'package:oravi_app/presentation/providers/whiteboard_providers.dart';
import 'package:oravi_app/presentation/widgets/ward_selection_dialog.dart';

class WardListApi extends WardBoardService {
  WardListApi() : super(getAccessToken: () => 'test', candidateUrls: []);
  int requests = 0;
  @override
  Future<List<HospitalWard>> getWards() async {
    requests++;
    return [];
  }
}

void main() {
  for (final role in ['ward_nurse', 'doctor_on_call', 'charge_nurse']) {
    testWidgets('ward selector access for $role', (tester) async {
      final api = WardListApi();
      final container = ProviderContainer(
        overrides: [wardBoardServiceProvider.overrideWithValue(api)],
      );
      container
          .read(authenticatedStaffProvider.notifier)
          .setStaff(
            StaffProfile(
              staffId: 'staff',
              name: 'Clinician',
              role: role,
              wardId: 'existing-ward',
              avatarColor: '#059669',
              initials: 'C',
            ),
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: WardSelectionDialog())),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.requests, role == 'charge_nurse' ? 1 : 0);
      expect(
        find.text('Select Hospital Ward'),
        role == 'charge_nurse' ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Ward assigned by the central board'),
        role == 'charge_nurse' ? findsNothing : findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  }
}
