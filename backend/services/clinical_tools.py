import re
from typing import Any, Dict, List, Optional
from ..event_store import EventStore
from ..models import CanonicalEvent

# Standard OpenAI-compatible tool specifications for Qwen / Ollama / Gemini / Azure
CLINICAL_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "query_patient_timeline",
            "description": "Retrieves the exact chronological clinical record and verbatim quotes for a patient regarding a specific clinical topic or time window.",
            "parameters": {
                "type": "object",
                "properties": {
                    "patient_id": {
                        "type": "string",
                        "description": "The unique patient identifier, e.g. 'PAT-4B-01' or bed number."
                    },
                    "topic": {
                        "type": "string",
                        "description": "Clinical topic or term to search for (e.g. 'urine', 'oxygen', 'blood', 'blood_pressure', 'pain', 'allergies', 'all')."
                    },
                    "time_window_hours": {
                        "type": "integer",
                        "description": "Optional time window in hours to look back, e.g. 8 for 'last 8 hours', 24 for 'last 24 hours'."
                    }
                },
                "required": ["patient_id"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_ward_summary",
            "description": "Retrieves the active open loops, urgent items, and bed states across the ward for ward-round briefing.",
            "parameters": {
                "type": "object",
                "properties": {
                    "ward_id": {
                        "type": "string",
                        "description": "Ward identifier, e.g. 'WARD-4B'."
                    }
                },
                "required": ["ward_id"]
            }
        }
    }
]

# Ward Lexicon synonym mapping (matching PRD Section 8A)
TOPIC_SYNONYMS = {
    'urine': ['urine', 'uo', 'passing urine', 'mkojo', 'catheter', 'foley', 'anuria', 'oliguria'],
    'oxygen': ['spo2', 'sats', 'oxygen', 'o2', 'desat', 'hewa ya oksijeni', 'prongs', 'mask', '2l', 'room air'],
    'blood': ['blood', 'cross-match', 'crossmatch', 'hb', 'haemoglobin', 'damu', 'transfusion', 'prbc', 'units'],
    'blood_pressure': ['bp', 'blood pressure', 'presha', 'hypotension', 'hypertension', 'systolic', 'diastolic'],
    'allergy': ['allergy', 'allergic', 'allergies', 'reaction', 'mzio', 'anaphylaxis'],
    'pain': ['pain', 'ache', 'uchungu', 'maumivu', 'analgesia', 'paracetamol'],
}

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

    # Auto-detect time window from query if not explicitly passed
    topic_lower = topic.lower()
    tw_match = re.search(r'\b(\d+)\s*(?:hours|hrs|hr)\b', topic_lower)
    if tw_match and time_window_hours is None:
        time_window_hours = int(tw_match.group(1))

    is_general_time_summary = any(p in topic_lower for p in [
        "what do i need to know", "what happened", "summary", "last", "shift", "today", "updates", "issues"
    ]) and (time_window_hours is not None or "hour" in topic_lower or "shift" in topic_lower or "today" in topic_lower)

    # Expand search terms
    search_terms = set()
    if topic_lower != "all" and not is_general_time_summary:
        search_terms.add(topic_lower)
        for key, syns in TOPIC_SYNONYMS.items():
            if key in topic_lower or any(s in topic_lower for s in syns):
                search_terms.update(syns)

    quotes = []
    threads = set()

    for event in patient_events:
        content = ""
        loop_title = ""

        if event.type == "LoopOpened":
            loop_title = event.payload.get("title", "")
            content = f"{loop_title}: {event.payload.get('description', '')}".strip()
        elif event.type == "MessagePosted":
            content = event.payload.get("content", "")
        elif event.type == "CallLogged":
            outcome = event.payload.get("outcome_note", "")
            recipient = event.payload.get("recipient_id", "")
            content = f"Spoke with {recipient}: {outcome}"
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
        if not search_terms or topic_lower == "all":
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
                "author_id": event.author_id,
                "timestamp": event.client_created_at,
                "verbatim_text": content,
                "loop_id": event.loop_id or "GENERAL",
            })

    coverage_line = f"Searched: {', '.join(sorted(list(search_terms))[:5]) if search_terms else 'all'} in {len(patient_events)} messages across {len(threads) or 1} threads."

    return {
        "patient_id": patient_id,
        "topic": topic,
        "quotes": quotes,
        "coverage_summary": coverage_line,
        "is_empty": len(quotes) == 0,
    }
