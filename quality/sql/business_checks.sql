-- Named Stage 6 checks. Each row is one check.
-- failed_rows = 0 means the check passed.
-- Derived rows (filled roster weeks, approval steps, leave days, attendance)
-- are counted on their own and are not added into the raw-file equality.

SELECT
    'reconciliation' AS check_group,
    'raw.employees' AS object_name,
    'raw rows = kept employees + dropped duplicates' AS check_name,
    (SELECT count(*) FROM raw.employees)::text AS expected_value,
    (
        (SELECT count(*) FROM staging.employees)
        + (SELECT count(*) FROM staging.employee_dedup_log)
    )::text AS actual_value,
    abs(
        (SELECT count(*) FROM raw.employees)
        - (SELECT count(*) FROM staging.employees)
        - (SELECT count(*) FROM staging.employee_dedup_log)
    )::integer AS failed_rows
UNION ALL
SELECT 'reconciliation', 'raw.employment_history', 'raw rows = staging rows',
    (SELECT count(*) FROM raw.employment_history)::text,
    (SELECT count(*) FROM staging.employment_history)::text,
    abs((SELECT count(*) FROM raw.employment_history) - (SELECT count(*) FROM staging.employment_history))::integer
UNION ALL
SELECT 'reconciliation', 'raw.departments', 'raw rows = staging rows',
    (SELECT count(*) FROM raw.departments)::text,
    (SELECT count(*) FROM staging.departments)::text,
    abs((SELECT count(*) FROM raw.departments) - (SELECT count(*) FROM staging.departments))::integer
UNION ALL
SELECT 'reconciliation', 'raw.shifts', 'raw rows = staging rows',
    (SELECT count(*) FROM raw.shifts)::text,
    (SELECT count(*) FROM staging.shifts)::text,
    abs((SELECT count(*) FROM raw.shifts) - (SELECT count(*) FROM staging.shifts))::integer
UNION ALL
SELECT 'reconciliation', 'raw.shift_roster', 'raw rows = delivered roster rows',
    (SELECT count(*) FROM raw.shift_roster)::text,
    (SELECT count(*) FROM staging.shift_roster WHERE roster_source = 'delivered')::text,
    abs(
        (SELECT count(*) FROM raw.shift_roster)
        - (SELECT count(*) FROM staging.shift_roster WHERE roster_source = 'delivered')
    )::integer
UNION ALL
SELECT 'reconciliation', 'staging.shift_roster', 'every roster row is delivered or forward-filled',
    (SELECT count(*) FROM staging.shift_roster)::text,
    (
        (SELECT count(*) FROM staging.shift_roster WHERE roster_source = 'delivered')
        + (SELECT count(*) FROM staging.shift_roster WHERE roster_source = 'forward_fill')
    )::text,
    abs(
        (SELECT count(*) FROM staging.shift_roster)
        - (SELECT count(*) FROM staging.shift_roster WHERE roster_source = 'delivered')
        - (SELECT count(*) FROM staging.shift_roster WHERE roster_source = 'forward_fill')
    )::integer
UNION ALL
SELECT 'reconciliation', 'raw.device_mapping', 'raw rows = staging rows',
    (SELECT count(*) FROM raw.device_mapping)::text,
    (SELECT count(*) FROM staging.device_mapping)::text,
    abs((SELECT count(*) FROM raw.device_mapping) - (SELECT count(*) FROM staging.device_mapping))::integer
UNION ALL
SELECT 'reconciliation', 'raw.biometric_punches', 'raw rows = kept punches + rejected punches',
    (SELECT count(*) FROM raw.biometric_punches)::text,
    (
        (SELECT count(*) FROM staging.biometric_punches)
        + (SELECT count(*) FROM staging.rejected_punches)
    )::text,
    abs(
        (SELECT count(*) FROM raw.biometric_punches)
        - (SELECT count(*) FROM staging.biometric_punches)
        - (SELECT count(*) FROM staging.rejected_punches)
    )::integer
UNION ALL
SELECT 'reconciliation', 'raw.holidays', 'raw rows = staging rows',
    (SELECT count(*) FROM raw.holidays)::text,
    (SELECT count(*) FROM staging.holidays)::text,
    abs((SELECT count(*) FROM raw.holidays) - (SELECT count(*) FROM staging.holidays))::integer
UNION ALL
SELECT 'reconciliation', 'raw.leave_requests', 'raw rows = staging requests',
    (SELECT count(*) FROM raw.leave_requests)::text,
    (SELECT count(*) FROM staging.leave_requests)::text,
    abs((SELECT count(*) FROM raw.leave_requests) - (SELECT count(*) FROM staging.leave_requests))::integer
UNION ALL
SELECT 'reconciliation', 'staging.leave_approvals', 'approval steps match the raw JSON array',
    (
        SELECT count(*)
        FROM raw.leave_requests AS request
        CROSS JOIN LATERAL jsonb_array_elements(request.approvals::jsonb)
    )::text,
    (SELECT count(*) FROM staging.leave_approvals)::text,
    abs(
        (
            SELECT count(*)
            FROM raw.leave_requests AS request
            CROSS JOIN LATERAL jsonb_array_elements(request.approvals::jsonb)
        )
        - (SELECT count(*) FROM staging.leave_approvals)
    )::integer
UNION ALL
SELECT 'reconciliation', 'staging.leave_days', 'leave days belong only to approved requests',
    '0',
    (
        SELECT count(*)
        FROM staging.leave_days AS leave_day
        JOIN staging.leave_requests AS request ON request.request_id = leave_day.request_id
        WHERE NOT request.is_approved
    )::text,
    (
        SELECT count(*)
        FROM staging.leave_days AS leave_day
        JOIN staging.leave_requests AS request ON request.request_id = leave_day.request_id
        WHERE NOT request.is_approved
    )::integer
UNION ALL
SELECT 'reconciliation', 'raw.overtime_requests', 'raw rows = staging rows',
    (SELECT count(*) FROM raw.overtime_requests)::text,
    (SELECT count(*) FROM staging.overtime_requests)::text,
    abs((SELECT count(*) FROM raw.overtime_requests) - (SELECT count(*) FROM staging.overtime_requests))::integer
UNION ALL
SELECT 'reconciliation', 'raw.payroll_lines', 'raw rows = staging rows',
    (SELECT count(*) FROM raw.payroll_lines)::text,
    (SELECT count(*) FROM staging.payroll_lines)::text,
    abs((SELECT count(*) FROM raw.payroll_lines) - (SELECT count(*) FROM staging.payroll_lines))::integer
UNION ALL
SELECT 'reconciliation', 'raw.applications', 'raw rows = staging rows',
    (SELECT count(*) FROM raw.applications)::text,
    (SELECT count(*) FROM staging.applications)::text,
    abs((SELECT count(*) FROM raw.applications) - (SELECT count(*) FROM staging.applications))::integer
UNION ALL
SELECT 'reconciliation', 'warehouse.dim_department', 'one warehouse row per staging department',
    (SELECT count(*) FROM staging.departments)::text,
    (SELECT count(*) FROM warehouse.dim_department)::text,
    abs((SELECT count(*) FROM staging.departments) - (SELECT count(*) FROM warehouse.dim_department))::integer
UNION ALL
SELECT 'reconciliation', 'warehouse.dim_shift', 'one warehouse row per staging shift',
    (SELECT count(*) FROM staging.shifts)::text,
    (SELECT count(*) FROM warehouse.dim_shift)::text,
    abs((SELECT count(*) FROM staging.shifts) - (SELECT count(*) FROM warehouse.dim_shift))::integer
UNION ALL
SELECT 'reconciliation', 'warehouse.dim_employee', 'one version per effective history row',
    (SELECT count(*) FROM staging.employment_history WHERE is_effective)::text,
    (SELECT count(*) FROM warehouse.dim_employee)::text,
    abs(
        (SELECT count(*) FROM staging.employment_history WHERE is_effective)
        - (SELECT count(*) FROM warehouse.dim_employee)
    )::integer
UNION ALL
SELECT 'reconciliation', 'warehouse.dim_date', 'every day from 1 Apr 2026 through 30 Sep 2026',
    '183',
    (SELECT count(*) FROM warehouse.dim_date)::text,
    (
        SELECT CASE
            WHEN min(date_key) = DATE '2026-04-01'
             AND max(date_key) = DATE '2026-09-30'
             AND count(*) = (max(date_key) - min(date_key) + 1)
            THEN 0
            ELSE 1
        END
        FROM warehouse.dim_date
    )::integer
UNION ALL
SELECT 'reconciliation', 'warehouse.fact_attendance_daily', 'one fact row per staging attendance day',
    (SELECT count(*) FROM staging.attendance_daily)::text,
    (SELECT count(*) FROM warehouse.fact_attendance_daily)::text,
    abs((SELECT count(*) FROM staging.attendance_daily) - (SELECT count(*) FROM warehouse.fact_attendance_daily))::integer
UNION ALL
SELECT 'reconciliation', 'warehouse.fact_leave_day', 'one fact row per staging leave day',
    (SELECT count(*) FROM staging.leave_days)::text,
    (SELECT count(*) FROM warehouse.fact_leave_day)::text,
    abs((SELECT count(*) FROM staging.leave_days) - (SELECT count(*) FROM warehouse.fact_leave_day))::integer
UNION ALL
SELECT 'reconciliation', 'warehouse.fact_overtime_approved', 'one fact row per approved overtime request',
    (SELECT count(*) FROM staging.overtime_requests WHERE status = 'Approved')::text,
    (SELECT count(*) FROM warehouse.fact_overtime_approved)::text,
    abs(
        (SELECT count(*) FROM staging.overtime_requests WHERE status = 'Approved')
        - (SELECT count(*) FROM warehouse.fact_overtime_approved)
    )::integer
UNION ALL
SELECT 'reconciliation', 'warehouse.fact_payroll_line', 'one fact row per staging payroll line',
    (SELECT count(*) FROM staging.payroll_lines)::text,
    (SELECT count(*) FROM warehouse.fact_payroll_line)::text,
    abs((SELECT count(*) FROM staging.payroll_lines) - (SELECT count(*) FROM warehouse.fact_payroll_line))::integer
UNION ALL
SELECT 'reconciliation', 'staging.reconciliation', 'staging build recorded no mismatch',
    '0',
    (SELECT count(*) FROM staging.reconciliation WHERE status = 'MISMATCH')::text,
    (SELECT count(*) FROM staging.reconciliation WHERE status = 'MISMATCH')::integer
UNION ALL
SELECT 'reconciliation', 'warehouse.reconciliation', 'warehouse build recorded no mismatch',
    '0',
    (SELECT count(*) FROM warehouse.reconciliation WHERE status <> 'MATCH')::text,
    (SELECT count(*) FROM warehouse.reconciliation WHERE status <> 'MATCH')::integer
UNION ALL
SELECT 'accepted_values', 'warehouse.fact_attendance_daily', 'attendance status is one of the six statuses',
    '0',
    (
        SELECT count(*)
        FROM warehouse.fact_attendance_daily
        WHERE status NOT IN ('Present', 'Absent', 'On Leave', 'Holiday', 'Weekly Off', 'Missing Punch')
    )::text,
    (
        SELECT count(*)
        FROM warehouse.fact_attendance_daily
        WHERE status NOT IN ('Present', 'Absent', 'On Leave', 'Holiday', 'Weekly Off', 'Missing Punch')
    )::integer
UNION ALL
SELECT 'accepted_values', 'staging.leave_requests', 'leave type is Annual, Casual, or Sick',
    '0',
    (
        SELECT count(*)
        FROM staging.leave_requests
        WHERE leave_type NOT IN ('Annual', 'Casual', 'Sick')
    )::text,
    (
        SELECT count(*)
        FROM staging.leave_requests
        WHERE leave_type NOT IN ('Annual', 'Casual', 'Sick')
    )::integer
UNION ALL
SELECT 'accepted_values', 'warehouse.fact_leave_day', 'leave type is Annual, Casual, or Sick',
    '0',
    (
        SELECT count(*)
        FROM warehouse.fact_leave_day
        WHERE leave_type NOT IN ('Annual', 'Casual', 'Sick')
    )::text,
    (
        SELECT count(*)
        FROM warehouse.fact_leave_day
        WHERE leave_type NOT IN ('Annual', 'Casual', 'Sick')
    )::integer
UNION ALL
SELECT 'accepted_values', 'staging.payroll_lines', 'pay component and type match the payslip list',
    '0',
    (
        SELECT count(*)
        FROM staging.payroll_lines
        WHERE (component, component_type) NOT IN (
            ('BASIC', 'EARNING'),
            ('HOUSE_RENT', 'EARNING'),
            ('MEDICAL', 'EARNING'),
            ('CONVEYANCE', 'EARNING'),
            ('OVERTIME', 'EARNING'),
            ('INCOME_TAX', 'DEDUCTION'),
            ('EOBI', 'DEDUCTION'),
            ('ABSENCE_DEDUCTION', 'DEDUCTION'),
            ('LOAN_INSTALLMENT', 'DEDUCTION')
        )
    )::text,
    (
        SELECT count(*)
        FROM staging.payroll_lines
        WHERE (component, component_type) NOT IN (
            ('BASIC', 'EARNING'),
            ('HOUSE_RENT', 'EARNING'),
            ('MEDICAL', 'EARNING'),
            ('CONVEYANCE', 'EARNING'),
            ('OVERTIME', 'EARNING'),
            ('INCOME_TAX', 'DEDUCTION'),
            ('EOBI', 'DEDUCTION'),
            ('ABSENCE_DEDUCTION', 'DEDUCTION'),
            ('LOAN_INSTALLMENT', 'DEDUCTION')
        )
    )::integer
UNION ALL
SELECT 'business_sanity', 'warehouse.fact_attendance_daily', 'worked minutes are never negative',
    '0',
    (SELECT count(*) FROM warehouse.fact_attendance_daily WHERE worked_minutes < 0)::text,
    (SELECT count(*) FROM warehouse.fact_attendance_daily WHERE worked_minutes < 0)::integer
UNION ALL
SELECT 'business_sanity', 'warehouse.fact_attendance_daily', 'paired shift is no longer than 16 hours',
    '0',
    (
        SELECT count(*)::text
            || ' rows, longest '
            || round(
                coalesce(max(extract(epoch FROM check_out - check_in)), 0) / 3600.0,
                1
            )::text
            || ' hours'
        FROM warehouse.fact_attendance_daily
        WHERE check_in IS NOT NULL
          AND check_out IS NOT NULL
          AND check_out - check_in > INTERVAL '16 hours'
    ),
    (
        SELECT count(*)
        FROM warehouse.fact_attendance_daily
        WHERE check_in IS NOT NULL
          AND check_out IS NOT NULL
          AND check_out - check_in > INTERVAL '16 hours'
    )::integer
UNION ALL
SELECT 'business_sanity', 'warehouse.dim_employee', 'SCD2 versions do not overlap',
    '0',
    (
        SELECT count(*)
        FROM (
            SELECT
                valid_from,
                lag(valid_to) OVER (PARTITION BY emp_id ORDER BY valid_from, employee_key) AS previous_valid_to
            FROM warehouse.dim_employee
        ) AS versions
        WHERE previous_valid_to IS NOT NULL
          AND valid_from <= previous_valid_to
    )::text,
    (
        SELECT count(*)
        FROM (
            SELECT
                valid_from,
                lag(valid_to) OVER (PARTITION BY emp_id ORDER BY valid_from, employee_key) AS previous_valid_to
            FROM warehouse.dim_employee
        ) AS versions
        WHERE previous_valid_to IS NOT NULL
          AND valid_from <= previous_valid_to
    )::integer
UNION ALL
SELECT 'business_sanity', 'warehouse.dim_employee', 'each version starts on or before its end date',
    '0',
    (SELECT count(*) FROM warehouse.dim_employee WHERE valid_from > valid_to)::text,
    (SELECT count(*) FROM warehouse.dim_employee WHERE valid_from > valid_to)::integer
UNION ALL
SELECT 'business_sanity', 'warehouse.dim_employee', 'each employee has one current version',
    '0',
    (
        SELECT count(*)
        FROM (
            SELECT emp_id
            FROM warehouse.dim_employee
            GROUP BY emp_id
            HAVING count(*) FILTER (WHERE is_current) <> 1
        ) AS employees
    )::text,
    (
        SELECT count(*)
        FROM (
            SELECT emp_id
            FROM warehouse.dim_employee
            GROUP BY emp_id
            HAVING count(*) FILTER (WHERE is_current) <> 1
        ) AS employees
    )::integer
