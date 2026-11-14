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
import threading
import time
from functools import wraps
from datetime import datetime, timezone
from typing import Callable, Dict, List, Optional, Tuple
from .models import CanonicalEvent, SyncAckItem

GENESIS_HASH = "0" * 64


def _with_store_lock(method):
    @wraps(method)
    def wrapped(self, *args, **kwargs):
        with self._lock:
            return method(self, *args, **kwargs)

    return wrapped


class EventStore:
    def __init__(self, db_path: Optional[str] = None):
        if db_path is None:
            # Default to persistent database file in backend directory
            base_dir = os.path.dirname(os.path.abspath(__file__))
            self.db_path = os.path.join(base_dir, "oravi_server.db")
        else:
            self.db_path = db_path

        self._lock = threading.RLock()
        self._conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._init_db()
        self._load_state()

    @_with_store_lock
    def _init_db(self):
        with self._lock, self._conn:
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
            self._conn.execute(
                """CREATE INDEX IF NOT EXISTS idx_server_events_patient_loop
                   ON server_events(patient_id, loop_id, server_seq)"""
            )
            self._conn.execute("""
                CREATE TABLE IF NOT EXISTS medical_issue_notification_outbox (
                    notification_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_id TEXT NOT NULL,
                    staff_id TEXT NOT NULL,
                    patient_id TEXT NOT NULL,
                    loop_id TEXT NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0,
                    next_attempt_at REAL NOT NULL DEFAULT 0,
                    last_error TEXT,
                    created_at TEXT NOT NULL,
                    delivered_at TEXT,
                    delivered_fids_json TEXT NOT NULL DEFAULT '[]',
                    UNIQUE(event_id, staff_id)
                )
            """)
            notification_columns = {
                row["name"]
                for row in self._conn.execute(
                    "PRAGMA table_info(medical_issue_notification_outbox)"
                ).fetchall()
            }
            if "delivered_fids_json" not in notification_columns:
                self._conn.execute(
                    """ALTER TABLE medical_issue_notification_outbox
                       ADD COLUMN delivered_fids_json TEXT NOT NULL DEFAULT '[]'"""
                )
            self._conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_issue_notifications_pending
                ON medical_issue_notification_outbox(delivered_at, next_attempt_at)
            """)

    @_with_store_lock
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

    @_with_store_lock
    def append_events(
        self,
        incoming: List[CanonicalEvent],
        notification_staff_ids_by_event: Optional[Dict[str, List[str]]] = None,
        transaction_action: Optional[Callable[[sqlite3.Connection], None]] = None,
    ) -> List[SyncAckItem]:
        acks: List[SyncAckItem] = []
        now_iso = datetime.now(timezone.utc).isoformat()
        previous_seq = self._latest_seq
        previous_hash = self._last_hash

        try:
            with self._conn:
                cursor = self._conn.cursor()
                for ev in incoming:
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

                    self._latest_seq += 1
                    ev.server_seq = self._latest_seq
                    ev.server_received_at = now_iso
                    ev.prev_hash = self._last_hash
                    canonical_repr = json.dumps({
                        "event_id": ev.event_id,
                        "type": ev.type,
                        "patient_id": ev.patient_id,
                        "server_seq": ev.server_seq,
                        "prev_hash": ev.prev_hash,
                        "payload": ev.payload
                    }, sort_keys=True)
                    ev_hash = hashlib.sha256(
                        (self._last_hash + canonical_repr).encode("utf-8")
                    ).hexdigest()
                    ev.hash = ev_hash
                    self._last_hash = ev_hash

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
                    if ev.loop_id is not None:
                        for staff_id in set(
                            (notification_staff_ids_by_event or {}).get(ev.event_id, [])
                        ):
                            cursor.execute(
                                """INSERT OR IGNORE INTO medical_issue_notification_outbox
                                   (event_id, staff_id, patient_id, loop_id, created_at)
                                   VALUES (?, ?, ?, ?, ?)""",
                                (ev.event_id, staff_id, ev.patient_id, ev.loop_id, now_iso),
                            )

                    acks.append(SyncAckItem(
                        event_id=ev.event_id,
                        server_seq=ev.server_seq,
                        server_received_at=now_iso,
                        hash=ev.hash,
                    ))
                if transaction_action is not None:
                    transaction_action(self._conn)
        except Exception:
            self._latest_seq = previous_seq
            self._last_hash = previous_hash
            raise

        return acks

    @_with_store_lock
    def get_due_medical_issue_notifications(
        self, limit: int = 100
    ) -> List[Dict[str, object]]:
        with self._lock:
            rows = self._conn.execute(
                """SELECT notification_id, event_id, staff_id, patient_id, loop_id, attempts
                   FROM medical_issue_notification_outbox
                   WHERE delivered_at IS NULL AND next_attempt_at <= ?
                   ORDER BY notification_id ASC LIMIT ?""",
                (time.time(), limit),
            ).fetchall()
        return [dict(row) for row in rows]

    @_with_store_lock
    def mark_medical_issue_notification_delivered(self, notification_id: int) -> None:
        with self._lock, self._conn:
            self._conn.execute(
                """UPDATE medical_issue_notification_outbox
                   SET delivered_at = ?, last_error = NULL
                   WHERE notification_id = ? AND delivered_at IS NULL""",
                (datetime.now(timezone.utc).isoformat(), notification_id),
            )

    @_with_store_lock
    def get_delivered_medical_issue_fids(self, notification_id: int) -> set[str]:
        row = self._conn.execute(
            """SELECT delivered_fids_json
               FROM medical_issue_notification_outbox
               WHERE notification_id = ?""",
            (notification_id,),
        ).fetchone()
        if row is None:
            return set()
        delivered_fids = json.loads(row["delivered_fids_json"])
        if not isinstance(delivered_fids, list) or not all(
            isinstance(fid, str) for fid in delivered_fids
        ):
            raise ValueError("Invalid delivered FID state in notification outbox.")
        return set(delivered_fids)

    @_with_store_lock
    def mark_medical_issue_notification_fid_delivered(
        self, notification_id: int, fid: str
    ) -> None:
        with self._lock, self._conn:
            row = self._conn.execute(
                """SELECT delivered_fids_json
                   FROM medical_issue_notification_outbox
                   WHERE notification_id = ? AND delivered_at IS NULL""",
                (notification_id,),
            ).fetchone()
            if row is None:
                return
            delivered_fids = set(json.loads(row["delivered_fids_json"]))
            delivered_fids.add(fid)
            self._conn.execute(
                """UPDATE medical_issue_notification_outbox
                   SET delivered_fids_json = ?
                   WHERE notification_id = ? AND delivered_at IS NULL""",
                (json.dumps(sorted(delivered_fids)), notification_id),
            )

    @_with_store_lock
    def mark_medical_issue_notification_failed(
        self, notification_id: int, error: str
    ) -> None:
        with self._lock, self._conn:
            row = self._conn.execute(
                """SELECT attempts FROM medical_issue_notification_outbox
                   WHERE notification_id = ? AND delivered_at IS NULL""",
                (notification_id,),
            ).fetchone()
            if row is None:
                return
            attempts = int(row["attempts"]) + 1
            retry_delay = min(30 * (2 ** min(attempts, 10)), 900)
            self._conn.execute(
                """UPDATE medical_issue_notification_outbox
                   SET attempts = ?, next_attempt_at = ?, last_error = ?
                   WHERE notification_id = ? AND delivered_at IS NULL""",
                (attempts, time.time() + retry_delay, error[:500], notification_id),
            )

    @_with_store_lock
    def get_events_since(
        self,
        since_seq: int = 0,
        limit: int = 100,
        ward_id: Optional[str] = None,
        patient_ids: Optional[set[str]] = None,
        loop_ids: Optional[set[str]] = None,
        issue_refs: Optional[set[Tuple[str, str]]] = None,
    ) -> Tuple[List[CanonicalEvent], int]:
        cursor = self._conn.cursor()
        if issue_refs:
            conditions = []
            values: List[object] = [since_seq]
            if patient_ids:
                patient_placeholders = ",".join("?" for _ in patient_ids)
                conditions.append(f"patient_id IN ({patient_placeholders})")
                values.extend(sorted(patient_ids))
                if ward_id is not None:
                    conditions.append(
                        "(patient_id = ? AND type IN ('HandoffStarted', 'HandoffCompleted'))"
                    )
                    values.append(ward_id)
            elif ward_id is not None:
                conditions.append(
                    "(patient_id = ? AND type IN ('HandoffStarted', 'HandoffCompleted'))"
                )
                values.append(ward_id)
            for patient_id, loop_id in sorted(issue_refs):
                conditions.append("(patient_id = ? AND loop_id = ?)")
                values.extend((patient_id, loop_id))
            values.append(limit)
            cursor.execute(
                f"""SELECT server_seq, event_id, patient_id, type, author_id, device_id,
                           client_created_at, server_received_at, loop_id, schema_version,
                           prev_hash, hash, payload_json
                    FROM server_events
                    WHERE server_seq > ?
                      AND ({' OR '.join(conditions)})
                    ORDER BY server_seq ASC
                    LIMIT ?""",
                values,
            )
        elif loop_ids is not None:
            if not patient_ids or not loop_ids:
                return [], since_seq
            patient_placeholders = ",".join("?" for _ in patient_ids)
            loop_placeholders = ",".join("?" for _ in loop_ids)
            cursor.execute(
                f"""SELECT server_seq, event_id, patient_id, type, author_id,
                           device_id, client_created_at, server_received_at,
                           loop_id, schema_version, prev_hash, hash, payload_json
                    FROM server_events
                    WHERE server_seq > ? AND patient_id IN ({patient_placeholders})
                      AND loop_id IN ({loop_placeholders})
                    ORDER BY server_seq ASC
                    LIMIT ?""",
                (
                    since_seq,
                    *sorted(patient_ids),
                    *sorted(loop_ids),
                    limit,
                ),
            )
        elif patient_ids is not None:
            if not patient_ids:
                if ward_id is None:
                    return [], self._latest_seq
                cursor.execute("""
                    SELECT server_seq, event_id, patient_id, type, author_id,
                           device_id, client_created_at, server_received_at,
                           loop_id, schema_version, prev_hash, hash, payload_json
                    FROM server_events
                    WHERE server_seq > ? AND patient_id = ?
                      AND type IN ('HandoffStarted', 'HandoffCompleted')
                    ORDER BY server_seq ASC
                    LIMIT ?
                """, (since_seq, ward_id, limit))
            else:
                placeholders = ",".join("?" for _ in patient_ids)
                if ward_id is None:
                    cursor.execute(f"""
                        SELECT server_seq, event_id, patient_id, type, author_id,
                               device_id, client_created_at, server_received_at,
                               loop_id, schema_version, prev_hash, hash, payload_json
                        FROM server_events
                        WHERE server_seq > ? AND patient_id IN ({placeholders})
                        ORDER BY server_seq ASC
                        LIMIT ?;
                    """, (since_seq, *sorted(patient_ids), limit))
                else:
                    cursor.execute(f"""
                        SELECT server_seq, event_id, patient_id, type, author_id,
                               device_id, client_created_at, server_received_at,
                               loop_id, schema_version, prev_hash, hash, payload_json
                        FROM server_events
                        WHERE server_seq > ?
                          AND (
                              patient_id IN ({placeholders})
                              OR (patient_id = ? AND type IN (
                                  'HandoffStarted', 'HandoffCompleted'
                              ))
                          )
                        ORDER BY server_seq ASC
                        LIMIT ?;
                    """, (since_seq, *sorted(patient_ids), ward_id, limit))
        elif ward_id is None:
            cursor.execute("""
            SELECT server_seq, event_id, patient_id, type, author_id, device_id,
                   client_created_at, server_received_at, loop_id, schema_version,
                   prev_hash, hash, payload_json
            FROM server_events
            WHERE server_seq > ?
            ORDER BY server_seq ASC
            LIMIT ?;
        """, (since_seq, limit))
        else:
            cursor.execute("""
            SELECT server_seq, event_id, patient_id, type, author_id, device_id,
                   client_created_at, server_received_at, loop_id, schema_version,
                   prev_hash, hash, payload_json
            FROM server_events
            WHERE server_seq > ?
              AND patient_id IN (
                  SELECT patient_id FROM server_events
                  WHERE json_extract(payload_json, '$.ward_id') = ?
              )
            ORDER BY server_seq ASC
            LIMIT ?;
            """, (since_seq, ward_id, limit))

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

        if loop_ids is not None:
            return results, results[-1].server_seq if results else since_seq
        if ward_id is None or len(results) < limit:
            return results, self._latest_seq
        return results, results[-1].server_seq or since_seq

    @_with_store_lock
    def get_loop_events(self, patient_id: str, loop_id: str) -> List[CanonicalEvent]:
        rows = self._conn.execute(
            """SELECT server_seq, event_id, patient_id, type, author_id, device_id,
                      client_created_at, server_received_at, loop_id, schema_version,
                      prev_hash, hash, payload_json
               FROM server_events
               WHERE patient_id = ? AND loop_id = ?
               ORDER BY server_seq ASC""",
            (patient_id, loop_id),
        ).fetchall()
        return [
            CanonicalEvent(
                event_id=row["event_id"],
                patient_id=row["patient_id"],
                type=row["type"],
                author_id=row["author_id"],
                device_id=row["device_id"],
                client_created_at=row["client_created_at"],
                loop_id=row["loop_id"],
                server_seq=row["server_seq"],
                server_received_at=row["server_received_at"],
                schema_version=row["schema_version"],
                prev_hash=row["prev_hash"],
                hash=row["hash"],
                payload=json.loads(row["payload_json"]),
            )
            for row in rows
        ]

    @_with_store_lock
    def get_patient_events(self, patient_id: str) -> List[CanonicalEvent]:
        rows = self._conn.execute(
            """SELECT server_seq, event_id, patient_id, type, author_id,
                      device_id, client_created_at, server_received_at, loop_id,
                      schema_version, prev_hash, hash, payload_json
               FROM server_events
               WHERE patient_id = ?
               ORDER BY server_seq ASC""",
            (patient_id,),
        ).fetchall()
        return [
            CanonicalEvent(
                event_id=row["event_id"],
                patient_id=row["patient_id"],
                type=row["type"],
                author_id=row["author_id"],
                device_id=row["device_id"],
                client_created_at=row["client_created_at"],
                server_seq=row["server_seq"],
                server_received_at=row["server_received_at"],
                loop_id=row["loop_id"],
                schema_version=row["schema_version"],
                prev_hash=row["prev_hash"],
                hash=row["hash"],
                payload=json.loads(row["payload_json"]),
            )
            for row in rows
        ]

    @_with_store_lock
    def get_handoff_started_event(
        self, handoff_session_id: str
    ) -> Optional[CanonicalEvent]:
        row = self._conn.execute(
            """SELECT server_seq, event_id, patient_id, type, author_id,
                      device_id, client_created_at, server_received_at, loop_id,
                      schema_version, prev_hash, hash, payload_json
               FROM server_events
               WHERE type = 'HandoffStarted'
                 AND json_extract(payload_json, '$.handoff_session_id') = ?
               ORDER BY server_seq ASC LIMIT 1""",
            (handoff_session_id,),
        ).fetchone()
        if row is None:
            return None
        return CanonicalEvent(
            event_id=row["event_id"],
            patient_id=row["patient_id"],
            type=row["type"],
            author_id=row["author_id"],
            device_id=row["device_id"],
            client_created_at=row["client_created_at"],
            server_seq=row["server_seq"],
            server_received_at=row["server_received_at"],
            loop_id=row["loop_id"],
            schema_version=row["schema_version"],
            prev_hash=row["prev_hash"],
            hash=row["hash"],
            payload=json.loads(row["payload_json"]),
        )

    @_with_store_lock
    def get_carried_forward_issue_candidates(
        self, owner_id: str
    ) -> List[Tuple[str, str]]:
        rows = self._conn.execute(
            """SELECT DISTINCT patient_id, loop_id
               FROM server_events
               WHERE type = 'LoopOwnerChanged' AND loop_id IS NOT NULL
                 AND json_extract(payload_json, '$.carry_forward') = 1
                 AND json_extract(payload_json, '$.new_owner_id') = ?
               ORDER BY patient_id, loop_id""",
            (owner_id,),
        ).fetchall()
        return [
            (str(row["patient_id"]), str(row["loop_id"]))
            for row in rows
        ]

    @_with_store_lock
    def patient_belongs_to_ward(self, patient_id: str, ward_id: str) -> bool:
        row = self._conn.execute(
            """SELECT 1 FROM server_events
               WHERE patient_id = ?
                 AND json_extract(payload_json, '$.ward_id') = ?
               LIMIT 1""",
            (patient_id, ward_id),
        ).fetchone()
        return row is not None

    @_with_store_lock
    def get_patient_ward(self, patient_id: str) -> Optional[str]:
        row = self._conn.execute(
            """SELECT json_extract(payload_json, '$.ward_id') AS ward_id
               FROM server_events WHERE patient_id = ?
                 AND json_extract(payload_json, '$.ward_id') IS NOT NULL
               ORDER BY server_seq ASC LIMIT 1""",
            (patient_id,),
        ).fetchone()
        return str(row["ward_id"]) if row else None

    @_with_store_lock
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

    @_with_store_lock
    def close(self):
        self._conn.close()
