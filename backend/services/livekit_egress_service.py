import os
import json
from datetime import timedelta
from typing import Any, Optional

from google.cloud import storage
from google.oauth2 import service_account
from livekit import api


class LiveKitEgressService:
    def __init__(self, client_factory: Any = api.LiveKitAPI):
        self.client_factory = client_factory

    def _configuration(self) -> dict[str, str]:
        values = {
            "url": os.getenv("LIVEKIT_URL", "").strip(),
            "api_key": os.getenv("LIVEKIT_API_KEY", "").strip(),
            "api_secret": os.getenv("LIVEKIT_API_SECRET", "").strip(),
            "bucket": os.getenv("LIVEKIT_EGRESS_GCS_BUCKET", "").strip(),
            "credentials_path": os.getenv(
                "GOOGLE_APPLICATION_CREDENTIALS", ""
            ).strip(),
            "credentials_json": os.getenv(
                "LIVEKIT_EGRESS_GCP_CREDENTIALS", ""
            ).strip(),
            "webhook_url": os.getenv("ORAVI_PUBLIC_URL", "").strip(),
        }
        missing = [
            key
            for key, value in values.items()
            if key not in {"credentials_path", "credentials_json"} and not value
        ]
        if not values["credentials_path"] and not values["credentials_json"]:
            missing.append(
                "GOOGLE_APPLICATION_CREDENTIALS or LIVEKIT_EGRESS_GCP_CREDENTIALS"
            )
        if missing:
            raise RuntimeError(
                "LiveKit recording is not configured. Missing: "
                + ", ".join(missing)
            )
        return values

    @staticmethod
    def _credentials_json(config: dict[str, str]) -> str:
        if config["credentials_json"]:
            return config["credentials_json"]
        try:
            with open(config["credentials_path"], encoding="utf-8") as file:
                json.load(file)
                file.seek(0)
                return file.read()
        except (OSError, json.JSONDecodeError) as error:
            raise RuntimeError(
                "The configured Google service-account credential file is invalid."
            ) from error

    async def start_room_recording(
        self, *, room_name: str, ritual_id: str
    ) -> dict[str, Optional[str]]:
        config = self._configuration()
        webhook_url = f"{config['webhook_url'].rstrip('/')}/api/v1/rituals/webhooks/livekit"
        storage_config = api.GCPUpload(
            credentials=self._credentials_json(config),
            bucket=config["bucket"],
        )
        output = api.FileOutput(
            filepath=f"oravi/rituals/{ritual_id}/{room_name}.mp4",
        )
        request = api.StartEgressRequest(
            room_name=room_name,
            template=api.TemplateSource(audio_only=True),
            outputs=[api.Output(file=output)],
            storage=api.StorageConfig(gcp=storage_config),
            webhooks=[api.WebhookConfig(url=webhook_url)],
        )
        async with self.client_factory(
            url=config["url"],
            api_key=config["api_key"],
            api_secret=config["api_secret"],
        ) as client:
            egress = await client.egress.start_egress(request)
        return {
            "egress_id": egress.egress_id,
            "room_name": room_name,
        }

    async def stop_room_recording(self, egress_id: str) -> None:
        config = self._configuration()
        async with self.client_factory(
            url=config["url"],
            api_key=config["api_key"],
            api_secret=config["api_secret"],
        ) as client:
            await client.egress.stop_egress(
                api.StopEgressRequest(egress_id=egress_id)
            )

    def recording_url(self, *, ritual_id: str, room_name: str, location: str) -> str:
        if location.startswith(("https://", "http://")):
            return location
        config = self._configuration()
        key = f"oravi/rituals/{ritual_id}/{room_name}.mp4"
        credentials_info = json.loads(self._credentials_json(config))
        credentials = service_account.Credentials.from_service_account_info(
            credentials_info
        )
        client = storage.Client(
            project=credentials_info.get("project_id"),
            credentials=credentials,
        )
        return client.bucket(config["bucket"]).blob(key).generate_signed_url(
            version="v4",
            expiration=timedelta(minutes=15),
            method="GET",
        )
