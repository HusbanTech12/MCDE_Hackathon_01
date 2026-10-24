-- Absenteeism rate by plant and month, excluding approved leave.
-- Absent days are the numerator.
-- The denominator is days the employee was expected to work:
-- Present, Absent and Missing Punch.
-- On Leave, Weekly Off and Holiday are excluded from both sides.
-- Plant is the plant of the department the employee was in on that day.

SELECT
    department.plant_name,
    date_trunc('month', attendance.work_date)::date AS month,
    COUNT(*) FILTER (WHERE attendance.status = 'Absent') AS absent_days,
    COUNT(*) FILTER (
        WHERE attendance.status IN ('Present', 'Absent', 'Missing Punch')
    ) AS expected_days,
    ROUND(
        COUNT(*) FILTER (WHERE attendance.status = 'Absent')::numeric
        / NULLIF(
            COUNT(*) FILTER (
                WHERE attendance.status IN ('Present', 'Absent', 'Missing Punch')
            ),
            0
        ),
        4
    ) AS absenteeism_rate
FROM warehouse.fact_attendance_daily AS attendance
JOIN warehouse.dim_department AS department
    ON department.department_key = attendance.department_key
GROUP BY department.plant_name, date_trunc('month', attendance.work_date)::date
ORDER BY month, department.plant_name;
