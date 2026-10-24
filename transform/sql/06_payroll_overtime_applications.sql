-- Typed payroll, overtime and recruitment rows. Empty numeric fields stay null.

CREATE TABLE staging.overtime_requests (
    request_id text PRIMARY KEY,
    emp_id text NOT NULL REFERENCES staging.employees (emp_id),
    ot_date date NOT NULL,
    requested_hours numeric NOT NULL,
    approved_hours numeric,
    status text NOT NULL,
    approver_id text,
    requested_at timestamp NOT NULL,
    raw_row_hash text NOT NULL UNIQUE
);

INSERT INTO staging.overtime_requests (
    request_id, emp_id, ot_date, requested_hours, approved_hours, status,
    approver_id, requested_at, raw_row_hash
)
SELECT
    request_id,
    emp_id,
    staging.parse_date(ot_date),
    requested_hours::numeric,
    NULLIF(btrim(approved_hours), '')::numeric,
    initcap(staging.normalize(status)),
    NULLIF(staging.normalize(approver_id), ''),
    staging.parse_timestamp(requested_at),
    _row_hash
FROM raw.overtime_requests;

CREATE TABLE staging.payroll_lines (
    line_id text PRIMARY KEY,
    payroll_month date NOT NULL,
    emp_id text NOT NULL REFERENCES staging.employees (emp_id),
    component text NOT NULL,
    component_type text NOT NULL,
    units numeric,
    amount numeric NOT NULL,
    raw_row_hash text NOT NULL UNIQUE
);

INSERT INTO staging.payroll_lines (
    line_id, payroll_month, emp_id, component, component_type, units, amount, raw_row_hash
)
SELECT
    line_id,
    to_date(payroll_month || '-01', 'YYYY-MM-DD'),
    emp_id,
    upper(staging.normalize(component)),
    upper(staging.normalize(component_type)),
    NULLIF(btrim(units), '')::numeric,
    amount::numeric,
    _row_hash
FROM raw.payroll_lines;

CREATE INDEX payroll_lines_emp_month_idx
    ON staging.payroll_lines (emp_id, payroll_month);

CREATE TABLE staging.applications (
    application_id text NOT NULL,
    candidate_id text NOT NULL,
    job_req_id text NOT NULL,
    dept_id text NOT NULL REFERENCES staging.departments (dept_id),
    stage text NOT NULL,
    stage_date date NOT NULL,
    raw_row_hash text NOT NULL UNIQUE,
    PRIMARY KEY (application_id, stage)
);

INSERT INTO staging.applications (
    application_id, candidate_id, job_req_id, dept_id, stage, stage_date, raw_row_hash
)
SELECT
    application_id,
    candidate_id,
    job_req_id,
    dept_id,
    staging.normalize(stage),
    staging.parse_date(stage_date),
    _row_hash
FROM raw.applications;
