import os
import secrets
import sqlite3
from datetime import date
from typing import List
from fastapi import FastAPI, Query, HTTPException, Header, Depends, status
from .models import (
    SyncPushRequest, SyncPushResponse, SyncPullResponse, AskRequest, AskResponse,
    StaffLoginRequest, StaffLoginResponse, CreateStaffRequest, StaffListResponse, StaffProfile,
    HospitalWardModel, ShiftAllocationModel, AllocationConflictCheckResponse
)
from .event_store import EventStore
from .staff_store import StaffStore
from .ward_store import WardStore
from .services.llm_service import LLMService

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


def require_staff(authorization: str = Header(default="")) -> StaffProfile:
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Sign-in required.")
    profile = staff_store.get_session(token)
    if profile is None:
        raise HTTPException(status_code=401, detail="Session is invalid or expired.")
    return profile


def require_dev_admin(profile: StaffProfile = Depends(require_staff)) -> StaffProfile:
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

@app.get("/health")
def health_check():
    return {"status": "ok", "service": "oravi-backend", "version": "0.3.0"}

# --- Hospital Wards & Shift Allocation Endpoints ---

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
    try:
        success = ward_store.publish_shift_allocation(allocation)
    except ValueError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    return {"success": success, "allocation_id": allocation.allocation_id}

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
    if (
        not isinstance(outgoing_nurse_id, str)
        or outgoing_nurse_id != profile.staff_id
        or not staff_store.is_active_clinical_staff(outgoing_nurse_id)
        or not isinstance(beds, list)
        or not beds
        or not all(isinstance(bed, str) and bed for bed in beds)
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
    try:
        updated = ward_store.transfer_handoff_beds(
            allocation_id=allocation_id,
            outgoing_nurse_id=outgoing_nurse_id,
            incoming_nurse_id=incoming_profile.staff_id,
            beds=beds,
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
    return staff_store.list_staff()

@app.post("/api/v1/auth/verify-pin", response_model=StaffLoginResponse)
def verify_staff_pin(request: StaffLoginRequest):
    success, profile, error_msg = staff_store.verify_pin(
        staff_id=request.staff_id,
        pin=request.pin,
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
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except sqlite3.IntegrityError as error:
        raise HTTPException(status_code=409, detail="That staff ID already exists.") from error

# --- Event Sync Endpoints ---

@app.post("/api/v1/sync/push", response_model=SyncPushResponse)
def sync_push(request: SyncPushRequest, profile: StaffProfile = Depends(require_staff)):
    patient_wards = {}
    for event in request.events:
        ward_id = event.payload.get("ward_id") or patient_wards.get(event.patient_id)
        if ward_id is None:
            ward_id = store.get_patient_ward(event.patient_id)
        event_date = event.client_created_at[:10]
        if (
            event.author_id != profile.staff_id
            or not ward_id
            or not _staff_can_access_ward(profile, ward_id, event_date)
        ):
            raise HTTPException(status_code=403, detail="Events must belong to your account and assigned ward.")
        patient_wards[event.patient_id] = ward_id
    acks = store.append_events(request.events)
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
    if not _staff_can_access_ward(
        profile, ward_id, date.today().isoformat()
    ):
        raise HTTPException(status_code=403, detail="You do not have access to this ward.")
    events, latest_seq = store.get_events_since(since_seq=since_seq, limit=limit, ward_id=ward_id)
    return SyncPullResponse(
        ward_id=ward_id,
        latest_seq=latest_seq,
        events=events,
    )

@app.post("/api/v1/patients/{patient_id}/ask", response_model=AskResponse)
def ask_patient_record(patient_id: str, request: AskRequest, profile: StaffProfile = Depends(require_staff)):
    patient_ward = store.get_patient_ward(patient_id)
    if (
        not patient_ward
        or not _staff_can_access_ward(profile, patient_ward, date.today().isoformat())
        or not store.patient_belongs_to_ward(patient_id, patient_ward)
    ):
        raise HTTPException(status_code=404, detail="Medical issue or patient context was not found in your ward.")
    result = llm_service.query(
        patient_id=patient_id,
        query_text=request.query,
        time_window_hours=request.time_window_hours,
    )
    return AskResponse(**result)
