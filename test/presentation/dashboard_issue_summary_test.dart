import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/domain/models/loop_enums.dart';
import 'package:oravi_app/domain/projections/projections.dart';
import 'package:oravi_app/presentation/providers/dashboard_issue_summary.dart';

LoopStateProjection issue(LoopState state) => LoopStateProjection(
  loopId: 'L',
  patientId: 'P',
  title: '',
  description: '',
  loopType: LoopType.taskOrPendingResult,
  urgency: LoopUrgency.routine,
  state: state,
  currentOwnerId: 'N',
  currentOwnerRole: 'ward_nurse',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  test('patient filters count patients; issue cards count issues', () {
    final summary = DashboardIssueSummary({
      'empty': [],
      'mixed': [issue(LoopState.raised), issue(LoopState.closed)],
      'done': [issue(LoopState.closed), issue(LoopState.closed)],
      'awaiting': [issue(LoopState.closedAwaitingConfirmation)],
    });
    expect(summary.pendingPatients, {'mixed', 'awaiting'});
    expect(summary.completedPatients, {'done'});
    expect(summary.openIssues, 2);
    expect(summary.closedIssues, 3);
    expect(DashboardIssueSummary({}).closedIssues, 0);
  });
}
