-- Employees paid in a month when they have no Present day.
-- Paid means the employee has payroll lines that month.
-- Zero attendance means no daily row with status Present, including employees
-- who have no attendance rows at all.
-- earning_amount is the sum of EARNING components.
-- Department is the department already stored on the payroll fact, which is
-- the month-end department, or the separation date if they left that month.

WITH paid AS (
    SELECT
        payroll.emp_id,
        payroll.payroll_month AS month,
        department.plant_name,
        department.dept_id,
        department.dept_name,
        SUM(payroll.amount) FILTER (WHERE payroll.component_type = 'EARNING') AS earning_amount
    FROM warehouse.fact_payroll_line AS payroll
    JOIN warehouse.dim_department AS department
        ON department.department_key = payroll.department_key
    GROUP BY
        payroll.emp_id,
        payroll.payroll_month,
        department.plant_name,
        department.dept_id,
        department.dept_name
),
attendance AS (
    SELECT
        emp_id,
        date_trunc('month', work_date)::date AS month,
        COUNT(*) AS attendance_days,
        COUNT(*) FILTER (WHERE status = 'Present') AS present_days
    FROM warehouse.fact_attendance_daily
    GROUP BY emp_id, date_trunc('month', work_date)::date
)
SELECT
    paid.emp_id,
    person.full_name,
    paid.month,
    paid.plant_name,
    paid.dept_id,
    paid.dept_name,
    person.separation_date,
    ROUND(paid.earning_amount, 2) AS earning_amount,
    COALESCE(attendance.attendance_days, 0) AS attendance_days,
    COALESCE(attendance.present_days, 0) AS present_days
FROM paid
JOIN warehouse.dim_employee AS person
    ON person.emp_id = paid.emp_id
   AND person.is_current
LEFT JOIN attendance
    ON attendance.emp_id = paid.emp_id
   AND attendance.month = paid.month
WHERE COALESCE(attendance.present_days, 0) = 0
ORDER BY paid.month, paid.emp_id;
