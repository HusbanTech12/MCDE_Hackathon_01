-- One leave request, one row per approval step, and one row per approved leave day.
-- A request counts only when Manager and HR both approved it and it was not cancelled.
-- Sundays and plant holidays inside the range are not leave days.
-- days_requested is kept as submitted and is not used to count days.

CREATE TABLE staging.leave_requests (
    request_id text PRIMARY KEY,
    emp_id text NOT NULL REFERENCES staging.employees (emp_id),
    plant text NOT NULL REFERENCES staging.plant (plant_name),
    plant_code text NOT NULL REFERENCES staging.plant (plant_code),
    leave_type text NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    days_requested integer NOT NULL,
    submitted_at timestamp NOT NULL,
    cancelled_at timestamp,
    is_approved boolean NOT NULL,
    raw_row_hash text NOT NULL UNIQUE
);

CREATE TABLE staging.leave_approvals (
    request_id text NOT NULL REFERENCES staging.leave_requests (request_id),
    step integer NOT NULL,
    approver_role text NOT NULL,
    approver_id text NOT NULL,
    action text NOT NULL,
    acted_at timestamp NOT NULL,
    PRIMARY KEY (request_id, step)
);

INSERT INTO staging.leave_requests (
    request_id, emp_id, plant, plant_code, leave_type, start_date, end_date,
    days_requested, submitted_at, cancelled_at, is_approved, raw_row_hash
)
WITH parsed AS (
    SELECT
        request_id,
        employee::jsonb ->> 'emp_id' AS emp_id,
        staging.canonical_plant(employee::jsonb ->> 'plant') AS plant,
        initcap(staging.normalize(leave::jsonb ->> 'type')) AS leave_type,
        staging.parse_date(leave::jsonb ->> 'from') AS start_date,
        staging.parse_date(leave::jsonb ->> 'to') AS end_date,
        (leave::jsonb ->> 'days_requested')::integer AS days_requested,
        staging.parse_timestamp(submitted_at) AS submitted_at,
        staging.parse_timestamp(cancelled_at) AS cancelled_at,
        approvals::jsonb AS approvals,
        _row_hash
    FROM raw.leave_requests
),
flags AS (
    SELECT
        parsed.*,
        EXISTS (
            SELECT 1
            FROM jsonb_array_elements(parsed.approvals) AS approval
            WHERE approval ->> 'approver_role' = 'Manager'
              AND approval ->> 'action' = 'Approved'
        ) AS manager_approved,
        EXISTS (
            SELECT 1
            FROM jsonb_array_elements(parsed.approvals) AS approval
            WHERE approval ->> 'approver_role' = 'HR'
              AND approval ->> 'action' = 'Approved'
        ) AS hr_approved
    FROM parsed
)
SELECT
    request_id,
    emp_id,
    plant,
    staging.plant_code(plant),
    leave_type,
    start_date,
    end_date,
    days_requested,
    submitted_at,
    cancelled_at,
    cancelled_at IS NULL AND manager_approved AND hr_approved,
    _row_hash
FROM flags;

INSERT INTO staging.leave_approvals (
    request_id, step, approver_role, approver_id, action, acted_at
)
SELECT
    request.request_id,
    (approval ->> 'step')::integer,
    staging.normalize(approval ->> 'approver_role'),
    staging.normalize(approval ->> 'approver_id'),
    staging.normalize(approval ->> 'action'),
    staging.parse_timestamp(approval ->> 'acted_at')
FROM raw.leave_requests AS request
CROSS JOIN LATERAL jsonb_array_elements(request.approvals::jsonb) AS approval;

CREATE TABLE staging.leave_days (
    request_id text NOT NULL REFERENCES staging.leave_requests (request_id),
    leave_date date NOT NULL,
    emp_id text NOT NULL REFERENCES staging.employees (emp_id),
    leave_type text NOT NULL,
    plant_code text NOT NULL,
    PRIMARY KEY (request_id, leave_date)
);

INSERT INTO staging.leave_days (request_id, leave_date, emp_id, leave_type, plant_code)
SELECT
    request.request_id,
    calendar.leave_date::date,
    request.emp_id,
    request.leave_type,
    request.plant_code
FROM staging.leave_requests AS request
CROSS JOIN LATERAL generate_series(request.start_date, request.end_date, INTERVAL '1 day') AS calendar (leave_date)
WHERE request.is_approved
  AND EXTRACT(DOW FROM calendar.leave_date) <> 0
  AND NOT EXISTS (
      SELECT 1
      FROM staging.holidays AS holiday
      WHERE holiday.holiday_date = calendar.leave_date::date
        AND (holiday.scope = 'ALL' OR holiday.scope = request.plant_code)
  );

CREATE INDEX leave_days_emp_date_idx
    ON staging.leave_days (emp_id, leave_date);
