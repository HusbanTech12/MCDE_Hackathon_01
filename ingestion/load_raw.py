"""Stage 1: load every HCM export into the raw schema.

Values stay text. Nested JSON is stored as text and is not flattened.
Each table receives _source_file, _loaded_at and _row_hash.
A second run inserts nothing for rows that were already loaded.

    python ingestion/load_raw.py
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import psycopg2
from psycopg2 import sql

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATABASE_URL = "postgresql://postgres:hackathon@localhost:5432/indus_weave"
IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


@dataclass(frozen=True)
class SourceFile:
    table: str
    filename: str
    kind: str
    json_array_key: str | None = None
    alternate_filenames: tuple[str, ...] = ()


# Same 12 files as the case-study pack. JSON array keys are explicit so
# leave approvals and shift fields are not exploded into more tables.
SOURCES = (
    SourceFile("employees", "employees.csv", "csv", alternate_filenames=("employees (1).csv",)),
    SourceFile("employment_history", "employment_history.csv", "csv"),
    SourceFile("departments", "departments.csv", "csv"),
    SourceFile("shifts", "shifts.json", "json", json_array_key="shifts"),
    SourceFile("shift_roster", "shift_roster.csv", "csv"),
    SourceFile("device_mapping", "device_mapping.csv", "csv"),
    SourceFile("biometric_punches", "biometric_punches.csv", "csv"),
    SourceFile("holidays", "holidays.csv", "csv"),
    SourceFile("leave_requests", "leave_requests.json", "json"),
    SourceFile("overtime_requests", "overtime_requests.csv", "csv"),
    SourceFile("payroll_lines", "payroll_lines.csv", "csv"),
    SourceFile("applications", "applications.csv", "csv"),
)


def require_identifier(name: str) -> str:
    if not IDENTIFIER.match(name):
        raise ValueError(f"Cannot use {name!r} as a column name")
    return name


def json_to_text(value: object) -> str:
    """Keep nested objects and arrays as JSON text. Do not flatten them."""
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, (dict, list, bool, int, float)):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    raise TypeError(f"Unsupported JSON value: {type(value).__name__}")


def content_hash(values: list[str]) -> str:
    # Hash only the delivered values. Metadata is excluded so a second
    # load of the same row produces the same hash and is skipped.
    payload = json.dumps(values, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def resolve_path(data_dir: Path, source: SourceFile) -> Path:
    for name in (source.filename, *source.alternate_filenames):
        path = data_dir / name
        if path.is_file():
            return path
    tried = ", ".join((source.filename, *source.alternate_filenames))
    raise FileNotFoundError(f"Missing {source.table} file. Looked for: {tried}")


def read_csv(path: Path) -> tuple[list[str], list[list[str]]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.reader(handle)
        try:
            header = [require_identifier(column) for column in next(reader)]
        except StopIteration as exc:
            raise ValueError(f"{path.name} has no header row") from exc
        rows: list[list[str]] = []
        for line_number, row in enumerate(reader, start=2):
            if len(row) != len(header):
                raise ValueError(
                    f"{path.name} line {line_number} has {len(row)} values; "
                    f"header has {len(header)}"
                )
            rows.append(row)
    return header, rows


def read_json(path: Path, array_key: str | None) -> tuple[list[str], list[list[str]]]:
    with path.open(encoding="utf-8") as handle:
        payload = json.load(handle)
    if array_key is not None:
        if not isinstance(payload, dict) or array_key not in payload:
            raise ValueError(f"{path.name} has no {array_key!r} array")
        payload = payload[array_key]
    if not isinstance(payload, list):
        raise ValueError(f"{path.name} is not a JSON array")

    columns: list[str] = []
    seen: set[str] = set()
    records: list[dict] = []
    for index, record in enumerate(payload):
        if not isinstance(record, dict):
            raise ValueError(f"{path.name} item {index} is not a JSON object")
        records.append(record)
        for key in record:
            if key not in seen:
                seen.add(require_identifier(key))
                columns.append(key)

    rows = [[json_to_text(record.get(column)) for column in columns] for record in records]
    return columns, rows


def ensure_schema(cursor) -> None:
    cursor.execute("CREATE SCHEMA IF NOT EXISTS raw")
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS raw.load_audit (
            audit_id BIGSERIAL PRIMARY KEY,
            source_file TEXT NOT NULL,
            table_name TEXT NOT NULL,
            file_rows INTEGER NOT NULL,
            table_rows INTEGER NOT NULL,
            inserted_rows INTEGER NOT NULL,
            status TEXT NOT NULL,
            loaded_at TIMESTAMPTZ NOT NULL
        )
        """
    )


def ensure_table(cursor, table: str, columns: list[str]) -> None:
    definitions = [sql.SQL("{} TEXT NOT NULL").format(sql.Identifier(column)) for column in columns]
    definitions.extend(
        [
            sql.SQL("_source_file TEXT NOT NULL"),
            sql.SQL("_loaded_at TIMESTAMPTZ NOT NULL"),
            sql.SQL("_row_hash TEXT NOT NULL"),
        ]
    )
    cursor.execute(
        sql.SQL(
            "CREATE TABLE IF NOT EXISTS {} ({}, CONSTRAINT {} UNIQUE (_row_hash))"
        ).format(
            sql.Identifier("raw", table),
            sql.SQL(", ").join(definitions),
            sql.Identifier(f"uq_{table}_row_hash"),
        )
    )


def table_count(cursor, table: str) -> int:
    cursor.execute(sql.SQL("SELECT COUNT(*) FROM {}").format(sql.Identifier("raw", table)))
    return int(cursor.fetchone()[0])


def copy_new_rows(
    cursor,
    table: str,
    columns: list[str],
    rows: list[list[str]],
    source_name: str,
    loaded_at: datetime,
) -> None:
    all_columns = [*columns, "_source_file", "_loaded_at", "_row_hash"]
    loaded_at_text = loaded_at.isoformat()
    staged = [
        [*values, source_name, loaded_at_text, content_hash(values)]
        for values in rows
    ]

    cursor.execute("DROP TABLE IF EXISTS pg_temp.stage1_batch")
    cursor.execute(
        sql.SQL("CREATE TEMP TABLE stage1_batch ({})").format(
            sql.SQL(", ").join(
                sql.SQL("{} TEXT").format(sql.Identifier(column)) for column in all_columns
            )
        )
    )
    buffer = io.StringIO()
    csv.writer(buffer, lineterminator="\n").writerows(staged)
    buffer.seek(0)
    # CSV COPY treats an empty field as NULL. Force those fields to stay
    # empty text so a blank separation date is stored as delivered.
    column_list = sql.SQL(", ").join(sql.Identifier(column) for column in all_columns)
    copy_sql = sql.SQL(
        "COPY stage1_batch ({columns}) FROM STDIN WITH (FORMAT csv, FORCE_NOT_NULL ({columns}))"
    ).format(columns=column_list)
    cursor.copy_expert(copy_sql.as_string(cursor.connection), buffer)

    # The batch is all text. Cast the load time on the way into the raw table.
    # Identical delivered rows collapse to one hash, and a hash already stored
    # is skipped, so running the loader twice does not duplicate rows.
    select_list = []
    for column in all_columns:
        if column == "_loaded_at":
            select_list.append(sql.SQL("_loaded_at::timestamptz"))
        else:
            select_list.append(sql.Identifier(column))
    cursor.execute(
        sql.SQL(
            """
            INSERT INTO {target} ({columns})
            SELECT DISTINCT ON (_row_hash) {select_list}
            FROM stage1_batch
            ORDER BY _row_hash
            ON CONFLICT (_row_hash) DO NOTHING
            """
        ).format(
            target=sql.Identifier("raw", table),
            columns=sql.SQL(", ").join(sql.Identifier(column) for column in all_columns),
            select_list=sql.SQL(", ").join(select_list),
        )
    )
    cursor.execute("DROP TABLE pg_temp.stage1_batch")


def load_source(cursor, source: SourceFile, data_dir: Path, loaded_at: datetime) -> dict:
    path = resolve_path(data_dir, source)
    if path.name != source.filename:
        print(f"Reading {path.name} into raw.{source.table}", flush=True)
    if source.kind == "csv":
        columns, rows = read_csv(path)
    elif source.kind == "json":
        columns, rows = read_json(path, source.json_array_key)
    else:
        raise ValueError(f"Unknown kind {source.kind}")

    print(f"Loading raw.{source.table} ({len(rows)} rows)", flush=True)
    ensure_table(cursor, source.table, columns)
    before = table_count(cursor, source.table)
    copy_new_rows(cursor, source.table, columns, rows, path.name, loaded_at)
    after = table_count(cursor, source.table)
    status = "MATCH" if after == len(rows) else "MISMATCH"
    cursor.execute(
        """
        INSERT INTO raw.load_audit (
            source_file, table_name, file_rows, table_rows, inserted_rows, status, loaded_at
        ) VALUES (%s, %s, %s, %s, %s, %s, %s)
        """,
        (path.name, source.table, len(rows), after, after - before, status, loaded_at),
    )
    return {
        "source_file": path.name,
        "table": source.table,
        "file_rows": len(rows),
        "table_rows": after,
        "inserted_rows": after - before,
        "status": status,
    }


def print_summary(results: list[dict]) -> None:
    print()
    print(f"{'source file':<28} {'table':<22} {'file':>8} {'table':>8} {'inserted':>8}  status")
    for result in results:
        print(
            f"{result['source_file']:<28} "
            f"raw.{result['table']:<18} "
            f"{result['file_rows']:>8} "
            f"{result['table_rows']:>8} "
            f"{result['inserted_rows']:>8}  "
            f"{result['status']}"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Load raw HCM exports into PostgreSQL.")
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=Path(os.environ.get("DATA_DIR", ROOT)),
        help="Folder that contains the 12 export files",
    )
    parser.add_argument(
        "--database-url",
        default=os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL),
        help="PostgreSQL URL. Defaults to the local indus_weave database.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    loaded_at = datetime.now(timezone.utc)
    try:
        connection = psycopg2.connect(args.database_url, connect_timeout=10)
    except psycopg2.OperationalError as exc:
        print("Could not connect to PostgreSQL.", file=sys.stderr)
        print(exc, file=sys.stderr)
        return 1

    connection.set_client_encoding("UTF8")
    results: list[dict] = []
    try:
        with connection.cursor() as cursor:
            ensure_schema(cursor)
            for source in SOURCES:
                results.append(load_source(cursor, source, args.data_dir, loaded_at))
        if any(result["status"] != "MATCH" for result in results):
            connection.rollback()
            print_summary(results)
            print("\nRow counts did not match. This load was rolled back.", file=sys.stderr)
            return 1
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()

    print_summary(results)
    print("\nRaw load committed. File row counts match table row counts.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
