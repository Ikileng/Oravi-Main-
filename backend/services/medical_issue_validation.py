from typing import Iterable, Set

from backend.models import CanonicalEvent


_QUIET_READ_TYPES = {"LoopRead", "LoopUserAcknowledged"}
_ISSUE_EVENT_TYPES = {
    "LoopOpened",
    "LoopAcknowledged",
    "LoopRead",
    "LoopUserAcknowledged",
    "LoopWorkStarted",
    "LoopOwnerChanged",
    "MessagePosted",
    "CallLogged",
    "LoopClosed",
    "LoopClosureConfirmed",
    "LoopReopened",
    "LoopLinked",
    "EscalationRaised",
    "EscalationAcknowledged",
    "EscalationReassigned",
}


def _current_state(events: Iterable[CanonicalEvent]) -> str | None:
    state = None
    urgency = ""
    for event in events:
        payload = event.payload
        if event.type == "LoopOpened":
            state = "raised"
            urgency = str(payload.get("urgency") or "")
        elif event.type == "LoopAcknowledged":
            state = "acknowledged"
        elif event.type == "LoopWorkStarted":
            state = "in_progress"
        elif event.type == "LoopClosed":
            state = (
                "closed_awaiting_confirmation"
                if urgency == "critical"
                else "closed"
            )
        elif event.type == "LoopClosureConfirmed":
            state = "closed"
        elif event.type == "LoopReopened":
            state = "raised"
    return state


def open_medical_issue_ids(events: Iterable[CanonicalEvent]) -> set[str]:
    histories: dict[str, list[CanonicalEvent]] = {}
    for event in events:
        if event.loop_id:
            histories.setdefault(event.loop_id, []).append(event)
    return {
        loop_id
        for loop_id, history in histories.items()
        if _current_state(history)
        in {"raised", "acknowledged", "in_progress", "closed_awaiting_confirmation"}
    }


def carried_forward_owner_id(events: Iterable[CanonicalEvent]) -> str | None:
    for event in reversed(list(events)):
        if event.type != "LoopOwnerChanged":
            continue
        if event.payload.get("carry_forward") is True:
            owner_id = event.payload.get("new_owner_id")
            return owner_id if isinstance(owner_id, str) else None
        return None
    return None


def validate_medical_issue_event(
    history: list[CanonicalEvent],
    event: CanonicalEvent,
    authorized_staff_ids: Set[str],
    board_doctor_ids: Set[str],
) -> None:
    if event.type not in _ISSUE_EVENT_TYPES:
        return

    payload = event.payload
    if event.type == "LoopOpened":
        if history:
            raise ValueError("A Medical Issue ID can only be opened once.")
        if not str(payload.get("title") or "").strip():
            raise ValueError("A Medical Issue title is required.")
        if payload.get("urgency") not in {"routine", "urgent", "critical"}:
            raise ValueError("A valid Medical Issue urgency is required.")
        if payload.get("initial_owner_id") not in authorized_staff_ids:
            raise ValueError("The initial owner must have access to this patient.")
        return

    if not history or history[0].type != "LoopOpened":
        raise ValueError("A Medical Issue must be opened before it is updated.")

    state = _current_state(history)
    if event.type in _QUIET_READ_TYPES:
        return
    if event.type == "LoopAcknowledged":
        if state != "raised":
            raise ValueError("Only a raised issue can be acknowledged.")
        return
    if event.type == "LoopWorkStarted":
        if state not in {"raised", "acknowledged"}:
            raise ValueError("Only an open issue can be started.")
        return
    if event.type == "LoopOwnerChanged":
        if state not in {
            "raised",
            "acknowledged",
            "in_progress",
            "closed_awaiting_confirmation",
        }:
            raise ValueError("Only an open issue can be reassigned.")
        carry_forward = payload.get("carry_forward") is True
        if payload.get("new_owner_id") not in authorized_staff_ids:
            raise ValueError("The new owner must have access to this patient.")
        if (
            not carry_forward
            and not str(payload.get("transfer_reason") or "").strip()
        ):
            raise ValueError("A reassignment reason is required.")
        return
    if event.type == "MessagePosted":
        if state not in {"raised", "acknowledged", "in_progress"}:
            raise ValueError("Messages can only be added to an open issue.")
        if not str(payload.get("content") or "").strip():
            raise ValueError("A Medical Issue message cannot be empty.")
        mentions = set(payload.get("mentioned_staff_ids") or [])
        if not mentions.issubset(authorized_staff_ids):
            raise ValueError("Every mentioned clinician must have patient access.")
        return
    if event.type == "CallLogged":
        if state not in {"raised", "acknowledged", "in_progress"}:
            raise ValueError("A call can only be logged on an open issue.")
        return
    if event.type == "LoopClosed":
        if state not in {"raised", "acknowledged", "in_progress"}:
            raise ValueError("Only an open issue can be closed.")
        closure_reason = payload.get("closure_reason")
        reason_code = payload.get("reason_code")
        if not str(closure_reason or "").strip() and not reason_code:
            raise ValueError("A free-text closure reason is required.")
        if not closure_reason and reason_code in {
            "medication_given",
            "action_taken",
            "other",
        } and not str(payload.get("free_text_note") or "").strip():
            raise ValueError("This legacy closure reason requires a clinical note.")
        outcome = payload.get("resolution_type", "resolved")
        if outcome not in {"resolved", "closed_without_resolution"}:
            raise ValueError("A valid closure outcome is required.")
        return
    if event.type == "LoopClosureConfirmed":
        if state != "closed_awaiting_confirmation":
            raise ValueError("Only a critical closure can be confirmed.")
        if event.author_id not in board_doctor_ids:
            raise ValueError("Only the board-assigned doctor can confirm closure.")
        return
    if event.type == "LoopReopened":
        if state not in {"closed", "closed_awaiting_confirmation"}:
            raise ValueError("Only a closed issue can be reopened.")
        if not str(payload.get("reopen_reason") or "").strip():
            raise ValueError("A reason is required to reopen an issue.")
        return
    if event.type == "LoopLinked":
        if not history:
            raise ValueError("A Medical Issue must exist before it can be linked.")
        return
    if event.type in {"EscalationRaised", "EscalationAcknowledged", "EscalationReassigned"}:
        if state not in {"raised", "acknowledged", "in_progress"}:
            raise ValueError("Escalation actions require an open issue.")
