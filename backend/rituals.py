import json
import os
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import date, datetime, timezone
from typing import Any, Optional

from fastapi import APIRouter, Depends, Header, HTTPException
from livekit import api as livekit_api
from pydantic import BaseModel, ConfigDict, Field

from .models import CanonicalEvent, StaffProfile


RITUAL_TYPES = {"brief", "huddle", "debrief"}
RITUAL_STATUSES = {"requested", "in_progress", "draft_ready", "approved"}


def dispatch_due_notifications(api) -> None:
    now = datetime.now(timezone.utc).isoformat()
    for notification in api.ritual_store.due_notifications(now):
        staff_id = str(notification["staff_id"])
        fids = api.staff_store.get_fcm_fids_for_staff(staff_id)
        if not fids:
            api.logger.warning(
                "Clinical Ritual notification has no registered device for %s.",
                staff_id,
            )
            continue
        delivered = False
        for fid in fids:
            try:
                delivered = (
                    api.fcm_service.send_clinical_ritual_alert(
                        fid,
                        ritual_id=str(notification["ritual_id"]),
                        ritual_type=str(notification["ritual_type"]),
                        title=str(notification["title"]),
                    )
                    or delivered
                )
                if not delivered:
                    api.staff_store.remove_fcm_fid(fid)
            except Exception as error:
                api.logger.error(
                    "Clinical Ritual notification failed for %s (%s).",
                    staff_id,
                    type(error).__name__,
                )
        if delivered:
            api.ritual_store.mark_notification_delivered(
                str(notification["ritual_id"]), staff_id
            )


class RitualCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    ritual_type: str
    title: str = Field(min_length=3, max_length=200)
    patient_id: Optional[str] = Field(default=None, max_length=120)
    scheduled_for: Optional[str] = None


class TranscriptRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    transcript: str = Field(min_length=1, max_length=200000)


class RitualDraftRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    summary: dict[str, Any]


class ClinicalRitualStore:
    def __init__(self, db_path: str):
        self.db_path = db_path
        with self.connection() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS clinical_rituals (
                    ritual_id TEXT PRIMARY KEY,
                    ritual_type TEXT NOT NULL,
                    title TEXT NOT NULL,
                    patient_id TEXT,
                    creator_id TEXT NOT NULL,
                    scheduled_for TEXT,
                    status TEXT NOT NULL,
                    transcript TEXT,
                    summary_json TEXT,
                    draft_editor_id TEXT,
                    version INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    approved_by TEXT,
                    approved_at TEXT,
                    room_name TEXT,
                    egress_id TEXT,
                    recording_status TEXT,
                    recording_location TEXT
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS clinical_ritual_notifications (
                    ritual_id TEXT NOT NULL,
                    staff_id TEXT NOT NULL,
                    scheduled_for TEXT NOT NULL,
                    delivered_at TEXT,
                    PRIMARY KEY (ritual_id, staff_id)
                )
                """
            )
            for column, definition in (
                ("room_name", "TEXT"),
                ("egress_id", "TEXT"),
                ("recording_status", "TEXT"),
                ("recording_location", "TEXT"),
            ):
                try:
                    conn.execute(
                        f"ALTER TABLE clinical_rituals ADD COLUMN {column} {definition}"
                    )
                except sqlite3.OperationalError as error:
                    if "duplicate column name" not in str(error).lower():
                        raise

    @contextmanager
    def connection(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        try:
            with conn:
                yield conn
        finally:
            conn.close()

    @staticmethod
    def _row(row: sqlite3.Row) -> dict[str, Any]:
        result = dict(row)
        result["summary"] = (
            json.loads(result.pop("summary_json"))
            if result.get("summary_json")
            else None
        )
        return result

    def create(self, request: RitualCreateRequest, creator_id: str) -> dict[str, Any]:
        now = datetime.now(timezone.utc).isoformat()
        ritual_id = f"RITUAL-{uuid.uuid4()}"
        room_name = f"oravi-ritual-{uuid.uuid4().hex}"
        with self.connection() as conn:
            conn.execute(
                """
                INSERT INTO clinical_rituals (
                    ritual_id, ritual_type, title, patient_id, creator_id,
                    scheduled_for, status, created_at, updated_at, room_name,
                    recording_status
                ) VALUES (?, ?, ?, ?, ?, ?, 'requested', ?, ?, ?, 'not_started')
                """,
                (
                    ritual_id,
                    request.ritual_type,
                    request.title.strip(),
                    request.patient_id,
                    creator_id,
                    request.scheduled_for,
                    now,
                    now,
                    room_name,
                ),
            )
        return self.get(ritual_id)

    def set_recording_started(
        self, ritual_id: str, egress_id: str, room_name: str
    ) -> dict[str, Any]:
        now = datetime.now(timezone.utc).isoformat()
        with self.connection() as conn:
            conn.execute(
                """
                UPDATE clinical_rituals
                SET egress_id = ?, room_name = ?, recording_status = 'recording',
                    status = 'in_progress', updated_at = ?
                WHERE ritual_id = ?
                """,
                (egress_id, room_name, now, ritual_id),
            )
        return self.get(ritual_id)

    def find_by_room_name(self, room_name: str) -> Optional[dict[str, Any]]:
        with self.connection() as conn:
            row = conn.execute(
                "SELECT * FROM clinical_rituals WHERE room_name = ?",
                (room_name,),
            ).fetchone()
        return self._row(row) if row else None

    def set_recording_status(
        self, ritual_id: str, status: str, location: Optional[str] = None
    ) -> dict[str, Any]:
        now = datetime.now(timezone.utc).isoformat()
        with self.connection() as conn:
            conn.execute(
                """
                UPDATE clinical_rituals
                SET recording_status = ?, recording_location = COALESCE(?, recording_location),
                    updated_at = ?
                WHERE ritual_id = ?
                """,
                (status, location, now, ritual_id),
            )
        return self.get(ritual_id)

    def get(self, ritual_id: str) -> Optional[dict[str, Any]]:
        with self.connection() as conn:
            row = conn.execute(
                "SELECT * FROM clinical_rituals WHERE ritual_id = ?",
                (ritual_id,),
            ).fetchone()
        return self._row(row) if row else None

    def queue_notifications(
        self, ritual_id: str, staff_ids: list[str], scheduled_for: str
    ) -> None:
        with self.connection() as conn:
            conn.executemany(
                """
                INSERT OR IGNORE INTO clinical_ritual_notifications
                    (ritual_id, staff_id, scheduled_for)
                VALUES (?, ?, ?)
                """,
                [(ritual_id, staff_id, scheduled_for) for staff_id in staff_ids],
            )

    def due_notifications(self, now: str) -> list[dict[str, Any]]:
        with self.connection() as conn:
            return [
                dict(row)
                for row in conn.execute(
                    """
                    SELECT n.ritual_id, n.staff_id, r.ritual_type, r.title
                    FROM clinical_ritual_notifications n
                    JOIN clinical_rituals r ON r.ritual_id = n.ritual_id
                    WHERE n.delivered_at IS NULL AND n.scheduled_for <= ?
                    """,
                    (now,),
                ).fetchall()
            ]

    def mark_notification_delivered(self, ritual_id: str, staff_id: str) -> None:
        with self.connection() as conn:
            conn.execute(
                """
                UPDATE clinical_ritual_notifications
                SET delivered_at = ?
                WHERE ritual_id = ? AND staff_id = ?
                """,
                (datetime.now(timezone.utc).isoformat(), ritual_id, staff_id),
            )

    def save_transcript(self, ritual_id: str, transcript: str) -> dict[str, Any]:
        now = datetime.now(timezone.utc).isoformat()
        with self.connection() as conn:
            conn.execute(
                """
                UPDATE clinical_rituals
                SET transcript = ?, status = 'in_progress', updated_at = ?,
                    version = version + 1
                WHERE ritual_id = ?
                """,
                (transcript.strip(), now, ritual_id),
            )
        return self.get(ritual_id)

    def save_draft(
        self, ritual_id: str, summary: dict[str, Any], editor_id: Optional[str] = None
    ) -> dict[str, Any]:
        now = datetime.now(timezone.utc).isoformat()
        with self.connection() as conn:
            conn.execute(
                """
                UPDATE clinical_rituals
                SET summary_json = ?, status = 'draft_ready',
                    draft_editor_id = ?, updated_at = ?, version = version + 1
                WHERE ritual_id = ?
                """,
                (json.dumps(summary), editor_id, now, ritual_id),
            )
        return self.get(ritual_id)

    def approve(
        self, ritual_id: str, summary: dict[str, Any], approver_id: str
    ) -> dict[str, Any]:
        now = datetime.now(timezone.utc).isoformat()
        with self.connection() as conn:
            cursor = conn.execute(
                """
                UPDATE clinical_rituals
                SET summary_json = ?, status = 'approved', approved_by = ?,
                    approved_at = ?, updated_at = ?, version = version + 1
                WHERE ritual_id = ? AND status = 'draft_ready'
                """,
                (json.dumps(summary), approver_id, now, now, ritual_id),
            )
            if cursor.rowcount != 1:
                raise HTTPException(
                    status_code=409,
                    detail="Only a ready draft can be approved.",
                )
        return self.get(ritual_id)


def build_router(api):
    router = APIRouter(prefix="/api/v1/rituals")

    def clinical_staff(profile: StaffProfile = Depends(api.require_staff)):
        return profile

    def get_ritual(ritual_id: str) -> dict[str, Any]:
        ritual = api.ritual_store.get(ritual_id)
        if ritual is None:
            raise HTTPException(status_code=404, detail="Clinical Ritual not found.")
        return ritual

    @router.post("")
    def create_ritual(
        request: RitualCreateRequest,
        profile: StaffProfile = Depends(clinical_staff),
    ):
        if request.ritual_type not in RITUAL_TYPES:
            raise HTTPException(status_code=400, detail="Invalid Clinical Ritual type.")
        ritual = api.ritual_store.create(request, profile.staff_id)
        if request.patient_id:
            recipient_ids = api._authorized_patient_staff_ids(
                request.patient_id, date.today().isoformat()
            ) - {profile.staff_id}
            scheduled_for = request.scheduled_for or datetime.now(
                timezone.utc
            ).isoformat()
            api.ritual_store.queue_notifications(
                ritual["ritual_id"], sorted(recipient_ids), scheduled_for
            )
            if request.scheduled_for is None:
                dispatch_due_notifications(api)
        return ritual

    @router.get("/{ritual_id}")
    def read_ritual(
        ritual_id: str, profile: StaffProfile = Depends(clinical_staff)
    ):
        return get_ritual(ritual_id)

    @router.get("")
    def list_rituals(profile: StaffProfile = Depends(clinical_staff)):
        with api.ritual_store.connection() as conn:
            rows = conn.execute(
                "SELECT * FROM clinical_rituals ORDER BY updated_at DESC LIMIT 100"
            ).fetchall()
        visible = []
        for row in rows:
            ritual = api.ritual_store._row(row)
            if ritual["creator_id"] == profile.staff_id:
                visible.append(ritual)
                continue
            patient_id = ritual["patient_id"]
            if patient_id and profile.staff_id in api._authorized_patient_staff_ids(
                patient_id, date.today().isoformat()
            ):
                visible.append(ritual)
        return visible

    @router.post("/{ritual_id}/transcript")
    def save_transcript(
        ritual_id: str,
        request: TranscriptRequest,
        profile: StaffProfile = Depends(clinical_staff),
    ):
        get_ritual(ritual_id)
        return api.ritual_store.save_transcript(ritual_id, request.transcript)

    @router.post("/{ritual_id}/recording/start")
    async def start_recording(
        ritual_id: str,
        profile: StaffProfile = Depends(clinical_staff),
    ):
        ritual = get_ritual(ritual_id)
        if ritual["recording_status"] in {"recording", "processing"}:
            raise HTTPException(status_code=409, detail="A recording is already active.")
        try:
            recording = await api.livekit_egress_service.start_room_recording(
                room_name=ritual["room_name"],
                ritual_id=ritual_id,
            )
        except RuntimeError as error:
            raise HTTPException(status_code=503, detail=str(error)) from error
        return api.ritual_store.set_recording_started(
            ritual_id, recording["egress_id"] or "", recording["room_name"] or ""
        )

    @router.post("/{ritual_id}/room-token")
    def room_token(
        ritual_id: str,
        profile: StaffProfile = Depends(clinical_staff),
    ):
        ritual = get_ritual(ritual_id)
        return {
            "room_name": ritual["room_name"],
            "livekit_url": os.getenv("LIVEKIT_URL"),
            "token": api._livekit_token(
                profile.staff_id, profile.name, ritual["room_name"]
            ),
        }

    @router.post("/{ritual_id}/recording/stop")
    async def stop_recording(
        ritual_id: str,
        profile: StaffProfile = Depends(clinical_staff),
    ):
        ritual = get_ritual(ritual_id)
        if ritual["recording_status"] != "recording" or not ritual["egress_id"]:
            return ritual
        try:
            await api.livekit_egress_service.stop_room_recording(
                ritual["egress_id"]
            )
        except RuntimeError as error:
            raise HTTPException(status_code=503, detail=str(error)) from error
        return api.ritual_store.set_recording_status(ritual_id, "processing")

    @router.post("/webhooks/livekit")
    async def livekit_webhook(
        body: bytes,
        authorization: str = Header(default=""),
    ):
        try:
            receiver = livekit_api.WebhookReceiver(
                livekit_api.TokenVerifier(
                    os.getenv("LIVEKIT_API_KEY", ""),
                    os.getenv("LIVEKIT_API_SECRET", ""),
                )
            )
            event = receiver.receive(body.decode("utf-8"), authorization)
        except Exception as error:
            raise HTTPException(status_code=401, detail="Invalid LiveKit webhook.") from error
        if event.event != "egress_ended":
            return {"accepted": True}
        ritual = api.ritual_store.find_by_room_name(event.egress_info.room_name)
        if ritual is None:
            raise HTTPException(status_code=404, detail="Ritual recording room not found.")
        if event.egress_info.status != livekit_api.EGRESS_COMPLETE:
            api.ritual_store.set_recording_status(
                ritual["ritual_id"], "failed"
            )
            return {"accepted": True}
        if not event.egress_info.file_results:
            api.ritual_store.set_recording_status(ritual["ritual_id"], "failed")
            raise HTTPException(status_code=422, detail="LiveKit returned no recording file.")
        location = event.egress_info.file_results[0].location
        try:
            source_url = api.livekit_egress_service.recording_url(
                ritual_id=ritual["ritual_id"],
                room_name=ritual["room_name"],
                location=location,
            )
        except RuntimeError as error:
            api.ritual_store.set_recording_status(ritual["ritual_id"], "failed")
            raise HTTPException(status_code=503, detail=str(error)) from error
        api.ritual_store.set_recording_status(
            ritual["ritual_id"], "processing", location=location
        )
        try:
            transcription = api.transcription_service.transcribe_url(source_url)
        except RuntimeError as error:
            api.ritual_store.set_recording_status(ritual["ritual_id"], "failed")
            raise HTTPException(status_code=503, detail=str(error)) from error
        if not transcription["text"]:
            api.ritual_store.set_recording_status(ritual["ritual_id"], "failed")
            raise HTTPException(status_code=422, detail="No speech was transcribed.")
        saved = api.ritual_store.save_transcript(
            ritual["ritual_id"], transcription["text"]
        )
        api.ritual_store.set_recording_status(ritual["ritual_id"], "transcribed")
        return {"accepted": True, "ritual_id": saved["ritual_id"]}

    @router.post("/{ritual_id}/draft")
    def generate_draft(
        ritual_id: str, profile: StaffProfile = Depends(clinical_staff)
    ):
        ritual = get_ritual(ritual_id)
        if not ritual["transcript"]:
            raise HTTPException(status_code=409, detail="A transcript is required.")
        summary = api.llm_service.summarize_ritual(
            ritual_type=ritual["ritual_type"],
            title=ritual["title"],
            transcript=ritual["transcript"],
        )
        return api.ritual_store.save_draft(ritual_id, summary)

    @router.put("/{ritual_id}/draft")
    def edit_draft(
        ritual_id: str,
        request: RitualDraftRequest,
        profile: StaffProfile = Depends(clinical_staff),
    ):
        ritual = get_ritual(ritual_id)
        if ritual["status"] != "draft_ready":
            raise HTTPException(status_code=409, detail="No editable draft is ready.")
        return api.ritual_store.save_draft(
            ritual_id, request.summary, editor_id=profile.staff_id
        )

    @router.post("/{ritual_id}/approve")
    def approve_draft(
        ritual_id: str,
        request: RitualDraftRequest,
        profile: StaffProfile = Depends(clinical_staff),
    ):
        ritual = get_ritual(ritual_id)
        approved = api.ritual_store.approve(
            ritual_id, request.summary, profile.staff_id
        )
        event = CanonicalEvent(
            event_id=str(uuid.uuid4()),
            patient_id=ritual["patient_id"] or "",
            type="ClinicalRitualApproved",
            author_id=profile.staff_id,
            device_id=f"RITUAL-{ritual_id}",
            client_created_at=approved["approved_at"],
            payload={
                "ritual_id": ritual_id,
                "ritual_type": ritual["ritual_type"],
                "title": ritual["title"],
                "summary": approved["summary"],
                "transcript_retained": bool(approved["transcript"]),
            },
        )
        api.store.append_events([event])
        return approved

    return router
