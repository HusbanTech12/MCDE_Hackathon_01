-- Employment history ignores the exported effective_to.
-- A row lasts until the day before that employee's next row.
-- Missing roster weeks copy the previous week's shift.

CREATE TABLE staging.device_mapping (
    device_id text NOT NULL,
    device_user_id text NOT NULL,
    emp_id text NOT NULL REFERENCES staging.employees (emp_id),
    enrolled_on date NOT NULL,
    raw_row_hash text NOT NULL UNIQUE,
    PRIMARY KEY (device_id, device_user_id)
);

INSERT INTO staging.device_mapping (device_id, device_user_id, emp_id, enrolled_on, raw_row_hash)
SELECT
    staging.normalize(device_id),
    staging.normalize(device_user_id),
    emp_id,
    staging.parse_date(enrolled_on),
    _row_hash
FROM raw.device_mapping;

CREATE TABLE staging.employment_history (
    history_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    emp_id text NOT NULL REFERENCES staging.employees (emp_id),
    effective_from date NOT NULL,
    effective_to date,
    effective_to_raw date,
    dept_id text NOT NULL REFERENCES staging.departments (dept_id),
    designation text NOT NULL,
    grade text NOT NULL,
    basic_salary numeric NOT NULL,
    change_reason text NOT NULL,
    is_effective boolean NOT NULL,
    raw_row_hash text NOT NULL UNIQUE
);

INSERT INTO staging.employment_history (
    emp_id, effective_from, effective_to, effective_to_raw, dept_id, designation,
    grade, basic_salary, change_reason, is_effective, raw_row_hash
)
WITH ordered AS (
    SELECT
        emp_id,
        staging.parse_date(effective_from) AS effective_from,
        staging.parse_date(effective_to) AS effective_to_raw,
        dept_id,
        staging.normalize(designation) AS designation,
        upper(staging.normalize(grade)) AS grade,
        basic_salary::numeric AS basic_salary,
        staging.normalize(change_reason) AS change_reason,
        _row_hash,
        lead(staging.parse_date(effective_from)) OVER (
            PARTITION BY emp_id
            ORDER BY
                staging.parse_date(effective_from),
                CASE staging.normalize(change_reason)
                    WHEN 'Hire' THEN 1
                    WHEN 'Transfer' THEN 2
                    WHEN 'Promotion' THEN 3
                    WHEN 'Salary Revision' THEN 4
                    ELSE 5
                END,
                _row_hash
        ) AS next_effective_from
    FROM raw.employment_history
)
SELECT
    emp_id,
    effective_from,
    CASE
        WHEN next_effective_from IS NULL THEN NULL
        ELSE next_effective_from - 1
    END,
    effective_to_raw,
    dept_id,
    designation,
    grade,
    basic_salary,
    change_reason,
    next_effective_from IS NULL OR next_effective_from - 1 >= effective_from,
    _row_hash
FROM ordered;

CREATE INDEX employment_history_emp_from_idx
    ON staging.employment_history (emp_id, effective_from);

CREATE TABLE staging.shift_roster (
    emp_id text NOT NULL REFERENCES staging.employees (emp_id),
    week_start date NOT NULL,
    shift_code text NOT NULL REFERENCES staging.shifts (shift_code),
    roster_source text NOT NULL CHECK (roster_source IN ('delivered', 'forward_fill')),
    raw_row_hash text UNIQUE,
    PRIMARY KEY (emp_id, week_start)
);

INSERT INTO staging.shift_roster (emp_id, week_start, shift_code, roster_source, raw_row_hash)
SELECT
    emp_id,
    staging.parse_date(week_start),
    upper(staging.normalize(shift_code)),
    'delivered',
    _row_hash
FROM raw.shift_roster;

INSERT INTO staging.shift_roster (emp_id, week_start, shift_code, roster_source)
WITH bounds AS (
    SELECT
        roster.emp_id,
        min(roster.week_start) AS first_week,
        least(
            DATE '2026-10-26',
            coalesce(
                employee.separation_date
                    - (EXTRACT(ISODOW FROM employee.separation_date)::integer - 1),
                DATE '2026-10-26'
            )
        ) AS last_week
    FROM staging.shift_roster AS roster
    JOIN staging.employees AS employee ON employee.emp_id = roster.emp_id
    GROUP BY roster.emp_id, employee.separation_date
),
missing AS (
    SELECT bounds.emp_id, calendar.week_start::date AS week_start
    FROM bounds
    JOIN generate_series(bounds.first_week, bounds.last_week, INTERVAL '7 days') AS calendar (week_start)
        ON calendar.week_start::date > bounds.first_week
    LEFT JOIN staging.shift_roster AS existing
        ON existing.emp_id = bounds.emp_id
       AND existing.week_start = calendar.week_start::date
    WHERE existing.emp_id IS NULL
)
SELECT missing.emp_id, missing.week_start, previous.shift_code, 'forward_fill'
FROM missing
JOIN LATERAL (
    SELECT shift_code
    FROM staging.shift_roster AS delivered
    WHERE delivered.emp_id = missing.emp_id
      AND delivered.roster_source = 'delivered'
      AND delivered.week_start < missing.week_start
    ORDER BY delivered.week_start DESC
    LIMIT 1
) AS previous ON TRUE;
