"""
Persistent SQLite Append-Only Event Store implementing:
- Tech Arch Section 4.1: Idempotency via client UUIDv7 event_id
- Tech Arch Section 7: Cryptographic SHA-256 audit hash chain
- Tech Arch Section 10: Persistent backend event stream
"""
import hashlib
import json
import os
import sqlite3
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple
from .models import CanonicalEvent, SyncAckItem

GENESIS_HASH = "0" * 64

class EventStore:
    def __init__(self, db_path: Optional[str] = None):
        if db_path is None:
            # Default to persistent database file in backend directory
            base_dir = os.path.dirname(os.path.abspath(__file__))
            self.db_path = os.path.join(base_dir, "oravi_server.db")
        else:
            self.db_path = db_path

        self._conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._init_db()
        self._load_state()

    def _init_db(self):
        with self._conn:
            self._conn.execute("PRAGMA journal_mode = WAL;")
            self._conn.execute("""
                CREATE TABLE IF NOT EXISTS server_events (
                    server_seq INTEGER PRIMARY KEY,
                    event_id TEXT UNIQUE NOT NULL,
                    patient_id TEXT NOT NULL,
                    type TEXT NOT NULL,
                    author_id TEXT NOT NULL,
                    device_id TEXT NOT NULL,
                    client_created_at TEXT NOT NULL,
                    server_received_at TEXT NOT NULL,
                    loop_id TEXT,
                    schema_version INTEGER DEFAULT 1,
                    prev_hash TEXT NOT NULL,
                    hash TEXT NOT NULL,
                    payload_json TEXT NOT NULL
                );
            """)
            self._conn.execute("CREATE INDEX IF NOT EXISTS idx_server_events_patient ON server_events(patient_id);")
            self._conn.execute("CREATE INDEX IF NOT EXISTS idx_server_events_seq ON server_events(server_seq);")

    def _load_state(self):
        cursor = self._conn.cursor()
        cursor.execute("SELECT server_seq, hash FROM server_events ORDER BY server_seq DESC LIMIT 1;")
        row = cursor.fetchone()
        if row:
            self._latest_seq = int(row["server_seq"])
            self._last_hash = str(row["hash"])
        else:
            self._latest_seq = 0
            self._last_hash = GENESIS_HASH

    def append_events(self, incoming: List[CanonicalEvent]) -> List[SyncAckItem]:
        acks: List[SyncAckItem] = []
        now_iso = datetime.now(timezone.utc).isoformat()

        with self._conn:
            cursor = self._conn.cursor()
            for ev in incoming:
                # 1. Idempotency check (Tech Arch Section 4.1)
                cursor.execute(
                    "SELECT server_seq, server_received_at, hash FROM server_events WHERE event_id = ?;",
                    (ev.event_id,)
                )
                existing = cursor.fetchone()
                if existing:
                    acks.append(SyncAckItem(
                        event_id=ev.event_id,
                        server_seq=int(existing["server_seq"]),
                        server_received_at=str(existing["server_received_at"]),
                        hash=str(existing["hash"]),
                    ))
                    continue

                # 2. Assign authoritative sequence & timestamps
                self._latest_seq += 1
                ev.server_seq = self._latest_seq
                ev.server_received_at = now_iso
                ev.prev_hash = self._last_hash

                # 3. Calculate SHA-256 hash = SHA-256(prev_hash + canonical_json) (Tech Arch Section 7)
                canonical_repr = json.dumps({
                    "event_id": ev.event_id,
                    "type": ev.type,
                    "patient_id": ev.patient_id,
                    "server_seq": ev.server_seq,
                    "prev_hash": ev.prev_hash,
                    "payload": ev.payload
                }, sort_keys=True)

                ev_hash = hashlib.sha256((self._last_hash + canonical_repr).encode("utf-8")).hexdigest()
                ev.hash = ev_hash
                self._last_hash = ev_hash

                # 4. Insert into persistent SQLite
                cursor.execute("""
                    INSERT INTO server_events (
                        server_seq, event_id, patient_id, type, author_id, device_id,
                        client_created_at, server_received_at, loop_id, schema_version,
                        prev_hash, hash, payload_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """, (
                    ev.server_seq,
                    ev.event_id,
                    ev.patient_id,
                    ev.type,
                    ev.author_id,
                    ev.device_id,
                    ev.client_created_at,
                    ev.server_received_at,
                    ev.loop_id,
                    ev.schema_version,
                    ev.prev_hash,
                    ev.hash,
                    json.dumps(ev.payload, sort_keys=True),
                ))

                acks.append(SyncAckItem(
                    event_id=ev.event_id,
                    server_seq=ev.server_seq,
                    server_received_at=now_iso,
                    hash=ev.hash,
                ))

        return acks

    def get_events_since(self, since_seq: int = 0, limit: int = 100) -> Tuple[List[CanonicalEvent], int]:
        cursor = self._conn.cursor()
        cursor.execute("""
            SELECT server_seq, event_id, patient_id, type, author_id, device_id,
                   client_created_at, server_received_at, loop_id, schema_version,
                   prev_hash, hash, payload_json
            FROM server_events
            WHERE server_seq > ?
            ORDER BY server_seq ASC
            LIMIT ?;
        """, (since_seq, limit))

        rows = cursor.fetchall()
        results: List[CanonicalEvent] = []
        for r in rows:
            ev = CanonicalEvent(
                event_id=r["event_id"],
                patient_id=r["patient_id"],
                type=r["type"],
                author_id=r["author_id"],
                device_id=r["device_id"],
                client_created_at=r["client_created_at"],
                loop_id=r["loop_id"],
                server_seq=r["server_seq"],
                server_received_at=r["server_received_at"],
                schema_version=r["schema_version"],
                prev_hash=r["prev_hash"],
                hash=r["hash"],
                payload=json.loads(r["payload_json"]),
            )
            results.append(ev)

        return results, self._latest_seq

    def verify_hash_chain(self) -> bool:
        """
        Cryptographically verifies the entire hash chain from Genesis (Tech Arch Section 7).
        Returns True if every hash is valid and unbroken; raises ValueError on tamper.
        """
        cursor = self._conn.cursor()
        cursor.execute("SELECT * FROM server_events ORDER BY server_seq ASC;")
        rows = cursor.fetchall()
        expected_prev_hash = GENESIS_HASH

        for row in rows:
            if row["prev_hash"] != expected_prev_hash:
                raise ValueError(
                    f"Hash chain broken at seq {row['server_seq']}: expected prev_hash {expected_prev_hash}, got {row['prev_hash']}"
                )
            canonical_repr = json.dumps({
                "event_id": row["event_id"],
                "type": row["type"],
                "patient_id": row["patient_id"],
                "server_seq": row["server_seq"],
                "prev_hash": row["prev_hash"],
                "payload": json.loads(row["payload_json"]),
            }, sort_keys=True)

            calc_hash = hashlib.sha256((expected_prev_hash + canonical_repr).encode("utf-8")).hexdigest()
            if calc_hash != row["hash"]:
                raise ValueError(
                    f"Hash signature mismatch at seq {row['server_seq']}: computed {calc_hash}, stored {row['hash']}"
                )
            expected_prev_hash = calc_hash

        return True

    def close(self):
        self._conn.close()
