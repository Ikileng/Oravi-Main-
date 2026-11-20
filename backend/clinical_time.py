"""Use the hospital calendar for assignment checks, regardless of wire timezone."""

import os
from datetime import datetime
from zoneinfo import ZoneInfo


def hospital_timezone() -> ZoneInfo:
    return ZoneInfo(os.getenv('ORAVI_TIMEZONE') or os.getenv('TZ') or 'Africa/Nairobi')


def clinical_date(timestamp: str | None = None) -> str:
    zone = hospital_timezone()
    if timestamp is None:
        return datetime.now(zone).date().isoformat()
    instant = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
    # Legacy clients sent naive local timestamps; preserve their local meaning.
    if instant.tzinfo is None:
        instant = instant.replace(tzinfo=zone)
    return instant.astimezone(zone).date().isoformat()
