import asyncio
import sys
from .staff_roles import CLINICAL_ROLES, PROVISIONABLE_ROLES
from .communications import CommunicationsStore, build_router
from .inbox import build_inbox_router
from .notebook import NotebookStore, build_notebook_router
from .ward_transfers import build_transfer_router
import logging
import os
from pathlib import Path
from dotenv import load_dotenv

# Explicit environment values take precedence over local development settings.
load_dotenv(Path(__file__).with_name('.env'), override=False)
import secrets
import sqlite3
import uuid
from datetime import date
from typing import List, Optional
from fastapi import FastAPI, Query, HTTPException, Header, Depends, status
from .models import (
    CanonicalEvent, SyncPushRequest, SyncPushResponse, SyncPullResponse, AskRequest, AskResponse,
    StaffLoginRequest, StaffLoginResponse, CreateStaffRequest, StaffListResponse, StaffProfile,
    HospitalWardModel, ShiftAllocationModel, AllocationConflictCheckResponse, WardConfigurationRequest
)
from .event_store import EventStore
from .call_store import CallStore
from .staff_store import StaffStore
from .ward_store import WardStore
from .services.llm_service import LLMService
from .services.fcm_service import FcmService
from .services.medical_issue_validation import (
    carried_forward_owner_id,
    open_medical_issue_ids,
    validate_medical_issue_event,
)

app = FastAPI(
    title="Oravi Ward Sync and Clinical Auth API",
    description="Offline-first clinical event stream, hash chain and Digital ID authentication backend",
    version="0.3.0",
)

database_path = os.environ.get("ORAVI_DATABASE_PATH") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "oravi_server.db"
)

store = EventStore(db_path=database_path)
staff_store = StaffStore(db_path=database_path)
ward_store = WardStore(db_path=database_path)
llm_service = LLMService(store=store)
fcm_service = FcmService()
call_store = CallStore(db_path=database_path)
communications_store = CommunicationsStore(database_path)
notebook_store = NotebookStore(database_path)
logger = logging.getLogger(__name__)


def require_authenticated_staff(authorization: str = Header(default="")) -> StaffProfile:
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Sign-in required.")
    profile = staff_store.get_session(token)
    if profile is None:
        raise HTTPException(status_code=401, detail="Session is invalid or expired.")
    return profile


def require_staff(profile: StaffProfile = Depends(require_authenticated_staff)) -> StaffProfile:
    if profile.role not in CLINICAL_ROLES:
        raise HTTPException(status_code=403, detail='Clinical access is not available to this account.')
    return profile


def require_communicating_staff(profile: StaffProfile = Depends(require_authenticated_staff)) -> StaffProfile:
    if profile.role not in PROVISIONABLE_ROLES:
        raise HTTPException(403, 'Staff communications access required.')
    return profile


def require_dev_admin(profile: StaffProfile = Depends(require_authenticated_staff)) -> StaffProfile:
    if profile.role != "dev_admin":
        raise HTTPException(status_code=403, detail="Dev Admin access required.")
    return profile


def require_charge_nurse(profile: StaffProfile = Depends(require_staff)) -> StaffProfile:
    if profile.role != "charge_nurse":
        raise HTTPException(status_code=403, detail="Charge Nurse access required.")
    return profile


def _staff_can_access_ward(
    profile: StaffProfile, ward_id: str, assignment_date: str
) -> bool:
    if profile.role == "charge_nurse":
        return staff_store.get_ward_preference(profile.staff_id) == ward_id
    return ward_store.has_staff_assignment_on_date(
        profile.staff_id, ward_id, assignment_date
    )


def _patient_assignment_for_user(
    profile: StaffProfile, patient_id: str, assignment_date: str
):
    assignment = ward_store.get_patient_assignment(patient_id, assignment_date)
    if assignment is None:
        return None
    if profile.role == "charge_nurse":
        if staff_store.get_ward_preference(profile.staff_id) == assignment["ward_id"]:
            return assignment
        return None
    if (
        profile.staff_id in assignment["staff_ids"]
        and staff_store.is_active_clinical_staff(profile.staff_id)
    ):
        return assignment
    return None


def _staff_can_access_patient(
    profile: StaffProfile, patient_id: str, assignment_date: str
) -> bool:
    return _patient_assignment_for_user(profile, patient_id, assignment_date) is not None


def _staff_can_access_carried_issue(
    staff_id: str, patient_id: str, loop_id: str
) -> bool:
    if not staff_store.is_active_clinical_staff(staff_id):
        return False
    history = store.get_loop_events(patient_id, loop_id)
    return carried_forward_owner_id(history) == staff_id


def _authorized_patient_staff_ids(patient_id: str, assignment_date: str) -> set[str]:
    assignment = ward_store.get_patient_assignment(patient_id, assignment_date)
    if assignment is None:
        return set()
    staff_ids = set(assignment["staff_ids"])
    charge_nurses = staff_store.get_charge_nurses_for_ward(assignment["ward_id"])
    staff_ids.update(charge_nurse.staff_id for charge_nurse in charge_nurses)
    return {
        staff_id
        for staff_id in staff_ids
        if staff_store.is_active_clinical_staff(staff_id)
        or staff_id in {nurse.staff_id for nurse in charge_nurses}
    }


def _notification_recipients_for_events(events) -> dict[str, list[str]]:
    histories: dict[tuple[str, str], list] = {}
    recipients_by_event: dict[str, list[str]] = {}
    quiet_event_types = {
        "LoopRead",
        "LoopUserAcknowledged",
        "LoopAcknowledged",
    }
    for event in events:
        if not event.loop_id or event.type in quiet_event_types:
            continue
        issue_key = (event.patient_id, event.loop_id)
        history = histories.get(issue_key)
        if history is None:
            history = store.get_loop_events(*issue_key)
        assignment_date = event.client_created_at[:10]
        authorized = _authorized_patient_staff_ids(
            event.patient_id, assignment_date
        )
        if not authorized:
            carried_owner = carried_forward_owner_id(history)
            if carried_owner and staff_store.is_active_clinical_staff(
                carried_owner
            ):
                authorized = {carried_owner}
        participants: set[str] = set()
        mentioned: set[str] = set()
        owner_id = event.author_id
        urgency = ""
        for prior in history:
            if prior.type == "LoopOpened":
                owner_id = str(
                    prior.payload.get("initial_owner_id") or prior.author_id
                )
                urgency = str(prior.payload.get("urgency") or "")
            elif prior.type == "LoopOwnerChanged":
                owner_id = str(prior.payload.get("new_owner_id") or owner_id)
            if prior.type not in quiet_event_types:
                participants.add(prior.author_id)
            mentioned.update(
                str(staff_id)
                for staff_id in prior.payload.get("mentioned_staff_ids", [])
                if staff_id
            )

        participants.add(event.author_id)
        mentioned.update(
            str(staff_id)
            for staff_id in event.payload.get("mentioned_staff_ids", [])
            if staff_id
        )
        if event.type == "LoopOwnerChanged":
            owner_id = str(event.payload.get("new_owner_id") or owner_id)
            participants.add(owner_id)

        if event.type == "LoopOpened":
            owner_id = str(event.payload.get("initial_owner_id") or event.author_id)
            urgency = str(event.payload.get("urgency") or "")
            all_clinicians = set(authorized)
            recipients = all_clinicians
        elif urgency == "critical":
            recipients = set(authorized)
        else:
            recipients = {owner_id, *participants, *mentioned, event.author_id}

        recipients_by_event[event.event_id] = sorted((recipients & authorized) - {event.author_id})
        history = [*history, event]
        histories[issue_key] = history
    return recipients_by_event


def _validate_patient_issue_events(
    events, allowed_carry_forward_event_ids: Optional[set[str]] = None
) -> None:
    allowed_carry_forward_event_ids = allowed_carry_forward_event_ids or set()
    histories: dict[tuple[str, str], list] = {}
    for event in events:
        if not event.loop_id:
            continue
        is_carry_forward = event.payload.get("carry_forward") is True
        if (
            is_carry_forward
            and event.event_id not in allowed_carry_forward_event_ids
        ):
            raise HTTPException(
                status_code=403,
                detail="Carry-forward ownership must be recorded with the board update.",
            )
        issue_key = (event.patient_id, event.loop_id)
        history = histories.get(issue_key)
        if history is None:
            history = store.get_loop_events(*issue_key)
        if any(prior.event_id == event.event_id for prior in history):
            continue
        assignment = ward_store.get_patient_assignment(
            event.patient_id, event.client_created_at[:10]
        )
        if assignment is None:
            if not _staff_can_access_carried_issue(
                event.author_id,
                event.patient_id,
                event.loop_id,
            ):
                raise HTTPException(
                    status_code=403,
                    detail="Medical Issues require a current board assignment or carried ownership.",
                )
            authorized_staff_ids = {event.author_id}
            profile = staff_store.get_active_staff_by_ids([event.author_id])[0]
            board_doctor_ids = (
                {event.author_id} if profile.role == "doctor_on_call" else set()
            )
        else:
            authorized_staff_ids = set(assignment["staff_ids"])
            charge_nurses = staff_store.get_charge_nurses_for_ward(
                assignment["ward_id"]
            )
            authorized_staff_ids.update(item.staff_id for item in charge_nurses)
            authorized_staff_ids = {
                staff_id
                for staff_id in authorized_staff_ids
                if staff_store.is_active_clinical_staff(staff_id)
                or staff_id in {item.staff_id for item in charge_nurses}
            }
            board_doctor_ids = set(assignment["doctor_ids"])
        if is_carry_forward:
            target_owner = event.payload.get("new_owner_id")
            if (
                not isinstance(target_owner, str)
                or not staff_store.is_active_clinical_staff(target_owner)
            ):
                raise HTTPException(
                    status_code=409,
                    detail="The carried issue owner must be an active clinician.",
                )
            authorized_staff_ids.add(target_owner)
        try:
            validate_medical_issue_event(
                history,
                event,
                authorized_staff_ids,
                board_doctor_ids,
            )
        except ValueError as error:
            raise HTTPException(status_code=409, detail=str(error)) from error
        history = [*history, event]
        histories[issue_key] = history


def _carried_forward_issue_references(
    staff_id: str,
    ward_id: str | None = None,
    *,
    include_events: bool = False,
):
    references = []
    for patient_id, loop_id in store.get_carried_forward_issue_candidates(staff_id):
        history = store.get_loop_events(patient_id, loop_id)
        if carried_forward_owner_id(history) != staff_id:
            continue
        issue_ward_id = store.get_patient_ward(patient_id)
        if not issue_ward_id or (ward_id and issue_ward_id != ward_id):
            continue
        opened = next(
            (event for event in history if event.type == "LoopOpened"),
            None,
        )
        if opened is None:
            continue
        reference = {
            "patient_id": patient_id,
            "ward_id": issue_ward_id,
            "loop_id": loop_id,
            "title": str(opened.payload.get("title") or "Medical Issue"),
            "urgency": str(opened.payload.get("urgency") or "routine"),
            "is_open": loop_id in open_medical_issue_ids(history),
        }
        if include_events:
            reference["events"] = [event.to_dict() for event in history]
        references.append(reference)
    return references


def _dispatch_due_medical_issue_notifications() -> None:
    for notification in store.get_due_medical_issue_notifications():
        notification_id = int(notification["notification_id"])
        staff_id = str(notification["staff_id"])
        fids = staff_store.get_fcm_fids_for_staff(staff_id)
        delivered_fids = store.get_delivered_medical_issue_fids(notification_id)
        if not fids and not delivered_fids:
            store.mark_medical_issue_notification_failed(
                notification_id, "Recipient has no registered installation."
            )
            continue
        delivery_errors = set()
        for fid in fids:
            if fid in delivered_fids:
                continue
            try:
                delivered = fcm_service.send_medical_issue_alert(
                    fid,
                    str(notification["patient_id"]),
                    str(notification["loop_id"]),
                )
                if not delivered:
                    staff_store.remove_fcm_fid(fid)
                store.mark_medical_issue_notification_fid_delivered(
                    notification_id, fid
                )
            except Exception as error:
                delivery_errors.add(type(error).__name__)
                logger.error(
                    "Medical issue notification delivery failed for staff %s (%s).",
                    staff_id,
                    type(error).__name__,
                )
        if delivery_errors:
            error_types = ", ".join(sorted(delivery_errors))
            store.mark_medical_issue_notification_failed(
                notification_id,
                f"FCM delivery failed for one or more installations ({error_types}).",
            )
            continue
        try:
            store.mark_medical_issue_notification_delivered(notification_id)
        except Exception as error:
            logger.error(
                "Medical issue notification delivery failed for staff %s (%s).",
                staff_id,
                type(error).__name__,
            )
            store.mark_medical_issue_notification_failed(
                notification_id,
                f"Could not update notification delivery state ({type(error).__name__}).",
            )


async def _medical_issue_notification_worker() -> None:
    while True:
        try:
            await asyncio.to_thread(_dispatch_due_medical_issue_notifications)
            await asyncio.to_thread(call_store.cleanup)
        except Exception as error:
            logger.error(
                "Medical issue notification worker failed (%s).",
                type(error).__name__,
            )
        await asyncio.sleep(15)


@app.get("/health")
def health_check():
    return {
        "status": "ok",
        "service": "oravi-backend",
        "version": "0.3.0",
        "medical_issue_push_configured": bool(
            os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
            or os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
        ),
    }


@app.on_event("startup")
async def start_medical_issue_notification_worker():
    app.state.medical_issue_notification_worker = asyncio.create_task(
        _medical_issue_notification_worker()
    )


@app.on_event("shutdown")
async def stop_medical_issue_notification_worker():
    worker = getattr(app.state, "medical_issue_notification_worker", None)
    if worker is not None:
        worker.cancel()
        try:
            await worker
        except asyncio.CancelledError:
            pass

# --- Hospital Wards & Shift Allocation Endpoints ---

@app.get("/api/v1/admin/wards")
def admin_wards(profile: StaffProfile = Depends(require_dev_admin)):
    return ward_store.get_all_wards()


def _configured_ward(request: WardConfigurationRequest, ward_id: str):
    beds = [bed.strip() for bed in request.bed_numbers]
    if not request.name.strip() or any(not bed for bed in beds):
        raise HTTPException(400, "Ward name and bed labels must not be blank.")
    if len({bed.casefold() for bed in beds}) != len(beds):
        raise HTTPException(400, "Bed labels must be unique within the ward.")
    return HospitalWardModel(ward_id, request.name.strip(), len(beds), beds,
                             request.department.strip(), request.description.strip())


@app.post("/api/v1/admin/wards")
def create_configured_ward(request: WardConfigurationRequest,
                           profile: StaffProfile = Depends(require_dev_admin)):
    ward = _configured_ward(request, "ward-" + uuid.uuid4().hex)
    ward_store.create_ward(ward)
    return ward


@app.put("/api/v1/admin/wards/{ward_id}")
def update_configured_ward(ward_id: str, request: WardConfigurationRequest,
                           profile: StaffProfile = Depends(require_dev_admin)):
    ward = _configured_ward(request, ward_id)
    if request.expected_bed_numbers is None:
        raise HTTPException(400, "Reload the ward before editing its beds.")
    try:
        ward_store.update_ward_configuration(ward, request.expected_bed_numbers)
    except KeyError:
        raise HTTPException(404, "Ward not found.")
    except ValueError as error:
        raise HTTPException(409, str(error))
    return ward


@app.get("/api/v1/wards")
def get_hospital_wards(profile: StaffProfile = Depends(require_staff)):
    """Returns configured wards to a charge nurse choosing a working context."""
    if profile.role != "charge_nurse":
        raise HTTPException(status_code=403, detail="Charge Nurse access required.")
    return [w.__dict__ for w in ward_store.get_all_wards()]


@app.get("/api/v1/staff/me/ward-context")
def get_charge_nurse_ward_context(profile: StaffProfile = Depends(require_charge_nurse)):
    """Returns the charge nurse's last selected ward preference, not a staff assignment."""
    ward_id = staff_store.get_ward_preference(profile.staff_id)
    if not ward_id:
        return {"ward_id": None}
    ward = next((ward for ward in ward_store.get_all_wards() if ward.ward_id == ward_id), None)
    return {"ward_id": ward_id, "ward": ward.__dict__ if ward else None}


@app.put("/api/v1/staff/me/ward-context")
def set_charge_nurse_ward_context(
    payload: dict, profile: StaffProfile = Depends(require_charge_nurse)
):
    ward_id = payload.get("ward_id")
    if not isinstance(ward_id, str) or ward_id not in {
        ward.ward_id for ward in ward_store.get_all_wards()
    }:
        raise HTTPException(status_code=404, detail="Ward is not configured for this hospital.")
    if not staff_store.set_ward_preference(profile.staff_id, ward_id):
        raise HTTPException(status_code=409, detail="Charge Nurse account is unavailable.")
    return {"success": True, "ward_id": ward_id}


@app.get("/api/v1/staff/me/active-assignment")
def get_current_staff_assignment(
    date: str = Query(..., description="Shift date in YYYY-MM-DD format"),
    shift_type: str = Query(..., description="'day' or 'night'"),
    profile: StaffProfile = Depends(require_staff),
):
    if shift_type not in {"day", "night"}:
        raise HTTPException(status_code=400, detail="Shift type must be day or night.")
    try:
        assignment = ward_store.get_staff_active_assignment(
            profile.staff_id, date, shift_type
        )
    except ValueError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    return {"active_assignment": assignment}


@app.get("/api/v1/wards/{ward_id}/staff", response_model=StaffListResponse)
def get_ward_staff_directory(
    ward_id: str,
    date: str = Query(..., description="Shift date in YYYY-MM-DD format"),
    shift_type: str = Query(..., description="'day' or 'night'"),
    profile: StaffProfile = Depends(require_staff),
):
    if shift_type not in {"day", "night"}:
        raise HTTPException(status_code=400, detail="Shift type must be day or night.")
    if profile.role == "charge_nurse":
        authorized = staff_store.get_ward_preference(profile.staff_id) == ward_id
    else:
        authorized = ward_store.has_staff_assignment(
            profile.staff_id, ward_id, date, shift_type
        )
    if not authorized:
        raise HTTPException(status_code=403, detail="You do not have access to this ward.")
    if ward_id not in {ward.ward_id for ward in ward_store.get_all_wards()}:
        raise HTTPException(status_code=404, detail="Ward was not found.")
    return StaffListResponse(
        ward_id=ward_id,
        staff=staff_store.get_active_clinical_staff(),
    )


@app.get("/api/v1/wards/{ward_id}/board")
def get_ward_board(ward_id: str, date: str, shift_type: str, profile: StaffProfile = Depends(require_staff)):
    if shift_type not in {"day", "night"}:
        raise HTTPException(status_code=400, detail="Shift type must be day or night.")
    if profile.role == "charge_nurse":
        if staff_store.get_ward_preference(profile.staff_id) != ward_id:
            raise HTTPException(status_code=403, detail="Confirm this ward before viewing its board.")
    elif not ward_store.has_staff_assignment(
        profile.staff_id, ward_id, date, shift_type
    ):
        raise HTTPException(
            status_code=403,
            detail="You do not have an assignment on this ward for the selected shift.",
        )
    board = ward_store.get_ward_board(ward_id, date, shift_type)
    return board or {"ward_id": ward_id, "date": date, "shift_type": shift_type,
                     "bed_assignments": [], "responsibilities": {}}


@app.get("/api/v1/patients/{patient_id}/staff")
def get_patient_clinicians(
    patient_id: str,
    date: str = Query(..., description="Current board date in YYYY-MM-DD format"),
    profile: StaffProfile = Depends(require_staff),
):
    assignment = _patient_assignment_for_user(profile, patient_id, date)
    if assignment is None:
        raise HTTPException(status_code=403, detail="You do not have access to this patient.")
    staff_ids = set(assignment["staff_ids"])
    charge_nurses = staff_store.get_charge_nurses_for_ward(assignment["ward_id"])
    staff_ids.update(charge_nurse.staff_id for charge_nurse in charge_nurses)
    return {
        "patient_id": patient_id,
        "staff": [
            staff.__dict__
            for staff in staff_store.get_active_staff_by_ids(sorted(staff_ids))
        ],
    }


@app.get("/api/v1/patients/{patient_id}/medical-issues/{loop_id}")
def get_medical_issue_thread(
    patient_id: str,
    loop_id: str,
    profile: StaffProfile = Depends(require_staff),
):
    history = store.get_loop_events(patient_id, loop_id)
    if not history or not (
        _staff_can_access_patient(profile, patient_id, date.today().isoformat())
        or _staff_can_access_carried_issue(profile.staff_id, patient_id, loop_id)
    ):
        raise HTTPException(
            status_code=404,
            detail="Medical Issue thread was not found or is not assigned to you.",
        )
    return {
        "patient_id": patient_id,
        "ward_id": store.get_patient_ward(patient_id),
        "loop_id": loop_id,
        "events": [event.to_dict() for event in history],
    }

@app.get("/api/v1/allocations/check-conflict", response_model=AllocationConflictCheckResponse)
def check_shift_conflict(
    nurse_id: str = Query(..., description="Staff ID of the nurse to check"),
    date: str = Query(..., description="Shift date in YYYY-MM-DD format"),
    shift_type: str = Query(..., description="'day' or 'night'"),
    target_ward_id: str = Query(..., description="Ward attempting to allocate this nurse"),
    profile: StaffProfile = Depends(require_charge_nurse),
):
    """
    Prevents cross-ward double booking. 
    Returns explicit clinical warning if nurse is already active elsewhere.
    """
    if staff_store.get_ward_preference(profile.staff_id) != target_ward_id:
        raise HTTPException(status_code=403, detail="Confirm this ward before managing its board.")
    return ward_store.check_nurse_shift_conflict(
        nurse_id=nurse_id,
        date=date,
        shift_type=shift_type,
        target_ward_id=target_ward_id
    )

@app.post("/api/v1/allocations/publish")
def publish_allocation(allocation: ShiftAllocationModel, profile: StaffProfile = Depends(require_charge_nurse)):
    """Publishes shift allocation matrix and saves canonical ward assignments."""
    if (
        staff_store.get_ward_preference(profile.staff_id) != allocation.ward_id
        or allocation.published_by != profile.staff_id
    ):
        raise HTTPException(status_code=403, detail="Confirm this ward before publishing its board.")
    if any(
        item.get("assigned_nurse_id")
        and not staff_store.is_active_clinical_staff(item["assigned_nurse_id"])
        for item in allocation.bed_assignments
    ):
        raise HTTPException(status_code=400, detail="Every assigned staff member must have an active clinical account.")
    if any(
        item.get("admitting_doctor")
        and not staff_store.is_active_doctor(item["admitting_doctor"])
        for item in allocation.bed_assignments
    ):
        raise HTTPException(status_code=400, detail="Every assigned doctor must have an active doctor account.")
    try:
        with store._lock:
            removed_patient_ids = ward_store.patient_ids_removed_by_allocation(
                allocation
            )
            expected_issue_keys: set[tuple[str, str]] = set()
            for patient_id in removed_patient_ids:
                if store.get_patient_ward(patient_id) != allocation.ward_id:
                    raise ValueError(
                        "A removed patient must have a verified ward history."
                    )
                history = store.get_patient_events(patient_id)
                expected_issue_keys.update(
                    (patient_id, loop_id)
                    for loop_id in open_medical_issue_ids(history)
                )

            carry_forward_owners = {}
            for item in allocation.carry_forward_issues:
                patient_id = item.get("patient_id")
                loop_id = item.get("loop_id")
                owner_id = item.get("owner_id")
                reason = item.get("reason", "")
                if (
                    not isinstance(patient_id, str)
                    or not isinstance(loop_id, str)
                    or not isinstance(owner_id, str)
                    or not isinstance(reason, str)
                ):
                    raise ValueError("Carry-forward issue details are invalid.")
                issue_key = (patient_id, loop_id)
                if issue_key in carry_forward_owners:
                    raise ValueError(
                        "Each open Medical Issue must have one named owner."
                    )
                if not staff_store.is_active_clinical_staff(owner_id):
                    raise ValueError(
                        "The named owner must be an active clinical staff member."
                    )
                carry_forward_owners[issue_key] = (owner_id, reason.strip())

            if set(carry_forward_owners) != expected_issue_keys:
                raise ValueError(
                    "Every open Medical Issue must be carried forward to a named owner "
                    "before the patient leaves all boards."
                )

            carry_forward_events = []
            notification_staff_ids_by_event = {}
            for (patient_id, loop_id), (owner_id, reason) in sorted(
                carry_forward_owners.items()
            ):
                owner = staff_store.get_active_staff_by_ids([owner_id])[0]
                event = CanonicalEvent(
                    event_id=str(uuid.uuid4()),
                    patient_id=patient_id,
                    type="LoopOwnerChanged",
                    author_id=profile.staff_id,
                    device_id=f"BOARD-{allocation.allocation_id}",
                    client_created_at=allocation.published_at,
                    loop_id=loop_id,
                    payload={
                        "new_owner_id": owner.staff_id,
                        "new_owner_role": owner.role,
                        "transfer_reason": reason,
                        "carry_forward": True,
                    },
                )
                carry_forward_events.append(event)
                notification_staff_ids_by_event[event.event_id] = [owner_id]

            _validate_patient_issue_events(
                carry_forward_events,
                {event.event_id for event in carry_forward_events},
            )

            def publish_atomically(connection):
                if ward_store.patient_ids_removed_by_allocation(
                    allocation, connection=connection
                ) != removed_patient_ids:
                    raise ValueError(
                        "The ward board changed while carry-forward was being prepared. "
                        "Reload and try again."
                    )
                ward_store.publish_shift_allocation(
                    allocation, connection=connection
                )

            store.append_events(
                carry_forward_events,
                notification_staff_ids_by_event,
                transaction_action=publish_atomically,
            )
    except ValueError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    return {
        "success": True,
        "allocation_id": allocation.allocation_id,
        "carry_forward_events": [
            event.to_dict() for event in carry_forward_events
        ],
    }

@app.get("/api/v1/nurses/{nurse_id}/active-shift")
def get_nurse_active_shift(
    nurse_id: str,
    date: str = Query(..., description="Shift date YYYY-MM-DD"),
    shift_type: str = Query(..., description="'day' or 'night'"),
    profile: StaffProfile = Depends(require_staff),
):
    """Returns the active shift and assigned beds for a given nurse."""
    if nurse_id != profile.staff_id and profile.role != "charge_nurse":
        raise HTTPException(status_code=403, detail="You may only view your own assignment list.")
    active = ward_store.get_nurse_active_shift(nurse_id=nurse_id, date=date, shift_type=shift_type)
    return {"active_shift": active}

@app.post("/api/v1/allocations/{allocation_id}/accept")
def accept_allocation_beds(allocation_id: str, payload: dict, profile: StaffProfile = Depends(require_staff)):
    nurse_id = profile.staff_id
    beds = payload.get("beds", [])
    if not nurse_id or not beds:
        raise HTTPException(status_code=400, detail="nurse_id and beds are required")
    updated = ward_store.accept_shift_beds(
        allocation_id=allocation_id,
        nurse_id=nurse_id,
        beds=beds,
    )
    return {"success": True, "accepted_count": updated}

@app.post("/api/v1/allocations/{allocation_id}/handoff/accept")
def accept_handoff_beds(
    allocation_id: str,
    payload: dict,
    incoming_authorization: str = Header(
        default="", alias="X-Incoming-Authorization"
    ),
    profile: StaffProfile = Depends(require_staff),
):
    if profile.role != "ward_nurse":
        raise HTTPException(
            status_code=403,
            detail="Only the outgoing ward nurse can initiate this handoff.",
        )
    outgoing_nurse_id = payload.get("outgoing_nurse_id")
    beds = payload.get("beds")
    handoff_session_id = payload.get("handoff_session_id")
    transferred_loop_ids_by_patient = payload.get(
        "transferred_loop_ids_by_patient"
    )
    if (
        not isinstance(outgoing_nurse_id, str)
        or outgoing_nurse_id != profile.staff_id
        or not staff_store.is_active_clinical_staff(outgoing_nurse_id)
        or not isinstance(beds, list)
        or not beds
        or not all(isinstance(bed, str) and bed for bed in beds)
        or not isinstance(handoff_session_id, str)
        or not handoff_session_id.strip()
        or not isinstance(transferred_loop_ids_by_patient, dict)
    ):
        raise HTTPException(
            status_code=400,
            detail="An active outgoing nurse and one or more bed numbers are required.",
        )
    scheme, _, incoming_token = incoming_authorization.partition(" ")
    incoming_profile = (
        staff_store.get_session(incoming_token)
        if scheme.lower() == "bearer" and incoming_token
        else None
    )
    if incoming_profile is None or incoming_profile.role != "ward_nurse":
        raise HTTPException(
            status_code=401,
            detail="Verify the incoming nurse's identity before accepting the handoff.",
        )
    handoff_start = store.get_handoff_started_event(handoff_session_id)
    if (
        handoff_start is None
        or handoff_start.author_id != outgoing_nurse_id
        or handoff_start.payload.get("outgoing_nurse_id") != outgoing_nurse_id
        or handoff_start.payload.get("incoming_nurse_id")
        != incoming_profile.staff_id
    ):
        raise HTTPException(
            status_code=409,
            detail="The handoff session does not match the verified nurses.",
        )
    issue_lists: dict[str, list[str]] = {}
    for patient_id, loop_ids in transferred_loop_ids_by_patient.items():
        if (
            not isinstance(patient_id, str)
            or not isinstance(loop_ids, list)
            or not all(isinstance(loop_id, str) for loop_id in loop_ids)
        ):
            raise HTTPException(
                status_code=400,
                detail="Transferred Medical Issue IDs must be valid patient lists.",
            )
        if not store.patient_belongs_to_ward(
            patient_id, str(handoff_start.payload.get("ward_id", ""))
        ):
            raise HTTPException(
                status_code=409,
                detail="A selected patient does not belong to this handoff ward.",
            )
        expected_loop_ids = open_medical_issue_ids(
            store.get_patient_events(patient_id)
        )
        if set(loop_ids) != expected_loop_ids:
            raise HTTPException(
                status_code=409,
                detail="All open Medical Issues must be included in the handoff.",
            )
        issue_lists[patient_id] = loop_ids
    try:
        updated = ward_store.transfer_handoff_beds(
            allocation_id=allocation_id,
            outgoing_nurse_id=outgoing_nurse_id,
            incoming_nurse_id=incoming_profile.staff_id,
            beds=beds,
            handoff_session_id=handoff_session_id,
            transferred_loop_ids_by_patient=issue_lists,
            expected_ward_id=str(handoff_start.payload["ward_id"]),
        )
    except ValueError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    return {"success": True, "accepted_count": updated}

# --- Clinical Staff & Authentication Endpoints ---

@app.get("/api/v1/auth/staff", response_model=StaffListResponse)
def get_ward_staff(ward_id: str = Query(..., description="Ward identifier"), profile: StaffProfile = Depends(require_staff)):
    if profile.role != "charge_nurse" or staff_store.get_ward_preference(profile.staff_id) != ward_id:
        raise HTTPException(status_code=403, detail="Charge Nurse must confirm this ward first.")
    return StaffListResponse(
        ward_id=ward_id,
        staff=staff_store.get_active_clinical_staff(),
    )


@app.get("/api/v1/auth/directory", response_model=List[StaffProfile])
def search_staff_directory(q: str = Query(default="", max_length=80)):
    """Search staff identity cards for the pre-authentication badge picker."""
    return staff_store.get_staff_directory(q)


@app.get("/api/v1/admin/staff", response_model=List[StaffProfile])
def list_provisioned_staff(admin: StaffProfile = Depends(require_dev_admin)):
    profiles = staff_store.list_staff()
    for profile in profiles:
        profile.ward_id = ''
    return profiles

@app.post("/api/v1/auth/verify-pin", response_model=StaffLoginResponse)
def verify_staff_pin(request: StaffLoginRequest):
    success, profile, error_msg = staff_store.verify_pin(
        staff_id=request.staff_id,
        pin=request.pin,
        email=request.email,
    )
    if not success:
        return StaffLoginResponse(success=False, error=error_msg)

    # Issue a secure session token
    session_token = f"oravi_sess_{secrets.token_hex(24)}"
    staff_store.create_session(profile.staff_id, session_token)
    return StaffLoginResponse(
        success=True,
        staff=profile,
        token=session_token,
    )


@app.post("/api/v1/auth/logout")
def logout_staff(authorization: str = Header(default="")):
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Sign-in required.")
    staff_store.revoke_session(token)
    return {"success": True}


@app.post("/api/v1/staff/me/fcm-installation")
def register_fcm_device_token(
    payload: dict, profile: StaffProfile = Depends(require_communicating_staff)
):
    token = payload.get("token")
    device_id = payload.get("device_id")
    platform = payload.get("platform")
    if (
        not isinstance(token, str)
        or not 20 <= len(token) <= 4096
        or not isinstance(device_id, str)
        or not 1 <= len(device_id) <= 200
        or platform not in {"android", "ios", "macos"}
    ):
        raise HTTPException(status_code=400, detail="A valid FCM registration token is required.")
    if not staff_store.register_fcm_installation(
        profile.staff_id, device_id, token, platform
    ):
        raise HTTPException(status_code=409, detail="The staff account is unavailable.")
    return {"success": True}


@app.delete("/api/v1/staff/me/fcm-installation")
def remove_fcm_device_token(
    payload: dict, profile: StaffProfile = Depends(require_communicating_staff)
):
    device_id = payload.get("device_id")
    if not isinstance(device_id, str) or not 1 <= len(device_id) <= 200:
        raise HTTPException(status_code=400, detail="A valid device ID is required.")
    staff_store.remove_fcm_installation(profile.staff_id, device_id)
    return {"success": True}


def _livekit_token(identity: str, name: str, room_name: str) -> str:
    livekit_url = os.getenv("LIVEKIT_URL")
    api_key = os.getenv("LIVEKIT_API_KEY")
    api_secret = os.getenv("LIVEKIT_API_SECRET")
    if not livekit_url or not api_key or not api_secret:
        raise HTTPException(status_code=503, detail="LiveKit calling is not configured on the Oravi service.")
    try:
        from livekit import api
    except ImportError as error:
        raise HTTPException(status_code=503, detail="The LiveKit server SDK is not installed on the Oravi service.") from error
    return (
        api.AccessToken(api_key, api_secret)
        .with_identity(identity)
        .with_name(name)
        .with_grants(api.VideoGrants(room_join=True, room=room_name, can_publish=True, can_subscribe=True, can_publish_data=True))
        .to_jwt()
    )


@app.post("/api/v1/calls/invite")
def invite_call(payload: dict, profile: StaffProfile = Depends(require_staff)):
    patient_id = payload.get("patient_id")
    loop_id = payload.get("loop_id")
    recipient_id = payload.get("recipient_id")
    if not all(isinstance(value, str) and value.strip() for value in (patient_id, loop_id, recipient_id)):
        raise HTTPException(status_code=400, detail="A patient, issue, and recipient are required.")
    assignment_date = date.today().isoformat()
    if not _staff_can_access_patient(profile, patient_id, assignment_date):
        raise HTTPException(status_code=403, detail="You do not have access to this patient.")
    if not store.get_loop_events(patient_id, loop_id):
        raise HTTPException(status_code=404, detail="The Medical Issue was not found for this patient.")
    authorized_ids = _authorized_patient_staff_ids(patient_id, assignment_date)
    if recipient_id not in authorized_ids or not staff_store.is_active_clinical_staff(recipient_id):
        raise HTTPException(status_code=403, detail="The selected clinician is not authorized for this patient.")
    recipient_fids = staff_store.get_fcm_fids_for_staff(recipient_id)
    if not recipient_fids:
        raise HTTPException(status_code=409, detail="The selected clinician has no registered Oravi device.")
    call_id = f"CALL-{uuid.uuid4()}"
    room_name = f"oravi-call-{uuid.uuid4().hex}"
    livekit_url = os.getenv("LIVEKIT_URL")
    call_store.create(call_id=call_id, room_name=room_name, patient_id=patient_id, loop_id=loop_id, caller_id=profile.staff_id, recipient_id=recipient_id)
    caller_token = _livekit_token(profile.staff_id, profile.name, room_name)
    delivered = 0
    for fid in recipient_fids:
        try:
            if fcm_service.send_call_invitation(fid, call_id=call_id):
                delivered += 1
        except Exception as error:
            logger.error("Call invitation delivery failed (%s).", type(error).__name__)
    if delivered == 0:
        raise HTTPException(status_code=503, detail="The clinician could not be notified.")
    recipient = staff_store.get_active_staff_by_ids([recipient_id])[0]
    return {"call_id": call_id, "patient_id": patient_id, "loop_id": loop_id, "caller_id": profile.staff_id, "caller_name": profile.name, "recipient_id": recipient.staff_id, "recipient_name": recipient.name, "recipient_role": recipient.role, "room_name": room_name, "livekit_url": livekit_url, "token": caller_token, "status": "ringing"}


@app.get("/api/v1/calls/{call_id}")
def get_call(call_id: str, profile: StaffProfile = Depends(require_communicating_staff)):
    call = call_store.get(call_id)
    if call is not None and profile.role not in CLINICAL_ROLES and (call['patient_id'] or call['loop_id']):
        raise HTTPException(404, 'Call not found.')
    if call is None or profile.staff_id not in {call["caller_id"], call["recipient_id"]}:
        raise HTTPException(status_code=404, detail="Call not found.")
    people = {p.staff_id: p for p in staff_store.get_active_staff_by_ids([call["caller_id"], call["recipient_id"]])}
    if call['caller_id'] not in people or call['recipient_id'] not in people:
        raise HTTPException(409, 'A call participant is no longer available.')
    caller, recipient = people[call['caller_id']], people[call['recipient_id']]
    return {"call_id": call["call_id"], "patient_id": call["patient_id"], "loop_id": call["loop_id"], "caller_id": caller.staff_id, "caller_name": caller.name, "caller_role": caller.role, "recipient_id": recipient.staff_id, "recipient_name": recipient.name, "recipient_role": recipient.role, "status": call["status"]}


@app.post("/api/v1/calls/{call_id}/accept")
def accept_call(call_id: str, profile: StaffProfile = Depends(require_communicating_staff)):
    call = call_store.get(call_id)
    if call is not None and profile.role not in CLINICAL_ROLES and (call['patient_id'] or call['loop_id']):
        raise HTTPException(404, 'Call not found.')
    if call is None or profile.staff_id != call["recipient_id"] or call['status'] != 'ringing':
        raise HTTPException(status_code=409, detail="This call is no longer available.")
    callers = staff_store.get_active_staff_by_ids([call['caller_id']])
    if not callers:
        raise HTTPException(409, 'The caller is no longer available.')
    token = _livekit_token(profile.staff_id, profile.name, call["room_name"])
    if not call_store.mark_answered(call_id):
        raise HTTPException(409, 'This call is no longer available.')
    livekit_url = os.getenv("LIVEKIT_URL")
    caller = callers[0]
    return {"call_id": call_id, "patient_id": call["patient_id"], "loop_id": call["loop_id"], "caller_id": caller.staff_id, "caller_name": caller.name, "caller_role": caller.role, "recipient_id": profile.staff_id, "recipient_name": profile.name, "recipient_role": profile.role, "room_name": call["room_name"], "livekit_url": livekit_url, "token": token, "status": "answered", "is_incoming": True}


@app.post("/api/v1/calls/{call_id}/end")
def end_call(call_id: str, profile: StaffProfile = Depends(require_communicating_staff)):
    if not call_store.mark_ended(call_id, profile.staff_id):
        raise HTTPException(status_code=404, detail="Call not found or already ended.")
    return {"success": True}


@app.post("/api/v1/calls/{call_id}/decline")
def decline_call(call_id: str, profile: StaffProfile = Depends(require_communicating_staff)):
    if not call_store.mark_declined(call_id, profile.staff_id):
        raise HTTPException(status_code=409, detail="This call is no longer available.")
    return {"success": True, "status": "declined"}


@app.post("/api/v1/calls/{call_id}/cancel")
def cancel_call(call_id: str, profile: StaffProfile = Depends(require_communicating_staff)):
    if not call_store.mark_cancelled(call_id, profile.staff_id):
        raise HTTPException(status_code=409, detail="This call is no longer ringing.")
    return {"success": True, "status": "cancelled"}

@app.post("/api/v1/admin/staff", response_model=StaffProfile)
def create_staff_member(request: CreateStaffRequest, admin: StaffProfile = Depends(require_dev_admin)):
    try:
        return staff_store.create_staff(
            staff_id=request.staff_id,
            name=request.name,
            role=request.role,
            ward_id="",
            pin=request.pin,
            avatar_color=request.avatar_color,
            email=request.email,
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except sqlite3.IntegrityError as error:
        raise HTTPException(status_code=409, detail="That staff ID already exists.") from error

# --- Event Sync Endpoints ---

@app.patch('/api/v1/admin/staff/{staff_id}', response_model=StaffProfile)
def update_staff_status(staff_id: str, payload: dict, admin: StaffProfile = Depends(require_dev_admin)):
    active = payload.get('is_active')
    if not isinstance(active, bool):
        raise HTTPException(status_code=400, detail='is_active must be true or false.')
    if not staff_store.set_staff_active(staff_id, active):
        raise HTTPException(status_code=404, detail='Clinical staff account not found.')
    return next(profile for profile in list_provisioned_staff(admin) if profile.staff_id == staff_id)


@app.delete('/api/v1/admin/staff/{staff_id}')
def delete_staff_account(staff_id: str, admin: StaffProfile = Depends(require_dev_admin)):
    if not staff_store.delete_clinical_staff(staff_id):
        raise HTTPException(status_code=404, detail='Clinical staff account not found.')
    return {'success': True}

@app.post("/api/v1/sync/push", response_model=SyncPushResponse)
def sync_push(request: SyncPushRequest, profile: StaffProfile = Depends(require_staff)):
    for event in request.events:
        access_date = event.client_created_at[:10]
        handoff_session_id = event.payload.get("handoff_session_id")
        handoff_start = (
            store.get_handoff_started_event(handoff_session_id)
            if isinstance(handoff_session_id, str)
            else None
        )
        is_completed_handoff = event.type == "HandoffCompleted"
        is_accepted_bed = event.type == "HandoffBedAccepted"
        is_transferred_issue = (
            event.type == "LoopOwnerChanged"
            and isinstance(handoff_session_id, str)
        )
        if is_completed_handoff:
            payload = event.payload
            authorized = bool(
                handoff_start
                and handoff_start.payload.get("ward_id") == event.patient_id
                and handoff_start.payload.get("outgoing_nurse_id")
                == profile.staff_id
                and isinstance(payload.get("total_beds_handed_over"), int)
                and not isinstance(payload.get("total_beds_handed_over"), bool)
                and isinstance(payload.get("total_loops_transferred"), int)
                and not isinstance(payload.get("total_loops_transferred"), bool)
                and ward_store.handoff_has_no_unaccepted_patients(
                    handoff_session_id,
                    profile.staff_id,
                    event.patient_id,
                    access_date,
                    payload["total_beds_handed_over"],
                    payload["total_loops_transferred"],
                )
            )
        elif is_accepted_bed or is_transferred_issue:
            authorized = bool(
                handoff_start
                and handoff_start.payload.get("outgoing_nurse_id")
                == profile.staff_id
                and event.author_id == profile.staff_id
                and ward_store.authorizes_handoff_event(
                    handoff_session_id=handoff_session_id,
                    patient_id=event.patient_id,
                    author_id=event.author_id,
                    event_type=event.type,
                    loop_id=event.loop_id,
                    new_owner_id=event.payload.get("new_owner_id"),
                    bed_number=event.payload.get("bed_number"),
                    transferred_loop_ids=event.payload.get(
                        "transferred_loop_ids"
                    ),
                )
                and (
                    event.type != "HandoffBedAccepted"
                    or (
                        isinstance(
                            event.payload.get("nothing_pending_confirmed"), bool
                        )
                        and event.payload["nothing_pending_confirmed"]
                        == (not event.payload.get("transferred_loop_ids"))
                    )
                )
            )
        else:
            is_ward_handoff = event.type == "HandoffStarted"
            ward_id = (
                event.payload.get("ward_id")
                if is_ward_handoff
                else None
            )
            authorized = (
                _staff_can_access_ward(
                    profile, ward_id or event.patient_id, access_date
                )
                if is_ward_handoff
                else _staff_can_access_patient(
                    profile, event.patient_id, access_date
                )
                or bool(
                    event.loop_id
                    and _staff_can_access_carried_issue(
                        profile.staff_id, event.patient_id, event.loop_id
                    )
                )
            )
        if event.author_id != profile.staff_id or not authorized:
            raise HTTPException(
                status_code=403,
                detail="Events must belong to your account and an assigned patient.",
            )
        if event.type == 'MessagePosted':
            event.payload['author_role'] = profile.role
    _validate_patient_issue_events(request.events)
    notifications = _notification_recipients_for_events(request.events)
    acks = store.append_events(
        request.events, notification_staff_ids_by_event=notifications
    )
    return SyncPushResponse(
        status="success",
        acknowledged_count=len(acks),
        acks=acks,
    )

@app.get("/api/v1/sync/pull", response_model=SyncPullResponse)
def sync_pull(
    ward_id: str = Query(..., description="Target clinical ward identifier"),
    since_seq: int = Query(0, description="Latest server sequence client has stored"),
    limit: int = Query(100, description="Max batch size"),
    profile: StaffProfile = Depends(require_staff),
):
    assignment_date = date.today().isoformat()
    has_patient_access = _staff_can_access_ward(
        profile, ward_id, assignment_date
    )
    carried_issues = _carried_forward_issue_references(
        profile.staff_id, include_events=False
    )
    has_handoff_audit_access = ward_store.has_handoff_audit_access(
        profile.staff_id, ward_id, assignment_date
    )
    if not has_patient_access and not has_handoff_audit_access and not carried_issues:
        raise HTTPException(status_code=403, detail="You do not have access to this ward.")
    if not has_patient_access:
        patient_ids = set()
    elif profile.role == "charge_nurse":
        patient_ids = set(ward_store.get_patient_ids_for_ward(ward_id, assignment_date))
    else:
        patient_ids = set(
            ward_store.get_patient_ids_for_staff(
                profile.staff_id, assignment_date, ward_id
            )
        )
    events, latest_seq = store.get_events_since(
        since_seq=since_seq,
        limit=limit,
        ward_id=(
            ward_id
            if has_patient_access or has_handoff_audit_access
            else None
        ),
        patient_ids=patient_ids,
        issue_refs={
            (item["patient_id"], item["loop_id"])
            for item in carried_issues
        },
    )
    return SyncPullResponse(
        ward_id=ward_id,
        latest_seq=latest_seq,
        events=events,
    )

@app.get("/api/v1/medical-issues/carried")
def get_carried_forward_issues(
    profile: StaffProfile = Depends(require_staff),
):
    """Returns carried issues, exposing only their thread events to the named owner."""
    return {
        "issues": _carried_forward_issue_references(
            profile.staff_id, include_events=True
        )
    }

@app.post("/api/v1/patients/{patient_id}/ask", response_model=AskResponse)
def ask_patient_record(patient_id: str, request: AskRequest, profile: StaffProfile = Depends(require_staff)):
    patient_ward = store.get_patient_ward(patient_id)
    if (
        not patient_ward
        or not _staff_can_access_patient(profile, patient_id, date.today().isoformat())
        or not store.patient_belongs_to_ward(patient_id, patient_ward)
    ):
        raise HTTPException(status_code=404, detail="Medical issue or patient context was not found in your ward.")
    result = llm_service.query(
        patient_id=patient_id,
        query_text=request.query,
        time_window_hours=request.time_window_hours,
    )
    return AskResponse(**result)


app.include_router(build_router(sys.modules[__name__]))
app.include_router(build_inbox_router(sys.modules[__name__]))
app.include_router(build_notebook_router(sys.modules[__name__]))
app.include_router(build_transfer_router(sys.modules[__name__]))
