-- Employees who still have a payslip in a month after their separation date.
-- separation_date is the last day worked. Pay for the month in which they left
-- is their final pay and is not listed here.
-- A later payroll_month is the first day of that month, so it is after the
-- separation date only when the whole payslip month is later.

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
)
SELECT
    paid.emp_id,
    person.full_name,
    person.separation_date,
    paid.month,
    paid.plant_name,
    paid.dept_id,
    paid.dept_name,
    ROUND(paid.earning_amount, 2) AS earning_amount
FROM paid
JOIN warehouse.dim_employee AS person
    ON person.emp_id = paid.emp_id
   AND person.is_current
WHERE person.separation_date IS NOT NULL
  AND paid.month > person.separation_date
ORDER BY person.separation_date, paid.month, paid.emp_id;
