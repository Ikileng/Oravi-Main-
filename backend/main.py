import secrets
from fastapi import FastAPI, Query, HTTPException, status
from .models import (
    SyncPushRequest, SyncPushResponse, SyncPullResponse, AskRequest, AskResponse,
    StaffLoginRequest, StaffLoginResponse, CreateStaffRequest, StaffListResponse, StaffProfile,
    HospitalWardModel, ShiftAllocationModel, AllocationConflictCheckResponse
)
from .event_store import EventStore
from .staff_store import StaffStore
from .ward_store import WardStore
from .services.llm_service import LLMService
from .seed_data import seed_store_if_empty

app = FastAPI(
    title="Oravi Ward Sync and Clinical Auth API",
    description="Offline-first clinical event stream, hash chain and Digital ID authentication backend",
    version="0.3.0",
)

store = EventStore()
seed_store_if_empty(store)
staff_store = StaffStore()
ward_store = WardStore()
llm_service = LLMService(store=store)

@app.get("/health")
def health_check():
    return {"status": "ok", "service": "oravi-backend", "version": "0.3.0"}

# --- Hospital Wards & Shift Allocation Endpoints ---

@app.get("/api/v1/wards")
def get_hospital_wards():
    """Returns the pre-configured hospital ward catalog (Jacaranda, Edna, Kilimanjaro, 4B)"""
    return [w.__dict__ for w in ward_store.get_all_wards()]

@app.get("/api/v1/allocations/check-conflict", response_model=AllocationConflictCheckResponse)
def check_shift_conflict(
    nurse_id: str = Query(..., description="Staff ID of the nurse to check"),
    date: str = Query(..., description="Shift date in YYYY-MM-DD format"),
    shift_type: str = Query(..., description="'day' or 'night'"),
    target_ward_id: str = Query(..., description="Ward attempting to allocate this nurse")
):
    """
    Prevents cross-ward double booking. 
    Returns explicit clinical warning if nurse is already active elsewhere.
    """
    return ward_store.check_nurse_shift_conflict(
        nurse_id=nurse_id,
        date=date,
        shift_type=shift_type,
        target_ward_id=target_ward_id
    )

@app.post("/api/v1/allocations/publish")
def publish_allocation(allocation: ShiftAllocationModel):
    """Publishes shift allocation matrix and saves canonical ward assignments."""
    success = ward_store.publish_shift_allocation(allocation)
    return {"success": success, "allocation_id": allocation.allocation_id}

@app.get("/api/v1/nurses/{nurse_id}/active-shift")
def get_nurse_active_shift(
    nurse_id: str,
    date: str = Query(..., description="Shift date YYYY-MM-DD"),
    shift_type: str = Query(..., description="'day' or 'night'")
):
    """Returns the active shift and assigned beds for a given nurse."""
    active = ward_store.get_nurse_active_shift(nurse_id=nurse_id, date=date, shift_type=shift_type)
    return {"active_shift": active}

@app.post("/api/v1/allocations/{allocation_id}/accept")
def accept_allocation_beds(allocation_id: str, payload: dict):
    nurse_id = payload.get("nurse_id")
    beds = payload.get("beds", [])
    if not nurse_id or not beds:
        raise HTTPException(status_code=400, detail="nurse_id and beds are required")
    updated = ward_store.accept_shift_beds(allocation_id=allocation_id, nurse_id=nurse_id, beds=beds)
    return {"success": True, "accepted_count": updated}

# --- Clinical Staff & Authentication Endpoints ---

@app.get("/api/v1/auth/staff", response_model=StaffListResponse)
def get_ward_staff(ward_id: str = Query("WARD-4B", description="Ward identifier")):
    staff_list = staff_store.get_staff_for_ward(ward_id=ward_id)
    return StaffListResponse(ward_id=ward_id, staff=staff_list)

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
    return StaffLoginResponse(
        success=True,
        staff=profile,
        token=session_token,
    )

@app.post("/api/v1/admin/staff", response_model=StaffProfile)
def create_staff_member(request: CreateStaffRequest):
    profile = staff_store.create_staff(
        staff_id=request.staff_id,
        name=request.name,
        role=request.role,
        ward_id=request.ward_id,
        pin=request.pin,
        avatar_color=request.avatar_color,
    )
    return profile

# --- Event Sync Endpoints ---

@app.post("/api/v1/sync/push", response_model=SyncPushResponse)
def sync_push(request: SyncPushRequest):
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
):
    events, latest_seq = store.get_events_since(since_seq=since_seq, limit=limit)
    return SyncPullResponse(
        ward_id=ward_id,
        latest_seq=latest_seq,
        events=events,
    )

@app.post("/api/v1/patients/{patient_id}/ask", response_model=AskResponse)
def ask_patient_record(patient_id: str, request: AskRequest):
    result = llm_service.query(
        patient_id=patient_id,
        query_text=request.query,
        time_window_hours=request.time_window_hours,
    )
    return AskResponse(**result)
