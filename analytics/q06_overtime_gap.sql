-- Department-months where paid overtime exceeds punch-computed overtime by more than 15%.
-- Same hours and same month-end department rule as q05_overtime_comparison.sql.
-- The test is paid_hours > computed_hours * 1.15, applied before rounding.
-- excess_rate = (paid - computed) / computed.

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
),
by_department_month AS (
    SELECT
        month,
        plant_name,
        dept_id,
        dept_name,
        SUM(computed_hours) AS computed_hours,
        SUM(approved_hours) AS approved_hours,
        SUM(paid_hours) AS paid_hours
    FROM attributed
    GROUP BY month, plant_name, dept_id, dept_name
)
SELECT
    month,
    plant_name,
    dept_id,
    dept_name,
    ROUND(computed_hours, 1) AS computed_hours,
    ROUND(approved_hours, 1) AS approved_hours,
    ROUND(paid_hours, 1) AS paid_hours,
    ROUND(paid_hours - computed_hours, 1) AS excess_hours,
    ROUND((paid_hours - computed_hours) / computed_hours, 4) AS excess_rate
FROM by_department_month
WHERE paid_hours > computed_hours * 1.15
ORDER BY month, plant_name, dept_id;
