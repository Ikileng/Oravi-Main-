"""
Seed data module for Oravi Ward 4B (PRD Section 7.1, 7.2 & Tech Arch Section 4).
Matches lib/data/mock/seeded_ward_data.dart so the Python server and mobile app
share the exact same baseline patient event stream.
"""
from datetime import datetime, timezone, timedelta
from typing import List
from .models import CanonicalEvent
from .event_store import EventStore

def get_ward_seed_events() -> List[CanonicalEvent]:
    now = datetime.now(timezone.utc)
    t_minus_4h = (now - timedelta(hours=4)).isoformat()
    t_minus_2h = (now - timedelta(hours=2)).isoformat()
    t_minus_30m = (now - timedelta(minutes=30)).isoformat()

    return [
        # Bed 1: John K. (Admitted with severe pneumonia, oxygen requirements)
        CanonicalEvent(
            event_id="0192a5b6-0001-7000-8000-000000000001",
            patient_id="PAT-4B-01",
            author_id="NURSE-MWANGI",
            device_id="PHONE-WARD4B-SHARED",
            client_created_at=t_minus_4h,
            type="PatientAdmitted",
            payload={
                "ward_id": "WARD-4B",
                "bed_number": "Bed 1",
                "admission_number": "ADM-2026-8812",
                "name_or_initials": "J.K.",
                "age": 58,
                "sex": "M",
                "short_admitting_note": "Severe CAP; bilateral crackles, SpO2 88% on room air on arrival.",
                "key_alerts": ["Penicillin allergy", "Fall risk"],
            },
        ),
        CanonicalEvent(
            event_id="0192a5b6-0001-7000-8000-000000000002",
            patient_id="PAT-4B-01",
            loop_id="LOOP-4B-01-A",
            author_id="NURSE-MWANGI",
            device_id="PHONE-WARD4B-SHARED",
            client_created_at=t_minus_4h,
            type="LoopOpened",
            payload={
                "title": "Maintain SpO2 > 92% on nasal cannula",
                "description": "Currently on 2L/min. If dropping below 90, notify medical officer.",
                "loop_type": "taskOrPendingResult",
                "urgency": "urgent",
                "initial_owner_id": "NURSE-MWANGI",
                "initial_owner_role": "ward_nurse",
            },
        ),
        CanonicalEvent(
            event_id="0192a5b6-0001-7000-8000-000000000003",
            patient_id="PAT-4B-01",
            loop_id="LOOP-4B-01-A",
            author_id="NURSE-MWANGI",
            device_id="PHONE-WARD4B-SHARED",
            client_created_at=t_minus_2h,
            type="MessagePosted",
            payload={
                "message_id": "MSG-01-01",
                "content": "SpO2 stable at 94% on 2L nasal prongs. Patient resting comfortably.",
            },
        ),

        # Bed 2: Peter O. (Post-op Day 1 Laparotomy, STAT repeat hemoglobin needed)
        CanonicalEvent(
            event_id="0192a5b6-0002-7000-8000-000000000001",
            patient_id="PAT-4B-02",
            author_id="NURSE-MWANGI",
            device_id="PHONE-WARD4B-SHARED",
            client_created_at=t_minus_4h,
            type="PatientAdmitted",
            payload={
                "ward_id": "WARD-4B",
                "bed_number": "Bed 2",
                "admission_number": "ADM-2026-8834",
                "name_or_initials": "P.O.",
                "age": 42,
                "sex": "M",
                "short_admitting_note": "POD 1 exploratory laparotomy for perforated ulcer. Abdominal drain in situ.",
                "key_alerts": ["NPO", "Strict fluid balance"],
            },
        ),
        CanonicalEvent(
            event_id="0192a5b6-0002-7000-8000-000000000002",
            patient_id="PAT-4B-02",
            loop_id="LOOP-4B-02-STAT",
            author_id="DOC-OTIENO",
            device_id="PHONE-WARD4B-SHARED",
            client_created_at=t_minus_2h,
            type="LoopOpened",
            payload={
                "title": "STAT: Draw urgent Hb and cross-match 2 units PRBC",
                "description": "Drain output 250ml serosanguinous in 2 hrs, BP 90/60.",
                "loop_type": "escalation",
                "urgency": "critical",
                "initial_owner_id": "NURSE-MWANGI",
                "initial_owner_role": "ward_nurse",
            },
        ),
        CanonicalEvent(
            event_id="0192a5b6-0002-7000-8000-000000000003",
            patient_id="PAT-4B-02",
            loop_id="LOOP-4B-02-STAT",
            author_id="NURSE-MWANGI",
            device_id="PHONE-WARD4B-SHARED",
            client_created_at=t_minus_30m,
            type="EscalationRaised",
            payload={
                "escalation_id": "ESC-4B-02-1",
                "target_role": "doctor_on_call",
                "initial_target_user_id": "DOC-OTIENO",
                "escalation_reason": "Lab called: Hb is 7.1 g/dL. Requesting urgent blood bank release confirmation.",
                "timeout_minutes": 15,
            },
        ),

        # Bed 3: David M. (Diabetic Ketoacidosis resolution, regular insulin sliding scale)
        CanonicalEvent(
            event_id="0192a5b6-0003-7000-8000-000000000001",
            patient_id="PAT-4B-03",
            author_id="NURSE-MWANGI",
            device_id="PHONE-WARD4B-SHARED",
            client_created_at=t_minus_4h,
            type="PatientAdmitted",
            payload={
                "ward_id": "WARD-4B",
                "bed_number": "Bed 3",
                "admission_number": "ADM-2026-8790",
                "name_or_initials": "D.M.",
                "age": 29,
                "sex": "M",
                "short_admitting_note": "DKA on resolution. Transitioned to subQ sliding scale insulin.",
                "key_alerts": ["Type 1 Diabetes Mellitus"],
            },
        ),
        CanonicalEvent(
            event_id="0192a5b6-0003-7000-8000-000000000002",
            patient_id="PAT-4B-03",
            loop_id="LOOP-4B-03-A",
            author_id="NURSE-MWANGI",
            device_id="PHONE-WARD4B-SHARED",
            client_created_at=t_minus_4h,
            type="LoopOpened",
            payload={
                "title": "Check 2-hourly blood glucose & record in counter-book",
                "description": "Notify MO if random blood sugar > 14 mmol/L or < 4 mmol/L.",
                "loop_type": "taskOrPendingResult",
                "urgency": "routine",
                "initial_owner_id": "NURSE-MWANGI",
                "initial_owner_role": "ward_nurse",
            },
        ),

        # Bed 4: Samuel W. (Cellulitis - Loop recently closed to test audit history)
        CanonicalEvent(
            event_id="0192a5b6-0004-7000-8000-000000000001",
            patient_id="PAT-4B-04",
            author_id="NURSE-MWANGI",
            device_id="PHONE-WARD4B-SHARED",
            client_created_at=t_minus_4h,
            type="PatientAdmitted",
            payload={
                "ward_id": "WARD-4B",
                "bed_number": "Bed 4",
                "admission_number": "ADM-2026-8855",
                "name_or_initials": "S.W.",
                "age": 63,
                "sex": "M",
                "short_admitting_note": "Right lower limb cellulitis. Day 3 IV Ceftriaxone.",
                "key_alerts": ["Hypertension"],
            },
        ),
        CanonicalEvent(
            event_id="0192a5b6-0004-7000-8000-000000000002",
            patient_id="PAT-4B-04",
            loop_id="LOOP-4B-04-A",
            author_id="NURSE-MWANGI",
            device_id="PHONE-WARD4B-SHARED",
            client_created_at=t_minus_4h,
            type="LoopOpened",
            payload={
                "title": "Administer IV Ceftriaxone 2g daily dose",
                "description": "Due at 14:00 after cannula patency check.",
                "loop_type": "taskOrPendingResult",
                "urgency": "routine",
                "initial_owner_id": "NURSE-MWANGI",
                "initial_owner_role": "ward_nurse",
            },
        ),
        CanonicalEvent(
            event_id="0192a5b6-0004-7000-8000-000000000003",
            patient_id="PAT-4B-04",
            loop_id="LOOP-4B-04-A",
            author_id="NURSE-MWANGI",
            device_id="PHONE-WARD4B-SHARED",
            client_created_at=t_minus_30m,
            type="LoopClosed",
            payload={
                "reason_code": "medication_given",
                "free_text_note": "2g Ceftriaxone in 100ml NS infused over 30 mins. Site clean.",
                "resolution_type": "resolved",
            },
        ),

        # Bed 5: Joseph K. (Snr) (Routine post-reduction fracture - All clear / zero pending)
        CanonicalEvent(
            event_id="0192a5b6-0005-7000-8000-000000000001",
            patient_id="PAT-4B-05",
            author_id="NURSE-MWANGI",
            device_id="PHONE-WARD4B-SHARED",
            client_created_at=t_minus_4h,
            type="PatientAdmitted",
            payload={
                "ward_id": "WARD-4B",
                "bed_number": "Bed 5",
                "admission_number": "ADM-2026-8890",
                "name_or_initials": "J.K. (Snr)",
                "age": 71,
                "sex": "M",
                "short_admitting_note": "Closed right Colles fracture post-cast application. Limb elevated.",
                "key_alerts": ["No known allergies"],
            },
        ),
    ]

def seed_store_if_empty(store: EventStore) -> int:
    """Populates the in-memory EventStore with baseline events if empty."""
    events, _ = store.get_events_since(since_seq=0, limit=1)
    if not events:
        seed_events = get_ward_seed_events()
        store.append_events(seed_events)
        return len(seed_events)
    return 0
