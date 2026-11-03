from contextlib import contextmanager
import json
import os
import sqlite3
from typing import Dict, Iterator, List, Optional, Tuple, Any
from backend.models import HospitalWardModel, ShiftAllocationModel, AllocationConflictCheckResponse

DEFAULT_DB_PATH = os.path.join(os.path.dirname(__file__), "oravi_server.db")

class WardStore:
    def __init__(self, db_path: str = DEFAULT_DB_PATH):
        self.db_path = db_path
        self._init_tables()

    @contextmanager
    def _get_connection(self) -> Iterator[sqlite3.Connection]:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
        finally:
            conn.close()

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
                    patient_id TEXT,
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
            columns = {
                row["name"]
                for row in cursor.execute(
                    "PRAGMA table_info(shift_bed_assignments)"
                ).fetchall()
            }
            if "patient_id" not in columns:
                cursor.execute(
                    "ALTER TABLE shift_bed_assignments ADD COLUMN patient_id TEXT"
                )
            conn.commit()

    def get_all_wards(self) -> List[HospitalWardModel]:
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

    def create_ward(self, ward: HospitalWardModel) -> None:
        with self._get_connection() as conn:
            conn.execute(
                """INSERT INTO hospital_wards
                   (ward_id, name, bed_count, bed_numbers, department, description)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (ward.ward_id, ward.name, len(ward.bed_numbers), json.dumps(ward.bed_numbers), ward.department, ward.description),
            )
            conn.commit()

    def get_ward_board(self, ward_id: str, date: str, shift_type: str) -> Optional[Dict[str, Any]]:
        with self._get_connection() as conn:
            ward = conn.execute(
                "SELECT bed_numbers FROM hospital_wards WHERE ward_id = ?",
                (ward_id,),
            ).fetchone()
            if ward is None:
                return None
            allocations = conn.execute(
                """SELECT allocation_id, shift_type, support_roster_json FROM shift_allocations
                   WHERE ward_id = ? AND date = ? AND shift_type = ?
                   ORDER BY published_at DESC LIMIT 1""",
                (ward_id, date, shift_type),
            ).fetchone()
            other_shift = "night" if shift_type == "day" else "day"
            other_allocation = conn.execute(
                """SELECT allocation_id, support_roster_json FROM shift_allocations
                   WHERE ward_id = ? AND date = ? AND shift_type = ?
                   ORDER BY published_at DESC LIMIT 1""",
                (ward_id, date, other_shift),
            ).fetchone()
            assignments = conn.execute(
                """SELECT bed_number, patient_id, patient_initials, admitting_doctor,
                          assigned_nurse_id, shift_type, status
                   FROM shift_bed_assignments
                   WHERE ward_id = ? AND date = ?
                   ORDER BY bed_number""",
                (ward_id, date),
            ).fetchall()

        by_bed: Dict[str, Dict[str, Any]] = {
            bed_number: {
                "bed_number": bed_number,
                "patient_id": None,
                "patient_initials": "",
                "admitting_doctor": "",
                "day_shift_nurse_id": None,
                "night_shift_nurse_id": None,
                "status": "available",
            }
            for bed_number in json.loads(ward["bed_numbers"])
        }
        for assignment in assignments:
            row = by_bed.setdefault(
                assignment["bed_number"],
                {
                    "bed_number": assignment["bed_number"],
                    "patient_id": None,
                    "patient_initials": "",
                    "admitting_doctor": "",
                    "day_shift_nurse_id": None,
                    "night_shift_nurse_id": None,
                    "status": "available",
                },
            )
            if assignment["patient_id"] or assignment["patient_initials"]:
                row["patient_id"] = assignment["patient_id"]
                row["patient_initials"] = assignment["patient_initials"] or ""
                row["admitting_doctor"] = assignment["admitting_doctor"] or ""
                row["status"] = assignment["status"]
            row[f'{assignment["shift_type"]}_shift_nurse_id'] = assignment[
                "assigned_nurse_id"
            ]

        return {
            "allocation_id": allocations["allocation_id"] if allocations else None,
            "ward_id": ward_id,
            "date": date,
            "shift_type": shift_type,
            "bed_assignments": list(by_bed.values()),
            "responsibilities": json.loads(
                (allocations or other_allocation)["support_roster_json"]
            ) if allocations or other_allocation else {},
        }

    def check_nurse_shift_conflict(
        self, nurse_id: str, date: str, shift_type: str, target_ward_id: str
    ) -> AllocationConflictCheckResponse:
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

    def get_staff_active_assignment(
        self, staff_id: str, date: str, shift_type: str
    ) -> Optional[Dict[str, Any]]:
        with self._get_connection() as conn:
            rows = conn.execute(
                """SELECT DISTINCT a.ward_id, w.name AS ward_name
                   FROM shift_bed_assignments b
                   JOIN shift_allocations a ON a.allocation_id = b.allocation_id
                   JOIN hospital_wards w ON w.ward_id = a.ward_id
                   WHERE b.assigned_nurse_id = ? AND a.date = ? AND a.shift_type = ?
                     AND b.patient_id IS NOT NULL AND b.patient_initials != ''""",
                (staff_id, date, shift_type),
            ).fetchall()
        if not rows:
            return None
        if len(rows) > 1:
            raise ValueError(
                f"Staff member {staff_id} has conflicting {shift_type} ward assignments."
            )
        return {
            "staff_id": staff_id,
            "ward_id": rows[0]["ward_id"],
            "ward_name": rows[0]["ward_name"],
            "date": date,
            "shift_type": shift_type,
        }

    def has_staff_assignment(
        self, staff_id: str, ward_id: str, date: str, shift_type: str
    ) -> bool:
        with self._get_connection() as conn:
            row = conn.execute(
                """SELECT 1 FROM shift_bed_assignments
                   WHERE assigned_nurse_id = ? AND ward_id = ? AND date = ?
                     AND shift_type = ? AND patient_id IS NOT NULL
                   LIMIT 1""",
                (staff_id, ward_id, date, shift_type),
            ).fetchone()
        return row is not None

    def has_staff_assignment_on_date(
        self, staff_id: str, ward_id: str, date: str
    ) -> bool:
        with self._get_connection() as conn:
            row = conn.execute(
                """SELECT 1 FROM shift_bed_assignments
                   WHERE assigned_nurse_id = ? AND ward_id = ? AND date = ?
                     AND patient_id IS NOT NULL
                   LIMIT 1""",
                (staff_id, ward_id, date),
            ).fetchone()
        return row is not None

    def publish_shift_allocation(self, allocation: ShiftAllocationModel) -> bool:
        with self._get_connection() as conn:
            with conn:
                cursor = conn.cursor()
                patient_ids = [
                    str(item["patient_id"])
                    for item in allocation.bed_assignments
                    if item.get("patient_id")
                ]
                if len(patient_ids) != len(set(patient_ids)):
                    raise ValueError(
                        "A patient may only occupy one bed on this ward and shift."
                    )

                for nurse_id in {
                    str(item["assigned_nurse_id"])
                    for item in allocation.bed_assignments
                    if item.get("assigned_nurse_id")
                }:
                    conflict = cursor.execute(
                        """SELECT w.name AS ward_name
                           FROM shift_bed_assignments b
                           JOIN hospital_wards w ON w.ward_id = b.ward_id
                           JOIN shift_allocations a ON a.allocation_id = b.allocation_id
                           WHERE b.assigned_nurse_id = ? AND a.date = ?
                             AND a.shift_type = ? AND a.ward_id != ?
                           LIMIT 1""",
                        (
                            nurse_id,
                            allocation.date,
                            allocation.shift_type,
                            allocation.ward_id,
                        ),
                    ).fetchone()
                    if conflict:
                        raise ValueError(
                            f"{nurse_id} is already assigned to {conflict['ward_name']} "
                            f"for the {allocation.shift_type} shift on {allocation.date}."
                        )

                for patient_id in set(patient_ids):
                    conflict = cursor.execute(
                        """SELECT w.name AS ward_name
                           FROM shift_bed_assignments b
                           JOIN hospital_wards w ON w.ward_id = b.ward_id
                           JOIN shift_allocations a ON a.allocation_id = b.allocation_id
                           WHERE b.patient_id = ? AND a.date = ? AND a.ward_id != ?
                           LIMIT 1""",
                        (patient_id, allocation.date, allocation.ward_id),
                    ).fetchone()
                    if conflict:
                        raise ValueError(
                            f"This patient is already on the board for "
                            f"{conflict['ward_name']} on {allocation.date}."
                        )

                cursor.execute(
                    """DELETE FROM shift_bed_assignments
                       WHERE allocation_id IN (
                           SELECT allocation_id FROM shift_allocations
                           WHERE ward_id = ? AND date = ? AND shift_type = ?
                       )""",
                    (allocation.ward_id, allocation.date, allocation.shift_type),
                )
                cursor.execute(
                    """DELETE FROM shift_allocations
                       WHERE ward_id = ? AND date = ? AND shift_type = ?""",
                    (allocation.ward_id, allocation.date, allocation.shift_type),
                )
                cursor.execute(
                    """INSERT INTO shift_allocations (
                           allocation_id, ward_id, shift_type, date, published_by,
                           published_at, support_roster_json
                       ) VALUES (?, ?, ?, ?, ?, ?, ?)""",
                    (
                        allocation.allocation_id,
                        allocation.ward_id,
                        allocation.shift_type,
                        allocation.date,
                        allocation.published_by,
                        allocation.published_at,
                        json.dumps(allocation.support_roster),
                    ),
                )

                for assignment in allocation.bed_assignments:
                    patient_id = assignment.get("patient_id")
                    initials = assignment.get("patient_initials", "")
                    if initials and not patient_id:
                        raise ValueError(
                            "Every occupied bed must reference a stable patient ID."
                        )
                    cursor.execute(
                        """INSERT INTO shift_bed_assignments (
                               allocation_id, ward_id, bed_number, patient_id,
                               patient_initials, admission_number, admitting_doctor,
                               assigned_nurse_id, shift_type, date, status
                           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                        (
                            allocation.allocation_id,
                            allocation.ward_id,
                            assignment.get("bed_number", ""),
                            patient_id,
                            initials,
                            assignment.get("admission_number"),
                            assignment.get("admitting_doctor", ""),
                            assignment.get("assigned_nurse_id"),
                            allocation.shift_type,
                            allocation.date,
                            assignment.get("status", "pending"),
                        ),
                    )
            return True

    def accept_shift_beds(self, allocation_id: str, nurse_id: str, beds: List[str], ward_id: Optional[str] = None) -> int:
        with self._get_connection() as conn:
            cursor = conn.cursor()
            placeholders = ",".join("?" for _ in beds)
            ward_filter = " AND ward_id = ?" if ward_id is not None else ""
            parameters = [allocation_id, nurse_id, *beds]
            if ward_id is not None:
                parameters.append(ward_id)
            cursor.execute(f"""
                UPDATE shift_bed_assignments
                SET status = 'accepted'
                WHERE allocation_id = ? 
                  AND assigned_nurse_id = ? 
                  AND bed_number IN ({placeholders})
                  {ward_filter}
            """, parameters)
            updated = cursor.rowcount
            conn.commit()
            return updated

    def transfer_handoff_beds(
        self,
        allocation_id: str,
        outgoing_nurse_id: str,
        incoming_nurse_id: str,
        beds: List[str],
    ) -> int:
        requested_beds = list(dict.fromkeys(beds))
        if not requested_beds:
            raise ValueError("Select at least one patient bed to accept.")

        with self._get_connection() as conn:
            allocation = conn.execute(
                """SELECT ward_id, date, shift_type
                   FROM shift_allocations WHERE allocation_id = ?""",
                (allocation_id,),
            ).fetchone()
            if allocation is None:
                raise ValueError("The ward allocation was not found.")

            ward_id = allocation["ward_id"]
            date = allocation["date"]
            shift_type = allocation["shift_type"]
            incoming_assignment = conn.execute(
                """SELECT 1 FROM shift_bed_assignments
                   WHERE assigned_nurse_id = ? AND ward_id = ? AND date = ?
                     AND shift_type = ? AND patient_id IS NOT NULL
                   LIMIT 1""",
                (incoming_nurse_id, ward_id, date, shift_type),
            ).fetchone()
            if incoming_assignment is None:
                raise ValueError(
                    "The incoming nurse must already be assigned to this ward and shift."
                )

            conflict = conn.execute(
                """SELECT ward_id FROM shift_bed_assignments
                   WHERE assigned_nurse_id = ? AND date = ? AND shift_type = ?
                     AND ward_id != ? AND patient_id IS NOT NULL
                   LIMIT 1""",
                (incoming_nurse_id, date, shift_type, ward_id),
            ).fetchone()
            if conflict is not None:
                raise ValueError(
                    "The incoming nurse is assigned to another ward for this shift."
                )

            placeholders = ",".join("?" for _ in requested_beds)
            assignments = conn.execute(
                f"""SELECT bed_number, assigned_nurse_id
                    FROM shift_bed_assignments
                    WHERE allocation_id = ? AND bed_number IN ({placeholders})
                      AND patient_id IS NOT NULL""",
                (allocation_id, *requested_beds),
            ).fetchall()
            if len(assignments) != len(requested_beds):
                raise ValueError(
                    "Every selected bed must contain a patient on this allocation."
                )
            if any(
                row["assigned_nurse_id"]
                not in {outgoing_nurse_id, incoming_nurse_id}
                for row in assignments
            ):
                raise ValueError(
                    "A selected bed is not owned by the outgoing or incoming nurse."
                )

            conn.execute(
                f"""UPDATE shift_bed_assignments
                    SET assigned_nurse_id = ?, status = 'accepted'
                    WHERE allocation_id = ? AND bed_number IN ({placeholders})
                      AND patient_id IS NOT NULL""",
                (incoming_nurse_id, allocation_id, *requested_beds),
            )
            conn.commit()
            return len(requested_beds)

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
