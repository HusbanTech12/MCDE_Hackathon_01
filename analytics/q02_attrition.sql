-- Monthly attrition rate by department.
-- Rate = separations in the month / average headcount.
-- Average headcount = (headcount on the day before the month + month-end headcount) / 2.
-- April's opening headcount is therefore 31 March 2026.
-- A separation is charged to the department valid on the separation date.

WITH months AS (
    SELECT DISTINCT
        month_start,
        month_end,
        (month_start - INTERVAL '1 day')::date AS opening_date
    FROM warehouse.dim_date
),
points AS (
    SELECT month_start, month_end AS point_date, 'closing' AS point_name
    FROM months
    UNION ALL
    SELECT month_start, opening_date, 'opening'
    FROM months
),
headcount AS (
    SELECT
        points.month_start,
        points.point_name,
        department.plant_name,
        department.dept_id,
        department.dept_name,
        COUNT(*) AS headcount
    FROM points
    JOIN warehouse.dim_employee AS employee
        ON points.point_date BETWEEN employee.valid_from AND employee.valid_to
       AND employee.hire_date <= points.point_date
       AND (
            employee.separation_date IS NULL
            OR employee.separation_date > points.point_date
       )
    JOIN warehouse.dim_department AS department
        ON department.dept_id = employee.dept_id
    GROUP BY
        points.month_start,
        points.point_name,
        department.plant_name,
        department.dept_id,
        department.dept_name
),
snapshot AS (
    SELECT
        month_start,
        plant_name,
        dept_id,
        dept_name,
        SUM(headcount) FILTER (WHERE point_name = 'opening') AS opening_headcount,
        SUM(headcount) FILTER (WHERE point_name = 'closing') AS closing_headcount
    FROM headcount
    GROUP BY month_start, plant_name, dept_id, dept_name
),
separations AS (
    SELECT
        date_trunc('month', person.separation_date)::date AS month_start,
        department.dept_id,
        COUNT(*) AS separations
    FROM warehouse.dim_employee AS person
    JOIN warehouse.dim_employee AS version
        ON version.emp_id = person.emp_id
       AND person.separation_date BETWEEN version.valid_from AND version.valid_to
    JOIN warehouse.dim_department AS department
        ON department.dept_id = version.dept_id
    WHERE person.is_current
      AND person.separation_date BETWEEN DATE '2026-04-01' AND DATE '2026-09-30'
    GROUP BY date_trunc('month', person.separation_date)::date, department.dept_id
)
SELECT
    snapshot.month_start AS month,
    snapshot.plant_name,
    snapshot.dept_id,
    snapshot.dept_name,
    COALESCE(separations.separations, 0) AS separations,
    COALESCE(snapshot.opening_headcount, 0) AS opening_headcount,
    COALESCE(snapshot.closing_headcount, 0) AS closing_headcount,
    ROUND(
        (COALESCE(snapshot.opening_headcount, 0) + COALESCE(snapshot.closing_headcount, 0)) / 2.0,
        1
    ) AS average_headcount,
    ROUND(
        COALESCE(separations.separations, 0)::numeric
        / NULLIF(
            (COALESCE(snapshot.opening_headcount, 0) + COALESCE(snapshot.closing_headcount, 0)) / 2.0,
            0
        ),
        4
    ) AS attrition_rate
FROM snapshot
LEFT JOIN separations
    ON separations.month_start = snapshot.month_start
   AND separations.dept_id = snapshot.dept_id
ORDER BY snapshot.month_start, snapshot.plant_name, snapshot.dept_id;
