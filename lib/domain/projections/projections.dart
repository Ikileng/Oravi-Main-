import 'package:equatable/equatable.dart';
import '../models/loop_enums.dart';

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
  final bool isCallLog;
  final String? callRecipientId;
  final String? callRecipientRole;

  const ThreadMessage({
    required this.messageId,
    required this.authorId,
    this.authorRole = 'ward_nurse',
    required this.deviceId,
    required this.content,
    required this.createdAt,
    this.editedAt,
    this.previousContent,
    this.quotedMessageId,
    this.roleMentions = const [],
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
      deviceId: deviceId,
      content: content ?? this.content,
      createdAt: createdAt,
      editedAt: editedAt ?? this.editedAt,
      previousContent: previousContent ?? this.previousContent,
      quotedMessageId: quotedMessageId,
      roleMentions: roleMentions,
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
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ThreadMessage> messages;
  final ClosureReasonCode? closureReason;
  final String? closureNote;
  final ClosureResolutionType? resolutionType;
  final String? closedByUserId;
  final DateTime? closedAt;
  final String? confirmedByRole;
  final int reopenCount;
  final List<String> reopenReasons;
  final List<String> linkedLoopIds;
  final LoopEscalationState? activeEscalation;

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
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
    this.closureReason,
    this.closureNote,
    this.resolutionType,
    this.closedByUserId,
    this.closedAt,
    this.confirmedByRole,
    this.reopenCount = 0,
    this.reopenReasons = const [],
    this.linkedLoopIds = const [],
    this.activeEscalation,
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
    DateTime? updatedAt,
    List<ThreadMessage>? messages,
    ClosureReasonCode? closureReason,
    String? closureNote,
    ClosureResolutionType? resolutionType,
    String? closedByUserId,
    DateTime? closedAt,
    String? confirmedByRole,
    int? reopenCount,
    List<String>? reopenReasons,
    List<String>? linkedLoopIds,
    LoopEscalationState? activeEscalation,
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
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      closureReason: closureReason ?? this.closureReason,
      closureNote: closureNote ?? this.closureNote,
      resolutionType: resolutionType ?? this.resolutionType,
      closedByUserId: closedByUserId ?? this.closedByUserId,
      closedAt: closedAt ?? this.closedAt,
      confirmedByRole: confirmedByRole ?? this.confirmedByRole,
      reopenCount: reopenCount ?? this.reopenCount,
      reopenReasons: reopenReasons ?? this.reopenReasons,
      linkedLoopIds: linkedLoopIds ?? this.linkedLoopIds,
      activeEscalation: activeEscalation ?? this.activeEscalation,
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
        createdAt,
        updatedAt,
        messages,
        closureReason,
        closureNote,
        resolutionType,
        closedByUserId,
        closedAt,
        confirmedByRole,
        reopenCount,
        reopenReasons,
        linkedLoopIds,
        activeEscalation,
      ];
}

/// Current state projection of a Patient, reduced from admission/transfer events.
///
/// Tech Arch Section 4.2 & PRD FR-2 & FR-3.
class PatientStateProjection extends Equatable {
  final String patientId;
  final String wardId;
  final String bedNumber;
  final String admissionNumber; // Second required identifier (FR-3)
  final String nameOrInitials;
  final int age;
  final String sex;
  final String shortAdmittingNote;
  final List<String> keyAlerts;
  final bool isDischarged;
  final String? dischargeDisposition;
  final DateTime admittedAt;
  final DateTime updatedAt;

  const PatientStateProjection({
    required this.patientId,
    required this.wardId,
    required this.bedNumber,
    required this.admissionNumber,
    required this.nameOrInitials,
    required this.age,
    required this.sex,
    required this.shortAdmittingNote,
    this.keyAlerts = const [],
    this.isDischarged = false,
    this.dischargeDisposition,
    required this.admittedAt,
    required this.updatedAt,
  });

  PatientStateProjection copyWith({
    String? wardId,
    String? bedNumber,
    String? admissionNumber,
    String? nameOrInitials,
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
      admissionNumber: admissionNumber ?? this.admissionNumber,
      nameOrInitials: nameOrInitials ?? this.nameOrInitials,
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
        admissionNumber,
        nameOrInitials,
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
