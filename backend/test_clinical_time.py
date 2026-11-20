import os
import unittest
from unittest.mock import patch

from backend.clinical_time import clinical_date


class TestClinicalDate(unittest.TestCase):
    @patch.dict(os.environ, {'ORAVI_TIMEZONE': 'Africa/Nairobi'})
    def test_equivalent_wire_timestamps_use_hospital_date(self):
        for timestamp in ['2026-11-18T21:30:00Z', '2026-11-18T21:30:00+00:00',
                          '2026-11-19T00:30:00+03:00', '2026-11-19T00:30:00']:
            self.assertEqual(clinical_date(timestamp), '2026-11-19')
        self.assertEqual(clinical_date('2026-11-18T20:59:59Z'), '2026-11-18')

    @patch.dict(os.environ, {'ORAVI_TIMEZONE': 'America/New_York'})
    def test_configured_hospital_timezone_is_used(self):
        self.assertEqual(clinical_date('2026-11-19T01:30:00Z'), '2026-11-18')
