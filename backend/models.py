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
