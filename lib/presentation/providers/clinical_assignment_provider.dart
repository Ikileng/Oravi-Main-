import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/hospital_ward.dart';
import 'auth_providers.dart';
import 'ward_context_providers.dart';
import 'whiteboard_providers.dart';

String clinicalGreeting(DateTime now) => now.hour < 12
    ? 'Good morning'
    : now.hour < 17
    ? 'Good afternoon'
    : 'Good evening';

String clinicalShiftLabel(String shift, {required bool hasWard}) => !hasWard
    ? 'No shift assigned'
    : shift == 'night'
    ? 'Night shift'
    : 'Day shift';

/// Re-resolves assignments even when the clinician had no ward at sign-in.
final clinicalAssignmentRefreshProvider =
    NotifierProvider<ClinicalAssignmentRefresh, int>(
      ClinicalAssignmentRefresh.new,
    );

class ClinicalAssignmentRefresh extends Notifier<int> {
  bool _busy = false;
  @override
  int build() => 0;

  Future<void> refresh() async {
    final staff = ref.read(authenticatedStaffProvider);
    final token = ref.read(authAccessTokenProvider);
    if (_busy ||
        staff == null ||
        !staff.isClinical ||
        staff.isChargeNurse ||
        token == null) {
      return;
    }
    _busy = true;
    final originalShift = ref.read(selectedShiftTypeProvider);
    final day = activeWardShiftDate();
    bool stillCurrent() =>
        ref.read(authenticatedStaffProvider)?.staffId == staff.staffId &&
        ref.read(authAccessTokenProvider) == token &&
        ref.read(selectedShiftTypeProvider) == originalShift &&
        activeWardShiftDate() == day;
    try {
      final api = ref.read(wardBoardServiceProvider);
      var shift = originalShift;
      var assignment = await api.getActiveAssignment(
        date: day,
        shiftType: shift,
      );
      if (assignment == null) {
        shift = shift == 'day' ? 'night' : 'day';
        assignment = await api.getActiveAssignment(date: day, shiftType: shift);
      }
      // A response for an old account or selection must never replace the current context.
      if (!stillCurrent()) return;
      final currentWard = ref.read(selectedWardProvider);
      final wardId = assignment?['ward_id'] as String? ?? '';
      if (assignment != null) {
        ref
            .read(selectedShiftTypeProvider.notifier)
            .select(assignment['shift_type'] as String? ?? shift);
      }
      if (currentWard.wardId != wardId) {
        ref
            .read(selectedWardProvider.notifier)
            .selectWard(
              HospitalWard(
                wardId: wardId,
                name: assignment?['ward_name'] as String? ?? 'No ward assigned',
                bedCount: 0,
                bedNumbers: const [],
                department: '',
                description: '',
              ),
            );
      }
      ref.read(wardContextErrorProvider.notifier).setError(null);
      ref.invalidate(wardBoardProvider);
      state++;
    } catch (_) {
      if (stillCurrent()) {
        ref
            .read(wardContextErrorProvider.notifier)
            .setError(
              'Could not refresh your assignment. Check your connection and retry.',
            );
      }
    } finally {
      _busy = false;
    }
  }
}
