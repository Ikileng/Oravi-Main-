import hashlib
import os
import secrets
import sqlite3
import threading
import time
from typing import Dict, List, Optional, Tuple
from .models import StaffProfile

class StaffStore:
    def __init__(self, db_path: Optional[str] = None):
        if db_path is None:
            base_dir = os.path.dirname(os.path.abspath(__file__))
            self.db_path = os.path.join(base_dir, "oravi_server.db")
        else:
            self.db_path = db_path

        self._lock = threading.RLock()
        self.conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self.conn.execute("PRAGMA foreign_keys = ON")
        self.conn.row_factory = sqlite3.Row
        self._failed_attempts: Dict[str, List[float]] = {}
        self._init_db()

    def _init_db(self) -> None:
        with self._lock, self.conn:
            self.conn.execute('''CREATE TABLE IF NOT EXISTS deleted_staff_ids (
                staff_id TEXT PRIMARY KEY, deleted_at TEXT NOT NULL
            )''')
            self.conn.execute(
                """
                CREATE TABLE IF NOT EXISTS staff_users (
                    staff_id TEXT PRIMARY KEY,
                    email TEXT NOT NULL DEFAULT '',
                    name TEXT NOT NULL,
                    role TEXT NOT NULL,
                    ward_id TEXT NOT NULL,
                    pin_hash TEXT NOT NULL,
                    pin_salt TEXT NOT NULL,
                    avatar_color TEXT NOT NULL,
                    initials TEXT NOT NULL,
                    is_active INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL
                )
                """
            )
            columns = {row["name"] for row in self.conn.execute("PRAGMA table_info(staff_users)").fetchall()}
            if "email" not in columns:
                self.conn.execute("ALTER TABLE staff_users ADD COLUMN email TEXT NOT NULL DEFAULT ''")
            self.conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_staff_ward ON staff_users(ward_id)"
            )
            self.conn.execute(
                """CREATE TABLE IF NOT EXISTS auth_sessions (
                    token_hash TEXT PRIMARY KEY,
                    staff_id TEXT NOT NULL,
                    expires_at REAL NOT NULL,
                    created_at REAL NOT NULL,
                    FOREIGN KEY (staff_id) REFERENCES staff_users(staff_id)
                )"""
            )
            self.conn.execute(
                """CREATE TABLE IF NOT EXISTS auth_failures (
                    staff_id TEXT PRIMARY KEY,
                    failure_count INTEGER NOT NULL,
                    window_started REAL NOT NULL,
                    locked_until REAL NOT NULL DEFAULT 0
                )"""
            )
            self.conn.execute(
                """CREATE TABLE IF NOT EXISTS staff_ward_preferences (
                    staff_id TEXT PRIMARY KEY,
                    ward_id TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    FOREIGN KEY (staff_id) REFERENCES staff_users(staff_id)
                )"""
            )
            self.conn.execute(
                """CREATE TABLE IF NOT EXISTS fcm_device_tokens (
                    staff_id TEXT NOT NULL,
                    device_id TEXT NOT NULL,
                    fid TEXT NOT NULL UNIQUE,
                    platform TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    PRIMARY KEY (staff_id, device_id),
                    FOREIGN KEY (staff_id) REFERENCES staff_users(staff_id)
                )"""
            )
            fcm_columns = {
                row["name"]
                for row in self.conn.execute(
                    "PRAGMA table_info(fcm_device_tokens)"
                ).fetchall()
            }
            if "token" in fcm_columns and "fid" not in fcm_columns:
                self.conn.execute(
                    "ALTER TABLE fcm_device_tokens RENAME COLUMN token TO fid"
                )
                self.conn.execute("DELETE FROM fcm_device_tokens")

    @staticmethod
    def hash_pin(pin: str, salt: str) -> str:
        return hashlib.pbkdf2_hmac(
            "sha256", pin.encode("utf-8"), bytes.fromhex(salt), 310_000
        ).hex()

    def create_session(self, staff_id: str, token: str, lifetime_seconds: int = 28_800) -> None:
        now = time.time()
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        with self.conn:
            self.conn.execute("DELETE FROM auth_sessions WHERE expires_at <= ?", (now,))
            self.conn.execute(
                "INSERT INTO auth_sessions (token_hash, staff_id, expires_at, created_at) VALUES (?, ?, ?, ?)",
                (token_hash, staff_id, now + lifetime_seconds, now),
            )

    def create_first_admin(self, staff_id: str, name: str, pin: str) -> StaffProfile:
        if not pin.isdigit() or not 6 <= len(pin) <= 8:
            raise ValueError("Dev Admin PIN must contain 6 to 8 digits.")
        parts = [part for part in name.split() if part]
        initials = "".join(part[0] for part in parts[:2]).upper() or "DA"
        salt = secrets.token_hex(16)
        now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        with self.conn:
            count = self.conn.execute(
                "SELECT COUNT(*) FROM staff_users WHERE role = 'dev_admin'"
            ).fetchone()[0]
            if count:
                raise ValueError("A Dev Admin already exists; bootstrap is one-time only.")
            self.conn.execute(
                """INSERT INTO staff_users (
                    staff_id, name, role, ward_id, pin_hash, pin_salt,
                    avatar_color, initials, is_active, created_at
                ) VALUES (?, ?, 'dev_admin', '', ?, ?, '#475569', ?, 1, ?)""",
                (staff_id, name, self.hash_pin(pin, salt), salt, initials, now_iso),
            )
        return StaffProfile(staff_id, name, "dev_admin", "", "#475569", initials, True)

    def get_session(self, token: str) -> Optional[StaffProfile]:
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        with self.conn:
            row = self.conn.execute(
                """SELECT u.staff_id, u.name, u.role, u.ward_id, u.avatar_color,
                          u.initials, u.is_active
                   FROM auth_sessions s JOIN staff_users u ON u.staff_id = s.staff_id
                   WHERE s.token_hash = ? AND s.expires_at > ?""",
                (token_hash, time.time()),
            ).fetchone()
        if row is None or not row["is_active"]:
            return None
        return StaffProfile(
            staff_id=row["staff_id"], name=row["name"], role=row["role"],
            ward_id=row["ward_id"], avatar_color=row["avatar_color"],
            initials=row["initials"], is_active=bool(row["is_active"]),
        )

    def revoke_session(self, token: str) -> None:
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        with self.conn:
            self.conn.execute("DELETE FROM auth_sessions WHERE token_hash = ?", (token_hash,))

    def get_staff_for_ward(self, ward_id: str) -> List[StaffProfile]:
        with self.conn:
            cursor = self.conn.cursor()
            cursor.execute(
                """
                SELECT staff_id, name, role, ward_id, avatar_color, initials, is_active
                FROM staff_users
                WHERE role != 'dev_admin' AND is_active = 1
                ORDER BY role DESC, name ASC
                """
            )
            rows = cursor.fetchall()
            return [
                StaffProfile(
                    staff_id=r["staff_id"],
                    name=r["name"],
                    role=r["role"],
                    ward_id=r["ward_id"],
                    avatar_color=r["avatar_color"],
                    initials=r["initials"],
                    is_active=bool(r["is_active"]),
                )
                for r in rows
            ]

    def get_active_clinical_staff(self) -> List[StaffProfile]:
        return self.get_staff_for_ward("")

    def get_active_staff_by_ids(self, staff_ids: List[str]) -> List[StaffProfile]:
        if not staff_ids:
            return []
        placeholders = ",".join("?" for _ in staff_ids)
        with self.conn:
            rows = self.conn.execute(
                f"""SELECT staff_id, name, role, ward_id, avatar_color, initials, is_active
                    FROM staff_users
                    WHERE is_active = 1 AND role != 'dev_admin'
                      AND staff_id IN ({placeholders})
                    ORDER BY role DESC, name ASC""",
                staff_ids,
            ).fetchall()
        return [
            StaffProfile(
                staff_id=row["staff_id"],
                name=row["name"],
                role=row["role"],
                ward_id=row["ward_id"],
                avatar_color=row["avatar_color"],
                initials=row["initials"],
                is_active=bool(row["is_active"]),
            )
            for row in rows
        ]

    def get_charge_nurses_for_ward(self, ward_id: str) -> List[StaffProfile]:
        with self.conn:
            rows = self.conn.execute(
                """SELECT u.staff_id, u.name, u.role, u.ward_id, u.avatar_color,
                          u.initials, u.is_active
                   FROM staff_users u
                   JOIN staff_ward_preferences p ON p.staff_id = u.staff_id
                   WHERE u.role = 'charge_nurse' AND u.is_active = 1
                     AND p.ward_id = ?
                   ORDER BY u.name""",
                (ward_id,),
            ).fetchall()
        return [
            StaffProfile(
                staff_id=row["staff_id"],
                name=row["name"],
                role=row["role"],
                ward_id=row["ward_id"],
                avatar_color=row["avatar_color"],
                initials=row["initials"],
                is_active=bool(row["is_active"]),
            )
            for row in rows
        ]

    def register_fcm_installation(
        self, staff_id: str, device_id: str, fid: str, platform: str
    ) -> bool:
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        with self._lock, self.conn:
            self.conn.execute(
                "DELETE FROM fcm_device_tokens WHERE fid = ? AND staff_id != ?",
                (fid, staff_id),
            )
            cursor = self.conn.execute(
                """INSERT INTO fcm_device_tokens
                   (staff_id, device_id, fid, platform, updated_at)
                   SELECT staff_id, ?, ?, ?, ? FROM staff_users
                   WHERE staff_id = ? AND is_active = 1 AND role != 'dev_admin'
                   ON CONFLICT(staff_id, device_id) DO UPDATE SET
                       fid = excluded.fid, platform = excluded.platform,
                       updated_at = excluded.updated_at""",
                (device_id, fid, platform, now, staff_id),
            )
        return cursor.rowcount == 1

    def get_fcm_fids_for_staff(self, staff_id: str) -> List[str]:
        with self._lock:
            rows = self.conn.execute(
                "SELECT fid FROM fcm_device_tokens WHERE staff_id = ?",
                (staff_id,),
            ).fetchall()
        return [str(row["fid"]) for row in rows]

    def remove_fcm_installation(self, staff_id: str, device_id: str) -> None:
        with self._lock, self.conn:
            self.conn.execute(
                "DELETE FROM fcm_device_tokens WHERE staff_id = ? AND device_id = ?",
                (staff_id, device_id),
            )

    def remove_fcm_fid(self, fid: str) -> None:
        with self._lock, self.conn:
            self.conn.execute(
                "DELETE FROM fcm_device_tokens WHERE fid = ?",
                (fid,),
            )

    def is_active_clinical_staff(self, staff_id: str) -> bool:
        row = self.conn.execute(
            """SELECT 1 FROM staff_users
               WHERE staff_id = ? AND is_active = 1 AND role != 'dev_admin'""",
            (staff_id,),
        ).fetchone()
        return row is not None

    def is_active_doctor(self, staff_id: str) -> bool:
        row = self.conn.execute(
            """SELECT 1 FROM staff_users
               WHERE staff_id = ? AND is_active = 1 AND role = 'doctor_on_call'""",
            (staff_id,),
        ).fetchone()
        return row is not None

    def get_ward_preference(self, staff_id: str) -> Optional[str]:
        row = self.conn.execute(
            "SELECT ward_id FROM staff_ward_preferences WHERE staff_id = ?",
            (staff_id,),
        ).fetchone()
        return row["ward_id"] if row else None

    def set_ward_preference(self, staff_id: str, ward_id: str) -> bool:
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        with self.conn:
            cursor = self.conn.execute(
                """INSERT INTO staff_ward_preferences (staff_id, ward_id, updated_at)
                   SELECT staff_id, ?, ? FROM staff_users
                   WHERE staff_id = ? AND role = 'charge_nurse' AND is_active = 1
                   ON CONFLICT(staff_id) DO UPDATE SET
                       ward_id = excluded.ward_id, updated_at = excluded.updated_at""",
                (ward_id, now, staff_id),
            )
            return cursor.rowcount == 1

    def list_staff(self) -> List[StaffProfile]:
        with self.conn:
            rows = self.conn.execute(
                """SELECT staff_id, name, role, ward_id, avatar_color, initials, is_active
                   FROM staff_users WHERE role != 'dev_admin' ORDER BY name"""
            ).fetchall()
        return [StaffProfile(
            staff_id=r["staff_id"], name=r["name"], role=r["role"], ward_id=r["ward_id"],
            avatar_color=r["avatar_color"], initials=r["initials"], is_active=bool(r["is_active"]),
        ) for r in rows]

    def get_staff_directory(self, query: str = "") -> List[StaffProfile]:
        search = f"%{query.strip().lower()}%"
        with self.conn:
            rows = self.conn.execute(
                """SELECT staff_id, name, role, avatar_color, initials
                   FROM staff_users
                   WHERE is_active = 1 AND role != 'dev_admin'
                     AND (lower(name) LIKE ? OR lower(staff_id) LIKE ?)
                   ORDER BY name LIMIT 50""",
                (search, search),
            ).fetchall()
        return [StaffProfile(
            staff_id=r["staff_id"], name=r["name"], role=r["role"], ward_id="",
            avatar_color=r["avatar_color"], initials=r["initials"], is_active=True,
        ) for r in rows]

    def verify_pin(self, staff_id: str, pin: str, email: Optional[str] = None) -> Tuple[bool, Optional[StaffProfile], Optional[str]]:
        identifier = (email or staff_id).strip()
        now = time.time()
        if not identifier or not pin.isdigit() or len(pin) > 8:
            return False, None, "Invalid staff ID or PIN."
        failure = self.conn.execute(
            "SELECT failure_count, window_started, locked_until FROM auth_failures WHERE staff_id = ?",
            (identifier,),
        ).fetchone()
        if failure and failure["locked_until"] > now:
            remaining = max(1, int(failure["locked_until"] - now))
            return False, None, f"Too many failed attempts. Locked for {remaining}s."
        if failure and now - failure["window_started"] >= 180:
            with self.conn:
                self.conn.execute("DELETE FROM auth_failures WHERE staff_id = ?", (staff_id,))
            failure = None

        with self.conn:
            cursor = self.conn.cursor()
            cursor.execute(
                """
                SELECT staff_id, name, role, ward_id, pin_hash, pin_salt,
                       avatar_color, initials, is_active
                FROM staff_users
                WHERE is_active = 1 AND (staff_id = ? OR lower(email) = lower(?))
                """,
                (identifier, identifier),
            )
            row = cursor.fetchone()

        if not row:
            self._record_failure(identifier, now, failure)
            return False, None, "Staff account not found or inactive."

        expected_hash = self.hash_pin(pin, row["pin_salt"])
        if secrets.compare_digest(expected_hash, row["pin_hash"]):
            # Clear failed attempts upon successful login
            with self.conn:
                self.conn.execute("DELETE FROM auth_failures WHERE staff_id = ?", (staff_id,))
            profile = StaffProfile(
                staff_id=row["staff_id"],
                name=row["name"],
                role=row["role"],
                ward_id=row["ward_id"],
                avatar_color=row["avatar_color"],
                initials=row["initials"],
                is_active=bool(row["is_active"]),
            )
            return True, profile, None
        else:
            failure_count = self._record_failure(identifier, now, failure)
            remaining = 5 - failure_count
            if remaining > 0:
                err_msg = f"Invalid PIN. {remaining} attempt(s) remaining."
            else:
                err_msg = "Invalid PIN. Account locked for 3 minutes."
            return False, None, err_msg

    def _record_failure(self, staff_id: str, now: float, previous) -> int:
        count = (int(previous["failure_count"]) if previous else 0) + 1
        window_started = float(previous["window_started"]) if previous else now
        locked_until = now + 180 if count >= 5 else 0
        with self.conn:
            self.conn.execute(
                """INSERT INTO auth_failures (staff_id, failure_count, window_started, locked_until)
                   VALUES (?, ?, ?, ?) ON CONFLICT(staff_id) DO UPDATE SET
                   failure_count = excluded.failure_count,
                   window_started = excluded.window_started,
                   locked_until = excluded.locked_until""",
                (staff_id, count, window_started, locked_until),
            )
        return count

    def create_staff(
        self,
        staff_id: str,
        name: str,
        role: str,
        ward_id: str,
        pin: str,
        avatar_color: Optional[str] = None,
        email: Optional[str] = None,
    ) -> StaffProfile:
        staff_id, name = staff_id.strip(), name.strip()
        if not staff_id or not name or len(staff_id) > 80 or len(name) > 120:
            raise ValueError('Staff ID and name are required (maximum 80 and 120 characters).')
        if self.conn.execute('SELECT 1 FROM deleted_staff_ids WHERE staff_id = ?', (staff_id,)).fetchone():
            raise ValueError('This staff ID belonged to a deleted account and cannot be reused.')
        if role not in {"ward_nurse", "charge_nurse", "doctor_on_call"}:
            raise ValueError("Only clinical roles can be provisioned here.")
        if not pin.isdigit() or not 4 <= len(pin) <= 8:
            raise ValueError("PIN must contain 4 to 8 digits.")
        parts = [p for p in name.replace(",", "").split() if p and not p.lower().startswith("rn") and not p.lower().startswith("dr")]
        if len(parts) >= 2:
            initials = (parts[0][0] + parts[1][0]).upper()
        elif len(parts) == 1:
            initials = parts[0][:2].upper()
        else:
            initials = staff_id[:2].upper()

        color = avatar_color or "#059669"
        salt = secrets.token_hex(16)
        p_hash = self.hash_pin(pin, salt)
        now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

        with self.conn:
            cursor = self.conn.cursor()
            cursor.execute(
                """
                INSERT INTO staff_users (
                    staff_id, email, name, role, ward_id, pin_hash, pin_salt,
                    avatar_color, initials, is_active, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)
                """,
                (staff_id, (email or "").strip().lower(), name, role, "", p_hash, salt, color, initials, now_iso),
            )

        return StaffProfile(
            staff_id=staff_id,
            name=name,
            role=role,
            ward_id="",
            avatar_color=color,
            initials=initials,
            is_active=True,
        )

    def set_staff_active(self, staff_id: str, active: bool) -> bool:
        with self._lock, self.conn:
            cursor = self.conn.execute(
                "UPDATE staff_users SET is_active = ? WHERE staff_id = ? AND role != 'dev_admin'",
                (int(active), staff_id),
            )
            if not cursor.rowcount:
                return False
            if not active:
                self.conn.execute('DELETE FROM auth_sessions WHERE staff_id = ?', (staff_id,))
                self.conn.execute('DELETE FROM fcm_device_tokens WHERE staff_id = ?', (staff_id,))
            return True

    def delete_clinical_staff(self, staff_id: str) -> bool:
        with self._lock, self.conn:
            row = self.conn.execute(
                "SELECT email FROM staff_users WHERE staff_id = ? AND role != 'dev_admin'", (staff_id,),
            ).fetchone()
            if row is None:
                return False
            for table in ('auth_sessions', 'fcm_device_tokens', 'staff_ward_preferences'):
                self.conn.execute(f'DELETE FROM {table} WHERE staff_id = ?', (staff_id,))
            self.conn.execute('DELETE FROM auth_failures WHERE staff_id IN (?, ?)', (staff_id, row['email']))
            self.conn.execute('INSERT INTO deleted_staff_ids VALUES (?, ?)', (staff_id, time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())))
            self.conn.execute('DELETE FROM staff_users WHERE staff_id = ?', (staff_id,))
            return True

    def close(self):
        self.conn.close()
