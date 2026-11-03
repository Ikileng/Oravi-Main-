import unittest
import backend.main as main
from backend.staff_store import StaffStore
from backend.main import get_ward_staff, verify_staff_pin, create_staff_member
from backend.models import StaffLoginRequest, CreateStaffRequest, StaffProfile

class TestM7StaffAuth(unittest.TestCase):
    def setUp(self):
        # Use isolated in-memory DB for pure unit testing
        self.staff_store = StaffStore(db_path=":memory:")
        fixtures = [
            ("NUR-401", "Mary Wanjiku, RN", "ward_nurse", "1234"),
            ("NUR-402", "Grace Achieng, RN", "charge_nurse", "5678"),
            ("NUR-403", "Faith Njeri, RN", "ward_nurse", "1111"),
            ("DOC-401", "Dr. James Kamau", "doctor_on_call", "9090"),
            ("NUR-404", "Sarah Otieno, RN", "ward_nurse", "2222"),
            ("NUR-405", "Jane Muthoni, RN", "ward_nurse", "3333"),
        ]
        for staff_id, name, role, pin in fixtures:
            self.staff_store.create_staff(
                staff_id=staff_id,
                name=name,
                role=role,
                ward_id="",
                pin=pin,
            )
        self.original_staff_store = main.staff_store
        main.staff_store = self.staff_store

    def tearDown(self):
        main.staff_store = self.original_staff_store
        self.staff_store.close()

    def test_fresh_store_has_no_staff_or_demo_credentials(self):
        store = StaffStore(db_path=":memory:")
        try:
            self.assertEqual(store.get_active_clinical_staff(), [])
            success, profile, _ = store.verify_pin("NUR-401", "1234")
            self.assertFalse(success)
            self.assertIsNone(profile)
        finally:
            store.close()

    def test_explicitly_provisioned_staff_have_no_permanent_ward(self):
        staff = self.staff_store.get_active_clinical_staff()
        self.assertEqual(len(staff), 6)
        staff_ids = {s.staff_id for s in staff}
        self.assertIn("NUR-401", staff_ids)
        self.assertIn("NUR-402", staff_ids)
        self.assertIn("DOC-401", staff_ids)

        # Check roles
        mary = next(s for s in staff if s.staff_id == "NUR-401")
        self.assertEqual(mary.name, "Mary Wanjiku, RN")
        self.assertEqual(mary.role, "ward_nurse")
        self.assertEqual(mary.initials, "MW")
        self.assertEqual(mary.ward_id, "")

        grace = next(s for s in staff if s.staff_id == "NUR-402")
        self.assertEqual(grace.role, "charge_nurse")

        kamau = next(s for s in staff if s.staff_id == "DOC-401")
        self.assertEqual(kamau.role, "doctor_on_call")

    def test_verify_pin_success(self):
        # Mary Wanjiku PIN is 1234
        success, profile, err = self.staff_store.verify_pin("NUR-401", "1234")
        self.assertTrue(success)
        self.assertIsNotNone(profile)
        self.assertIsNone(err)
        self.assertEqual(profile.staff_id, "NUR-401")
        self.assertEqual(profile.name, "Mary Wanjiku, RN")

    def test_verify_pin_failure_and_countdown(self):
        # Wrong PIN
        success, profile, err = self.staff_store.verify_pin("NUR-401", "9999")
        self.assertFalse(success)
        self.assertIsNone(profile)
        self.assertIn("Invalid PIN", err)
        self.assertIn("4 attempt(s) remaining", err)

    def test_pin_rate_limiting_lockout(self):
        # 5 wrong attempts
        for _ in range(4):
            self.staff_store.verify_pin("NUR-401", "0000")
        success, profile, err = self.staff_store.verify_pin("NUR-401", "0000")
        self.assertFalse(success)
        self.assertIn("Account locked", err)

        # 6th attempt is blocked even if correct PIN is entered
        success, profile, err = self.staff_store.verify_pin("NUR-401", "1234")
        self.assertFalse(success)
        self.assertIn("Too many failed attempts", err)

    def test_admin_create_staff(self):
        new_nurse = self.staff_store.create_staff(
            staff_id="NUR-499",
            name="Beatrice Mutua, RN",
            role="ward_nurse",
            ward_id="WARD-4B",
            pin="7788",
            avatar_color="#059669",
        )
        self.assertEqual(new_nurse.staff_id, "NUR-499")
        self.assertEqual(new_nurse.name, "Beatrice Mutua, RN")
        self.assertEqual(new_nurse.initials, "BM")

        # Verify login with new PIN
        success, profile, _ = self.staff_store.verify_pin("NUR-499", "7788")
        self.assertTrue(success)
        self.assertEqual(profile.name, "Beatrice Mutua, RN")

    def test_main_get_ward_staff_endpoint(self):
        profile = StaffProfile(
            staff_id="NUR-402",
            name="Grace Achieng, RN",
            role="charge_nurse",
            ward_id="",
            avatar_color="#2563EB",
            initials="GA",
        )
        self.staff_store.set_ward_preference("NUR-402", "WARD-4B")
        response = get_ward_staff(ward_id="WARD-4B", profile=profile)
        self.assertEqual(response.ward_id, "WARD-4B")
        self.assertEqual(len(response.staff), 6)

    def test_main_verify_pin_endpoint_success(self):
        req = StaffLoginRequest(staff_id="NUR-401", pin="1234")
        res = verify_staff_pin(req)
        self.assertTrue(res.success)
        self.assertIsNotNone(res.staff)
        self.assertEqual(res.staff.name, "Mary Wanjiku, RN")
        self.assertTrue(res.token.startswith("oravi_sess_"))

    def test_main_verify_pin_endpoint_failure(self):
        req = StaffLoginRequest(staff_id="NUR-401", pin="9999")
        res = verify_staff_pin(req)
        self.assertFalse(res.success)
        self.assertIn("Invalid PIN", res.error)

    def test_main_admin_create_staff_endpoint(self):
        req = CreateStaffRequest(
            staff_id="DOC-499",
            name="Dr. Lucy Wangari",
            role="doctor_on_call",
            ward_id="",
            pin="4455",
            avatar_color="#7C3AED",
        )
        profile = create_staff_member(req)
        self.assertEqual(profile.staff_id, "DOC-499")
        self.assertEqual(profile.name, "Dr. Lucy Wangari")

        # Verify she can log in
        login_res = verify_staff_pin(StaffLoginRequest(staff_id="DOC-499", pin="4455"))
        self.assertTrue(login_res.success)

if __name__ == "__main__":
    unittest.main()
