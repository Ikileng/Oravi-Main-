import os
import unittest
from unittest.mock import patch

from backend.services.fcm_service import FcmService


class FcmCredentialsTests(unittest.TestCase):
    def test_missing_file_does_not_report_configured(self):
        with patch.dict(os.environ, {
            'FIREBASE_SERVICE_ACCOUNT_JSON': '',
            'GOOGLE_APPLICATION_CREDENTIALS': '/nonexistent/oravi-firebase.json',
        }):
            self.assertFalse(FcmService.credentials_ready())

    def test_malformed_inline_credentials_do_not_report_configured(self):
        with patch.dict(os.environ, {'FIREBASE_SERVICE_ACCOUNT_JSON': '{invalid'}):
            self.assertFalse(FcmService.credentials_ready())

    def test_adc_is_loaded_without_sending_or_refreshing(self):
        with patch.dict(os.environ, {'FIREBASE_SERVICE_ACCOUNT_JSON': ''}), \
                patch('google.auth.default', return_value=(object(), 'test-project')) as load:
            self.assertTrue(FcmService.credentials_ready())
            load.assert_called_once_with(scopes=['https://www.googleapis.com/auth/firebase.messaging'])
