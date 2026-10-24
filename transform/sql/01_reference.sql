-- Stage 2 reference data: plants, departments, shifts and holidays.
-- Text is trimmed, dates become real dates, and names use one canonical form.

DROP SCHEMA IF EXISTS staging CASCADE;
CREATE SCHEMA staging;

CREATE FUNCTION staging.normalize(value text) RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT NULLIF(regexp_replace(btrim(coalesce(value, '')), '\s+', ' ', 'g'), '')
$$;

CREATE FUNCTION staging.parse_date(value text) RETURNS date
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    cleaned text := btrim(coalesce(value, ''));
BEGIN
    IF cleaned = '' THEN
        RETURN NULL;
    END IF;
    IF cleaned ~ '^\d{4}-\d{2}-\d{2}$' THEN
        RETURN cleaned::date;
    ELSIF cleaned ~ '^\d{2}/\d{2}/\d{4}$' THEN
        RETURN to_date(cleaned, 'DD/MM/YYYY');
    ELSIF cleaned ~ '^\d{2}-[A-Za-z]{3}-\d{4}$' THEN
        RETURN to_date(cleaned, 'DD-Mon-YYYY');
    END IF;
    RAISE EXCEPTION 'Cannot parse date: %', value;
END;
$$;

CREATE FUNCTION staging.parse_timestamp(value text) RETURNS timestamp
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    cleaned text := btrim(coalesce(value, ''));
BEGIN
    IF cleaned = '' THEN
        RETURN NULL;
    END IF;
    IF cleaned ~ '^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}$' THEN
        RETURN replace(cleaned, 'T', ' ')::timestamp;
    END IF;
    RAISE EXCEPTION 'Cannot parse timestamp: %', value;
END;
$$;

CREATE FUNCTION staging.canonical_plant(value text) RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    cleaned text := lower(staging.normalize(value));
BEGIN
    IF cleaned = 'head office' THEN
        RETURN 'Head Office';
    ELSIF cleaned = 'korangi plant' THEN
        RETURN 'Korangi Plant';
    ELSIF cleaned = 'site plant' THEN
        RETURN 'SITE Plant';
    ELSIF cleaned = 'faisalabad plant' THEN
        RETURN 'Faisalabad Plant';
    ELSIF cleaned IS NULL THEN
        RETURN NULL;
    END IF;
    RAISE EXCEPTION 'Unknown plant: %', value;
END;
$$;

CREATE FUNCTION staging.plant_code(plant_name text) RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE plant_name
        WHEN 'Head Office' THEN 'HO'
        WHEN 'Korangi Plant' THEN 'KOR'
        WHEN 'SITE Plant' THEN 'SITE'
        WHEN 'Faisalabad Plant' THEN 'FSD'
    END
$$;

CREATE TABLE staging.plant (
    plant_code text PRIMARY KEY,
    plant_name text NOT NULL UNIQUE
);

INSERT INTO staging.plant (plant_code, plant_name)
VALUES
    ('HO', 'Head Office'),
    ('KOR', 'Korangi Plant'),
    ('SITE', 'SITE Plant'),
    ('FSD', 'Faisalabad Plant');

CREATE TABLE staging.departments (
    dept_id text PRIMARY KEY,
    dept_name text NOT NULL,
    plant text NOT NULL REFERENCES staging.plant (plant_name),
    plant_code text NOT NULL REFERENCES staging.plant (plant_code),
    cost_center text NOT NULL,
    previous_name text,
    renamed_on date,
    raw_row_hash text NOT NULL UNIQUE
);

INSERT INTO staging.departments (
    dept_id, dept_name, plant, plant_code, cost_center, previous_name, renamed_on, raw_row_hash
)
SELECT
    dept_id,
    staging.normalize(dept_name),
    staging.canonical_plant(plant),
    staging.plant_code(staging.canonical_plant(plant)),
    staging.normalize(cost_center),
    staging.normalize(previous_name),
    staging.parse_date(renamed_on),
    _row_hash
FROM raw.departments;

CREATE TABLE staging.shifts (
    shift_code text PRIMARY KEY,
    shift_name text NOT NULL,
    start_time time NOT NULL,
    end_time time NOT NULL,
    crosses_midnight boolean NOT NULL,
    grace_minutes integer NOT NULL,
    applies_to text NOT NULL,
    raw_row_hash text NOT NULL UNIQUE
);

INSERT INTO staging.shifts (
    shift_code, shift_name, start_time, end_time, crosses_midnight,
    grace_minutes, applies_to, raw_row_hash
)
SELECT
    upper(staging.normalize(shift_code)),
    staging.normalize(name),
    start_time::time,
    end_time::time,
    crosses_midnight::boolean,
    grace_minutes::integer,
    staging.normalize(applies_to),
    _row_hash
FROM raw.shifts;

CREATE TABLE staging.holidays (
    holiday_date date NOT NULL,
    holiday_name text NOT NULL,
    scope text NOT NULL,
    raw_row_hash text NOT NULL UNIQUE,
    PRIMARY KEY (holiday_date, scope)
);

INSERT INTO staging.holidays (holiday_date, holiday_name, scope, raw_row_hash)
SELECT
    staging.parse_date(holiday_date),
    staging.normalize(holiday_name),
    upper(staging.normalize(scope)),
    _row_hash
FROM raw.holidays;
