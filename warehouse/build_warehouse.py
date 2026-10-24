"""Stage 4: build the star schema and draw the ERD.

Run this after the staging build:

    python warehouse/build_warehouse.py
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import psycopg2

SQL_DIR = Path(__file__).resolve().parent / "ddl"
DEFAULT_DATABASE_URL = "postgresql://postgres:hackathon@localhost:5432/indus_weave"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the warehouse star schema.")
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
                SELECT table_name, source_rows, warehouse_rows, status
                FROM warehouse.reconciliation
                ORDER BY table_name
                """
            )
            reconciliation = cursor.fetchall()
            cursor.execute(
                """
                SELECT conrelid::regclass::text AS table_name, count(*) AS foreign_keys
                FROM pg_constraint
                WHERE contype = 'f'
                  AND connamespace = 'warehouse'::regnamespace
                GROUP BY conrelid
                ORDER BY 1
                """
            )
            foreign_keys = cursor.fetchall()
        if any(row[3] == "MISMATCH" for row in reconciliation):
            connection.rollback()
            _print_report(reconciliation, foreign_keys)
            print("\nWarehouse build failed reconciliation and was rolled back.", file=sys.stderr)
            return 1
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()

    _print_report(reconciliation, foreign_keys)
    from draw_erd import draw_erd

    erd_path = draw_erd(Path(__file__).resolve().parent / "erd.png")
    print(f"\nERD written to {erd_path}")
    print("Warehouse build committed.")
    return 0


def _print_report(reconciliation, foreign_keys) -> None:
    print()
    print(f"{'table':<28} {'source':>10} {'warehouse':>10}  status")
    for table_name, source_rows, warehouse_rows, status in reconciliation:
        print(f"{table_name:<28} {source_rows:>10} {warehouse_rows:>10}  {status}")
    print("\nForeign keys")
    for table_name, foreign_key_count in foreign_keys:
        print(f"  {table_name}: {foreign_key_count}")


if __name__ == "__main__":
    sys.exit(main())
