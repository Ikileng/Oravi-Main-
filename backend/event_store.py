import hashlib
import json
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple
from .models import CanonicalEvent, SyncAckItem

class EventStore:
    """
    Append-only event store implementing Tech Arch Section 4.1 & Section 7.
    - Idempotency via client UUIDv7 event_id.
    - Authoritative server sequence numbering.
    - Cryptographic SHA-256 audit hash chain.
    """
    def __init__(self):
        self._events: List[CanonicalEvent] = []
        self._event_map: Dict[str, CanonicalEvent] = {}
        self._latest_seq: int = 0
        self._last_hash: str = "0" * 64 # Genesis hash

    def append_events(self, incoming: List[CanonicalEvent]) -> List[SyncAckItem]:
        acks: List[SyncAckItem] = []

        for ev in incoming:
            # Idempotency check (Tech Arch Section 4.1)
            if ev.event_id in self._event_map:
                existing = self._event_map[ev.event_id]
                acks.append(SyncAckItem(
                    event_id=existing.event_id,
                    server_seq=existing.server_seq or 0,
                    server_received_at=existing.server_received_at or "",
                    hash=existing.hash or "",
                ))
                continue

            self._latest_seq += 1
            now_iso = datetime.now(timezone.utc).isoformat()

            ev.server_seq = self._latest_seq
            ev.server_received_at = now_iso
            ev.prev_hash = self._last_hash

            # Calculate SHA-256 hash = SHA-256(prev_hash + canonical_json)
            # Tech Arch Section 7
            canonical_repr = json.dumps({
                "event_id": ev.event_id,
                "type": ev.type,
                "patient_id": ev.patient_id,
                "server_seq": ev.server_seq,
                "prev_hash": ev.prev_hash,
                "payload": ev.payload
            }, sort_keys=True)

            ev_hash = hashlib.sha256((self._last_hash + canonical_repr).encode('utf-8')).hexdigest()
            ev.hash = ev_hash
            self._last_hash = ev_hash

            self._events.append(ev)
            self._event_map[ev.event_id] = ev

            acks.append(SyncAckItem(
                event_id=ev.event_id,
                server_seq=ev.server_seq,
                server_received_at=now_iso,
                hash=ev.hash,
            ))

        return acks

    def get_events_since(self, since_seq: int = 0, limit: int = 100) -> Tuple[List[CanonicalEvent], int]:
        results = [e for e in self._events if (e.server_seq or 0) > since_seq][:limit]
        return results, self._latest_seq
