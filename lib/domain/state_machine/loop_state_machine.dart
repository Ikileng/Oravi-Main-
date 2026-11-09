import '../models/loop_enums.dart';

/// Explicit validation error thrown when an illegal transition is attempted.
///
/// Tech Arch Section 5:
/// "The state machine is defined once as data (a table of allowed transitions)
/// and checked by both the phone and the server. A transition that is not allowed
/// is rejected with a reason and kept visible to the user, never dropped silently."
class InvalidLoopTransitionException implements Exception {
  final LoopState fromState;
  final String attemptedAction;
  final String reason;

  InvalidLoopTransitionException({
    required this.fromState,
    required this.attemptedAction,
    required this.reason,
  });

  @override
  String toString() =>
      'InvalidLoopTransitionException: Cannot perform "$attemptedAction" from state "${fromState.wireName}". Reason: $reason';
}

/// The deterministic state machine governing Open Loop lifecycles.
///
/// Enforces rules from PRD Section 6 & Tech Arch Section 5.
class LoopStateMachine {
  /// Evaluates and returns the next [LoopState] given the current state and incoming action.
  /// Throws [InvalidLoopTransitionException] if the transition is prohibited.
  static LoopState transitionOnClose({
    required LoopState currentState,
    required LoopUrgency urgency,
    ClosureReasonCode? reasonCode,
    String? closureReason,
    String? freeTextNote,
  }) {
    if (currentState.isTerminalClosed ||
        currentState == LoopState.closedAwaitingConfirmation) {
      throw InvalidLoopTransitionException(
        fromState: currentState,
        attemptedAction: 'close',
        reason: currentState.isTerminalClosed
            ? 'Loop is already closed.'
            : 'Critical closure is awaiting confirmation; confirm or reopen it.',
      );
    }

    if ((closureReason == null || closureReason.trim().isEmpty) &&
        reasonCode == null) {
      throw InvalidLoopTransitionException(
        fromState: currentState,
        attemptedAction: 'close',
        reason: 'A closure reason is required.',
      );
    }

    // Older stored events used a reason code and required a note for selected codes.
    if (closureReason == null &&
        reasonCode?.requiresFreeTextNote == true &&
        (freeTextNote == null || freeTextNote.trim().isEmpty)) {
      throw InvalidLoopTransitionException(
        fromState: currentState,
        attemptedAction: 'close',
        reason: 'A brief closure note is required for this legacy reason code.',
      );
    }

    // PRD Section 6 & FR-51: Critical (STAT) loops enter awaiting confirmation
    if (urgency == LoopUrgency.critical) {
      return LoopState.closedAwaitingConfirmation;
    }

    // Routine & Urgent loops transition immediately to closed
    return LoopState.closed;
  }

  /// Confirms closure of a Critical (STAT) loop that is in [LoopState.closedAwaitingConfirmation].
  static LoopState transitionOnConfirmClosure({
    required LoopState currentState,
  }) {
    if (currentState != LoopState.closedAwaitingConfirmation) {
      throw InvalidLoopTransitionException(
        fromState: currentState,
        attemptedAction: 'confirm_closure',
        reason:
            'Only loops in "closed_awaiting_confirmation" can have closure confirmed.',
      );
    }
    return LoopState.closed;
  }

  /// Reopens a closed or awaiting confirmation loop.
  static LoopState transitionOnReopen({
    required LoopState currentState,
    required String reopenReason,
  }) {
    if (currentState != LoopState.closed &&
        currentState != LoopState.closedAwaitingConfirmation) {
      throw InvalidLoopTransitionException(
        fromState: currentState,
        attemptedAction: 'reopen',
        reason: 'Only closed or awaiting-confirmation loops can be reopened.',
      );
    }
    if (reopenReason.trim().isEmpty) {
      throw InvalidLoopTransitionException(
        fromState: currentState,
        attemptedAction: 'reopen',
        reason: 'A reason is strictly required to reopen a loop.',
      );
    }
    return LoopState.raised;
  }

  /// Acknowledges an open loop (PRD Section 6).
  static LoopState transitionOnAcknowledge({required LoopState currentState}) {
    if (currentState != LoopState.raised) {
      throw InvalidLoopTransitionException(
        fromState: currentState,
        attemptedAction: 'acknowledge',
        reason:
            'Only loops in "raised" state can be transitioned to "acknowledged".',
      );
    }
    return LoopState.acknowledged;
  }

  /// Starts work on an open loop.
  static LoopState transitionOnStartWork({required LoopState currentState}) {
    // Replaying a duplicate start event must not make the whole ward projection
    // fail. The command layer prevents appending another start once work began.
    if (currentState == LoopState.inProgress) return LoopState.inProgress;
    if (currentState != LoopState.raised &&
        currentState != LoopState.acknowledged) {
      throw InvalidLoopTransitionException(
        fromState: currentState,
        attemptedAction: 'start_work',
        reason:
            'Cannot start work on a loop in state "${currentState.wireName}".',
      );
    }
    return LoopState.inProgress;
  }
}
