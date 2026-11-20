import json
import os
from typing import Dict


class FcmService:
    @staticmethod
    def credentials_ready() -> bool:
        """Validate local credential loading, without sending a notification.

        This does not prove remote FCM permissions or delivery.
        """
        try:
            from firebase_admin import credentials
            import google.auth
            inline = os.getenv('FIREBASE_SERVICE_ACCOUNT_JSON')
            if inline:
                credentials.Certificate(json.loads(inline)).get_credential()
            else:
                google.auth.default(scopes=['https://www.googleapis.com/auth/firebase.messaging'])
            return True
        except Exception:
            # Never include private key material or paths in the health response.
            return False

    def send_staff_message(self, token: str, *, transfer: bool = False) -> bool:
        import firebase_admin
        from firebase_admin import credentials, messaging

        try:
            app = firebase_admin.get_app()
        except ValueError:
            service_account_json = os.getenv('FIREBASE_SERVICE_ACCOUNT_JSON')
            options = {}
            if os.getenv('FIREBASE_PROJECT_ID'):
                options['projectId'] = os.environ['FIREBASE_PROJECT_ID']
            if service_account_json:
                app = firebase_admin.initialize_app(
                    credentials.Certificate(json.loads(service_account_json)), options=options)
            else:
                app = firebase_admin.initialize_app(options=options)
        message = messaging.Message(
            notification=messaging.Notification(
                title='Oravi ward transfer update' if transfer else 'New Oravi message',
                body='Open Transfers in Oravi to review your transfer or handoff.' if transfer else 'Open Messages & calls in Oravi to read it.'),
            data={'type': 'ward_transfer' if transfer else 'staff_message'},
            android=messaging.AndroidConfig(priority='high'), token=token)
        try:
            messaging.send(message, app=app)
        except messaging.UnregisteredError:
            return False
        return True

    def send_transfer_alert(self, token: str) -> bool:
        return self.send_staff_message(token, transfer=True)

    def send_medical_issue_alert(
        self, token: str, patient_id: str, loop_id: str
    ) -> bool:
        import firebase_admin
        from firebase_admin import credentials, messaging

        try:
            app = firebase_admin.get_app()
        except ValueError:
            service_account_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
            options: Dict[str, str] = {}
            project_id = os.getenv("FIREBASE_PROJECT_ID")
            if project_id:
                options["projectId"] = project_id
            if service_account_json:
                credential = credentials.Certificate(
                    json.loads(service_account_json)
                )
                app = firebase_admin.initialize_app(credential, options=options)
            else:
                app = firebase_admin.initialize_app(options=options)

        message = messaging.Message(
            notification=messaging.Notification(
                title="Medical issue update",
                body="A medical issue requires your attention. Open Oravi to review.",
            ),
            data={
                "type": "medical_issue",
                "patient_id": patient_id,
                "loop_id": loop_id,
            },
            token=token,
        )
        try:
            messaging.send(message, app=app)
        except messaging.UnregisteredError:
            return False
        return True

    def send_call_invitation(self, token: str, *, call_id: str) -> bool:
        import firebase_admin
        from firebase_admin import credentials, messaging

        try:
            app = firebase_admin.get_app()
        except ValueError:
            service_account_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
            options: Dict[str, str] = {}
            project_id = os.getenv("FIREBASE_PROJECT_ID")
            if project_id:
                options["projectId"] = project_id
            if service_account_json:
                credential = credentials.Certificate(json.loads(service_account_json))
                app = firebase_admin.initialize_app(credential, options=options)
            else:
                app = firebase_admin.initialize_app(options=options)

        message = messaging.Message(
            notification=messaging.Notification(
                title="Incoming Oravi call",
                body="Open Oravi to answer the call.",
            ),
            data={"type": "oravi_call", "call_id": call_id},
            android=messaging.AndroidConfig(priority="high"),
            token=token,
        )
        try:
            messaging.send(message, app=app)
        except messaging.UnregisteredError:
            return False
        return True

    def send_clinical_ritual_alert(
        self, token: str, *, ritual_id: str, ritual_type: str, title: str
    ) -> bool:
        import firebase_admin
        from firebase_admin import credentials, messaging

        try:
            app = firebase_admin.get_app()
        except ValueError:
            service_account_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
            options: Dict[str, str] = {}
            project_id = os.getenv("FIREBASE_PROJECT_ID")
            if project_id:
                options["projectId"] = project_id
            if service_account_json:
                app = firebase_admin.initialize_app(
                    credentials.Certificate(json.loads(service_account_json)),
                    options=options,
                )
            else:
                app = firebase_admin.initialize_app(options=options)

        message = messaging.Message(
            notification=messaging.Notification(
                title=f"Clinical {ritual_type} requested",
                body=title,
            ),
            data={
                "type": "clinical_ritual",
                "ritual_id": ritual_id,
                "ritual_type": ritual_type,
            },
            android=messaging.AndroidConfig(priority="high"),
            token=token,
        )
        try:
            messaging.send(message, app=app)
        except messaging.UnregisteredError:
            return False
        return True

    def send_clinical_ritual_review_alert(self, token: str, *, ritual_id: str, title: str) -> bool:
        import firebase_admin
        from firebase_admin import credentials, messaging
        try:
            app = firebase_admin.get_app()
        except ValueError:
            service_account_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
            options = {"projectId": os.environ["FIREBASE_PROJECT_ID"]} if os.getenv("FIREBASE_PROJECT_ID") else {}
            if service_account_json:
                app = firebase_admin.initialize_app(credentials.Certificate(json.loads(service_account_json)), options=options)
            else:
                app = firebase_admin.initialize_app(options=options)
        message = messaging.Message(
            notification=messaging.Notification(title="Clinical ritual summary ready", body=title),
            data={"type": "clinical_ritual_review", "ritual_id": ritual_id},
            android=messaging.AndroidConfig(priority="high"), token=token,
        )
        try:
            messaging.send(message, app=app)
        except messaging.UnregisteredError:
            return False
        return True
