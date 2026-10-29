import hashlib
import os
import secrets
import sqlite3
import time
from typing import Dict, List, Optional, Tuple
from .models import StaffProfile

DEFAULT_WARD_STAFF = [
    {
        "staff_id": "NUR-401",
        "name": "Mary Wanjiku, RN",
        "role": "ward_nurse",
        "ward_id": "WARD-4B",
        "pin": "1234",
        "avatar_color": "#059669",  # Emerald
        "initials": "MW",
    },
    {
        "staff_id": "NUR-402",
        "name": "Grace Achieng, RN",
        "role": "charge_nurse",
        "ward_id": "WARD-4B",
        "pin": "5678",
        "avatar_color": "#2563EB",  # Royal Blue
        "initials": "GA",
    },
    {
        "staff_id": "NUR-403",
        "name": "Faith Njeri, RN",
        "role": "ward_nurse",
        "ward_id": "WARD-4B",
        "pin": "1111",
        "avatar_color": "#0D9488",  # Teal
        "initials": "FN",
    },
    {
        "staff_id": "DOC-401",
        "name": "Dr. James Kamau",
        "role": "doctor_on_call",
        "ward_id": "WARD-4B",
        "pin": "9090",
        "avatar_color": "#7C3AED",  # Purple
        "initials": "JK",
    },
    {
        "staff_id": "NUR-404",
        "name": "Sarah Otieno, RN",
        "role": "ward_nurse",
        "ward_id": "WARD-4B",
        "pin": "2222",
        "avatar_color": "#D97706",  # Amber
        "initials": "SO",
    },
    {
        "staff_id": "NUR-405",
        "name": "Jane Muthoni, RN",
        "role": "ward_nurse",
        "ward_id": "WARD-4B",
        "pin": "3333",
        "avatar_color": "#E11D48",  # Rose
        "initials": "JM",
    },
]

class StaffStore:
    def __init__(self, db_path: Optional[str] = None):
        if db_path is None:
            base_dir = os.path.dirname(os.path.abspath(__file__))
            self.db_path = os.path.join(base_dir, "oravi_server.db")
        else:
            self.db_path = db_path

        self.conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self._failed_attempts: Dict[str, List[float]] = {}
        self._init_db()
        self._seed_default_staff_if_empty()

    def _init_db(self):
        with self.conn:
            self.conn.execute(
                """
                CREATE TABLE IF NOT EXISTS staff_users (
                    staff_id TEXT PRIMARY KEY,
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
            self.conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_staff_ward ON staff_users(ward_id)"
            )

    @staticmethod
    def hash_pin(pin: str, salt: str) -> str:
        return hashlib.sha256(f"{salt}:{pin}".encode("utf-8")).hexdigest()

    def _seed_default_staff_if_empty(self):
        with self.conn:
            cursor = self.conn.cursor()
            cursor.execute("SELECT COUNT(*) as cnt FROM staff_users")
            row = cursor.fetchone()
            if row and row["cnt"] > 0:
                return

            now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            for member in DEFAULT_WARD_STAFF:
                salt = secrets.token_hex(8)
                p_hash = self.hash_pin(member["pin"], salt)
                cursor.execute(
                    """
                    INSERT INTO staff_users (
                        staff_id, name, role, ward_id, pin_hash, pin_salt,
                        avatar_color, initials, is_active, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?)
                    """,
                    (
                        member["staff_id"],
                        member["name"],
                        member["role"],
                        member["ward_id"],
                        p_hash,
                        salt,
                        member["avatar_color"],
                        member["initials"],
                        now_iso,
                    ),
                )

    def get_staff_for_ward(self, ward_id: str) -> List[StaffProfile]:
        with self.conn:
            cursor = self.conn.cursor()
            cursor.execute(
                """
                SELECT staff_id, name, role, ward_id, avatar_color, initials, is_active
                FROM staff_users
                WHERE ward_id = ? AND is_active = 1
                ORDER BY role DESC, name ASC
                """,
                (ward_id,),
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

    def verify_pin(self, staff_id: str, pin: str) -> Tuple[bool, Optional[StaffProfile], Optional[str]]:
        now = time.time()
        # Clean up failed attempts older than 3 minutes (180s)
        attempts = [t for t in self._failed_attempts.get(staff_id, []) if now - t < 180]
        self._failed_attempts[staff_id] = attempts

        if len(attempts) >= 5:
            remaining_seconds = int(180 - (now - attempts[0]))
            return False, None, f"Too many failed attempts. Locked for {remaining_seconds}s."

        with self.conn:
            cursor = self.conn.cursor()
            cursor.execute(
                """
                SELECT staff_id, name, role, ward_id, pin_hash, pin_salt,
                       avatar_color, initials, is_active
                FROM staff_users
                WHERE staff_id = ? AND is_active = 1
                """,
                (staff_id,),
            )
            row = cursor.fetchone()

        if not row:
            return False, None, "Staff account not found or inactive."

        expected_hash = self.hash_pin(pin, row["pin_salt"])
        if secrets.compare_digest(expected_hash, row["pin_hash"]):
            # Clear failed attempts upon successful login
            if staff_id in self._failed_attempts:
                del self._failed_attempts[staff_id]
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
            self._failed_attempts.setdefault(staff_id, []).append(now)
            remaining = 5 - len(self._failed_attempts[staff_id])
            if remaining > 0:
                err_msg = f"Invalid PIN. {remaining} attempt(s) remaining."
            else:
                err_msg = "Invalid PIN. Account locked for 3 minutes."
            return False, None, err_msg

    def create_staff(
        self,
        staff_id: str,
        name: str,
        role: str,
        ward_id: str,
        pin: str,
        avatar_color: Optional[str] = None,
    ) -> StaffProfile:
        parts = [p for p in name.replace(",", "").split() if p and not p.lower().startswith("rn") and not p.lower().startswith("dr")]
        if len(parts) >= 2:
            initials = (parts[0][0] + parts[1][0]).upper()
        elif len(parts) == 1:
            initials = parts[0][:2].upper()
        else:
            initials = staff_id[:2].upper()

        color = avatar_color or "#059669"
        salt = secrets.token_hex(8)
        p_hash = self.hash_pin(pin, salt)
        now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

        with self.conn:
            cursor = self.conn.cursor()
            cursor.execute(
                """
                INSERT OR REPLACE INTO staff_users (
                    staff_id, name, role, ward_id, pin_hash, pin_salt,
                    avatar_color, initials, is_active, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?)
                """,
                (staff_id, name, role, ward_id, p_hash, salt, color, initials, now_iso),
            )

        return StaffProfile(
            staff_id=staff_id,
            name=name,
            role=role,
            ward_id=ward_id,
            avatar_color=color,
            initials=initials,
            is_active=True,
        )

    def close(self):
        self.conn.close()
