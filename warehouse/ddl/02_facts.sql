-- Facts point at the employee version valid on the event date.
-- Monthly payroll uses the department on the last day of the month,
-- or on the separation date when the employee left during that month.

CREATE TABLE warehouse.fact_attendance_daily (
    attendance_key bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    emp_id text NOT NULL,
    employee_key bigint NOT NULL REFERENCES warehouse.dim_employee (employee_key),
    work_date date NOT NULL REFERENCES warehouse.dim_date (date_key),
    department_key bigint NOT NULL REFERENCES warehouse.dim_department (department_key),
    shift_key bigint NOT NULL REFERENCES warehouse.dim_shift (shift_key),
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
    UNIQUE (emp_id, work_date)
);

INSERT INTO warehouse.fact_attendance_daily (
    emp_id, employee_key, work_date, department_key, shift_key, punch_count,
    check_in, check_out, worked_minutes, late_minutes, early_departure_minutes,
    overtime_hours, status
)
SELECT
    attendance.emp_id,
    employee.employee_key,
    attendance.work_date,
    department.department_key,
    shift.shift_key,
    attendance.punch_count,
    attendance.check_in,
    attendance.check_out,
    attendance.worked_minutes,
    attendance.late_minutes,
    attendance.early_departure_minutes,
    attendance.overtime_hours,
    attendance.status
FROM staging.attendance_daily AS attendance
JOIN warehouse.dim_employee AS employee
    ON employee.emp_id = attendance.emp_id
   AND attendance.work_date BETWEEN employee.valid_from AND employee.valid_to
JOIN warehouse.dim_department AS department
    ON department.dept_id = employee.dept_id
JOIN warehouse.dim_shift AS shift
    ON shift.shift_code = attendance.shift_code;

CREATE INDEX fact_attendance_department_idx
    ON warehouse.fact_attendance_daily (department_key, work_date);
CREATE INDEX fact_attendance_status_idx
    ON warehouse.fact_attendance_daily (status, work_date);

CREATE TABLE warehouse.fact_leave_day (
    leave_day_key bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    request_id text NOT NULL,
    emp_id text NOT NULL,
    employee_key bigint NOT NULL REFERENCES warehouse.dim_employee (employee_key),
    leave_date date NOT NULL REFERENCES warehouse.dim_date (date_key),
    department_key bigint NOT NULL REFERENCES warehouse.dim_department (department_key),
    leave_type text NOT NULL,
    UNIQUE (request_id, leave_date)
);

INSERT INTO warehouse.fact_leave_day (
    request_id, emp_id, employee_key, leave_date, department_key, leave_type
)
SELECT
    leave_day.request_id,
    leave_day.emp_id,
    employee.employee_key,
    leave_day.leave_date,
    department.department_key,
    leave_day.leave_type
FROM staging.leave_days AS leave_day
JOIN warehouse.dim_employee AS employee
    ON employee.emp_id = leave_day.emp_id
   AND leave_day.leave_date BETWEEN employee.valid_from AND employee.valid_to
JOIN warehouse.dim_department AS department
    ON department.dept_id = employee.dept_id;

CREATE TABLE warehouse.fact_overtime_approved (
    overtime_key bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    request_id text NOT NULL UNIQUE,
    emp_id text NOT NULL,
    employee_key bigint NOT NULL REFERENCES warehouse.dim_employee (employee_key),
    ot_date date NOT NULL REFERENCES warehouse.dim_date (date_key),
    department_key bigint NOT NULL REFERENCES warehouse.dim_department (department_key),
    requested_hours numeric NOT NULL,
    approved_hours numeric NOT NULL
);

INSERT INTO warehouse.fact_overtime_approved (
    request_id, emp_id, employee_key, ot_date, department_key,
    requested_hours, approved_hours
)
SELECT
    request.request_id,
    request.emp_id,
    employee.employee_key,
    request.ot_date,
    department.department_key,
    request.requested_hours,
    request.approved_hours
FROM staging.overtime_requests AS request
JOIN warehouse.dim_employee AS employee
    ON employee.emp_id = request.emp_id
   AND request.ot_date BETWEEN employee.valid_from AND employee.valid_to
JOIN warehouse.dim_department AS department
    ON department.dept_id = employee.dept_id
WHERE request.status = 'Approved';

CREATE INDEX fact_overtime_department_idx
    ON warehouse.fact_overtime_approved (department_key, ot_date);

CREATE TABLE warehouse.fact_payroll_line (
    payroll_key bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    line_id text NOT NULL UNIQUE,
    emp_id text NOT NULL,
    employee_key bigint NOT NULL REFERENCES warehouse.dim_employee (employee_key),
    payroll_month date NOT NULL,
    pay_date date NOT NULL REFERENCES warehouse.dim_date (date_key),
    department_key bigint NOT NULL REFERENCES warehouse.dim_department (department_key),
    component text NOT NULL,
    component_type text NOT NULL,
    units numeric,
    amount numeric NOT NULL
);

INSERT INTO warehouse.fact_payroll_line (
    line_id, emp_id, employee_key, payroll_month, pay_date, department_key,
    component, component_type, units, amount
)
SELECT
    payroll.line_id,
    payroll.emp_id,
    employee.employee_key,
    payroll.payroll_month,
    pay.pay_date,
    department.department_key,
    payroll.component,
    payroll.component_type,
    payroll.units,
    payroll.amount
FROM staging.payroll_lines AS payroll
JOIN staging.employees AS person ON person.emp_id = payroll.emp_id
CROSS JOIN LATERAL (
    SELECT CASE
        WHEN person.separation_date >= payroll.payroll_month
         AND person.separation_date < (payroll.payroll_month + INTERVAL '1 month')::date
        THEN person.separation_date
        ELSE (payroll.payroll_month + INTERVAL '1 month' - INTERVAL '1 day')::date
    END AS pay_date
) AS pay
JOIN warehouse.dim_employee AS employee
    ON employee.emp_id = payroll.emp_id
   AND pay.pay_date BETWEEN employee.valid_from AND employee.valid_to
JOIN warehouse.dim_department AS department
    ON department.dept_id = employee.dept_id;

CREATE INDEX fact_payroll_department_idx
    ON warehouse.fact_payroll_line (department_key, payroll_month);

CREATE TABLE warehouse.reconciliation (
    table_name text PRIMARY KEY,
    source_rows integer NOT NULL,
    warehouse_rows integer NOT NULL,
    status text NOT NULL
);

INSERT INTO warehouse.reconciliation (table_name, source_rows, warehouse_rows, status)
SELECT 'dim_department',
       (SELECT count(*) FROM staging.departments),
       (SELECT count(*) FROM warehouse.dim_department),
       CASE WHEN (SELECT count(*) FROM staging.departments) = (SELECT count(*) FROM warehouse.dim_department)
            THEN 'MATCH' ELSE 'MISMATCH' END
UNION ALL
SELECT 'dim_shift',
       (SELECT count(*) FROM staging.shifts),
       (SELECT count(*) FROM warehouse.dim_shift),
       CASE WHEN (SELECT count(*) FROM staging.shifts) = (SELECT count(*) FROM warehouse.dim_shift)
            THEN 'MATCH' ELSE 'MISMATCH' END
UNION ALL
SELECT 'dim_employee',
       (SELECT count(*) FROM staging.employment_history WHERE is_effective),
       (SELECT count(*) FROM warehouse.dim_employee),
       CASE WHEN (SELECT count(*) FROM staging.employment_history WHERE is_effective)
                 = (SELECT count(*) FROM warehouse.dim_employee)
            THEN 'MATCH' ELSE 'MISMATCH' END
UNION ALL
SELECT 'fact_attendance_daily',
       (SELECT count(*) FROM staging.attendance_daily),
       (SELECT count(*) FROM warehouse.fact_attendance_daily),
       CASE WHEN (SELECT count(*) FROM staging.attendance_daily)
                 = (SELECT count(*) FROM warehouse.fact_attendance_daily)
            THEN 'MATCH' ELSE 'MISMATCH' END
UNION ALL
SELECT 'fact_leave_day',
       (SELECT count(*) FROM staging.leave_days),
       (SELECT count(*) FROM warehouse.fact_leave_day),
       CASE WHEN (SELECT count(*) FROM staging.leave_days) = (SELECT count(*) FROM warehouse.fact_leave_day)
            THEN 'MATCH' ELSE 'MISMATCH' END
UNION ALL
SELECT 'fact_overtime_approved',
       (SELECT count(*) FROM staging.overtime_requests WHERE status = 'Approved'),
       (SELECT count(*) FROM warehouse.fact_overtime_approved),
       CASE WHEN (SELECT count(*) FROM staging.overtime_requests WHERE status = 'Approved')
                 = (SELECT count(*) FROM warehouse.fact_overtime_approved)
            THEN 'MATCH' ELSE 'MISMATCH' END
UNION ALL
SELECT 'fact_payroll_line',
       (SELECT count(*) FROM staging.payroll_lines),
       (SELECT count(*) FROM warehouse.fact_payroll_line),
       CASE WHEN (SELECT count(*) FROM staging.payroll_lines) = (SELECT count(*) FROM warehouse.fact_payroll_line)
            THEN 'MATCH' ELSE 'MISMATCH' END;
