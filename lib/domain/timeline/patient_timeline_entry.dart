import 'package:equatable/equatable.dart';
import '../models/loop_enums.dart';

/// The specific clinical event type in the chronological patient timeline.
enum TimelineEntryType {
  loopOpened,
  message,
  callLog,
  escalationRaised,
  escalationAcknowledged,
  loopClosed,
  closureConfirmed,
  loopReopened,
}

/// Verbatim chronological timeline entry in a patient's Oravi record.
///
/// Implements PRD Section 8A (FR-35, FR-38, FR-43):
/// - Verbatim quote with exact wording.
/// - Author identifier and role token (for cadre badge coloring).
/// - Exact timestamp.
/// - Originating loop thread title and urgency.
/// - Actionable target for messaging, calling, or viewing thread.
class PatientTimelineEntry extends Equatable {
  final String id;
  final String patientId;
  final String? loopId;
  final String loopTitle;
  final LoopUrgency loopUrgency;
  final LoopState loopState;
  final TimelineEntryType entryType;
  final String authorId;
  final String authorRole;
  final String verbatimText;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  const PatientTimelineEntry({
    required this.id,
    required this.patientId,
    this.loopId,
    required this.loopTitle,
    required this.loopUrgency,
    required this.loopState,
    required this.entryType,
    required this.authorId,
    required this.authorRole,
    required this.verbatimText,
    required this.timestamp,
    this.metadata = const {},
  });

  /// Readable display label for the entry type.
  String get typeLabel {
    switch (entryType) {
      case TimelineEntryType.loopOpened:
        return 'Opened loop';
      case TimelineEntryType.message:
        return 'Message';
      case TimelineEntryType.callLog:
        return 'Call Log';
      case TimelineEntryType.escalationRaised:
        return 'Escalated';
      case TimelineEntryType.escalationAcknowledged:
        return 'Escalation Acknowledged';
      case TimelineEntryType.loopClosed:
        return 'Closed loop';
      case TimelineEntryType.closureConfirmed:
        return 'Closure Confirmed';
      case TimelineEntryType.loopReopened:
        return 'Reopened loop';
    }
  }

  @override
  List<Object?> get props => [
        id,
        patientId,
        loopId,
        loopTitle,
        loopUrgency,
        loopState,
        entryType,
        authorId,
        authorRole,
        verbatimText,
        timestamp,
        metadata,
      ];
}
