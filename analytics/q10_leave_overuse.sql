-- Employees whose approved Annual leave in these six months already exceeds
-- their full-year entitlement.
-- fact_leave_day contains only days that were approved by both Manager and HR,
-- were not cancelled, and were not a Sunday or a plant holiday.
-- The entitlement is the annual_leave_entitlement on the employee record.

SELECT
    employee.emp_id,
    employee.full_name,
    employee.plant_name,
    employee.dept_id,
    employee.dept_name,
    employee.annual_leave_entitlement,
    COUNT(*) AS annual_leave_days,
    COUNT(*) - employee.annual_leave_entitlement AS days_over
FROM warehouse.dim_employee AS employee
JOIN warehouse.fact_leave_day AS leave_day
    ON leave_day.emp_id = employee.emp_id
   AND leave_day.leave_type = 'Annual'
WHERE employee.is_current
GROUP BY
    employee.emp_id,
    employee.full_name,
    employee.plant_name,
    employee.dept_id,
    employee.dept_name,
    employee.annual_leave_entitlement
HAVING COUNT(*) > employee.annual_leave_entitlement
ORDER BY days_over DESC, employee.emp_id;
