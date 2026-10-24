-- raw rows = staging rows kept from that file + rejected rows.
-- Derived rows (filled roster weeks, approval steps, leave days) are reported separately.

CREATE TABLE staging.reconciliation (
    table_name text PRIMARY KEY,
    raw_rows integer,
    staging_rows integer NOT NULL,
    rejected_rows integer NOT NULL,
    derived_rows integer NOT NULL,
    status text NOT NULL
);

INSERT INTO staging.reconciliation (table_name, raw_rows, staging_rows, rejected_rows, derived_rows, status)
SELECT
    'employees',
    (SELECT count(*) FROM raw.employees),
    (SELECT count(*) FROM staging.employees),
    (SELECT count(*) FROM staging.employee_dedup_log),
    0,
    CASE
        WHEN (SELECT count(*) FROM raw.employees)
           = (SELECT count(*) FROM staging.employees) + (SELECT count(*) FROM staging.employee_dedup_log)
         AND (SELECT count(*) FROM staging.employees WHERE dept_id IS NULL) = 0
        THEN 'MATCH'
        ELSE 'MISMATCH'
    END
UNION ALL
SELECT
    'employment_history',
    (SELECT count(*) FROM raw.employment_history),
    (SELECT count(*) FROM staging.employment_history),
    0, 0,
    CASE
        WHEN (SELECT count(*) FROM raw.employment_history) = (SELECT count(*) FROM staging.employment_history)
        THEN 'MATCH' ELSE 'MISMATCH'
    END
UNION ALL
SELECT 'departments', (SELECT count(*) FROM raw.departments), (SELECT count(*) FROM staging.departments), 0, 0,
    CASE WHEN (SELECT count(*) FROM raw.departments) = (SELECT count(*) FROM staging.departments) THEN 'MATCH' ELSE 'MISMATCH' END
UNION ALL
SELECT 'shifts', (SELECT count(*) FROM raw.shifts), (SELECT count(*) FROM staging.shifts), 0, 0,
    CASE WHEN (SELECT count(*) FROM raw.shifts) = (SELECT count(*) FROM staging.shifts) THEN 'MATCH' ELSE 'MISMATCH' END
UNION ALL
SELECT
    'shift_roster',
    (SELECT count(*) FROM raw.shift_roster),
    (SELECT count(*) FROM staging.shift_roster WHERE roster_source = 'delivered'),
    0,
    (SELECT count(*) FROM staging.shift_roster WHERE roster_source = 'forward_fill'),
    CASE
        WHEN (SELECT count(*) FROM raw.shift_roster)
           = (SELECT count(*) FROM staging.shift_roster WHERE roster_source = 'delivered')
        THEN 'MATCH' ELSE 'MISMATCH'
    END
UNION ALL
SELECT 'device_mapping', (SELECT count(*) FROM raw.device_mapping), (SELECT count(*) FROM staging.device_mapping), 0, 0,
    CASE WHEN (SELECT count(*) FROM raw.device_mapping) = (SELECT count(*) FROM staging.device_mapping) THEN 'MATCH' ELSE 'MISMATCH' END
UNION ALL
SELECT
    'biometric_punches',
    (SELECT count(*) FROM raw.biometric_punches),
    (SELECT count(*) FROM staging.biometric_punches),
    (SELECT count(*) FROM staging.rejected_punches),
    0,
    CASE
        WHEN (SELECT count(*) FROM raw.biometric_punches)
           = (SELECT count(*) FROM staging.biometric_punches) + (SELECT count(*) FROM staging.rejected_punches)
        THEN 'MATCH' ELSE 'MISMATCH'
    END
UNION ALL
SELECT 'holidays', (SELECT count(*) FROM raw.holidays), (SELECT count(*) FROM staging.holidays), 0, 0,
    CASE WHEN (SELECT count(*) FROM raw.holidays) = (SELECT count(*) FROM staging.holidays) THEN 'MATCH' ELSE 'MISMATCH' END
UNION ALL
SELECT 'leave_requests', (SELECT count(*) FROM raw.leave_requests), (SELECT count(*) FROM staging.leave_requests), 0,
    (SELECT count(*) FROM staging.leave_days),
    CASE WHEN (SELECT count(*) FROM raw.leave_requests) = (SELECT count(*) FROM staging.leave_requests) THEN 'MATCH' ELSE 'MISMATCH' END
UNION ALL
SELECT 'leave_approvals', NULL, (SELECT count(*) FROM staging.leave_approvals), 0, 0, 'DERIVED'
UNION ALL
SELECT 'overtime_requests', (SELECT count(*) FROM raw.overtime_requests), (SELECT count(*) FROM staging.overtime_requests), 0, 0,
    CASE WHEN (SELECT count(*) FROM raw.overtime_requests) = (SELECT count(*) FROM staging.overtime_requests) THEN 'MATCH' ELSE 'MISMATCH' END
UNION ALL
SELECT 'payroll_lines', (SELECT count(*) FROM raw.payroll_lines), (SELECT count(*) FROM staging.payroll_lines), 0, 0,
    CASE WHEN (SELECT count(*) FROM raw.payroll_lines) = (SELECT count(*) FROM staging.payroll_lines) THEN 'MATCH' ELSE 'MISMATCH' END
UNION ALL
SELECT 'applications', (SELECT count(*) FROM raw.applications), (SELECT count(*) FROM staging.applications), 0, 0,
    CASE WHEN (SELECT count(*) FROM raw.applications) = (SELECT count(*) FROM staging.applications) THEN 'MATCH' ELSE 'MISMATCH' END;
