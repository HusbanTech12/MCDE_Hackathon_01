-- Star schema. Dimensions are rebuilt from staging on every run.
-- dim_employee is SCD Type 2: one row per employment-history version.
-- An open version ends on 9999-12-31 so facts can use
-- work_date BETWEEN valid_from AND valid_to.

DROP SCHEMA IF EXISTS warehouse CASCADE;
CREATE SCHEMA warehouse;

CREATE TABLE warehouse.dim_department (
    department_key bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dept_id text NOT NULL UNIQUE,
    dept_name text NOT NULL,
    plant_name text NOT NULL,
    plant_code text NOT NULL,
    cost_center text NOT NULL,
    previous_name text,
    renamed_on date
);

INSERT INTO warehouse.dim_department (
    dept_id, dept_name, plant_name, plant_code, cost_center, previous_name, renamed_on
)
SELECT dept_id, dept_name, plant, plant_code, cost_center, previous_name, renamed_on
FROM staging.departments
ORDER BY dept_id;

CREATE TABLE warehouse.dim_shift (
    shift_key bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    shift_code text NOT NULL UNIQUE,
    shift_name text NOT NULL,
    start_time time NOT NULL,
    end_time time NOT NULL,
    crosses_midnight boolean NOT NULL,
    grace_minutes integer NOT NULL,
    applies_to text NOT NULL
);

INSERT INTO warehouse.dim_shift (
    shift_code, shift_name, start_time, end_time, crosses_midnight, grace_minutes, applies_to
)
SELECT shift_code, shift_name, start_time, end_time, crosses_midnight, grace_minutes, applies_to
FROM staging.shifts
ORDER BY shift_code;

CREATE TABLE warehouse.dim_date (
    date_key date PRIMARY KEY,
    year integer NOT NULL,
    quarter integer NOT NULL,
    month integer NOT NULL,
    month_name text NOT NULL,
    month_start date NOT NULL,
    month_end date NOT NULL,
    day_of_month integer NOT NULL,
    day_name text NOT NULL,
    week_start date NOT NULL,
    is_sunday boolean NOT NULL
);

INSERT INTO warehouse.dim_date (
    date_key, year, quarter, month, month_name, month_start, month_end,
    day_of_month, day_name, week_start, is_sunday
)
WITH used_dates AS (
    SELECT work_date AS used_date FROM staging.attendance_daily
    UNION
    SELECT leave_date FROM staging.leave_days
    UNION
    SELECT ot_date FROM staging.overtime_requests
    UNION
    SELECT payroll_month FROM staging.payroll_lines
    UNION
    SELECT CASE
        WHEN employee.separation_date >= payroll.payroll_month
         AND employee.separation_date < (payroll.payroll_month + INTERVAL '1 month')::date
        THEN employee.separation_date
        ELSE (payroll.payroll_month + INTERVAL '1 month' - INTERVAL '1 day')::date
    END
    FROM staging.payroll_lines AS payroll
    JOIN staging.employees AS employee ON employee.emp_id = payroll.emp_id
),
bounds AS (
    SELECT min(used_date) AS start_date, max(used_date) AS end_date
    FROM used_dates
)
SELECT
    calendar.full_date::date,
    EXTRACT(YEAR FROM calendar.full_date)::integer,
    EXTRACT(QUARTER FROM calendar.full_date)::integer,
    EXTRACT(MONTH FROM calendar.full_date)::integer,
    (ARRAY[
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
    ])[EXTRACT(MONTH FROM calendar.full_date)::integer],
    date_trunc('month', calendar.full_date)::date,
    (date_trunc('month', calendar.full_date) + INTERVAL '1 month' - INTERVAL '1 day')::date,
    EXTRACT(DAY FROM calendar.full_date)::integer,
    (ARRAY[
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ])[EXTRACT(ISODOW FROM calendar.full_date)::integer],
    (calendar.full_date::date - (EXTRACT(ISODOW FROM calendar.full_date)::integer - 1)),
    EXTRACT(ISODOW FROM calendar.full_date) = 7
FROM bounds
CROSS JOIN generate_series(bounds.start_date, bounds.end_date, INTERVAL '1 day') AS calendar (full_date);

CREATE TABLE warehouse.dim_employee (
    employee_key bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    emp_id text NOT NULL,
    full_name text NOT NULL,
    gender text NOT NULL,
    date_of_birth date NOT NULL,
    email text NOT NULL,
    phone text NOT NULL,
    employment_type text NOT NULL,
    hire_date date NOT NULL,
    separation_date date,
    status text NOT NULL,
    annual_leave_entitlement integer NOT NULL,
    plant_name text NOT NULL,
    plant_code text NOT NULL,
    dept_id text NOT NULL,
    dept_name text NOT NULL,
    designation text NOT NULL,
    grade text NOT NULL,
    basic_salary numeric NOT NULL,
    change_reason text NOT NULL,
    valid_from date NOT NULL,
    valid_to date NOT NULL,
    is_current boolean NOT NULL,
    UNIQUE (emp_id, valid_from)
);

-- Job attributes come from the history version. Name, status and separation
-- come from the deduplicated employee snapshot. Rows with an empty
-- effective interval are not versions.
INSERT INTO warehouse.dim_employee (
    emp_id, full_name, gender, date_of_birth, email, phone, employment_type,
    hire_date, separation_date, status, annual_leave_entitlement, plant_name,
    plant_code, dept_id, dept_name, designation, grade, basic_salary, change_reason,
    valid_from, valid_to, is_current
)
SELECT
    history.emp_id,
    employee.full_name,
    employee.gender,
    employee.date_of_birth,
    employee.email,
    employee.phone,
    employee.employment_type,
    employee.hire_date,
    employee.separation_date,
    employee.status,
    employee.annual_leave_entitlement,
    department.plant,
    department.plant_code,
    history.dept_id,
    department.dept_name,
    history.designation,
    history.grade,
    history.basic_salary,
    history.change_reason,
    history.effective_from,
    coalesce(history.effective_to, DATE '9999-12-31'),
    history.effective_to IS NULL
FROM staging.employment_history AS history
JOIN staging.employees AS employee ON employee.emp_id = history.emp_id
JOIN staging.departments AS department ON department.dept_id = history.dept_id
WHERE history.is_effective
ORDER BY history.emp_id, history.effective_from;

CREATE INDEX dim_employee_validity_idx
    ON warehouse.dim_employee (emp_id, valid_from, valid_to);
