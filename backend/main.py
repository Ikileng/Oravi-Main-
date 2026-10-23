from fastapi import FastAPI, Query
from .models import SyncPushRequest, SyncPushResponse, SyncPullResponse, AskRequest, AskResponse
from .event_store import EventStore
from .services.llm_service import LLMService

app = FastAPI(
    title="Oravi Ward Sync API",
    description="Offline-first clinical event stream & hash chain backend (Tech Arch Section 10)",
    version="0.1.0",
)

store = EventStore()
llm_service = LLMService(store=store)

@app.get("/health")
def health_check():
    return {"status": "ok", "service": "oravi-backend", "version": "0.1.0"}

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
