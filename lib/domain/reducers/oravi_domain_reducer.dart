import '../events/domain_events.dart';
import '../events/oravi_event.dart';
import '../models/loop_enums.dart';
import '../projections/projections.dart';
import '../state_machine/loop_state_machine.dart';

/// Pure functional reducer that folds an event sequence into current domain state.
///
/// Tech Arch Section 4.3:
/// "The phone recomputes projections locally from its events, so it works offline.
/// A shared conformance suite of JSON fixtures runs in both test suites on every change."
class OraviDomainReducer {
  /// Reduces a list of events for a single loop into its [LoopStateProjection].
  static LoopStateProjection? reduceLoopEvents(
    Iterable<OraviEvent> events, {
    LoopStateProjection? initialProjection,
  }) {
    LoopStateProjection? current = initialProjection;

    for (final event in events) {
      if (event is LoopOpenedEvent) {
        if (current != null) {
          throw InvalidLoopTransitionException(
            fromState: current.state,
            attemptedAction: 'raise',
            reason: 'A loop with this identifier has already been opened.',
          );
        }
        current = LoopStateProjection(
          loopId: event.loopId!,
          patientId: event.patientId,
          title: event.title,
          description: event.description,
          loopType: event.loopType,
          urgency: event.urgency,
          state: LoopState.raised,
          currentOwnerId: event.initialOwnerId,
          currentOwnerRole: event.initialOwnerRole,
          openedByUserId: event.authorId,
          createdAt: event.clientCreatedAt,
          updatedAt: event.clientCreatedAt,
          linkedLoopIds: event.linkedLoopId != null
              ? [event.linkedLoopId!]
              : const [],
        );
      } else if (current != null && event.loopId == current.loopId) {
        if (event is LoopAcknowledgedEvent) {
          final nextState = LoopStateMachine.transitionOnAcknowledge(
            currentState: current.state,
          );
          current = current.copyWith(
            state: nextState,
            updatedAt: event.clientCreatedAt,
          );
        } else if (event is LoopWorkStartedEvent) {
          final nextState = LoopStateMachine.transitionOnStartWork(
            currentState: current.state,
          );
          current = current.copyWith(
            state: nextState,
            updatedAt: event.clientCreatedAt,
          );
        } else if (event is LoopOwnerChangedEvent) {
          if (current.state == LoopState.closed ||
              current.state == LoopState.closedAwaitingConfirmation) {
            throw InvalidLoopTransitionException(
              fromState: current.state,
              attemptedAction: 'change_owner',
              reason: 'Only an active issue can be reassigned.',
            );
          }
          current = current.copyWith(
            currentOwnerId: event.newOwnerId,
            currentOwnerRole: event.newOwnerRole,
            updatedAt: event.clientCreatedAt,
          );
        } else if (event is MessagePostedEvent) {
          final message = ThreadMessage(
            messageId: event.messageId,
            authorId: event.authorId,
            deviceId: event.deviceId,
            content: event.content,
            createdAt: event.clientCreatedAt,
            quotedMessageId: event.quotedMessageId,
            roleMentions: event.roleMentions,
          );
          current = current.copyWith(
            messages: [...current.messages, message],
            updatedAt: event.clientCreatedAt,
          );
        } else if (event is CallLoggedEvent) {
          final callMessage = ThreadMessage(
            messageId: event.callId,
            authorId: event.callerId,
            authorRole: event.callerRole,
            deviceId: event.deviceId,
            content:
                '📞 Call with ${event.recipientId} (${event.recipientRole}): "${event.outcomeNote}"',
            createdAt: event.clientCreatedAt,
            isCallLog: true,
            callRecipientId: event.recipientId,
            callRecipientRole: event.recipientRole,
          );
          current = current.copyWith(
            messages: [...current.messages, callMessage],
            updatedAt: event.clientCreatedAt,
          );
        } else if (event is MessageEditedEvent) {
          final updatedMessages = current.messages.map((m) {
            if (m.messageId == event.messageId) {
              return m.copyWith(
                content: event.newContent,
                previousContent: event.previousContent,
                editedAt: event.clientCreatedAt,
              );
            }
            return m;
          }).toList();
          current = current.copyWith(
            messages: updatedMessages,
            updatedAt: event.clientCreatedAt,
          );
        } else if (event is LoopClosedEvent) {
          final nextState = LoopStateMachine.transitionOnClose(
            currentState: current.state,
            urgency: current.urgency,
            reasonCode: event.reasonCode,
            freeTextNote: event.freeTextNote,
          );
          current = current.copyWith(
            state: nextState,
            closureReason: event.reasonCode,
            closureNote: event.freeTextNote,
            resolutionType: event.resolutionType,
            closedByUserId: event.authorId,
            closedAt: event.clientCreatedAt,
            updatedAt: event.clientCreatedAt,
          );
        } else if (event is LoopClosureConfirmedEvent) {
          final nextState = LoopStateMachine.transitionOnConfirmClosure(
            currentState: current.state,
          );
          current = current.copyWith(
            state: nextState,
            confirmedByRole: event.confirmedByRole,
            updatedAt: event.clientCreatedAt,
          );
        } else if (event is LoopReopenedEvent) {
          final nextState = LoopStateMachine.transitionOnReopen(
            currentState: current.state,
            reopenReason: event.reopenReason,
          );
          current = current.copyWith(
            state: nextState,
            reopenCount: current.reopenCount + 1,
            reopenReasons: [...current.reopenReasons, event.reopenReason],
            updatedAt: event.clientCreatedAt,
          );
        } else if (event is LoopLinkedEvent) {
          current = current.copyWith(
            linkedLoopIds: [...current.linkedLoopIds, event.targetLoopId],
            updatedAt: event.clientCreatedAt,
          );
        } else if (event is EscalationRaisedEvent) {
          current = current.copyWith(
            activeEscalation: LoopEscalationState(
              escalationId: event.escalationId,
              targetRole: event.targetRole,
              currentTargetUserId: event.initialTargetUserId,
              reason: event.escalationReason,
              timeoutMinutes: event.timeoutMinutes,
              raisedAt: event.clientCreatedAt,
            ),
            updatedAt: event.clientCreatedAt,
          );
        } else if (event is EscalationAcknowledgedEvent) {
          if (current.activeEscalation != null &&
              current.activeEscalation!.escalationId == event.escalationId) {
            current = current.copyWith(
              activeEscalation: current.activeEscalation!.copyWith(
                isAcknowledged: true,
                acknowledgedAt: event.clientCreatedAt,
                acknowledgeNote: event.note,
              ),
              updatedAt: event.clientCreatedAt,
            );
          }
        } else if (event is EscalationPassedOnEvent) {
          if (current.activeEscalation != null &&
              current.activeEscalation!.escalationId == event.escalationId) {
            current = current.copyWith(
              activeEscalation: current.activeEscalation!.copyWith(
                currentTargetUserId: event.nextTargetUserId,
              ),
              updatedAt: event.clientCreatedAt,
            );
          }
        }
      }
    }

    return current;
  }

  /// Reduces a list of events for a patient into their [PatientStateProjection].
  static PatientStateProjection? reducePatientEvents(
    Iterable<OraviEvent> events, {
    PatientStateProjection? initialProjection,
  }) {
    PatientStateProjection? current = initialProjection;

    for (final event in events) {
      if (event is PatientAdmittedEvent) {
        current = PatientStateProjection(
          patientId: event.patientId,
          wardId: event.wardId,
          bedNumber: event.bedNumber,
          patientInitials: event.patientInitials,
          age: event.age,
          sex: event.sex,
          shortAdmittingNote: event.shortAdmittingNote,
          keyAlerts: event.keyAlerts,
          admittedAt: event.clientCreatedAt,
          updatedAt: event.clientCreatedAt,
        );
      } else if (current != null && event.patientId == current.patientId) {
        if (event is PatientTransferredEvent) {
          current = current.copyWith(
            wardId: event.toWardId,
            bedNumber: event.toBedNumber,
            updatedAt: event.clientCreatedAt,
          );
        } else if (event is PatientDischargedEvent) {
          current = current.copyWith(
            isDischarged: true,
            dischargeDisposition: event.dischargeDisposition,
            updatedAt: event.clientCreatedAt,
          );
        }
      }
    }

    return current;
  }

  /// Reduces a list of handoff events into a [HandoffSessionProjection].
  static HandoffSessionProjection? reduceHandoffEvents(
    Iterable<OraviEvent> events, {
    HandoffSessionProjection? initialProjection,
  }) {
    HandoffSessionProjection? current = initialProjection;

    for (final event in events) {
      if (event is HandoffStartedEvent) {
        current = HandoffSessionProjection(
          handoffSessionId: event.handoffSessionId,
          wardId: event.wardId,
          outgoingNurseId: event.outgoingNurseId,
          incomingNurseId: event.incomingNurseId,
          startedAt: event.clientCreatedAt,
        );
      } else if (current != null) {
        if (event is HandoffBedAcceptedEvent &&
            event.handoffSessionId == current.handoffSessionId) {
          final review = HandoffBedReview(
            bedNumber: event.bedNumber,
            patientId: event.patientId,
            nothingPendingConfirmed: event.nothingPendingConfirmed,
            transferredLoopIds: event.transferredLoopIds,
            reviewedAt: event.clientCreatedAt,
          );
          final updatedReviews = Map<String, HandoffBedReview>.from(
            current.bedReviews,
          );
          updatedReviews[event.bedNumber] = review;
          current = current.copyWith(
            bedReviews: updatedReviews,
            totalBedsHandedOver: updatedReviews.length,
            totalLoopsTransferred: updatedReviews.values
                .map((r) => r.transferredLoopIds.length)
                .fold<int>(0, (a, b) => a + b),
          );
        } else if (event is HandoffCompletedEvent &&
            event.handoffSessionId == current.handoffSessionId) {
          current = current.copyWith(
            isLocked: true,
            completedAt: event.clientCreatedAt,
            totalBedsHandedOver: event.totalBedsHandedOver,
            totalLoopsTransferred: event.totalLoopsTransferred,
          );
        }
      }
    }

    return current;
  }
}
