import 'package:equatable/equatable.dart';
import '../models/loop_enums.dart';
import '../models/patient_identity.dart';

/// Single message in a loop's append-only communication thread (PRD FR-6).
class ThreadMessage extends Equatable {
  final String messageId;
  final String authorId;
  final String authorRole;
  final String deviceId;
  final String content;
  final DateTime createdAt;
  final DateTime? editedAt;
  final String? previousContent;
  final String? quotedMessageId;
  final List<String> roleMentions;
  final List<String> mentionedStaffIds;
  final bool isCallLog;
  final String? callRecipientId;
  final String? callRecipientRole;

  const ThreadMessage({
    required this.messageId,
    required this.authorId,
    this.authorRole = '',
    required this.deviceId,
    required this.content,
    required this.createdAt,
    this.editedAt,
    this.previousContent,
    this.quotedMessageId,
    this.roleMentions = const [],
    this.mentionedStaffIds = const [],
    this.isCallLog = false,
    this.callRecipientId,
    this.callRecipientRole,
  });

  ThreadMessage copyWith({
    String? content,
    DateTime? editedAt,
    String? previousContent,
  }) {
    return ThreadMessage(
      messageId: messageId,
      authorId: authorId,
      authorRole: authorRole,
      deviceId: deviceId,
      content: content ?? this.content,
      createdAt: createdAt,
      editedAt: editedAt ?? this.editedAt,
      previousContent: previousContent ?? this.previousContent,
      quotedMessageId: quotedMessageId,
      roleMentions: roleMentions,
      mentionedStaffIds: mentionedStaffIds,
      isCallLog: isCallLog,
      callRecipientId: callRecipientId,
      callRecipientRole: callRecipientRole,
    );
  }

  @override
  List<Object?> get props => [
    messageId,
    authorId,
    authorRole,
    deviceId,
    content,
    createdAt,
    editedAt,
    previousContent,
    quotedMessageId,
    roleMentions,
    mentionedStaffIds,
    isCallLog,
    callRecipientId,
    callRecipientRole,
  ];
}

/// Record of an escalation event on a loop.
class LoopEscalationState extends Equatable {
  final String escalationId;
  final String targetRole;
  final String currentTargetUserId;
  final String reason;
  final int timeoutMinutes;
  final DateTime raisedAt;
  final bool isAcknowledged;
  final DateTime? acknowledgedAt;
  final String? acknowledgeNote;

  const LoopEscalationState({
    required this.escalationId,
    required this.targetRole,
    required this.currentTargetUserId,
    required this.reason,
    required this.timeoutMinutes,
    required this.raisedAt,
    this.isAcknowledged = false,
    this.acknowledgedAt,
    this.acknowledgeNote,
  });

  LoopEscalationState copyWith({
    String? currentTargetUserId,
    bool? isAcknowledged,
    DateTime? acknowledgedAt,
    String? acknowledgeNote,
  }) {
    return LoopEscalationState(
      escalationId: escalationId,
      targetRole: targetRole,
      currentTargetUserId: currentTargetUserId ?? this.currentTargetUserId,
      reason: reason,
      timeoutMinutes: timeoutMinutes,
      raisedAt: raisedAt,
      isAcknowledged: isAcknowledged ?? this.isAcknowledged,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      acknowledgeNote: acknowledgeNote ?? this.acknowledgeNote,
    );
  }

  @override
  List<Object?> get props => [
    escalationId,
    targetRole,
    currentTargetUserId,
    reason,
    timeoutMinutes,
    raisedAt,
    isAcknowledged,
    acknowledgedAt,
    acknowledgeNote,
  ];
}

/// Current state projection of an Open Loop, reduced from its events.
///
/// Tech Arch Section 4.2 & PRD Section 6.
class LoopStateProjection extends Equatable {
  final String loopId;
  final String patientId;
  final String title;
  final String description;
  final LoopType loopType;
  final LoopUrgency urgency;
  final LoopState state;
  final String currentOwnerId;
  final String currentOwnerRole;
  final String? openedByUserId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ThreadMessage> messages;
  final ClosureReasonCode? closureReason;
  final String? closureNote;
  final ClosureResolutionType? resolutionType;
  final String? closedByUserId;
  final DateTime? closedAt;
  final String? confirmedByRole;
  final String? closureReasonText;
  final int reopenCount;
  final List<String> reopenReasons;
  final List<String> linkedLoopIds;
  final LoopEscalationState? activeEscalation;
  final Map<String, DateTime> readByUserIds;
  final Map<String, DateTime> acknowledgedByUserIds;

  const LoopStateProjection({
    required this.loopId,
    required this.patientId,
    required this.title,
    required this.description,
    required this.loopType,
    required this.urgency,
    required this.state,
    required this.currentOwnerId,
    required this.currentOwnerRole,
    this.openedByUserId,
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
    this.closureReason,
    this.closureNote,
    this.resolutionType,
    this.closedByUserId,
    this.closedAt,
    this.confirmedByRole,
    this.closureReasonText,
    this.reopenCount = 0,
    this.reopenReasons = const [],
    this.linkedLoopIds = const [],
    this.activeEscalation,
    this.readByUserIds = const {},
    this.acknowledgedByUserIds = const {},
  });

  bool get isOpen => state.isOpen;
  bool get isCritical => urgency == LoopUrgency.critical;

  LoopStateProjection copyWith({
    String? title,
    String? description,
    LoopType? loopType,
    LoopUrgency? urgency,
    LoopState? state,
    String? currentOwnerId,
    String? currentOwnerRole,
    String? openedByUserId,
    DateTime? updatedAt,
    List<ThreadMessage>? messages,
    ClosureReasonCode? closureReason,
    String? closureNote,
    ClosureResolutionType? resolutionType,
    String? closedByUserId,
    DateTime? closedAt,
    String? confirmedByRole,
    String? closureReasonText,
    int? reopenCount,
    List<String>? reopenReasons,
    List<String>? linkedLoopIds,
    LoopEscalationState? activeEscalation,
    Map<String, DateTime>? readByUserIds,
    Map<String, DateTime>? acknowledgedByUserIds,
  }) {
    return LoopStateProjection(
      loopId: loopId,
      patientId: patientId,
      title: title ?? this.title,
      description: description ?? this.description,
      loopType: loopType ?? this.loopType,
      urgency: urgency ?? this.urgency,
      state: state ?? this.state,
      currentOwnerId: currentOwnerId ?? this.currentOwnerId,
      currentOwnerRole: currentOwnerRole ?? this.currentOwnerRole,
      openedByUserId: openedByUserId ?? this.openedByUserId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      closureReason: closureReason ?? this.closureReason,
      closureNote: closureNote ?? this.closureNote,
      resolutionType: resolutionType ?? this.resolutionType,
      closedByUserId: closedByUserId ?? this.closedByUserId,
      closedAt: closedAt ?? this.closedAt,
      confirmedByRole: confirmedByRole ?? this.confirmedByRole,
      closureReasonText: closureReasonText ?? this.closureReasonText,
      reopenCount: reopenCount ?? this.reopenCount,
      reopenReasons: reopenReasons ?? this.reopenReasons,
      linkedLoopIds: linkedLoopIds ?? this.linkedLoopIds,
      activeEscalation: activeEscalation ?? this.activeEscalation,
      readByUserIds: readByUserIds ?? this.readByUserIds,
      acknowledgedByUserIds:
          acknowledgedByUserIds ?? this.acknowledgedByUserIds,
    );
  }

  @override
  List<Object?> get props => [
    loopId,
    patientId,
    title,
    description,
    loopType,
    urgency,
    state,
    currentOwnerId,
    currentOwnerRole,
    openedByUserId,
    createdAt,
    updatedAt,
    messages,
    closureReason,
    closureNote,
    resolutionType,
    closedByUserId,
    closedAt,
    confirmedByRole,
    closureReasonText,
    reopenCount,
    reopenReasons,
    linkedLoopIds,
    activeEscalation,
    readByUserIds,
    acknowledgedByUserIds,
  ];
}

/// Current state projection of a Patient, reduced from admission/transfer events.
///
/// Tech Arch Section 4.2 & PRD FR-2 & FR-3.
class PatientStateProjection extends Equatable {
  final String patientId;
  final String wardId;
  final String bedNumber;
  final String patientInitials;
  final int age;
  final String sex;
  final String shortAdmittingNote;
  final List<String> keyAlerts;
  final bool isDischarged;
  final String? dischargeDisposition;
  final DateTime admittedAt;
  final DateTime updatedAt;

  PatientStateProjection({
    required this.patientId,
    required this.wardId,
    required this.bedNumber,
    required String patientInitials,
    required this.age,
    required this.sex,
    required this.shortAdmittingNote,
    this.keyAlerts = const [],
    this.isDischarged = false,
    this.dischargeDisposition,
    required this.admittedAt,
    required this.updatedAt,
  }) : patientInitials = PatientIdentity.initialsFromLegacy(patientInitials);

  PatientStateProjection copyWith({
    String? wardId,
    String? bedNumber,
    String? patientInitials,
    int? age,
    String? sex,
    String? shortAdmittingNote,
    List<String>? keyAlerts,
    bool? isDischarged,
    String? dischargeDisposition,
    DateTime? updatedAt,
  }) {
    return PatientStateProjection(
      patientId: patientId,
      wardId: wardId ?? this.wardId,
      bedNumber: bedNumber ?? this.bedNumber,
      patientInitials: patientInitials == null
          ? this.patientInitials
          : PatientIdentity.initialsFromLegacy(patientInitials),
      age: age ?? this.age,
      sex: sex ?? this.sex,
      shortAdmittingNote: shortAdmittingNote ?? this.shortAdmittingNote,
      keyAlerts: keyAlerts ?? this.keyAlerts,
      isDischarged: isDischarged ?? this.isDischarged,
      dischargeDisposition: dischargeDisposition ?? this.dischargeDisposition,
      admittedAt: admittedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    patientId,
    wardId,
    bedNumber,
    patientInitials,
    age,
    sex,
    shortAdmittingNote,
    keyAlerts,
    isDischarged,
    dischargeDisposition,
    admittedAt,
    updatedAt,
  ];
}

/// Record of a single bed's review in a handoff session (PRD FR-11 & FR-14).
class HandoffBedReview extends Equatable {
  final String bedNumber;
  final String patientId;
  final bool nothingPendingConfirmed;
  final List<String> transferredLoopIds;
  final DateTime reviewedAt;

  const HandoffBedReview({
    required this.bedNumber,
    required this.patientId,
    required this.nothingPendingConfirmed,
    this.transferredLoopIds = const [],
    required this.reviewedAt,
  });

  @override
  List<Object?> get props => [
    bedNumber,
    patientId,
    nothingPendingConfirmed,
    transferredLoopIds,
    reviewedAt,
  ];
}

/// State projection of a shift handoff session (PRD Section 7.3 & FR-11 to FR-16).
class HandoffSessionProjection extends Equatable {
  final String handoffSessionId;
  final String wardId;
  final String outgoingNurseId;
  final String incomingNurseId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final bool isLocked;
  final Map<String, HandoffBedReview> bedReviews;
  final int totalBedsHandedOver;
  final int totalLoopsTransferred;

  const HandoffSessionProjection({
    required this.handoffSessionId,
    required this.wardId,
    required this.outgoingNurseId,
    required this.incomingNurseId,
    required this.startedAt,
    this.completedAt,
    this.isLocked = false,
    this.bedReviews = const {},
    this.totalBedsHandedOver = 0,
    this.totalLoopsTransferred = 0,
  });

  HandoffSessionProjection copyWith({
    DateTime? completedAt,
    bool? isLocked,
    Map<String, HandoffBedReview>? bedReviews,
    int? totalBedsHandedOver,
    int? totalLoopsTransferred,
  }) {
    return HandoffSessionProjection(
      handoffSessionId: handoffSessionId,
      wardId: wardId,
      outgoingNurseId: outgoingNurseId,
      incomingNurseId: incomingNurseId,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      isLocked: isLocked ?? this.isLocked,
      bedReviews: bedReviews ?? this.bedReviews,
      totalBedsHandedOver: totalBedsHandedOver ?? this.totalBedsHandedOver,
      totalLoopsTransferred:
          totalLoopsTransferred ?? this.totalLoopsTransferred,
    );
  }

  @override
  List<Object?> get props => [
    handoffSessionId,
    wardId,
    outgoingNurseId,
    incomingNurseId,
    startedAt,
    completedAt,
    isLocked,
    bedReviews,
    totalBedsHandedOver,
    totalLoopsTransferred,
  ];
}

/// Structured SBAR summary per patient compiled automatically from structured entries and open loops (PRD FR-13).
/// Situation, Background, Assessment, Recommendation layout without AI in v1.
class SbarSummary extends Equatable {
  final String situation;
  final String background;
  final String assessment;
  final String recommendation;

  const SbarSummary({
    required this.situation,
    required this.background,
    required this.assessment,
    required this.recommendation,
  });

  factory SbarSummary.fromPatientAndLoops({
    required PatientStateProjection patient,
    required List<LoopStateProjection> loops,
  }) {
    // 1. Situation: Patient identity, location, primary complaint/admitting note
    final situation =
        '${patient.bedNumber} — ${patient.patientInitials}, ${patient.age}y ${patient.sex}. Admitted for: ${patient.shortAdmittingNote}';

    // 2. Background: Clinical flags/alerts and admission timeline
    final alertsText = patient.keyAlerts.isNotEmpty
        ? 'Key alerts: ${patient.keyAlerts.join(", ")}.'
        : 'No specific alert flags recorded.';
    final background =
        'Admitted ${patient.admittedAt.toIso8601String().substring(0, 10)}. $alertsText';

    // 3. Assessment: Current pending loops breakdown by urgency
    final openLoops = loops.where((l) => l.isOpen).toList();
    final String assessment;
    if (openLoops.isEmpty) {
      assessment = 'ALL CLEAR: No open clinical loops pending.';
    } else {
      final criticalCount = openLoops
          .where((l) => l.urgency == LoopUrgency.critical)
          .length;
      final urgentCount = openLoops
          .where((l) => l.urgency == LoopUrgency.urgent)
          .length;
      final routineCount = openLoops
          .where((l) => l.urgency == LoopUrgency.routine)
          .length;

      final parts = <String>[];
      if (criticalCount > 0) parts.add('$criticalCount CRITICAL/STAT');
      if (urgentCount > 0) parts.add('$urgentCount Urgent');
      if (routineCount > 0) parts.add('$routineCount Routine');

      final titles = openLoops
          .map((l) => '[${l.urgency.name.toUpperCase()}] ${l.title}')
          .join('; ');
      assessment =
          '${openLoops.length} pending items (${parts.join(", ")}): $titles.';
    }

    // 4. Recommendation: Action items for the incoming shift
    final String recommendation;
    if (openLoops.isEmpty) {
      recommendation = 'Maintain routine baseline monitoring as charted.';
    } else {
      final actionItems = openLoops
          .map((l) {
            if (l.urgency == LoopUrgency.critical) {
              return 'ACTION STAT: Follow up "${l.title}" immediately';
            } else if (l.urgency == LoopUrgency.urgent) {
              return 'Prioritize: "${l.title}"';
            } else {
              return 'Routine follow up: "${l.title}"';
            }
          })
          .join('; ');
      recommendation = '$actionItems.';
    }

    return SbarSummary(
      situation: situation,
      background: background,
      assessment: assessment,
      recommendation: recommendation,
    );
  }

  @override
  List<Object?> get props => [
    situation,
    background,
    assessment,
    recommendation,
  ];
}
