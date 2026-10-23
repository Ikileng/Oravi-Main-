from dataclasses import dataclass, field, asdict
from typing import Any, Dict, List, Optional

@dataclass
class CanonicalEvent:
    event_id: str
    patient_id: str
    type: str
    author_id: str
    device_id: str
    client_created_at: str
    loop_id: Optional[str] = None
    server_seq: Optional[int] = None
    server_received_at: Optional[str] = None
    schema_version: int = 1
    prev_hash: Optional[str] = None
    hash: Optional[str] = None
    payload: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

@dataclass
class SyncAckItem:
    event_id: str
    server_seq: int
    server_received_at: str
    hash: str

@dataclass
class SyncPushRequest:
    device_id: str
    events: List[CanonicalEvent]

@dataclass
class SyncPushResponse:
    status: str
    acknowledged_count: int
    acks: List[SyncAckItem]

@dataclass
class SyncPullResponse:
    ward_id: str
    latest_seq: int
    events: List[CanonicalEvent]

@dataclass
class AskRequest:
    query: str
    time_window_hours: Optional[int] = None

@dataclass
class AskResponse:
    patient_id: str
    query: str
    verbatim_quotes: List[Dict[str, Any]]
    coverage_summary: str
    observation_note: Optional[str] = None
    is_refusal: bool = False
    refusal_message: Optional[str] = None
    is_absence: bool = False
    absence_message: Optional[str] = None
    doctor_in_charge: str = "DOC-OTIENO"
    verification_passed: bool = True
    model_provider: str = "ollama"
    model_name: str = "qwen2.5:7b"
