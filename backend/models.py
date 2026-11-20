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
class SyncRejectedItem:
    event_id: str
    reason: str

@dataclass
class SyncPushRequest:
    device_id: str
    events: List[CanonicalEvent]

@dataclass
class SyncPushResponse:
    status: str
    acknowledged_count: int
    acks: List[SyncAckItem]
    rejected: List[SyncRejectedItem] = field(default_factory=list)

@dataclass
class SyncPullResponse:
    ward_id: str
    latest_seq: int
    events: List[CanonicalEvent]

@dataclass
class AskRequest:
    query: str
    time_window_hours: Optional[int] = None
    conversation_history: Optional[List[Dict[str, str]]] = None

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


@dataclass
class StaffProfile:
    staff_id: str
    name: str
    role: str
    ward_id: str
    avatar_color: str
    initials: str
    is_active: bool = True

@dataclass
class StaffLoginRequest:
    staff_id: str = ""
    pin: str = ""
    email: Optional[str] = None

@dataclass
class StaffLoginResponse:
    success: bool
    staff: Optional[StaffProfile] = None
    token: Optional[str] = None
    error: Optional[str] = None

@dataclass
class CreateStaffRequest:
    staff_id: str
    name: str
    role: str
    pin: str
    email: Optional[str] = None
    ward_id: str = ""
    avatar_color: Optional[str] = None

@dataclass
class StaffListResponse:
    ward_id: str
    staff: List[StaffProfile]


@dataclass
class HospitalWardModel:
    ward_id: str
    name: str
    bed_count: int
    bed_numbers: List[str]
    department: str
    description: str

@dataclass
class WardConfigurationRequest:
    name: str
    bed_numbers: List[str]
    department: str = ""
    description: str = ""
    expected_bed_numbers: Optional[List[str]] = None

@dataclass
class ShiftAllocationModel:
    allocation_id: str
    ward_id: str
    shift_type: str
    date: str
    published_by: str
    published_at: str
    bed_assignments: List[Dict[str, Any]]
    support_roster: Dict[str, Any]
    carry_forward_issues: List[Dict[str, Any]] = field(default_factory=list)
    confirmed_double_shift_nurse_ids: List[str] = field(default_factory=list)

@dataclass
class AllocationConflictCheckResponse:
    has_conflict: bool
    conflict_ward_id: Optional[str] = None
    conflict_ward_name: Optional[str] = None
    conflict_nurse_id: Optional[str] = None
    conflict_shift_type: Optional[str] = None
    message: Optional[str] = None
