import sqlite3
import threading
import time
from typing import Optional


class CallStore:
    """Small durable store for short-lived Oravi call invitations."""

    def __init__(self, db_path: str):
        self._lock = threading.RLock()
        self.conn = sqlite3.connect(db_path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self._init_db()

    def _init_db(self) -> None:
        with self._lock, self.conn:
            self.conn.execute(
                """CREATE TABLE IF NOT EXISTS call_sessions (
                    call_id TEXT PRIMARY KEY,
                    room_name TEXT NOT NULL UNIQUE,
                    patient_id TEXT NOT NULL,
                    loop_id TEXT NOT NULL,
                    caller_id TEXT NOT NULL,
                    recipient_id TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    expires_at REAL NOT NULL,
                    answered_at REAL,
                    ended_at REAL
                )"""
            )

    def create(self, *, call_id: str, room_name: str, patient_id: str,
               loop_id: str, caller_id: str, recipient_id: str,
               lifetime_seconds: int = 90) -> None:
        now = time.time()
        with self._lock, self.conn:
            self.conn.execute(
                """INSERT INTO call_sessions (
                    call_id, room_name, patient_id, loop_id, caller_id,
                    recipient_id, status, created_at, expires_at
                ) VALUES (?, ?, ?, ?, ?, ?, 'ringing', ?, ?)""",
                (call_id, room_name, patient_id, loop_id, caller_id,
                 recipient_id, now, now + lifetime_seconds),
            )

    def get(self, call_id: str) -> Optional[sqlite3.Row]:
        with self._lock, self.conn:
            self._expire_stale_locked()
            return self.conn.execute(
                "SELECT * FROM call_sessions WHERE call_id = ?", (call_id,)
            ).fetchone()

    def _expire_stale_locked(self) -> None:
        self.conn.execute(
            """UPDATE call_sessions
               SET status = 'missed', ended_at = ?
               WHERE status = 'ringing' AND expires_at <= ?""",
            (time.time(), time.time()),
        )

    def expire_stale(self) -> int:
        with self._lock, self.conn:
            before = self.conn.total_changes
            self._expire_stale_locked()
            return self.conn.total_changes - before

    def mark_answered(self, call_id: str) -> bool:
        with self._lock, self.conn:
            cursor = self.conn.execute(
                """UPDATE call_sessions
                   SET status = 'answered', answered_at = ?
                   WHERE call_id = ? AND status = 'ringing' AND expires_at > ?""",
                (time.time(), call_id, time.time()),
            )
            return cursor.rowcount == 1

    def mark_ended(self, call_id: str, staff_id: str) -> bool:
        with self._lock, self.conn:
            cursor = self.conn.execute(
                """UPDATE call_sessions
                   SET status = 'ended', ended_at = ?
                   WHERE call_id = ?
                     AND (caller_id = ? OR recipient_id = ?)
                     AND status IN ('ringing', 'answered')""",
                (time.time(), call_id, staff_id, staff_id),
            )
            return cursor.rowcount == 1

    def mark_declined(self, call_id: str, staff_id: str) -> bool:
        with self._lock, self.conn:
            self._expire_stale_locked()
            cursor = self.conn.execute(
                """UPDATE call_sessions
                   SET status = 'declined', ended_at = ?
                   WHERE call_id = ? AND recipient_id = ? AND status = 'ringing'""",
                (time.time(), call_id, staff_id),
            )
            return cursor.rowcount == 1

    def mark_cancelled(self, call_id: str, staff_id: str) -> bool:
        with self._lock, self.conn:
            self._expire_stale_locked()
            cursor = self.conn.execute(
                """UPDATE call_sessions
                   SET status = 'cancelled', ended_at = ?
                   WHERE call_id = ? AND caller_id = ? AND status = 'ringing'""",
                (time.time(), call_id, staff_id),
            )
            return cursor.rowcount == 1

    def cleanup(self, retention_seconds: int = 86400) -> int:
        cutoff = time.time() - retention_seconds
        with self._lock, self.conn:
            self._expire_stale_locked()
            cursor = self.conn.execute(
                """DELETE FROM call_sessions
                   WHERE status IN ('ended', 'declined', 'cancelled', 'missed')
                     AND ended_at IS NOT NULL AND ended_at < ?""",
                (cutoff,),
            )
            return cursor.rowcount
