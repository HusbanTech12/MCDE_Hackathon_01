"""Stage 6: data-quality checks. Results go to quality.dq_results.

    python quality/run_checks.py

Each run appends one batch. A failed check is a result, not a crashed run.
"""

from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import psycopg2
from psycopg2 import sql

CHECK_DIR = Path(__file__).resolve().parent
BUSINESS_CHECKS = CHECK_DIR / "sql" / "business_checks.sql"
DEFAULT_DATABASE_URL = "postgresql://postgres:hackathon@localhost:5432/indus_weave"

CREATE_RESULTS = """
CREATE SCHEMA IF NOT EXISTS quality;

CREATE TABLE IF NOT EXISTS quality.dq_results (
    check_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_at timestamptz NOT NULL,
    check_group text NOT NULL,
    object_name text NOT NULL,
    check_name text NOT NULL,
    expected_value text NOT NULL,
    actual_value text NOT NULL,
    failed_rows integer NOT NULL,
    status text NOT NULL CHECK (status IN ('PASS', 'FAIL'))
);

CREATE INDEX IF NOT EXISTS dq_results_run_idx
    ON quality.dq_results (run_at, check_group);
"""

KEY_SQL = """
SELECT
    namespace.nspname AS schema_name,
    relation.relname AS table_name,
    constraint_row.conname AS constraint_name,
    constraint_row.contype AS constraint_type,
    array_agg(attribute.attname ORDER BY key.ordinality) AS columns
FROM pg_constraint AS constraint_row
JOIN pg_class AS relation ON relation.oid = constraint_row.conrelid
JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
JOIN LATERAL unnest(constraint_row.conkey) WITH ORDINALITY AS key(attnum, ordinality) ON true
JOIN pg_attribute AS attribute
    ON attribute.attrelid = relation.oid
   AND attribute.attnum = key.attnum
WHERE namespace.nspname IN ('raw', 'staging', 'warehouse')
  AND constraint_row.contype IN ('p', 'u')
GROUP BY namespace.nspname, relation.relname, constraint_row.conname, constraint_row.contype
ORDER BY schema_name, table_name, constraint_name
"""

FOREIGN_KEY_SQL = """
SELECT
    child_namespace.nspname AS child_schema,
    child.relname AS child_table,
    parent_namespace.nspname AS parent_schema,
    parent.relname AS parent_table,
    constraint_row.conname AS constraint_name,
    array_agg(child_attribute.attname ORDER BY key.ordinality) AS child_columns,
    array_agg(parent_attribute.attname ORDER BY key.ordinality) AS parent_columns
FROM pg_constraint AS constraint_row
JOIN pg_class AS child ON child.oid = constraint_row.conrelid
JOIN pg_namespace AS child_namespace ON child_namespace.oid = child.relnamespace
JOIN pg_class AS parent ON parent.oid = constraint_row.confrelid
JOIN pg_namespace AS parent_namespace ON parent_namespace.oid = parent.relnamespace
JOIN LATERAL unnest(constraint_row.conkey, constraint_row.confkey)
    WITH ORDINALITY AS key(child_attnum, parent_attnum, ordinality) ON true
JOIN pg_attribute AS child_attribute
    ON child_attribute.attrelid = child.oid
   AND child_attribute.attnum = key.child_attnum
JOIN pg_attribute AS parent_attribute
    ON parent_attribute.attrelid = parent.oid
   AND parent_attribute.attnum = key.parent_attnum
WHERE child_namespace.nspname IN ('staging', 'warehouse')
  AND constraint_row.contype = 'f'
GROUP BY
    child_namespace.nspname,
    child.relname,
    parent_namespace.nspname,
    parent.relname,
    constraint_row.conname
ORDER BY child_schema, child_table, constraint_name
"""

LOAD_AUDIT_SQL = """
SELECT table_name, file_rows, table_rows, status
FROM (
    SELECT DISTINCT ON (table_name)
        table_name, file_rows, table_rows, status
    FROM raw.load_audit
    ORDER BY table_name, loaded_at DESC
) AS latest
ORDER BY table_name
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the Stage 6 data-quality checks.")
    parser.add_argument(
        "--database-url",
        default=os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL),
    )
    return parser.parse_args()


def result(group, object_name, check_name, expected, actual, failed_rows):
    failed = int(failed_rows)
    return {
        "check_group": group,
        "object_name": object_name,
        "check_name": check_name,
        "expected_value": str(expected),
        "actual_value": str(actual),
        "failed_rows": failed,
        "status": "PASS" if failed == 0 else "FAIL",
    }


def table_sql(schema_name, table_name):
    return sql.SQL("{}.{}").format(sql.Identifier(schema_name), sql.Identifier(table_name))


def column_list(columns):
    return sql.SQL(", ").join(sql.Identifier(column) for column in columns)


def key_checks(cursor):
    cursor.execute(KEY_SQL)
    checks = []
    for schema_name, table_name, constraint_name, constraint_type, columns in cursor.fetchall():
        null_test = sql.SQL(" OR ").join(
            sql.SQL("{} IS NULL").format(sql.Identifier(column)) for column in columns
        )
        # PostgreSQL unique constraints allow several nulls. Derived roster
        # weeks have no source hash, so only a repeated non-null key is a duplicate.
        present = sql.SQL(" AND ").join(
            sql.SQL("{} IS NOT NULL").format(sql.Identifier(column)) for column in columns
        )
        cursor.execute(
            sql.SQL(
                """
                SELECT
                    count(*) FILTER (WHERE {null_test})::bigint AS null_rows,
                    COALESCE((
                        SELECT sum(copies - 1)
                        FROM (
                            SELECT count(*) AS copies
                            FROM {table}
                            WHERE {present}
                            GROUP BY {columns}
                            HAVING count(*) > 1
                        ) AS grouped
                    ), 0)::bigint AS duplicate_rows
                FROM {table}
                """
            ).format(
                columns=column_list(columns),
                null_test=null_test,
                present=present,
                table=table_sql(schema_name, table_name),
            )
        )
        null_rows, duplicate_rows = cursor.fetchone()
        object_name = f"{schema_name}.{table_name}"
        checks.append(
            result(
                "uniqueness",
                object_name,
                f"unique {constraint_name}",
                "0 duplicate keys",
                f"{duplicate_rows} duplicate keys",
                duplicate_rows,
            )
        )
        if constraint_type == "p" or columns == ["_row_hash"]:
            checks.append(
                result(
                    "not_null",
                    object_name,
                    f"not null {constraint_name}",
                    "0 null keys",
                    f"{null_rows} null keys",
                    null_rows,
                )
            )
    return checks


def foreign_key_checks(cursor):
    cursor.execute(FOREIGN_KEY_SQL)
    foreign_keys = cursor.fetchall()
    checks = []
    for child_schema, child_table, parent_schema, parent_table, constraint_name, child_columns, parent_columns in foreign_keys:
        join_condition = sql.SQL(" AND ").join(
            sql.SQL("parent.{parent_column} = child.{child_column}").format(
                parent_column=sql.Identifier(parent_column),
                child_column=sql.Identifier(child_column),
            )
            for child_column, parent_column in zip(child_columns, parent_columns)
        )
        present = sql.SQL(" AND ").join(
            sql.SQL("child.{} IS NOT NULL").format(sql.Identifier(column)) for column in child_columns
        )
        cursor.execute(
            sql.SQL(
                """
                SELECT count(*)::bigint
                FROM {child} AS child
                LEFT JOIN {parent} AS parent ON {join_condition}
                WHERE {present}
                  AND parent.{parent_column} IS NULL
                """
            ).format(
                child=table_sql(child_schema, child_table),
                parent=table_sql(parent_schema, parent_table),
                join_condition=join_condition,
                present=present,
                parent_column=sql.Identifier(parent_columns[0]),
            )
        )
        orphans = cursor.fetchone()[0]
        checks.append(
            result(
                "referential_integrity",
                f"{child_schema}.{child_table}",
                f"{constraint_name} -> {parent_schema}.{parent_table}",
                "0 orphan rows",
                f"{orphans} orphan rows",
                orphans,
            )
        )
    return checks


def load_audit_checks(cursor):
    cursor.execute(LOAD_AUDIT_SQL)
    audits = cursor.fetchall()
    checks = []
    for table_name, file_rows, table_rows, status in audits:
        cursor.execute(
            sql.SQL("SELECT count(*)::bigint FROM {}").format(sql.Identifier("raw", table_name))
        )
        raw_rows = cursor.fetchone()[0]
        failed = 0 if status == "MATCH" and file_rows == table_rows == raw_rows else abs(file_rows - raw_rows) or 1
        checks.append(
            result(
                "reconciliation",
                f"raw.{table_name}",
                "file rows = raw table rows",
                str(file_rows),
                str(raw_rows),
                failed,
            )
        )
    return checks


def business_checks(cursor):
    cursor.execute(BUSINESS_CHECKS.read_text(encoding="utf-8"))
    checks = []
    for group, object_name, check_name, expected, actual, failed_rows in cursor.fetchall():
        checks.append(result(group, object_name, check_name, expected, actual, failed_rows))
    return checks


def save_results(cursor, run_at, checks):
    cursor.executemany(
        """
        INSERT INTO quality.dq_results (
            run_at, check_group, object_name, check_name,
            expected_value, actual_value, failed_rows, status
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """,
        [
            (
                run_at,
                check["check_group"],
                check["object_name"],
                check["check_name"],
                check["expected_value"],
                check["actual_value"],
                check["failed_rows"],
                check["status"],
            )
            for check in checks
        ],
    )


def print_report(checks):
    groups = {}
    failures = []
    for check in checks:
        groups.setdefault(check["check_group"], {"PASS": 0, "FAIL": 0})
        groups[check["check_group"]][check["status"]] += 1
        if check["status"] == "FAIL":
            failures.append(check)

    print(f"{'group':<24} {'pass':>6} {'fail':>6}")
    for group in sorted(groups):
        print(f"{group:<24} {groups[group]['PASS']:>6} {groups[group]['FAIL']:>6}")
    print(f"{'total':<24} {sum(item['PASS'] for item in groups.values()):>6} {len(failures):>6}")

    if failures:
        print("\nFailed checks")
        for check in failures:
            print(
                f"  {check['object_name']}: {check['check_name']} "
                f"(expected {check['expected_value']}, actual {check['actual_value']})"
            )


def main() -> int:
    args = parse_args()
    run_at = datetime.now(timezone.utc)
    try:
        connection = psycopg2.connect(args.database_url, connect_timeout=10)
    except psycopg2.OperationalError as exc:
        print("Could not connect to PostgreSQL.", file=sys.stderr)
        print(exc, file=sys.stderr)
        return 1

    try:
        with connection:
            with connection.cursor() as cursor:
                cursor.execute(CREATE_RESULTS)
                checks = []
                checks.extend(key_checks(cursor))
                checks.extend(foreign_key_checks(cursor))
                checks.extend(load_audit_checks(cursor))
                checks.extend(business_checks(cursor))
                save_results(cursor, run_at, checks)
    except Exception:
        connection.close()
        raise
    connection.close()
    print_report(checks)
    print(f"\n{len(checks)} checks written to quality.dq_results at {run_at.isoformat()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
