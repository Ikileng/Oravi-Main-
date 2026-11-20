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
RITUAL_STATUSES = {"requested", "in_progress", "draft_ready", "approved", "ended"}


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
    patient_id: str = Field(min_length=1, max_length=120)
    participant_ids: list[str] = Field(default_factory=list, max_length=50)
    scheduled_for: Optional[datetime] = None


class RitualParticipantRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    staff_id: str = Field(min_length=1, max_length=120)


class RecordingConsentRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    consent: bool


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
                    recording_location TEXT,
                    recording_consent_by TEXT,
                    recording_consent_at TEXT
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
            conn.execute(
                """CREATE TABLE IF NOT EXISTS clinical_ritual_participants (
                    ritual_id TEXT NOT NULL, staff_id TEXT NOT NULL,
                    source TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'invited',
                    invited_by TEXT NOT NULL, created_at TEXT NOT NULL,
                    accepted_at TEXT,
                    PRIMARY KEY (ritual_id, staff_id))"""
            )
            for column, definition in (
                ("room_name", "TEXT"),
                ("egress_id", "TEXT"),
                ("recording_status", "TEXT"),
                ("recording_location", "TEXT"),
                ("recording_consent_by", "TEXT"),
                ("recording_consent_at", "TEXT"),
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
                    request.scheduled_for.astimezone(timezone.utc).isoformat() if request.scheduled_for else None,
                    now,
                    now,
                    room_name,
                ),
            )
        return self.get(ritual_id)

    def add_participant(self, ritual_id: str, staff_id: str, source: str, invited_by: str) -> bool:
        with self.connection() as conn:
            return conn.execute(
                """INSERT OR IGNORE INTO clinical_ritual_participants
                   (ritual_id,staff_id,source,status,invited_by,created_at)
                   VALUES (?,?,?,'invited',?,?)""",
                (ritual_id, staff_id, source, invited_by, datetime.now(timezone.utc).isoformat()),
            ).rowcount == 1

    def participant(self, ritual_id: str, staff_id: str) -> Optional[dict[str, Any]]:
        with self.connection() as conn:
            row = conn.execute(
                "SELECT * FROM clinical_ritual_participants WHERE ritual_id=? AND staff_id=?",
                (ritual_id, staff_id),
            ).fetchone()
        return dict(row) if row else None

    def participants(self, ritual_id: str) -> list[dict[str, Any]]:
        with self.connection() as conn:
            return [dict(row) for row in conn.execute(
                "SELECT * FROM clinical_ritual_participants WHERE ritual_id=? ORDER BY created_at",
                (ritual_id,),
            ).fetchall()]

    def accept_participant(self, ritual_id: str, staff_id: str) -> bool:
        with self.connection() as conn:
            cursor = conn.execute(
                """UPDATE clinical_ritual_participants SET status='accepted',accepted_at=?
                   WHERE ritual_id=? AND staff_id=? AND status='invited'""",
                (datetime.now(timezone.utc).isoformat(), ritual_id, staff_id),
            )
        return cursor.rowcount == 1

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
                SET recording_status = ?, status = CASE
                    WHEN ? IN ('processing','failed','transcribed') THEN 'ended'
                    WHEN ?='declined' THEN 'in_progress'
                    ELSE status END,
                    recording_location = COALESCE(?, recording_location),
                    updated_at = ?
                WHERE ritual_id = ?
                """,
                (status, status, status, location, now, ritual_id),
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
                SET transcript = ?, status = 'ended', updated_at = ?,
                    version = version + 1
                WHERE ritual_id = ?
                """,
                (transcript.strip(), now, ritual_id),
            )
        return self.get(ritual_id)

    def end_without_recording(self, ritual_id: str) -> dict[str, Any]:
        now = datetime.now(timezone.utc).isoformat()
        with self.connection() as conn:
            conn.execute("UPDATE clinical_rituals SET status='ended', updated_at=? WHERE ritual_id=?", (now, ritual_id))
        return self.get(ritual_id)

    def record_consent(self, ritual_id: str, staff_id: str, consent: bool) -> None:
        with self.connection() as conn:
            conn.execute(
                "UPDATE clinical_rituals SET recording_consent_by=?,recording_consent_at=?,recording_status=? WHERE ritual_id=?",
                (staff_id, datetime.now(timezone.utc).isoformat(), "consented" if consent else "declined", ritual_id),
            )

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

    def authorized(ritual: dict[str, Any], profile: StaffProfile, *, require_acceptance: bool = False) -> None:
        if ritual["creator_id"] == profile.staff_id:
            return
        is_care_team = bool(ritual["patient_id"]) and profile.staff_id in api._authorized_patient_staff_ids(
            ritual["patient_id"], date.today().isoformat()
        )
        participant = api.ritual_store.participant(ritual["ritual_id"], profile.staff_id)
        if not is_care_team and participant is None:
            raise HTTPException(status_code=404, detail="Clinical Ritual not found.")
        if require_acceptance and not is_care_team and participant["status"] != "accepted":
            raise HTTPException(status_code=403, detail="Accept the invitation before joining.")

    def protect_unaccepted_invitation(ritual: dict[str, Any], profile: StaffProfile) -> dict[str, Any]:
        participant = api.ritual_store.participant(ritual["ritual_id"], profile.staff_id)
        in_team = bool(ritual["patient_id"]) and profile.staff_id in api._authorized_patient_staff_ids(ritual["patient_id"], date.today().isoformat())
        if participant and participant["status"] != "accepted" and not in_team:
            ritual["transcript"] = None
            ritual["summary"] = None
            ritual["recording_location"] = None
            ritual["egress_id"] = None
        return ritual

    def queue_invitation(api, ritual: dict[str, Any], staff_id: str, scheduled_for: datetime) -> None:
        api.ritual_store.queue_notifications(
            ritual["ritual_id"], [staff_id], scheduled_for.astimezone(timezone.utc).isoformat()
        )

    def ensure_scheduled_time_reached(ritual: dict[str, Any]) -> None:
        scheduled = ritual.get("scheduled_for")
        if scheduled and datetime.fromisoformat(scheduled).astimezone(timezone.utc) > datetime.now(timezone.utc):
            raise HTTPException(status_code=409, detail="This ritual has not reached its scheduled start time.")

    @router.get("/staff-search")
    def staff_search(q: str = "", patient_id: str = "", profile: StaffProfile = Depends(clinical_staff)):
        if not patient_id or not api._staff_can_access_patient(profile, patient_id, date.today().isoformat()):
            raise HTTPException(status_code=403, detail="You do not have access to this patient.")
        from .staff_roles import CLINICAL_ROLES
        team_ids = api._authorized_patient_staff_ids(patient_id, date.today().isoformat())
        query = q.strip().casefold()
        return [
            {"staff_id": person.staff_id, "name": person.name, "role": person.role,
             "care_team": person.staff_id in team_ids}
            for person in api.staff_store.list_staff()
            if person.is_active and person.role in CLINICAL_ROLES
            and (not query or query in f"{person.name} {person.staff_id}".casefold())
        ]

    @router.post("")
    def create_ritual(
        request: RitualCreateRequest,
        profile: StaffProfile = Depends(clinical_staff),
    ):
        if request.ritual_type not in RITUAL_TYPES:
            raise HTTPException(status_code=400, detail="Invalid Clinical Ritual type.")
        if not api._staff_can_access_patient(profile, request.patient_id, date.today().isoformat()):
            raise HTTPException(status_code=403, detail="You do not have access to this patient.")
        if request.ritual_type == "huddle" and request.scheduled_for is not None:
            raise HTTPException(status_code=400, detail="Huddles start immediately.")
        scheduled = request.scheduled_for
        if scheduled is not None:
            if scheduled.tzinfo is None:
                raise HTTPException(status_code=400, detail="Scheduled time must include a timezone.")
            scheduled = scheduled.astimezone(timezone.utc)
            if scheduled <= datetime.now(timezone.utc):
                raise HTTPException(status_code=400, detail="Scheduled time must be in the future.")
        normalized = request.model_copy(update={"title": request.title.strip(), "scheduled_for": scheduled})
        if len(normalized.title) < 3:
            raise HTTPException(status_code=422, detail="Title must contain at least three characters.")
        team_ids = api._authorized_patient_staff_ids(request.patient_id, date.today().isoformat())
        selected_ids = (set(request.participant_ids) | team_ids) - {profile.staff_id}
        active_clinicians = {p.staff_id for p in api.staff_store.list_staff() if p.is_active and p.role in {"ward_nurse", "charge_nurse", "doctor_on_call"}}
        if not selected_ids <= active_clinicians:
            raise HTTPException(status_code=400, detail="One or more ritual participants are unavailable.")
        ritual = api.ritual_store.create(normalized, profile.staff_id)
        moment = scheduled or datetime.now(timezone.utc)
        for staff_id in sorted(selected_ids):
            source = "care_team" if staff_id in team_ids else "added"
            api.ritual_store.add_participant(ritual["ritual_id"], staff_id, source, profile.staff_id)
            queue_invitation(api, ritual, staff_id, moment)
        if scheduled is None:
            dispatch_due_notifications(api)
        ritual["participants"] = api.ritual_store.participants(ritual["ritual_id"])
        return ritual

    @router.get("")
    def list_rituals(profile: StaffProfile = Depends(clinical_staff)):
        with api.ritual_store.connection() as conn:
            rows = conn.execute(
                "SELECT * FROM clinical_rituals ORDER BY updated_at DESC LIMIT 100"
            ).fetchall()
        visible = []
        for row in rows:
            ritual = api.ritual_store._row(row)
            ritual["participants"] = api.ritual_store.participants(ritual["ritual_id"])
            if ritual["creator_id"] == profile.staff_id:
                visible.append(ritual)
                continue
            patient_id = ritual["patient_id"]
            if (patient_id and profile.staff_id in api._authorized_patient_staff_ids(patient_id, date.today().isoformat())) or api.ritual_store.participant(ritual["ritual_id"], profile.staff_id):
                current = api.ritual_store.participant(ritual["ritual_id"], profile.staff_id)
                ritual["participant_status"] = current["status"] if current else None
                visible.append(protect_unaccepted_invitation(ritual, profile))
        return visible

    @router.get("/alerts")
    def ritual_alerts(profile: StaffProfile = Depends(clinical_staff)):
        """Return only rituals that still need attention on the Home screen."""
        with api.ritual_store.connection() as conn:
            rows = conn.execute(
                "SELECT * FROM clinical_rituals "
                "WHERE status IN ('requested','in_progress','draft_ready','ended') "
                "ORDER BY updated_at DESC LIMIT 100"
            ).fetchall()

        alerts = []
        for row in rows:
            ritual = api.ritual_store._row(row)
            is_creator = ritual["creator_id"] == profile.staff_id
            participant = api.ritual_store.participant(
                ritual["ritual_id"], profile.staff_id
            )
            if is_creator:
                # A ready draft (or a transcribed recording whose summary
                # generation can be retried) is a fresh review task.
                is_review_task = ritual["status"] == "draft_ready" or (
                    ritual["status"] == "ended"
                    and ritual.get("recording_status") == "transcribed"
                )
                if ritual["status"] not in {"requested", "in_progress"} and not is_review_task:
                    continue
                alert_type = "review" if is_review_task else "active"
            elif participant is not None:
                if ritual["status"] not in {"requested", "in_progress"}:
                    continue
                if participant["status"] not in {"invited", "accepted"}:
                    continue
                alert_type = "invitation" if participant["status"] == "invited" else "active"
            else:
                # Care-team visibility alone is not an invitation or alert.
                continue

            ritual["participants"] = api.ritual_store.participants(ritual["ritual_id"])
            ritual["participant_status"] = participant["status"] if participant else None
            ritual["alert_type"] = alert_type
            alerts.append(protect_unaccepted_invitation(ritual, profile))
        return alerts

    @router.get("/{ritual_id}")
    def read_ritual(
        ritual_id: str, profile: StaffProfile = Depends(clinical_staff)
    ):
        ritual = get_ritual(ritual_id)
        authorized(ritual, profile)
        ritual["participants"] = api.ritual_store.participants(ritual_id)
        current = api.ritual_store.participant(ritual_id, profile.staff_id)
        ritual["participant_status"] = current["status"] if current else None
        return protect_unaccepted_invitation(ritual, profile)

    @router.post("/{ritual_id}/participants")
    def add_ritual_participant(ritual_id: str, request: RitualParticipantRequest, profile: StaffProfile = Depends(clinical_staff)):
        ritual = get_ritual(ritual_id)
        if ritual["creator_id"] != profile.staff_id or ritual["status"] in {"approved", "ended"}:
            raise HTTPException(status_code=403, detail="Only the initiator can invite participants during an active ritual.")
        person = next((p for p in api.staff_store.list_staff() if p.staff_id == request.staff_id and p.is_active and p.role in {"ward_nurse", "charge_nurse", "doctor_on_call"}), None)
        if person is None:
            raise HTTPException(status_code=404, detail="Clinician not found.")
        if not api.ritual_store.add_participant(ritual_id, person.staff_id, "added", profile.staff_id):
            raise HTTPException(status_code=409, detail="This clinician has already been invited.")
        moment = datetime.now(timezone.utc) if ritual["status"] == "in_progress" else datetime.fromisoformat(ritual["scheduled_for"]) if ritual.get("scheduled_for") else datetime.now(timezone.utc)
        queue_invitation(api, ritual, person.staff_id, moment)
        if moment <= datetime.now(timezone.utc):
            dispatch_due_notifications(api)
        return {"success": True, "participant": api.ritual_store.participant(ritual_id, person.staff_id)}

    @router.post("/{ritual_id}/accept")
    def accept_invitation(ritual_id: str, profile: StaffProfile = Depends(clinical_staff)):
        get_ritual(ritual_id)
        if not api.ritual_store.accept_participant(ritual_id, profile.staff_id):
            participant = api.ritual_store.participant(ritual_id, profile.staff_id)
            if participant is None or participant["status"] != "accepted":
                raise HTTPException(status_code=403, detail="No active invitation was found.")
        return {"success": True}

    @router.post("/{ritual_id}/recording/start")
    async def start_recording(
        ritual_id: str,
        request: RecordingConsentRequest,
        profile: StaffProfile = Depends(clinical_staff),
    ):
        ritual = get_ritual(ritual_id)
        authorized(ritual, profile, require_acceptance=True)
        ensure_scheduled_time_reached(ritual)
        if ritual["creator_id"] != profile.staff_id:
            raise HTTPException(status_code=403, detail="Only the initiator can authorize recording.")
        api.ritual_store.record_consent(ritual_id, profile.staff_id, request.consent)
        if not request.consent:
            api.ritual_store.set_recording_status(ritual_id, "declined")
            return api.ritual_store.get(ritual_id)
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
        authorized(ritual, profile, require_acceptance=True)
        ensure_scheduled_time_reached(ritual)
        return {
            "room_name": ritual["room_name"],
            "livekit_url": os.getenv("LIVEKIT_PUBLIC_URL") or os.getenv("LIVEKIT_URL"),
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
        authorized(ritual, profile, require_acceptance=True)
        if ritual["creator_id"] != profile.staff_id:
            raise HTTPException(status_code=403, detail="Only the initiator can end the ritual.")
        if ritual["recording_status"] == "recording" and ritual["egress_id"]:
            try:
                await api.livekit_egress_service.stop_room_recording(ritual["egress_id"])
            except RuntimeError as error:
                raise HTTPException(status_code=503, detail=str(error)) from error
            api.ritual_store.set_recording_status(ritual_id, "processing")
        else:
            api.ritual_store.end_without_recording(ritual_id)
        return api.ritual_store.get(ritual_id)

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
        if ritual["status"] in {"draft_ready", "approved"}:
            return {"accepted": True, "ritual_id": ritual["ritual_id"], "status": ritual["status"]}
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
            if os.getenv("TRANSCRIPTION_PROVIDER", "elevenlabs").strip().lower() == "whisper_local":
                transcription = api.transcription_service.transcribe_file(source_url)
            else:
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
        try:
            summary = api.llm_service.summarize_ritual(
                ritual_type=ritual["ritual_type"], title=ritual["title"], transcript=transcription["text"]
            )
        except Exception as error:
            api.logger.error("Clinical Ritual summary generation failed (%s).", type(error).__name__)
            raise HTTPException(status_code=503, detail="Transcript saved; summary generation can be retried from Home.") from error
        draft = api.ritual_store.save_draft(ritual["ritual_id"], summary)
        for fid in api.staff_store.get_fcm_fids_for_staff(ritual["creator_id"]):
            try:
                if not api.fcm_service.send_clinical_ritual_review_alert(fid, ritual_id=ritual["ritual_id"], title=ritual["title"]):
                    api.staff_store.remove_fcm_fid(fid)
            except Exception as error:
                api.logger.error("Clinical Ritual review alert failed (%s).", type(error).__name__)
        return {"accepted": True, "ritual_id": saved["ritual_id"], "status": draft["status"]}

    @router.post("/{ritual_id}/draft")
    def generate_draft(
        ritual_id: str, profile: StaffProfile = Depends(clinical_staff)
    ):
        ritual = get_ritual(ritual_id)
        authorized(ritual, profile)
        if ritual["creator_id"] != profile.staff_id:
            raise HTTPException(status_code=403, detail="Only the initiator can prepare the review draft.")
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
        authorized(ritual, profile)
        if ritual["creator_id"] != profile.staff_id:
            raise HTTPException(status_code=403, detail="Only the initiator can edit the review draft.")
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
        authorized(ritual, profile)
        if ritual["creator_id"] != profile.staff_id:
            raise HTTPException(status_code=403, detail="Only the initiator can approve the summary.")
        if ritual["status"] == "approved":
            return ritual
        if ritual["status"] != "draft_ready":
            raise HTTPException(status_code=409, detail="Only a ready draft can be approved.")
        now = datetime.now(timezone.utc).isoformat()
        event = CanonicalEvent(
            event_id=str(uuid.uuid4()),
            patient_id=ritual["patient_id"] or "",
            type="ClinicalRitualApproved",
            author_id=profile.staff_id,
            device_id=f"RITUAL-{ritual_id}",
            client_created_at=now,
            payload={
                "ritual_id": ritual_id,
                "ritual_type": ritual["ritual_type"],
                "title": ritual["title"],
                "summary": request.summary,
                "transcript_retained": bool(ritual["transcript"]),
            },
        )
        def approve_in_event_transaction(conn):
            cursor = conn.execute(
                """UPDATE clinical_rituals SET summary_json=?,status='approved',approved_by=?,
                   approved_at=?,updated_at=?,version=version+1 WHERE ritual_id=? AND status='draft_ready'""",
                (json.dumps(request.summary), profile.staff_id, now, now, ritual_id),
            )
            if cursor.rowcount != 1:
                raise HTTPException(status_code=409, detail="Only a ready draft can be approved.")
        api.store.append_events([event], transaction_action=approve_in_event_transaction)
        return api.ritual_store.get(ritual_id)

    return router
