import os
import json
from datetime import timedelta
from pathlib import Path
from typing import Any, Optional

from google.cloud import storage
from google.oauth2 import service_account
from livekit import api


class LiveKitEgressService:
    def __init__(self, client_factory: Any = api.LiveKitAPI):
        self.client_factory = client_factory

    def _configuration(self) -> dict[str, str]:
        storage_mode = os.getenv("LIVEKIT_EGRESS_STORAGE", "gcs").strip().lower()
        values = {
            "url": (
                os.getenv("LIVEKIT_INTERNAL_URL")
                or os.getenv("LIVEKIT_URL", "")
            ).strip(),
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
            "storage_mode": storage_mode,
            "local_recording_dir": os.getenv(
                "LIVEKIT_LOCAL_RECORDING_DIR", "/recordings"
            ).strip(),
        }
        required_keys = {"url", "api_key", "api_secret", "webhook_url"}
        if storage_mode == "gcs":
            required_keys.add("bucket")
        missing = [key for key in required_keys if not values[key]]
        if storage_mode not in {"gcs", "local"}:
            raise RuntimeError(
                "LIVEKIT_EGRESS_STORAGE must be either 'local' or 'gcs'."
            )
        if storage_mode == "gcs" and not values["credentials_path"] and not values["credentials_json"]:
            missing.append(
                "GOOGLE_APPLICATION_CREDENTIALS or LIVEKIT_EGRESS_GCP_CREDENTIALS"
            )
        if storage_mode == "local" and not values["local_recording_dir"]:
            missing.append("LIVEKIT_LOCAL_RECORDING_DIR")
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
        filepath = f"oravi/rituals/{ritual_id}/{room_name}.mp4"
        storage_config = None
        if config["storage_mode"] == "gcs":
            storage_config = api.StorageConfig(
                gcp=api.GCPUpload(
                    credentials=self._credentials_json(config),
                    bucket=config["bucket"],
                )
            )
        else:
            filepath = str(
                Path(config["local_recording_dir"])
                / "oravi"
                / "rituals"
                / ritual_id
                / f"{room_name}.mp4"
            )
        output = api.FileOutput(
            filepath=filepath,
        )
        request_kwargs = {
            "room_name": room_name,
            "template": api.TemplateSource(audio_only=True),
            "outputs": [api.Output(file=output)],
            # LiveKit signs Egress lifecycle webhooks with the API key.  The
            # backend verifies the signature with the configured API key and
            # secret, so omitting this value causes LiveKit to record the file
            # but silently skip the webhook notification.
            "webhooks": [
                api.WebhookConfig(
                    url=webhook_url,
                    signing_key=config["api_key"],
                )
            ],
        }
        if storage_config is not None:
            request_kwargs["storage"] = storage_config
        request = api.StartEgressRequest(
            **request_kwargs,
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
        if config["storage_mode"] == "local":
            # Egress reports the completed file path, including its actual
            # extension. Audio-only Egress currently writes OGG even when the
            # requested filename ends in .mp4. Preserve that reported path
            # instead of reconstructing a possibly different filename.
            reported_path = Path(location)
            recordings_root = Path(config["local_recording_dir"]).resolve()
            normalized_location = location.replace("\\", "/")
            if normalized_location.startswith("/recordings/"):
                reported_path = recordings_root / normalized_location.removeprefix("/recordings/")
            if not reported_path.is_absolute():
                reported_path = recordings_root / reported_path
            reported_path = reported_path.resolve()
            if recordings_root not in reported_path.parents:
                raise RuntimeError("LiveKit returned a recording path outside the local recording directory.")
            if not reported_path.is_file():
                raise RuntimeError(f"The local recording is not available: {reported_path}")
            return str(reported_path)
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

    def recording_path(self, *, ritual_id: str, room_name: str) -> str:
        config = self._configuration()
        if config["storage_mode"] != "local":
            raise RuntimeError("Local recording paths are only available in local storage mode.")
        path = (
            Path(config["local_recording_dir"])
            / "oravi"
            / "rituals"
            / ritual_id
            / f"{room_name}.mp4"
        )
        if not path.is_file():
            raise RuntimeError(f"The local recording is not available: {path}")
        return str(path)
