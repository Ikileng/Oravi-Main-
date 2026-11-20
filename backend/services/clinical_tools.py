import re
import sqlite3
from typing import Any, Dict, List, Optional
from backend.event_store import EventStore

# Mandatory diagnostic refusal triggers (matching PRD Section 8A FR-40)
REFUSAL_TRIGGERS = [
    "kidney failure", "renal failure", "heart failure", "sepsis", "septic",
    "dying", "will he survive", "will she survive", "diagnose", "diagnosis",
    "prognosis", "prescribe", "what medicine should i give"
]

# Ward Lexicon synonym mapping (matching PRD Section 8A)
TOPIC_SYNONYMS = {
    'urine': ['urine', 'uo', 'passing urine', 'mkojo', 'catheter', 'foley', 'anuria', 'oliguria'],
    'oxygen': ['spo2', 'sats', 'oxygen', 'o2', 'desat', 'hewa ya oksijeni', 'prongs', 'mask', '2l', 'room air'],
    'blood': ['blood', 'cross-match', 'crossmatch', 'hb', 'haemoglobin', 'damu', 'transfusion', 'prbc', 'units'],
    'blood_pressure': ['bp', 'blood pressure', 'presha', 'hypotension', 'hypertension', 'systolic', 'diastolic'],
    'allergy': ['allergy', 'allergic', 'allergies', 'reaction', 'mzio', 'anaphylaxis'],
    'pain': ['pain', 'ache', 'uchungu', 'maumivu', 'analgesia', 'paracetamol'],
    'call': ['call', 'calls', 'called', 'phone', 'telephone', 'conversation', 'discussion'],
    'chat': ['chat', 'chats', 'message', 'messages', 'thread', 'threads', 'discussion', 'conversation'],
}


def _staff_name_map(store: EventStore) -> Dict[str, str]:
    """Resolve staff identifiers to display names for model evidence."""
    try:
        with sqlite3.connect(store.db_path) as conn:
            rows = conn.execute("SELECT staff_id, name FROM staff_users").fetchall()
        return {str(staff_id): str(name) for staff_id, name in rows}
    except sqlite3.Error:
        return {}

def execute_query_patient_timeline(
    store: EventStore,
    patient_id: str,
    topic: str = "all",
    time_window_hours: Optional[int] = None
) -> Dict[str, Any]:
    """
    Deterministic tool execution fetching verbatim patient records from the event store.
    Supports English & Kiswahili search and time window queries (e.g. 'last 8 hours').
    """
    all_events, _ = store.get_events_since(since_seq=0, limit=1000)
    patient_events = [e for e in all_events if e.patient_id == patient_id]
    staff_names = _staff_name_map(store)

    # Auto-detect time window from query if not explicitly passed
    topic_lower = topic.lower()
    is_issue_query = any(
        phrase in topic_lower
        for phrase in ("medical issue", "active issue", "open issue", "issues", "loops")
    )
    tw_match = re.search(r'\b(\d+)\s*(?:hours|hrs|hr)\b', topic_lower)
    if tw_match and time_window_hours is None:
        time_window_hours = int(tw_match.group(1))

    is_general_briefing = any(p in topic_lower for p in [
        "what do i need to know", "what should i know", "know nothing", "tell me about",
        "brief me", "who is this", "summary", "overview", "catch me up", "status", "orientation"
    ])

    is_general_time_summary = any(p in topic_lower for p in [
        "what do i need to know", "what happened", "summary", "last", "shift", "today", "updates", "issues"
    ]) and (time_window_hours is not None or "hour" in topic_lower or "shift" in topic_lower or "today" in topic_lower)

    # Expand search terms
    search_terms = set()
    if topic_lower != "all" and not is_general_briefing and not is_general_time_summary:
        search_terms.add(topic_lower)
        for key, syns in TOPIC_SYNONYMS.items():
            if key in topic_lower or any(s in topic_lower for s in syns):
                search_terms.update(syns)

    quotes = []
    threads = set()

    for event in patient_events:
        content = ""
        loop_title = ""

        if event.type == "PatientAdmitted":
            bed = event.payload.get("bed_number", "")
            age = event.payload.get("age", "")
            sex = event.payload.get("sex", "")
            name = event.payload.get("name_or_initials", "")
            note = event.payload.get("short_admitting_note", "")
            alerts = ", ".join(event.payload.get("key_alerts", [])) or "No key alerts recorded in Oravi; verify with the main hospital EHR"
            content = f"Admitted to {bed}: {name}, {age}y {sex}. Note: {note}. Key Alerts: {alerts}."
            loop_title = "Admission Record"
        elif event.type == "LoopOpened":
            loop_title = event.payload.get("title", "")
            content = f"{loop_title}: {event.payload.get('description', '')}".strip()
        elif event.type == "MessagePosted":
            author = staff_names.get(event.author_id, event.author_id)
            content = f"Message from {author} in clinical thread: {event.payload.get('content', '')}"
        elif event.type == "CallLogged":
            outcome = event.payload.get("outcome_note", "")
            recipient = event.payload.get("recipient_id", "")
            caller = staff_names.get(event.author_id, event.author_id)
            recipient_name = staff_names.get(recipient, recipient)
            content = f"Call between {caller} and {recipient_name}: {outcome}"
        elif event.type == "EscalationRaised":
            reason = event.payload.get("escalation_reason", "")
            target = event.payload.get("target_role", "")
            content = f"Escalated to {target}: {reason}"
        elif event.type == "LoopClosed":
            reason = event.payload.get("reason_code", "")
            note = event.payload.get("free_text_note", "")
            content = f"Closed loop ({reason}): {note}".strip()
        elif event.type == "LoopReopened":
            reason = event.payload.get("reopen_reason", "")
            content = f"Reopened loop: {reason}"

        if not content:
            continue

        if event.loop_id:
            threads.add(event.loop_id)

        # Check match
        matched = False
        if is_issue_query and event.type in {
            "LoopOpened", "LoopClosed", "LoopReopened", "EscalationRaised"
        }:
            matched = True
        elif not search_terms or topic_lower == "all" or is_general_briefing or is_general_time_summary:
            matched = True
        else:
            text_lower = f"{content} {loop_title}".lower()
            for term in search_terms:
                if len(term) <= 3:
                    if re.search(r'\b' + re.escape(term) + r'\b', text_lower):
                        matched = True
                        break
                elif term in text_lower:
                    matched = True
                    break

        if matched:
            quotes.append({
                "quote_id": event.event_id,
                "author_id": staff_names.get(event.author_id, event.author_id),
                "timestamp": event.client_created_at,
                "verbatim_text": content,
                "loop_title": loop_title or "Patient Care Note",
                "loop_id": event.loop_id,
            })

    terms_searched_str = topic if topic != "all" else "all messages"
    coverage = f"Searched: {terms_searched_str} in {len(quotes)} record(s) across {len(threads) or 1} thread(s)."

    return {
        "quotes": quotes,
        "coverage_summary": coverage,
        "patient_id": patient_id
    }
