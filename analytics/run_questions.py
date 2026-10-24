"""Stage 5: run the ten business questions and write one CSV each.

    python analytics/run_questions.py
"""

from __future__ import annotations

import argparse
import csv
import os
import sys
from pathlib import Path

import psycopg2

QUESTION_DIR = Path(__file__).resolve().parent
RESULTS_DIR = QUESTION_DIR / "results"
DEFAULT_DATABASE_URL = "postgresql://postgres:hackathon@localhost:5432/indus_weave"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the Stage 5 questions.")
    parser.add_argument(
        "--database-url",
        default=os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    scripts = sorted(QUESTION_DIR.glob("q*.sql"))
    if len(scripts) != 10:
        print(f"Expected 10 question files, found {len(scripts)}.", file=sys.stderr)
        return 1

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    try:
        connection = psycopg2.connect(args.database_url, connect_timeout=10)
    except psycopg2.OperationalError as exc:
        print("Could not connect to PostgreSQL.", file=sys.stderr)
        print(exc, file=sys.stderr)
        return 1

    try:
        for script in scripts:
            sql = script.read_text(encoding="utf-8")
            with connection.cursor() as cursor:
                cursor.execute(sql)
                headers = [column.name for column in cursor.description]
                rows = cursor.fetchall()
            output = RESULTS_DIR / f"{script.stem}.csv"
            with output.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerow(headers)
                writer.writerows(rows)
            print(f"{script.stem:<32} {len(rows):>6} rows")
    finally:
        connection.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
