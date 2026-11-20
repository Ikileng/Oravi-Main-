# Local LiveKit development

This is a development-only stack for testing Oravi calls and server-side
recording with synthetic data. It keeps the FastAPI backend, LiveKit Server,
Redis and LiveKit Egress on the developer machine. Compose selects local Egress
storage and the local Whisper provider; the existing GCS/ElevenLabs path remains
available outside this local profile.

## Start the local media stack

From the repository root, copy `docker/local.env.example` to
`docker/local.env`, replace the example address with the laptop's IPv4 address
from `ipconfig`, and run:

```powershell
Copy-Item docker/local.env.example docker/local.env
docker compose --env-file docker/local.env -f docker-compose.local.yml up -d --build
docker compose --env-file docker/local.env -f docker-compose.local.yml ps
```

The local LiveKit endpoint is `ws://localhost:7880` from the laptop. A phone
must use the laptop's LAN address instead of `localhost`, for example
`ws://192.168.1.25:7880`. Windows Firewall must allow the development ports.

The backend is available at port `8000`. The `livekit-egress` container and the
backend share `var/livekit-recordings`. Local transcription uses Whisper Large
v3 through `faster-whisper`; the first build downloads the model when it is
first used. Speaker diarization and participant-track recording remain the next
quality step.

## Firebase credentials for call invitations

Phone Firebase configuration does not authorize the backend to send invitations.
In `docker/local.env`, set `ORAVI_FIREBASE_CREDENTIALS_FILE` to the absolute
Windows path of the existing Firebase Admin service-account JSON for the same
Firebase project as the phones. Quote paths containing spaces. For example:

```dotenv
ORAVI_FIREBASE_CREDENTIALS_FILE="D:/secure/oravi/firebase-service-account.json"
```

Compose mounts that file read-only at `/run/secrets/firebase-admin.json` and sets
`GOOGLE_APPLICATION_CREDENTIALS` to that Linux path. The key is not copied into
the image. Do not commit the file or paste its contents into chat.

After changing the path, recreate the backend from `D:\Oravi`:

```powershell
docker compose --env-file docker/local.env -f docker-compose.local.yml up -d --no-deps backend
curl.exe http://localhost:8000/health
```

`medical_issue_push_configured: true` now means credentials can be loaded, not
merely that an environment variable exists. Remote Firebase permissions, Internet
connectivity, and delivery to a phone still require a live call test.

## Hospital timezone

The backend uses `TZ=Africa/Nairobi` for date-based ward authorization. Its
image includes timezone data. After changing this setting, rebuild and recreate
the backend, then check `docker compose --env-file docker/local.env -f
docker-compose.local.yml exec backend date`. It should show East Africa Time;
UTC dates can disagree with phone assignment dates between midnight and 03:00.

Sync authorization and notification recipients convert event timestamps to the
hospital calendar before checking assignments. `ORAVI_TIMEZONE` overrides `TZ`;
the default is `Africa/Nairobi`. Changing the timestamp's UTC date by string
slicing is not equivalent to this conversion.

## Recover issues that stayed on one phone

Update the backend first, from `D:\Oravi`:

```powershell
docker compose --env-file docker/local.env -f docker-compose.local.yml up -d --build backend
```

Then update the app on each phone with the existing LAN API address and device ID:

```powershell
flutter devices
flutter run -d DEVICE_ID --dart-define=ORAVI_API_BASE_URL=http://LAPTOP_IPV4:8000
```

Do not uninstall the app or clear its storage: earlier issues may exist only in
the local database. The updated app retries historical assignment-date rejections
once, with normal server validation. Other rejected events remain flagged as
unshared. Sync the nurse's phone, the doctor's phone, and the nurse's phone again.
Both should show both clinicians' existing issues and replies for the same patient.
Verify a new reply in each direction. An upload error must remain visible while
incoming team updates continue to download.

## Stop the stack

```powershell
docker compose -f docker-compose.local.yml down
```

Use fictional patient data only. The development `devkey`/`secret` pair and
the local LiveKit configuration are intentionally unsuitable for production.

