-- Month-end headcount by plant and department, April through September 2026.
-- An employee counts on a month end when hire_date is on or before that day
-- and separation_date is empty or after that day. separation_date is the last
-- day worked, so an employee who left on the month end is not in headcount.
-- The department is the employment-history version valid on the month end.

WITH months AS (
    SELECT DISTINCT month_start, month_end
    FROM warehouse.dim_date
)
SELECT
    months.month_start AS month,
    department.plant_name,
    department.dept_id,
    department.dept_name,
    COUNT(*) AS headcount
FROM months
JOIN warehouse.dim_employee AS employee
    ON months.month_end BETWEEN employee.valid_from AND employee.valid_to
JOIN warehouse.dim_department AS department
    ON department.dept_id = employee.dept_id
WHERE employee.hire_date <= months.month_end
  AND (
        employee.separation_date IS NULL
        OR employee.separation_date > months.month_end
      )
GROUP BY
    months.month_start,
    department.plant_name,
    department.dept_id,
    department.dept_name
ORDER BY months.month_start, department.plant_name, department.dept_id;
