import os
import sqlite3
from typing import Dict, List, Optional, Tuple, Any
from backend.models import HospitalWardModel, ShiftAllocationModel, AllocationConflictCheckResponse

DEFAULT_DB_PATH = os.path.join(os.path.dirname(__file__), "oravi_server.db")

class WardStore:
    def __init__(self, db_path: str = DEFAULT_DB_PATH):
        self.db_path = db_path
        self._init_tables()
        self._seed_default_wards()

    def _get_connection(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_tables(self) -> None:
        with self._get_connection() as conn:
            cursor = conn.cursor()
            # 1. Hospital Wards Catalog
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS hospital_wards (
                    ward_id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    bed_count INTEGER NOT NULL,
                    bed_numbers TEXT NOT NULL,
                    department TEXT NOT NULL,
                    description TEXT NOT NULL
                )
            """)

            # 2. Shift Allocations Table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS shift_allocations (
                    allocation_id TEXT PRIMARY KEY,
                    ward_id TEXT NOT NULL,
                    shift_type TEXT NOT NULL,
                    date TEXT NOT NULL,
                    published_by TEXT NOT NULL,
                    published_at TEXT NOT NULL,
                    support_roster_json TEXT NOT NULL
                )
            """)

            # 3. Bed Allocations
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS shift_bed_assignments (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    allocation_id TEXT NOT NULL,
                    ward_id TEXT NOT NULL,
                    bed_number TEXT NOT NULL,
                    patient_initials TEXT,
                    admission_number TEXT,
                    admitting_doctor TEXT,
                    assigned_nurse_id TEXT,
                    shift_type TEXT NOT NULL,
                    date TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'pending',
                    FOREIGN KEY (allocation_id) REFERENCES shift_allocations(allocation_id)
                )
            """)
            conn.commit()

    def _seed_default_wards(self) -> None:
        import json
        wards = [
            (
                "ward-jacaranda",
                "Jacaranda Ward (Pediatrics)",
                12,
                json.dumps(["25", "26", "27", "28", "29", "30", "31", "43", "44", "45", "46", "47"]),
                "Pediatrics",
                "General Pediatric Inpatient Ward & Short-Stay Unit"
            ),
            (
                "ward-edna",
                "Edna Ward (Surgical)",
                10,
                json.dumps(["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]),
                "Surgery",
                "Post-operative Surgical Recovery & Orthopedics"
            ),
            (
                "ward-kilimanjaro",
                "Kilimanjaro Ward (Adult Medical)",
                14,
                json.dumps(["101", "102", "103", "104", "105", "106", "107", "108", "109", "110", "111", "112", "113", "114"]),
                "Internal Medicine",
                "Acute Adult Medical Admissions & High Dependency"
            ),
            (
                "ward-4b",
                "Ward 4B (Inpatient Medical/Surgical)",
                5,
                json.dumps(["Bed 1", "Bed 2", "Bed 3", "Bed 4", "Bed 5"]),
                "Mixed Med-Surg",
                "Clinical Station Reference Ward 4B"
            )
        ]
        with self._get_connection() as conn:
            cursor = conn.cursor()
            for w in wards:
                cursor.execute("""
                    INSERT OR IGNORE INTO hospital_wards (ward_id, name, bed_count, bed_numbers, department, description)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, w)
            conn.commit()

    def get_all_wards(self) -> List[HospitalWardModel]:
        import json
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT ward_id, name, bed_count, bed_numbers, department, description FROM hospital_wards")
            rows = cursor.fetchall()
            return [
                HospitalWardModel(
                    ward_id=r["ward_id"],
                    name=r["name"],
                    bed_count=r["bed_count"],
                    bed_numbers=json.loads(r["bed_numbers"]),
                    department=r["department"],
                    description=r["description"]
                )
                for r in rows
            ]

    def check_nurse_shift_conflict(self, nurse_id: str, date: str, shift_type: str, target_ward_id: str) -> AllocationConflictCheckResponse:
        """
        FR-Guardrail: Cross-ward double-booking prevention.
        Checks if nurse_id is already assigned in another ward on the same date and shift.
        """
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT s.ward_id, w.name as ward_name, COUNT(b.id) as bed_count
                FROM shift_bed_assignments b
                JOIN hospital_wards w ON b.ward_id = w.ward_id
                JOIN shift_allocations s ON b.allocation_id = s.allocation_id
                WHERE b.assigned_nurse_id = ? 
                  AND b.date = ? 
                  AND b.shift_type = ? 
                  AND b.ward_id != ?
                GROUP BY s.ward_id, w.name
            """, (nurse_id, date, shift_type, target_ward_id))
            row = cursor.fetchone()

            if row:
                conflict_ward = row["ward_name"]
                beds = row["bed_count"]
                return AllocationConflictCheckResponse(
                    has_conflict=True,
                    conflict_ward_id=row["ward_id"],
                    conflict_ward_name=conflict_ward,
                    conflict_nurse_id=nurse_id,
                    conflict_shift_type=shift_type,
                    message=f"Nurse {nurse_id} is already active on {shift_type.capitalize()} Shift in {conflict_ward} ({beds} beds assigned). Cannot assign to another ward without transfer."
                )

            return AllocationConflictCheckResponse(has_conflict=False)

    def publish_shift_allocation(self, allocation: ShiftAllocationModel) -> bool:
        import json
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT OR REPLACE INTO shift_allocations (
                    allocation_id, ward_id, shift_type, date, published_by, published_at, support_roster_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (
                allocation.allocation_id,
                allocation.ward_id,
                allocation.shift_type,
                allocation.date,
                allocation.published_by,
                allocation.published_at,
                json.dumps(allocation.support_roster)
            ))

            # Remove previous bed assignments for this allocation if any
            cursor.execute("DELETE FROM shift_bed_assignments WHERE allocation_id = ?", (allocation.allocation_id,))

            for b in allocation.bed_assignments:
                cursor.execute("""
                    INSERT INTO shift_bed_assignments (
                        allocation_id, ward_id, bed_number, patient_initials, admission_number,
                        admitting_doctor, assigned_nurse_id, shift_type, date, status
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    allocation.allocation_id,
                    allocation.ward_id,
                    b.get("bed_number", ""),
                    b.get("patient_initials", ""),
                    b.get("admission_number", ""),
                    b.get("admitting_doctor", ""),
                    b.get("assigned_nurse_id"),
                    allocation.shift_type,
                    allocation.date,
                    b.get("status", "pending")
                ))

            conn.commit()
            return True

    def accept_shift_beds(self, allocation_id: str, nurse_id: str, beds: List[str]) -> int:
        with self._get_connection() as conn:
            cursor = conn.cursor()
            placeholders = ",".join("?" for _ in beds)
            cursor.execute(f"""
                UPDATE shift_bed_assignments
                SET status = 'accepted'
                WHERE allocation_id = ? 
                  AND assigned_nurse_id = ? 
                  AND bed_number IN ({placeholders})
            """, [allocation_id, nurse_id, *beds])
            updated = cursor.rowcount
            conn.commit()
            return updated

    def get_nurse_active_shift(self, nurse_id: str, date: str, shift_type: str) -> Optional[Dict[str, Any]]:
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT b.allocation_id, b.ward_id, w.name as ward_name, b.bed_number, 
                       b.patient_initials, b.admitting_doctor, b.status
                FROM shift_bed_assignments b
                JOIN hospital_wards w ON b.ward_id = w.ward_id
                WHERE b.assigned_nurse_id = ? AND b.date = ? AND b.shift_type = ?
            """, (nurse_id, date, shift_type))
            rows = cursor.fetchall()
            if not rows:
                return None

            ward_id = rows[0]["ward_id"]
            ward_name = rows[0]["ward_name"]
            alloc_id = rows[0]["allocation_id"]
            beds = [
                {
                    "bed_number": r["bed_number"],
                    "patient_initials": r["patient_initials"],
                    "admitting_doctor": r["admitting_doctor"],
                    "status": r["status"]
                }
                for r in rows
            ]
            return {
                "allocation_id": alloc_id,
                "ward_id": ward_id,
                "ward_name": ward_name,
                "shift_type": shift_type,
                "date": date,
                "nurse_id": nurse_id,
                "beds": beds
            }
