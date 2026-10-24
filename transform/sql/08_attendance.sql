-- One row per employee for every day they were employed from 1 April
-- through 30 September 2026. separation_date is their last worked day.
--
-- Night shift runs 22:00 to 06:00. A punch before 10:00 belongs to the
-- previous day when that day was a night shift: morning check-outs stay
-- with the shift that started the night before, and the next shift's
-- later punches stay on their own day. Check-in is the first punch on
-- that shift date and check-out is the last.
--
-- Status priority: Weekly Off, Holiday, On Leave, Present, Missing Punch, Absent.
-- Late and early minutes are stored only for Present working days.
-- Working-day overtime is time after shift end, rounded down to half hours.
-- Sunday or holiday work is all overtime, rounded down the same way.

DROP TABLE IF EXISTS staging.attendance_daily;

CREATE TABLE staging.attendance_daily (
    emp_id text NOT NULL REFERENCES staging.employees (emp_id),
    work_date date NOT NULL,
    plant_code text NOT NULL,
    dept_id text REFERENCES staging.departments (dept_id),
    shift_code text REFERENCES staging.shifts (shift_code),
    shift_start timestamp,
    shift_end timestamp,
    punch_count integer NOT NULL,
    check_in timestamp,
    check_out timestamp,
    worked_minutes integer,
    late_minutes integer NOT NULL,
    early_departure_minutes integer NOT NULL,
    overtime_hours numeric(6, 1) NOT NULL,
    status text NOT NULL CHECK (
        status IN ('Present', 'Absent', 'On Leave', 'Holiday', 'Weekly Off', 'Missing Punch')
    ),
    PRIMARY KEY (emp_id, work_date)
);

INSERT INTO staging.attendance_daily (
    emp_id, work_date, plant_code, dept_id, shift_code, shift_start, shift_end,
    punch_count, check_in, check_out, worked_minutes, late_minutes,
    early_departure_minutes, overtime_hours, status
)
WITH employment_days AS (
    SELECT
        employee.emp_id,
        employee.plant_code,
        calendar.work_date::date AS work_date
    FROM staging.employees AS employee
    JOIN generate_series(
        GREATEST(employee.hire_date, DATE '2026-04-01'),
        LEAST(coalesce(employee.separation_date, DATE '2026-09-30'), DATE '2026-09-30'),
        INTERVAL '1 day'
    ) AS calendar (work_date)
        ON GREATEST(employee.hire_date, DATE '2026-04-01')
         <= LEAST(coalesce(employee.separation_date, DATE '2026-09-30'), DATE '2026-09-30')
),
scheduled AS (
    SELECT
        employment_days.emp_id,
        employment_days.work_date,
        employment_days.plant_code,
        roster.shift_code,
        employment_days.work_date + shift.start_time AS shift_start,
        CASE
            WHEN shift.crosses_midnight THEN (employment_days.work_date + 1) + shift.end_time
            ELSE employment_days.work_date + shift.end_time
        END AS shift_end,
        make_interval(mins => shift.grace_minutes) AS grace
    FROM employment_days
    LEFT JOIN staging.shift_roster AS roster
        ON roster.emp_id = employment_days.emp_id
       AND roster.week_start = employment_days.work_date
            - (EXTRACT(ISODOW FROM employment_days.work_date)::integer - 1)
    LEFT JOIN staging.shifts AS shift
        ON shift.shift_code = roster.shift_code
),
assigned_punches AS (
    SELECT
        punch.emp_id,
        punch.punch_time,
        CASE
            WHEN previous_roster.shift_code = 'NIGHT'
             AND punch.punch_time::time < TIME '10:00'
            THEN punch.punch_time::date - 1
            ELSE punch.punch_time::date
        END AS work_date
    FROM staging.biometric_punches AS punch
    LEFT JOIN staging.shift_roster AS previous_roster
        ON previous_roster.emp_id = punch.emp_id
       AND previous_roster.week_start = (punch.punch_time::date - 1)
            - (EXTRACT(ISODOW FROM (punch.punch_time::date - 1))::integer - 1)
),
punch_span AS (
    SELECT
        emp_id,
        work_date,
        count(*)::integer AS punch_count,
        min(punch_time) AS check_in,
        CASE
            WHEN count(*) >= 2 THEN max(punch_time)
        END AS check_out
    FROM assigned_punches
    GROUP BY emp_id, work_date
),
classified AS (
    SELECT
        scheduled.emp_id,
        scheduled.work_date,
        scheduled.plant_code,
        history.dept_id,
        scheduled.shift_code,
        scheduled.shift_start,
        scheduled.shift_end,
        scheduled.grace,
        coalesce(punch_span.punch_count, 0) AS punch_count,
        punch_span.check_in,
        punch_span.check_out,
        EXTRACT(DOW FROM scheduled.work_date) = 0 AS is_sunday,
        EXISTS (
            SELECT 1
            FROM staging.holidays AS holiday
            WHERE holiday.holiday_date = scheduled.work_date
              AND (holiday.scope = 'ALL' OR holiday.scope = scheduled.plant_code)
        ) AS is_holiday,
        EXISTS (
            SELECT 1
            FROM staging.leave_days AS leave_day
            WHERE leave_day.emp_id = scheduled.emp_id
              AND leave_day.leave_date = scheduled.work_date
        ) AS is_on_leave
    FROM scheduled
    LEFT JOIN punch_span
        ON punch_span.emp_id = scheduled.emp_id
       AND punch_span.work_date = scheduled.work_date
    LEFT JOIN LATERAL (
        SELECT employment.dept_id
        FROM staging.employment_history AS employment
        WHERE employment.emp_id = scheduled.emp_id
          AND employment.is_effective
          AND scheduled.work_date >= employment.effective_from
          AND (
              employment.effective_to IS NULL
              OR scheduled.work_date <= employment.effective_to
          )
        ORDER BY employment.effective_from DESC
        LIMIT 1
    ) AS history ON TRUE
)
SELECT
    emp_id,
    work_date,
    plant_code,
    dept_id,
    shift_code,
    shift_start,
    shift_end,
    punch_count,
    check_in,
    check_out,
    CASE
        WHEN check_out IS NULL THEN NULL
        ELSE round(EXTRACT(EPOCH FROM (check_out - check_in)) / 60.0)::integer
    END AS worked_minutes,
    CASE
        WHEN status = 'Present'
         AND NOT is_sunday
         AND NOT is_holiday
         AND check_in > shift_start + grace
        THEN ceil(EXTRACT(EPOCH FROM (check_in - shift_start)) / 60.0)::integer
        ELSE 0
    END AS late_minutes,
    CASE
        WHEN status = 'Present'
         AND NOT is_sunday
         AND NOT is_holiday
         AND check_out < shift_end - grace
        THEN ceil(EXTRACT(EPOCH FROM (shift_end - check_out)) / 60.0)::integer
        ELSE 0
    END AS early_departure_minutes,
    CASE
        WHEN check_out IS NULL THEN 0
        WHEN is_sunday OR is_holiday THEN (
            floor(EXTRACT(EPOCH FROM (check_out - check_in)) / 60.0 / 30.0) * 0.5
        )::numeric(6, 1)
        WHEN shift_end IS NOT NULL THEN (
            floor(GREATEST(EXTRACT(EPOCH FROM (check_out - shift_end)), 0) / 60.0 / 30.0) * 0.5
        )::numeric(6, 1)
        ELSE 0
    END AS overtime_hours,
    status
FROM (
    SELECT
        classified.*,
        CASE
            WHEN is_sunday AND punch_count = 0 THEN 'Weekly Off'
            WHEN is_holiday AND punch_count = 0 THEN 'Holiday'
            WHEN is_on_leave THEN 'On Leave'
            WHEN punch_count >= 2 THEN 'Present'
            WHEN punch_count = 1 THEN 'Missing Punch'
            ELSE 'Absent'
        END AS status
    FROM classified
) AS with_status;

CREATE INDEX attendance_daily_date_status_idx
    ON staging.attendance_daily (work_date, status);

DELETE FROM staging.reconciliation WHERE table_name = 'attendance_daily';

INSERT INTO staging.reconciliation (table_name, raw_rows, staging_rows, rejected_rows, derived_rows, status)
SELECT 'attendance_daily', NULL, count(*), 0, 0, 'DERIVED'
FROM staging.attendance_daily;
