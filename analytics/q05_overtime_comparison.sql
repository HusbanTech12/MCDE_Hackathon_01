-- Overtime hours by department and month: punches, approved requests, and payroll.
-- Computed hours are overtime_hours on the daily attendance fact.
-- Approved hours are approved overtime requests only.
-- Paid hours are the OVERTIME payroll component's units.
-- All three are assigned to the department valid on the last day of the month,
-- or on the separation date when the employee left during that month.
-- Payroll's component code is OVERTIME, not OT.

WITH computed AS (
    SELECT
        emp_id,
        date_trunc('month', work_date)::date AS month,
        SUM(overtime_hours) AS computed_hours
    FROM warehouse.fact_attendance_daily
    GROUP BY emp_id, date_trunc('month', work_date)::date
),
approved AS (
    SELECT
        emp_id,
        date_trunc('month', ot_date)::date AS month,
        SUM(approved_hours) AS approved_hours
    FROM warehouse.fact_overtime_approved
    GROUP BY emp_id, date_trunc('month', ot_date)::date
),
paid AS (
    SELECT
        emp_id,
        payroll_month AS month,
        SUM(units) AS paid_hours
    FROM warehouse.fact_payroll_line
    WHERE component = 'OVERTIME'
    GROUP BY emp_id, payroll_month
),
employee_month AS (
    SELECT emp_id, month FROM computed
    UNION
    SELECT emp_id, month FROM approved
    UNION
    SELECT emp_id, month FROM paid
),
attributed AS (
    SELECT
        employee_month.month,
        department.plant_name,
        department.dept_id,
        department.dept_name,
        COALESCE(computed.computed_hours, 0) AS computed_hours,
        COALESCE(approved.approved_hours, 0) AS approved_hours,
        COALESCE(paid.paid_hours, 0) AS paid_hours
    FROM employee_month
    JOIN warehouse.dim_employee AS person
        ON person.emp_id = employee_month.emp_id
       AND person.is_current
    JOIN warehouse.dim_employee AS version
        ON version.emp_id = employee_month.emp_id
       AND (
            CASE
                WHEN person.separation_date >= employee_month.month
                 AND person.separation_date < (employee_month.month + INTERVAL '1 month')::date
                THEN person.separation_date
                ELSE (employee_month.month + INTERVAL '1 month' - INTERVAL '1 day')::date
            END
       ) BETWEEN version.valid_from AND version.valid_to
    JOIN warehouse.dim_department AS department
        ON department.dept_id = version.dept_id
    LEFT JOIN computed
        ON computed.emp_id = employee_month.emp_id
       AND computed.month = employee_month.month
    LEFT JOIN approved
        ON approved.emp_id = employee_month.emp_id
       AND approved.month = employee_month.month
    LEFT JOIN paid
        ON paid.emp_id = employee_month.emp_id
       AND paid.month = employee_month.month
)
SELECT
    month,
    plant_name,
    dept_id,
    dept_name,
    ROUND(SUM(computed_hours), 1) AS computed_hours,
    ROUND(SUM(approved_hours), 1) AS approved_hours,
    ROUND(SUM(paid_hours), 1) AS paid_hours
FROM attributed
GROUP BY month, plant_name, dept_id, dept_name
ORDER BY month, plant_name, dept_id;
