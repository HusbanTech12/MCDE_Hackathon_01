-- Ten employees with the most late arrivals.
-- A late arrival is a Present working day whose check-in is more than the
-- 10-minute grace after shift start. late_minutes is already 0 on every
-- other status, including Sundays and holidays.
-- Department is the employee's current department.
-- RANK keeps every employee tied for tenth place.

WITH late AS (
    SELECT emp_id, COUNT(*) AS late_days
    FROM warehouse.fact_attendance_daily
    WHERE late_minutes > 0
    GROUP BY emp_id
),
ranked AS (
    SELECT
        emp_id,
        late_days,
        RANK() OVER (ORDER BY late_days DESC) AS late_rank
    FROM late
)
SELECT
    ranked.late_rank,
    ranked.emp_id,
    employee.full_name,
    employee.plant_name,
    employee.dept_id,
    employee.dept_name,
    ranked.late_days
FROM ranked
JOIN warehouse.dim_employee AS employee
    ON employee.emp_id = ranked.emp_id
   AND employee.is_current
WHERE ranked.late_rank <= 10
ORDER BY ranked.late_rank, ranked.emp_id;
