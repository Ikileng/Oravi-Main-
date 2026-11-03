import unittest
import os
import json
import tempfile
from backend.ward_store import WardStore
from backend.models import HospitalWardModel, ShiftAllocationModel

class TestWardStore(unittest.TestCase):
    def setUp(self):
        self.temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".db")
        self.temp_file.close()
        self.db_path = self.temp_file.name
        self.store = WardStore(db_path=self.db_path)
        self.store.create_ward(HospitalWardModel(
            ward_id="ward-jacaranda",
            name="Jacaranda Ward",
            bed_count=12,
            bed_numbers=[str(number) for number in range(25, 37)],
            department="Pediatrics",
            description="Test ward",
        ))
        self.store.create_ward(HospitalWardModel(
            ward_id="ward-edna",
            name="Edna Ward",
            bed_count=10,
            bed_numbers=[str(number) for number in range(1, 11)],
            department="Surgery",
            description="Test ward",
        ))
        self.store.create_ward(HospitalWardModel(
            ward_id="WARD-4B",
            name="Ward 4B",
            bed_count=5,
            bed_numbers=[f"Bed {number}" for number in range(1, 6)],
            department="Mixed",
            description="Test ward",
        ))

    def tearDown(self):
        try:
            if os.path.exists(self.db_path):
                os.remove(self.db_path)
        except OSError:
            pass

    def test_ward_catalog_contains_only_explicitly_configured_wards(self):
        wards = self.store.get_all_wards()
        self.assertEqual(len(wards), 3)
        
        ward_map = {w.ward_id: w for w in wards}
        self.assertIn("ward-jacaranda", ward_map)
        self.assertIn("ward-edna", ward_map)
        jac = ward_map["ward-jacaranda"]
        self.assertIn("25", jac.bed_numbers)
        self.assertEqual(jac.department, "Pediatrics")

    def test_ward_catalog_is_empty_without_demo_seed_opt_in(self):
        path = os.path.join(os.path.dirname(self.db_path), "unseeded.db")
        store = WardStore(db_path=path)
        try:
            self.assertEqual(store.get_all_wards(), [])
        finally:
            if os.path.exists(path):
                os.remove(path)

    def test_publish_and_retrieve_active_shift(self):
        allocation = ShiftAllocationModel(
            allocation_id="alloc-jac-day-001",
            ward_id="ward-jacaranda",
            shift_type="day",
            date="2026-10-30",
            published_by="NUR-402",
            published_at="2026-10-30T07:00:00Z",
            bed_assignments=[
                {
                    "bed_number": "25",
                    "patient_id": "test-patient-1",
                    "patient_initials": "J.M.H.",
                    "admission_number": "ADM-2026-8812",
                    "admitting_doctor": "DR. MBIATA",
                    "assigned_nurse_id": "NUR-403",
                    "status": "pending"
                },
                {
                    "bed_number": "26",
                    "patient_id": "test-patient-2",
                    "patient_initials": "N.G.H.",
                    "admission_number": "ADM-2026-8813",
                    "admitting_doctor": "DR. KAGENI",
                    "assigned_nurse_id": "NUR-403",
                    "status": "pending"
                }
            ],
            support_roster={
                "ward_manager": "CAPRICE A",
                "pca_day": "FAITH / MAUREEN"
            }
        )
        self.assertTrue(self.store.publish_shift_allocation(allocation))

        active = self.store.get_nurse_active_shift(nurse_id="NUR-403", date="2026-10-30", shift_type="day")
        self.assertIsNotNone(active)
        self.assertEqual(active["ward_id"], "ward-jacaranda")
        self.assertEqual(len(active["beds"]), 2)
        self.assertEqual(active["beds"][0]["bed_number"], "25")
        self.assertEqual(active["beds"][0]["status"], "pending")

    def test_cross_ward_conflict_detection_prevents_double_booking(self):
        # 1. Nurse NUR-403 is assigned to Jacaranda on 2026-10-30 Day Shift
        allocation = ShiftAllocationModel(
            allocation_id="alloc-jac-day-001",
            ward_id="ward-jacaranda",
            shift_type="day",
            date="2026-10-30",
            published_by="NUR-402",
            published_at="2026-10-30T07:00:00Z",
            bed_assignments=[
                {
                    "bed_number": "25",
                    "patient_id": "test-patient-3",
                    "assigned_nurse_id": "NUR-403",
                    "status": "pending"
                }
            ],
            support_roster={}
        )
        self.store.publish_shift_allocation(allocation)

        # 2. Check conflict from Edna Ward for the SAME nurse on the SAME date & shift
        conflict = self.store.check_nurse_shift_conflict(
            nurse_id="NUR-403",
            date="2026-10-30",
            shift_type="day",
            target_ward_id="ward-edna"
        )
        self.assertTrue(conflict.has_conflict)
        self.assertEqual(conflict.conflict_ward_id, "ward-jacaranda")
        self.assertIn("already active on Day Shift in Jacaranda Ward", conflict.message)

        # 3. Check conflict within the SAME ward (Jacaranda) -> Should NOT conflict
        same_ward_check = self.store.check_nurse_shift_conflict(
            nurse_id="NUR-403",
            date="2026-10-30",
            shift_type="day",
            target_ward_id="ward-jacaranda"
        )
        self.assertFalse(same_ward_check.has_conflict)

        # 4. Check different shift (Night Shift) -> Should NOT conflict
        night_check = self.store.check_nurse_shift_conflict(
            nurse_id="NUR-403",
            date="2026-10-30",
            shift_type="night",
            target_ward_id="ward-edna"
        )
        self.assertFalse(night_check.has_conflict)

    def test_accept_shift_beds_updates_status_to_accepted(self):
        allocation = ShiftAllocationModel(
            allocation_id="alloc-jac-day-002",
            ward_id="ward-jacaranda",
            shift_type="day",
            date="2026-10-30",
            published_by="NUR-402",
            published_at="2026-10-30T07:00:00Z",
            bed_assignments=[
                {"bed_number": "25", "patient_id": "test-patient-4", "patient_initials": "A.B", "assigned_nurse_id": "NUR-403", "status": "pending"},
                {"bed_number": "26", "patient_id": "test-patient-5", "patient_initials": "C.D", "assigned_nurse_id": "NUR-403", "status": "pending"}
            ],
            support_roster={}
        )
        self.store.publish_shift_allocation(allocation)

        updated_count = self.store.accept_shift_beds(
            allocation_id="alloc-jac-day-002",
            nurse_id="NUR-403",
            beds=["25", "26"]
        )
        self.assertEqual(updated_count, 2)

        active = self.store.get_nurse_active_shift(nurse_id="NUR-403", date="2026-10-30", shift_type="day")
        self.assertEqual(active["beds"][0]["status"], "accepted")
        self.assertEqual(active["beds"][1]["status"], "accepted")

    def test_handoff_acceptance_transfers_board_ownership_to_authenticated_nurse(self):
        allocation = ShiftAllocationModel(
            allocation_id="alloc-handoff-day",
            ward_id="ward-jacaranda",
            shift_type="day",
            date="2026-10-30",
            published_by="NUR-402",
            published_at="2026-10-30T07:00:00Z",
            bed_assignments=[
                {"bed_number": "25", "patient_id": "test-patient-6", "patient_initials": "A.B", "assigned_nurse_id": "NUR-403", "status": "pending"},
                {"bed_number": "26", "patient_id": "test-patient-7", "patient_initials": "C.D", "assigned_nurse_id": "NUR-404", "status": "pending"},
            ],
            support_roster={},
        )
        self.store.publish_shift_allocation(allocation)

        updated_count = self.store.transfer_handoff_beds(
            allocation_id="alloc-handoff-day",
            outgoing_nurse_id="NUR-403",
            incoming_nurse_id="NUR-404",
            beds=["25"],
        )

        self.assertEqual(updated_count, 1)
        active = self.store.get_nurse_active_shift(
            nurse_id="NUR-404", date="2026-10-30", shift_type="day"
        )
        self.assertEqual(
            {bed["bed_number"] for bed in active["beds"]}, {"25", "26"}
        )
        transferred_bed = next(
            bed for bed in active["beds"] if bed["bed_number"] == "25"
        )
        self.assertEqual(transferred_bed["status"], "accepted")

    def test_handoff_rejects_beds_not_owned_by_outgoing_or_incoming_nurse(self):
        allocation = ShiftAllocationModel(
            allocation_id="alloc-handoff-owner-check",
            ward_id="ward-jacaranda",
            shift_type="day",
            date="2026-10-30",
            published_by="NUR-402",
            published_at="2026-10-30T07:00:00Z",
            bed_assignments=[
                {"bed_number": "25", "patient_id": "test-patient-8", "patient_initials": "A.B", "assigned_nurse_id": "NUR-403", "status": "pending"},
                {"bed_number": "26", "patient_id": "test-patient-9", "patient_initials": "C.D", "assigned_nurse_id": "NUR-405", "status": "pending"},
                {"bed_number": "27", "patient_id": "test-patient-10", "patient_initials": "E.F", "assigned_nurse_id": "NUR-404", "status": "pending"},
            ],
            support_roster={},
        )
        self.store.publish_shift_allocation(allocation)

        with self.assertRaisesRegex(ValueError, "not owned"):
            self.store.transfer_handoff_beds(
                allocation_id="alloc-handoff-owner-check",
                outgoing_nurse_id="NUR-403",
                incoming_nurse_id="NUR-404",
                beds=["26"],
            )

if __name__ == "__main__":
    unittest.main()
