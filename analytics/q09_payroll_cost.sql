-- Payroll cost per employee by department, and the change from the previous month.
-- Payroll cost is the sum of EARNING lines. Deductions are not subtracted.
-- Cost is already on the payroll fact under the month-end department
-- (or the separation date if the employee left during the month).
-- Headcount is the month-end headcount of that same department.
-- cost_per_employee = payroll cost / headcount.
-- The first month has no previous value, so its change columns are empty.

WITH months AS (
    SELECT DISTINCT month_start AS month, month_end
    FROM warehouse.dim_date
),
headcount AS (
    SELECT
        months.month,
        department.dept_id,
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
    GROUP BY months.month, department.dept_id
),
cost AS (
    SELECT
        payroll.payroll_month AS month,
        department.plant_name,
        department.dept_id,
        department.dept_name,
        SUM(payroll.amount) AS payroll_cost
    FROM warehouse.fact_payroll_line AS payroll
    JOIN warehouse.dim_department AS department
        ON department.department_key = payroll.department_key
    WHERE payroll.component_type = 'EARNING'
    GROUP BY
        payroll.payroll_month,
        department.plant_name,
        department.dept_id,
        department.dept_name
),
per_employee AS (
    SELECT
        cost.month,
        cost.plant_name,
        cost.dept_id,
        cost.dept_name,
        headcount.headcount,
        ROUND(cost.payroll_cost, 2) AS payroll_cost,
        ROUND(cost.payroll_cost / headcount.headcount, 2) AS cost_per_employee
    FROM cost
    JOIN headcount
        ON headcount.month = cost.month
       AND headcount.dept_id = cost.dept_id
),
with_previous AS (
    SELECT
        per_employee.*,
        LAG(cost_per_employee) OVER (
            PARTITION BY dept_id
            ORDER BY month
        ) AS previous_cost_per_employee
    FROM per_employee
)
SELECT
    month,
    plant_name,
    dept_id,
    dept_name,
    headcount,
    payroll_cost,
    cost_per_employee,
    previous_cost_per_employee,
    ROUND(cost_per_employee - previous_cost_per_employee, 2) AS mom_change,
    ROUND(
        (cost_per_employee - previous_cost_per_employee)
        / NULLIF(previous_cost_per_employee, 0),
        4
    ) AS mom_change_rate
FROM with_previous
ORDER BY dept_id, month;
