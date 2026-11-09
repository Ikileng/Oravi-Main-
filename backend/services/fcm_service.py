import json
import os
from typing import Dict


class FcmService:
    def send_medical_issue_alert(
        self, fid: str, patient_id: str, loop_id: str
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
            fid=fid,
        )
        try:
            messaging.send(message, app=app)
        except messaging.UnregisteredError:
            return False
        return True
