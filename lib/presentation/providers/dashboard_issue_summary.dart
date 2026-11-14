import '../../domain/models/loop_enums.dart';
import '../../domain/projections/projections.dart';

class DashboardIssueSummary {
  final Set<String> pendingPatients = {};
  final Set<String> completedPatients = {};
  int openIssues = 0;
  int closedIssues = 0;

  DashboardIssueSummary(Map<String, List<LoopStateProjection>> patients) {
    for (final entry in patients.entries) {
      final open = entry.value.where((issue) => issue.isOpen).length;
      final closed = entry.value
          .where((issue) => issue.state == LoopState.closed)
          .length;
      openIssues += open;
      closedIssues += closed;
      if (open > 0) pendingPatients.add(entry.key);
      if (entry.value.isNotEmpty && closed == entry.value.length) {
        completedPatients.add(entry.key);
      }
    }
  }
}
