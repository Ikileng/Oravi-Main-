import secrets
from fastapi import FastAPI, Query, HTTPException, status
from .models import (
    SyncPushRequest, SyncPushResponse, SyncPullResponse, AskRequest, AskResponse,
    StaffLoginRequest, StaffLoginResponse, CreateStaffRequest, StaffListResponse, StaffProfile
)
from .event_store import EventStore
from .staff_store import StaffStore
from .services.llm_service import LLMService
from .seed_data import seed_store_if_empty

app = FastAPI(
    title="Oravi Ward Sync and Clinical Auth API",
    description="Offline-first clinical event stream, hash chain and Digital ID authentication backend",
    version="0.2.0",
)

store = EventStore()
seed_store_if_empty(store)
staff_store = StaffStore()
llm_service = LLMService(store=store)

@app.get("/health")
def health_check():
    return {"status": "ok", "service": "oravi-backend", "version": "0.2.0"}

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
