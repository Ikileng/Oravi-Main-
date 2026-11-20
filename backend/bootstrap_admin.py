"""One-time interactive setup for the first Oravi Dev Admin."""

from getpass import getpass
import os

from .staff_store import StaffStore


def main() -> None:
    database_path = os.environ.get("ORAVI_DATABASE_PATH")
    store = StaffStore(db_path=database_path) if database_path else StaffStore()
    try:
        staff_id = input("Dev Admin staff ID: ").strip()
        name = input("Dev Admin display name: ").strip()
        pin = getpass("Choose a 6-8 digit Dev Admin PIN: ").strip()
        confirmation = getpass("Confirm PIN: ").strip()
        if not staff_id or not name:
            raise ValueError("Staff ID and display name are required.")
        if pin != confirmation:
            raise ValueError("PIN confirmation did not match.")
        profile = store.create_first_admin(staff_id, name, pin)
        print(f"Created the one-time Dev Admin account {profile.staff_id}.")
    except ValueError as error:
        raise SystemExit(str(error)) from error
    finally:
        store.close()


if __name__ == "__main__":
    main()
