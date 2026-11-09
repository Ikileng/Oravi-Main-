from contextlib import contextmanager
import json
import os
import sqlite3
import uuid
from datetime import datetime, timezone
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
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS handoff_bed_acceptances (
                    handoff_session_id TEXT NOT NULL,
                    allocation_id TEXT NOT NULL,
                    patient_id TEXT NOT NULL,
                    bed_number TEXT NOT NULL,
                    outgoing_nurse_id TEXT NOT NULL,
                    incoming_nurse_id TEXT NOT NULL,
                    transferred_loop_ids_json TEXT NOT NULL,
                    accepted_at TEXT NOT NULL,
                    PRIMARY KEY (handoff_session_id, patient_id)
                )
            """)
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
                   WHERE (b.assigned_nurse_id = ? OR b.admitting_doctor = ?)
                     AND a.date = ? AND a.shift_type = ?
                     AND b.patient_id IS NOT NULL AND b.patient_initials != ''""",
                (staff_id, staff_id, date, shift_type),
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
                   UNION ALL
                   SELECT 1 FROM shift_bed_assignments
                   WHERE admitting_doctor = ? AND ward_id = ? AND date = ?
                     AND patient_id IS NOT NULL
                   LIMIT 1""",
                (staff_id, ward_id, date, shift_type, staff_id, ward_id, date),
            ).fetchone()
        return row is not None

    def has_staff_assignment_on_date(
        self, staff_id: str, ward_id: str, date: str
    ) -> bool:
        with self._get_connection() as conn:
            row = conn.execute(
                """SELECT 1 FROM shift_bed_assignments
                   WHERE ward_id = ? AND date = ? AND patient_id IS NOT NULL
                     AND (assigned_nurse_id = ? OR admitting_doctor = ?)
                   LIMIT 1""",
                (ward_id, date, staff_id, staff_id),
            ).fetchone()
        return row is not None

    def get_patient_assignment(
        self, patient_id: str, date: str
    ) -> Optional[Dict[str, Any]]:
        with self._get_connection() as conn:
            rows = conn.execute(
                """SELECT DISTINCT ward_id, assigned_nurse_id, admitting_doctor
                   FROM shift_bed_assignments
                   WHERE patient_id = ? AND date = ?""",
                (patient_id, date),
            ).fetchall()
        ward_ids = {row["ward_id"] for row in rows}
        if not rows or len(ward_ids) != 1:
            return None
        return {
            "ward_id": next(iter(ward_ids)),
            "staff_ids": {
                staff_id
                for row in rows
                for staff_id in (
                    row["assigned_nurse_id"],
                    row["admitting_doctor"],
                )
                if staff_id and staff_id != "-"
            },
            "doctor_ids": {
                row["admitting_doctor"]
                for row in rows
                if row["admitting_doctor"] and row["admitting_doctor"] != "-"
            },
        }

    def get_patient_ids_for_staff(
        self, staff_id: str, date: str, ward_id: Optional[str] = None
    ) -> List[str]:
        query = """SELECT DISTINCT patient_id
                   FROM shift_bed_assignments
                   WHERE date = ? AND patient_id IS NOT NULL
                     AND (assigned_nurse_id = ? OR admitting_doctor = ?)"""
        values: List[Any] = [date, staff_id, staff_id]
        if ward_id is not None:
            query += " AND ward_id = ?"
            values.append(ward_id)
        with self._get_connection() as conn:
            rows = conn.execute(query, values).fetchall()
        return [str(row["patient_id"]) for row in rows]

    def get_patient_ids_for_ward(self, ward_id: str, date: str) -> List[str]:
        with self._get_connection() as conn:
            rows = conn.execute(
                """SELECT DISTINCT patient_id FROM shift_bed_assignments
                   WHERE ward_id = ? AND date = ? AND patient_id IS NOT NULL""",
                (ward_id, date),
            ).fetchall()
        return [str(row["patient_id"]) for row in rows]

    def patient_ids_removed_by_allocation(
        self,
        allocation: ShiftAllocationModel,
        connection: Optional[sqlite3.Connection] = None,
    ) -> set[str]:
        if connection is None:
            with self._get_connection() as conn:
                return self._patient_ids_removed_by_allocation(conn, allocation)
        return self._patient_ids_removed_by_allocation(connection, allocation)

    def _patient_ids_removed_by_allocation(
        self, connection: sqlite3.Connection, allocation: ShiftAllocationModel
    ) -> set[str]:
        existing = connection.execute(
            """SELECT patient_id FROM shift_bed_assignments
               WHERE ward_id = ? AND date = ? AND shift_type = ?
                 AND patient_id IS NOT NULL""",
            (allocation.ward_id, allocation.date, allocation.shift_type),
        ).fetchall()
        other_shift = connection.execute(
            """SELECT patient_id FROM shift_bed_assignments
               WHERE ward_id = ? AND date = ? AND shift_type != ?
                 AND patient_id IS NOT NULL""",
            (allocation.ward_id, allocation.date, allocation.shift_type),
        ).fetchall()
        retained = {
            str(row["patient_id"])
            for row in other_shift
        } | {
            str(item["patient_id"])
            for item in allocation.bed_assignments
            if item.get("patient_id")
        }
        return {
            str(row["patient_id"])
            for row in existing
            if str(row["patient_id"]) not in retained
        }

    def publish_shift_allocation(
        self,
        allocation: ShiftAllocationModel,
        connection: Optional[sqlite3.Connection] = None,
    ) -> bool:
        if connection is not None:
            self._publish_shift_allocation_on_connection(connection, allocation)
            return True
        with self._get_connection() as conn:
            with conn:
                self._publish_shift_allocation_on_connection(conn, allocation)
        return True

    def _publish_shift_allocation_on_connection(
        self, conn: sqlite3.Connection, allocation: ShiftAllocationModel
    ) -> None:
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
        handoff_session_id: str,
        transferred_loop_ids_by_patient: Dict[str, List[str]],
        expected_ward_id: str,
    ) -> int:
        requested_beds = list(dict.fromkeys(beds))
        if not requested_beds:
            raise ValueError("Select at least one patient bed to accept.")
        if not handoff_session_id.strip():
            raise ValueError("A handoff session is required.")

        with self._get_connection() as conn:
            allocation = conn.execute(
                """SELECT ward_id, date, shift_type
                   FROM shift_allocations WHERE allocation_id = ?""",
                (allocation_id,),
            ).fetchone()
            if allocation is None:
                raise ValueError("The ward allocation was not found.")

            ward_id = allocation["ward_id"]
            if ward_id != expected_ward_id:
                raise ValueError(
                    "The allocation does not belong to the handoff ward."
                )
            date = allocation["date"]
            outgoing_shift = allocation["shift_type"]
            incoming_shift = "night" if outgoing_shift == "day" else "day"

            conflict = conn.execute(
                """SELECT ward_id FROM shift_bed_assignments
                   WHERE assigned_nurse_id = ? AND date = ? AND shift_type = ?
                     AND ward_id != ? AND patient_id IS NOT NULL
                   LIMIT 1""",
                (incoming_nurse_id, date, incoming_shift, ward_id),
            ).fetchone()
            if conflict is not None:
                raise ValueError(
                    f"The incoming nurse is assigned to another ward for the "
                    f"{incoming_shift} shift."
                )

            placeholders = ",".join("?" for _ in requested_beds)
            existing_acceptances = conn.execute(
                f"""SELECT patient_id, bed_number, outgoing_nurse_id,
                           incoming_nurse_id, transferred_loop_ids_json
                    FROM handoff_bed_acceptances
                    WHERE handoff_session_id = ? AND allocation_id = ?
                      AND bed_number IN ({placeholders})""",
                (handoff_session_id, allocation_id, *requested_beds),
            ).fetchall()
            if existing_acceptances:
                if len(existing_acceptances) != len(requested_beds) or any(
                    row["outgoing_nurse_id"] != outgoing_nurse_id
                    or row["incoming_nurse_id"] != incoming_nurse_id
                    or sorted(
                        set(
                            transferred_loop_ids_by_patient.get(
                                str(row["patient_id"]), []
                            )
                        )
                    )
                    != json.loads(row["transferred_loop_ids_json"])
                    for row in existing_acceptances
                ):
                    raise ValueError(
                        "This handoff bed was already accepted with different details."
                    )
                return len(existing_acceptances)

            assignments = conn.execute(
                f"""SELECT bed_number, patient_id, patient_initials,
                           admission_number, admitting_doctor, assigned_nurse_id
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
                row["assigned_nurse_id"] != outgoing_nurse_id
                for row in assignments
            ):
                raise ValueError(
                    "Every selected bed must be assigned to the outgoing nurse."
                )
            if {
                str(row["patient_id"]) for row in assignments
            } != set(transferred_loop_ids_by_patient.keys()):
                raise ValueError(
                    "The transferred issue list must match the selected patients."
                )

            target_allocation = conn.execute(
                """SELECT allocation_id FROM shift_allocations
                   WHERE ward_id = ? AND date = ? AND shift_type = ?
                   ORDER BY published_at DESC LIMIT 1""",
                (ward_id, date, incoming_shift),
            ).fetchone()
            target_allocation_id = (
                target_allocation["allocation_id"]
                if target_allocation
                else f"HANDOFF-{uuid.uuid4()}"
            )
            with conn:
                if target_allocation is None:
                    conn.execute(
                        """INSERT INTO shift_allocations (
                               allocation_id, ward_id, shift_type, date, published_by,
                               published_at, support_roster_json
                           ) VALUES (?, ?, ?, ?, ?, ?, ?)""",
                        (
                            target_allocation_id,
                            ward_id,
                            incoming_shift,
                            date,
                            outgoing_nurse_id,
                            datetime.now(timezone.utc).isoformat(),
                            "{}",
                        ),
                    )

                for assignment in assignments:
                    patient_id = str(assignment["patient_id"])
                    if conn.execute(
                        """SELECT 1 FROM handoff_bed_acceptances
                           WHERE handoff_session_id = ? AND patient_id = ?""",
                        (handoff_session_id, patient_id),
                    ).fetchone():
                        raise ValueError(
                            "This patient has already been accepted for this handoff."
                        )
                    target_patient = conn.execute(
                        """SELECT allocation_id FROM shift_bed_assignments
                           WHERE ward_id = ? AND date = ? AND shift_type = ?
                             AND patient_id = ?
                           LIMIT 1""",
                        (
                            ward_id,
                            date,
                            incoming_shift,
                            assignment["patient_id"],
                        ),
                    ).fetchone()
                    if target_patient is not None:
                        conn.execute(
                            """UPDATE shift_bed_assignments
                               SET assigned_nurse_id = ?, status = 'accepted'
                               WHERE allocation_id = ? AND patient_id = ?""",
                            (
                                incoming_nurse_id,
                                target_patient["allocation_id"],
                                assignment["patient_id"],
                            ),
                        )
                    else:
                        occupied = conn.execute(
                            """SELECT patient_id FROM shift_bed_assignments
                               WHERE allocation_id = ? AND bed_number = ?
                                 AND patient_id IS NOT NULL""",
                            (target_allocation_id, assignment["bed_number"]),
                        ).fetchone()
                        if occupied is not None:
                            raise ValueError(
                                f"Bed {assignment['bed_number']} is occupied on the "
                                f"{incoming_shift} shift. Update the destination board "
                                "before accepting this patient."
                            )

                        conn.execute(
                            """INSERT INTO shift_bed_assignments (
                                   allocation_id, ward_id, bed_number, patient_id,
                                   patient_initials, admission_number, admitting_doctor,
                                   assigned_nurse_id, shift_type, date, status
                               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'accepted')""",
                            (
                                target_allocation_id,
                                ward_id,
                                assignment["bed_number"],
                                assignment["patient_id"],
                                assignment["patient_initials"],
                                assignment["admission_number"],
                                assignment["admitting_doctor"],
                                incoming_nurse_id,
                                incoming_shift,
                                date,
                            ),
                        )
                    conn.execute(
                        """DELETE FROM shift_bed_assignments
                           WHERE allocation_id = ? AND patient_id = ?
                             AND assigned_nurse_id = ?""",
                        (allocation_id, patient_id, outgoing_nurse_id),
                    )
                    conn.execute(
                        """INSERT INTO handoff_bed_acceptances (
                               handoff_session_id, allocation_id, patient_id,
                               bed_number, outgoing_nurse_id, incoming_nurse_id,
                               transferred_loop_ids_json, accepted_at
                           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                        (
                            handoff_session_id,
                            allocation_id,
                            patient_id,
                            assignment["bed_number"],
                            outgoing_nurse_id,
                            incoming_nurse_id,
                            json.dumps(
                                sorted(
                                    set(
                                        transferred_loop_ids_by_patient[
                                            patient_id
                                        ]
                                    )
                                )
                            ),
                            datetime.now(timezone.utc).isoformat(),
                        ),
                    )
            return len(requested_beds)

    def authorizes_handoff_event(
        self,
        *,
        handoff_session_id: str,
        patient_id: str,
        author_id: str,
        event_type: str,
        loop_id: Optional[str] = None,
        new_owner_id: Optional[str] = None,
        bed_number: Optional[str] = None,
        transferred_loop_ids: Optional[List[str]] = None,
    ) -> bool:
        with self._get_connection() as conn:
            row = conn.execute(
                """SELECT outgoing_nurse_id, incoming_nurse_id, bed_number,
                          transferred_loop_ids_json
                   FROM handoff_bed_acceptances
                   WHERE handoff_session_id = ? AND patient_id = ?""",
                (handoff_session_id, patient_id),
            ).fetchone()
        if row is None or author_id != row["outgoing_nurse_id"]:
            return False
        if event_type == "HandoffBedAccepted":
            if not isinstance(transferred_loop_ids, list) or not all(
                isinstance(loop_id, str) for loop_id in transferred_loop_ids
            ):
                return False
            return bool(
                bed_number == row["bed_number"]
                and sorted(set(transferred_loop_ids or []))
                == json.loads(row["transferred_loop_ids_json"])
            )
        return (
            event_type == "LoopOwnerChanged"
            and new_owner_id == row["incoming_nurse_id"]
            and loop_id in json.loads(row["transferred_loop_ids_json"])
        )

    def handoff_has_no_unaccepted_patients(
        self,
        handoff_session_id: str,
        outgoing_nurse_id: str,
        ward_id: str,
        assignment_date: str,
        total_beds_handed_over: int,
        total_loops_transferred: int,
    ) -> bool:
        with self._get_connection() as conn:
            acceptances = conn.execute(
                """SELECT allocation_id, transferred_loop_ids_json
                   FROM handoff_bed_acceptances
                   WHERE handoff_session_id = ? AND outgoing_nurse_id = ?
                   """,
                (handoff_session_id, outgoing_nurse_id),
            ).fetchall()
            if not acceptances or len(acceptances) != total_beds_handed_over:
                return False
            transferred_loop_count = sum(
                len(json.loads(row["transferred_loop_ids_json"]))
                for row in acceptances
            )
            if transferred_loop_count != total_loops_transferred:
                return False
            source = conn.execute(
                """SELECT shift_type FROM shift_allocations
                   WHERE allocation_id = ? AND ward_id = ? AND date = ?""",
                (acceptances[0]["allocation_id"], ward_id, assignment_date),
            ).fetchone()
            if source is None:
                return False
            remaining = conn.execute(
                """SELECT 1 FROM shift_bed_assignments
                   WHERE ward_id = ? AND date = ? AND shift_type = ?
                     AND assigned_nurse_id = ? AND patient_id IS NOT NULL
                   LIMIT 1""",
                (ward_id, assignment_date, source["shift_type"], outgoing_nurse_id),
            ).fetchone()
        return remaining is None

    def has_handoff_audit_access(
        self, staff_id: str, ward_id: str, assignment_date: str
    ) -> bool:
        with self._get_connection() as conn:
            row = conn.execute(
                """SELECT 1 FROM handoff_bed_acceptances h
                   JOIN shift_allocations a ON a.allocation_id = h.allocation_id
                   WHERE h.outgoing_nurse_id = ? AND a.ward_id = ? AND a.date = ?
                   LIMIT 1""",
                (staff_id, ward_id, assignment_date),
            ).fetchone()
        return row is not None

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
