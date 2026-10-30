import unittest
import os
import json
import tempfile
from backend.ward_store import WardStore
from backend.models import ShiftAllocationModel

class TestWardStore(unittest.TestCase):
    def setUp(self):
        self.temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".db")
        self.temp_file.close()
        self.db_path = self.temp_file.name
        self.store = WardStore(db_path=self.db_path)

    def tearDown(self):
        try:
            if os.path.exists(self.db_path):
                os.remove(self.db_path)
        except OSError:
            pass

    def test_ward_catalog_seeded_with_gertrude_wards(self):
        wards = self.store.get_all_wards()
        self.assertGreaterEqual(len(wards), 4)
        
        ward_map = {w.ward_id: w for w in wards}
        self.assertIn("ward-jacaranda", ward_map)
        self.assertIn("ward-edna", ward_map)
        self.assertIn("ward-kilimanjaro", ward_map)
        
        jac = ward_map["ward-jacaranda"]
        self.assertIn("25", jac.bed_numbers)
        self.assertIn("29", jac.bed_numbers)
        self.assertEqual(jac.department, "Pediatrics")

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
                    "patient_initials": "J.M.H.",
                    "admission_number": "ADM-2026-8812",
                    "admitting_doctor": "DR. MBIATA",
                    "assigned_nurse_id": "NUR-403",
                    "status": "pending"
                },
                {
                    "bed_number": "26",
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
                {"bed_number": "25", "assigned_nurse_id": "NUR-403", "status": "pending"},
                {"bed_number": "26", "assigned_nurse_id": "NUR-403", "status": "pending"}
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

if __name__ == "__main__":
    unittest.main()
