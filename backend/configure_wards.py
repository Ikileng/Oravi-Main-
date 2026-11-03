"""Interactive, operator-only setup for a hospital's ward catalog."""

import re

from .models import HospitalWardModel
from .ward_store import WardStore


def main() -> None:
    store = WardStore()
    try:
        while True:
            name = input("Ward name (blank to finish): ").strip()
            if not name:
                break
            department = input("Department/service: ").strip()
            description = input("Description (optional): ").strip()
            raw_beds = input("Bed numbers, comma separated (leave blank if not configured): ").strip()
            bed_numbers = list(dict.fromkeys(
                item.strip() for item in raw_beds.split(",") if item.strip()
            ))
            ward_id = "ward-" + re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
            store.create_ward(HospitalWardModel(
                ward_id=ward_id,
                name=name,
                bed_count=len(bed_numbers),
                bed_numbers=bed_numbers,
                department=department,
                description=description,
            ))
            print(f"Added {name} ({ward_id}) with {len(bed_numbers)} configured beds.")
    finally:
        store.close()


if __name__ == "__main__":
    main()
