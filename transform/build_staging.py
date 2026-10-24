"""Stage 2: clean raw HCM tables into the staging schema.

    python transform/build_staging.py

The load is repeatable. Each run rebuilds staging from raw.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = Path(__file__).resolve().parent / "sql"
DEFAULT_DATABASE_URL = "postgresql://postgres:hackathon@localhost:5432/indus_weave"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the staging schema from raw tables.")
    parser.add_argument(
        "--database-url",
        default=os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    scripts = sorted(SQL_DIR.glob("*.sql"))
    if not scripts:
        print(f"No SQL files in {SQL_DIR}", file=sys.stderr)
        return 1

    try:
        connection = psycopg2.connect(args.database_url, connect_timeout=10)
    except psycopg2.OperationalError as exc:
        print("Could not connect to PostgreSQL.", file=sys.stderr)
        print(exc, file=sys.stderr)
        return 1

    connection.set_client_encoding("UTF8")
    try:
        with connection.cursor() as cursor:
            for script in scripts:
                print(f"Running {script.name}", flush=True)
                cursor.execute(script.read_text(encoding="utf-8"))
            cursor.execute(
                """
                SELECT table_name, raw_rows, staging_rows, rejected_rows, derived_rows, status
                FROM staging.reconciliation
                ORDER BY table_name
                """
            )
            reconciliation = cursor.fetchall()
            cursor.execute(
                """
                SELECT device_id, median_minutes_from_start, reference_minutes,
                       offset_minutes, detection_note
                FROM staging.device_clock_offset
                ORDER BY device_id
                """
            )
            clocks = cursor.fetchall()
            cursor.execute(
                """
                SELECT reason LIKE 'unmapped%' AS unmapped, count(*)
                FROM staging.rejected_punches
                GROUP BY 1
                ORDER BY 1 DESC
                """
            )
            rejected = cursor.fetchall()
        if any(row[5] == "MISMATCH" for row in reconciliation):
            connection.rollback()
            _print_report(reconciliation, clocks, rejected)
            print("\nStaging build failed reconciliation and was rolled back.", file=sys.stderr)
            return 1
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()

    _print_report(reconciliation, clocks, rejected)
    print("\nStaging build committed.")
    return 0


def _print_report(reconciliation, clocks, rejected) -> None:
    print()
    print(f"{'table':<24} {'raw':>8} {'staging':>8} {'rejected':>8} {'derived':>8}  status")
    for table_name, raw_rows, staging_rows, rejected_rows, derived_rows, status in reconciliation:
        raw_text = "" if raw_rows is None else str(raw_rows)
        print(
            f"{table_name:<24} {raw_text:>8} {staging_rows:>8} "
            f"{rejected_rows:>8} {derived_rows:>8}  {status}"
        )
    print("\nClock check")
    for device_id, median_minutes, reference_minutes, offset_minutes, note in clocks:
        print(
            f"{device_id}: median {median_minutes} min from shift start, "
            f"reference {reference_minutes}, offset {offset_minutes} min"
        )
        print(f"  {note}")
    print("\nRejected punches")
    for unmapped, count in rejected:
        label = "unmapped device user" if unmapped else "within 2 minutes"
        print(f"  {label}: {count}")


if __name__ == "__main__":
    sys.exit(main())
