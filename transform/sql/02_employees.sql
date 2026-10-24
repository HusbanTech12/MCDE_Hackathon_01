-- One employee row. Duplicate emp_id values keep the latest updated_at.
-- Department text is matched to the current department name, including old names.

CREATE TABLE staging.employees (
    emp_id text PRIMARY KEY,
    full_name text NOT NULL,
    gender text NOT NULL,
    date_of_birth date NOT NULL,
    email text NOT NULL,
    phone text NOT NULL,
    plant text NOT NULL REFERENCES staging.plant (plant_name),
    plant_code text NOT NULL REFERENCES staging.plant (plant_code),
    department text,
    dept_id text REFERENCES staging.departments (dept_id),
    designation text NOT NULL,
    grade text NOT NULL,
    employment_type text NOT NULL,
    hire_date date NOT NULL,
    separation_date date,
    status text NOT NULL,
    annual_leave_entitlement integer NOT NULL,
    updated_at timestamp NOT NULL,
    raw_row_hash text NOT NULL UNIQUE
);

CREATE TABLE staging.employee_dedup_log (
    emp_id text NOT NULL,
    dropped_row_hash text PRIMARY KEY,
    kept_row_hash text NOT NULL,
    dropped_updated_at timestamp NOT NULL,
    kept_updated_at timestamp NOT NULL,
    fields_changed text NOT NULL,
    reason text NOT NULL
);

INSERT INTO staging.employees (
    emp_id, full_name, gender, date_of_birth, email, phone, plant, plant_code,
    department, dept_id, designation, grade, employment_type, hire_date,
    separation_date, status, annual_leave_entitlement, updated_at, raw_row_hash
)
WITH ranked AS (
    SELECT
        raw.*,
        row_number() OVER (
            PARTITION BY emp_id
            ORDER BY staging.parse_timestamp(updated_at) DESC, _row_hash
        ) AS keep_rank
    FROM raw.employees AS raw
),
kept AS (
    SELECT * FROM ranked WHERE keep_rank = 1
),
matched AS (
    SELECT
        kept.*,
        dept.dept_id AS matched_dept_id,
        dept.dept_name AS matched_dept_name,
        row_number() OVER (
            PARTITION BY kept.emp_id
            ORDER BY
                CASE
                    WHEN lower(staging.normalize(dept.dept_name)) = lower(staging.normalize(kept.department)) THEN 0
                    ELSE 1
                END,
                dept.dept_id
        ) AS dept_rank
    FROM kept
    LEFT JOIN staging.departments AS dept
        ON dept.plant = staging.canonical_plant(kept.plant)
       AND (
            lower(staging.normalize(dept.dept_name)) = lower(staging.normalize(kept.department))
            OR lower(staging.normalize(dept.previous_name)) = lower(staging.normalize(kept.department))
       )
)
SELECT
    emp_id,
    CASE
        WHEN full_name = upper(full_name) OR full_name = lower(full_name) THEN initcap(staging.normalize(full_name))
        ELSE staging.normalize(full_name)
    END,
    upper(staging.normalize(gender)),
    staging.parse_date(date_of_birth),
    lower(staging.normalize(email)),
    staging.normalize(phone),
    staging.canonical_plant(plant),
    staging.plant_code(staging.canonical_plant(plant)),
    coalesce(matched_dept_name, staging.normalize(department)),
    matched_dept_id,
    staging.normalize(designation),
    upper(staging.normalize(grade)),
    initcap(staging.normalize(employment_type)),
    staging.parse_date(hire_date),
    staging.parse_date(separation_date),
    initcap(staging.normalize(status)),
    annual_leave_entitlement::integer,
    staging.parse_timestamp(updated_at),
    _row_hash
FROM matched
WHERE dept_rank = 1;

INSERT INTO staging.employee_dedup_log (
    emp_id, dropped_row_hash, kept_row_hash, dropped_updated_at, kept_updated_at,
    fields_changed, reason
)
WITH ranked AS (
    SELECT
        raw.*,
        staging.parse_timestamp(updated_at) AS updated_at_ts,
        row_number() OVER (
            PARTITION BY emp_id
            ORDER BY staging.parse_timestamp(updated_at) DESC, _row_hash
        ) AS keep_rank
    FROM raw.employees AS raw
)
SELECT
    dropped.emp_id,
    dropped._row_hash,
    kept._row_hash,
    dropped.updated_at_ts,
    kept.updated_at_ts,
    concat_ws(
        ', ',
        CASE WHEN kept.full_name IS DISTINCT FROM dropped.full_name THEN 'full_name' END,
        CASE WHEN kept.gender IS DISTINCT FROM dropped.gender THEN 'gender' END,
        CASE WHEN kept.date_of_birth IS DISTINCT FROM dropped.date_of_birth THEN 'date_of_birth' END,
        CASE WHEN kept.email IS DISTINCT FROM dropped.email THEN 'email' END,
        CASE WHEN kept.phone IS DISTINCT FROM dropped.phone THEN 'phone' END,
        CASE WHEN kept.plant IS DISTINCT FROM dropped.plant THEN 'plant' END,
        CASE WHEN kept.department IS DISTINCT FROM dropped.department THEN 'department' END,
        CASE WHEN kept.designation IS DISTINCT FROM dropped.designation THEN 'designation' END,
        CASE WHEN kept.grade IS DISTINCT FROM dropped.grade THEN 'grade' END,
        CASE WHEN kept.employment_type IS DISTINCT FROM dropped.employment_type THEN 'employment_type' END,
        CASE WHEN kept.hire_date IS DISTINCT FROM dropped.hire_date THEN 'hire_date' END,
        CASE WHEN kept.separation_date IS DISTINCT FROM dropped.separation_date THEN 'separation_date' END,
        CASE WHEN kept.status IS DISTINCT FROM dropped.status THEN 'status' END,
        CASE WHEN kept.annual_leave_entitlement IS DISTINCT FROM dropped.annual_leave_entitlement THEN 'annual_leave_entitlement' END,
        CASE WHEN kept.updated_at IS DISTINCT FROM dropped.updated_at THEN 'updated_at' END
    ),
    'same emp_id; kept the row with the latest updated_at'
FROM ranked AS dropped
JOIN ranked AS kept
    ON kept.emp_id = dropped.emp_id
   AND kept.keep_rank = 1
WHERE dropped.keep_rank > 1;
