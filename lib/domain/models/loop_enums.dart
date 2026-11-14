/// Domain-level value objects and enums for Oravi.
///
/// Implemented in pure Dart with zero Flutter/UI dependencies, strictly following
/// the Oravi PRD v0.1 and Technical Architecture v0.1.
library;

/// Urgency levels for an open loop (PRD Section 6).
enum LoopUrgency {
  routine,
  urgent,
  critical; // STAT level; triggers confirmation gate on closure (PRD FR-51)

  static LoopUrgency fromString(String value) {
    switch (value.toLowerCase()) {
      case 'critical':
      case 'stat':
        return LoopUrgency.critical;
      case 'urgent':
        return LoopUrgency.urgent;
      case 'routine':
      default:
        return LoopUrgency.routine;
    }
  }

  String get wireName {
    switch (this) {
      case LoopUrgency.critical:
        return 'critical';
      case LoopUrgency.urgent:
        return 'urgent';
      case LoopUrgency.routine:
        return 'routine';
    }
  }
}

/// Category/type of an open loop (PRD Section 6).
enum LoopType {
  taskOrPendingResult,
  questionOrClarification,
  escalation,
  consultRequest,
  riskFlag;

  static LoopType fromString(String value) {
    switch (value) {
      case 'task_or_pending_result':
      case 'taskOrPendingResult':
        return LoopType.taskOrPendingResult;
      case 'question_or_clarification':
      case 'questionOrClarification':
        return LoopType.questionOrClarification;
      case 'escalation':
        return LoopType.escalation;
      case 'consult_request':
      case 'consultRequest':
        return LoopType.consultRequest;
      case 'risk_flag':
      case 'riskFlag':
        return LoopType.riskFlag;
      default:
        return LoopType.taskOrPendingResult;
    }
  }

  String get wireName {
    switch (this) {
      case LoopType.taskOrPendingResult:
        return 'task_or_pending_result';
      case LoopType.questionOrClarification:
        return 'question_or_clarification';
      case LoopType.escalation:
        return 'escalation';
      case LoopType.consultRequest:
        return 'consult_request';
      case LoopType.riskFlag:
        return 'risk_flag';
    }
  }
}

/// Lifecycle states of an open loop (PRD Section 6 & Tech Arch Section 5).
enum LoopState {
  raised,
  acknowledged,
  inProgress,
  closedAwaitingConfirmation, // Critical/STAT loops pass through this state (FR-51)
  closed;

  bool get isOpen =>
      this == LoopState.raised ||
      this == LoopState.acknowledged ||
      this == LoopState.inProgress ||
      this == LoopState.closedAwaitingConfirmation;

  bool get isTerminalClosed => this == LoopState.closed;

  static LoopState fromString(String value) {
    switch (value) {
      case 'raised':
        return LoopState.raised;
      case 'acknowledged':
        return LoopState.acknowledged;
      case 'in_progress':
      case 'inProgress':
        return LoopState.inProgress;
      case 'closed_awaiting_confirmation':
      case 'closedAwaitingConfirmation':
        return LoopState.closedAwaitingConfirmation;
      case 'closed':
        return LoopState.closed;
      default:
        return LoopState.raised;
    }
  }

  String get wireName {
    switch (this) {
      case LoopState.raised:
        return 'raised';
      case LoopState.acknowledged:
        return 'acknowledged';
      case LoopState.inProgress:
        return 'in_progress';
      case LoopState.closedAwaitingConfirmation:
        return 'closed_awaiting_confirmation';
      case LoopState.closed:
        return 'closed';
    }
  }
}

/// Closure resolution classification (PRD FR-47).
enum ClosureResolutionType {
  resolved,
  closedWithoutResolution;

  static ClosureResolutionType fromString(String value) {
    if (value == 'closed_without_resolution' || value == 'closedWithoutResolution') {
      return ClosureResolutionType.closedWithoutResolution;
    }
    return ClosureResolutionType.resolved;
  }

  String get wireName {
    switch (this) {
      case ClosureResolutionType.resolved:
        return 'resolved';
      case ClosureResolutionType.closedWithoutResolution:
        return 'closed_without_resolution';
    }
  }
}

/// Pre-defined standard closure reasons (PRD FR-46).
/// Note: Reason chips never carry clinical judgment (e.g. 'result received', not 'result normal').
enum ClosureReasonCode {
  medicationGiven,
  resultReceived,
  doctorReviewed,
  actionTaken,
  duplicateOrCreatedInError,
  other;

  /// Returns true if a brief free-text note is strictly mandatory for this reason (PRD FR-46).
  bool get requiresFreeTextNote {
    return this == ClosureReasonCode.medicationGiven ||
        this == ClosureReasonCode.actionTaken ||
        this == ClosureReasonCode.other;
  }

  static ClosureReasonCode fromString(String value) {
    switch (value) {
      case 'medication_given':
      case 'medicationGiven':
        return ClosureReasonCode.medicationGiven;
      case 'result_received':
      case 'resultReceived':
        return ClosureReasonCode.resultReceived;
      case 'doctor_reviewed':
      case 'doctorReviewed':
        return ClosureReasonCode.doctorReviewed;
      case 'action_taken':
      case 'actionTaken':
        return ClosureReasonCode.actionTaken;
      case 'duplicate_or_created_in_error':
      case 'duplicateOrCreatedInError':
        return ClosureReasonCode.duplicateOrCreatedInError;
      case 'other':
      default:
        return ClosureReasonCode.other;
    }
  }

  String get wireName {
    switch (this) {
      case ClosureReasonCode.medicationGiven:
        return 'medication_given';
      case ClosureReasonCode.resultReceived:
        return 'result_received';
      case ClosureReasonCode.doctorReviewed:
        return 'doctor_reviewed';
      case ClosureReasonCode.actionTaken:
        return 'action_taken';
      case ClosureReasonCode.duplicateOrCreatedInError:
        return 'duplicate_or_created_in_error';
      case ClosureReasonCode.other:
        return 'other';
    }
  }
}
