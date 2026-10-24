-- The faulty clock is the device whose rostered check-ins sit far from shift start.
-- Other devices cluster a few minutes before the shift. This one is later by about
-- three quarters of an hour, so its punch times are moved back by that many minutes.
-- Unmapped device users are rejected. Two punches for the same employee within
-- two minutes then count as one; the later punch is rejected.

CREATE TABLE staging.device_clock_offset (
    device_id text PRIMARY KEY,
    checkin_count integer NOT NULL,
    median_minutes_from_start numeric NOT NULL,
    reference_minutes numeric NOT NULL,
    offset_minutes integer NOT NULL,
    detection_note text NOT NULL
);

INSERT INTO staging.device_clock_offset (
    device_id, checkin_count, median_minutes_from_start, reference_minutes,
    offset_minutes, detection_note
)
WITH windows AS (
    SELECT *
    FROM (VALUES
        ('DAY', TIME '04:00', TIME '12:00', TIME '06:00'),
        ('EVE', TIME '12:00', TIME '20:00', TIME '14:00'),
        ('NIGHT', TIME '20:00', TIME '23:59:59', TIME '22:00'),
        ('GEN', TIME '07:00', TIME '12:00', TIME '09:00')
    ) AS window_row (shift_code, window_start, window_end, shift_start)
),
mapped AS (
    SELECT
        punch.device_id,
        mapping.emp_id,
        staging.parse_timestamp(punch.punch_time) AS punch_time
    FROM raw.biometric_punches AS punch
    JOIN staging.device_mapping AS mapping
        ON mapping.device_id = punch.device_id
       AND mapping.device_user_id = punch.device_user_id
),
first_checkin AS (
    SELECT
        mapped.device_id,
        mapped.emp_id,
        windows.shift_code,
        windows.shift_start,
        mapped.punch_time::date AS work_date,
        min(mapped.punch_time) AS first_punch
    FROM mapped
    JOIN windows
        ON mapped.punch_time::time >= windows.window_start
       AND mapped.punch_time::time <= windows.window_end
    GROUP BY mapped.device_id, mapped.emp_id, windows.shift_code, windows.shift_start, mapped.punch_time::date
),
rostered AS (
    SELECT
        first_checkin.device_id,
        EXTRACT(EPOCH FROM (first_checkin.first_punch::time - first_checkin.shift_start)) / 60.0
            AS minutes_from_start
    FROM first_checkin
    JOIN staging.shift_roster AS roster
        ON roster.emp_id = first_checkin.emp_id
       AND roster.shift_code = first_checkin.shift_code
       AND roster.roster_source = 'delivered'
       AND roster.week_start = first_checkin.work_date
            - (EXTRACT(ISODOW FROM first_checkin.work_date)::integer - 1)
),
device_median AS (
    SELECT
        device_id,
        count(*) AS checkin_count,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY minutes_from_start) AS median_minutes
    FROM rostered
    GROUP BY device_id
),
center AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY median_minutes) AS center_minutes
    FROM device_median
),
outlier AS (
    SELECT device_median.device_id
    FROM device_median
    CROSS JOIN center
    ORDER BY abs(device_median.median_minutes - center.center_minutes) DESC, device_median.device_id
    LIMIT 1
),
reference AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY device_median.median_minutes) AS reference_minutes
    FROM device_median
    WHERE device_median.device_id <> (SELECT device_id FROM outlier)
)
SELECT
    device_median.device_id,
    device_median.checkin_count,
    round(device_median.median_minutes::numeric, 1),
    round(reference.reference_minutes::numeric, 1),
    CASE
        WHEN device_median.device_id = outlier.device_id
         AND abs(device_median.median_minutes - reference.reference_minutes) >= 30
        THEN round((device_median.median_minutes - reference.reference_minutes)::numeric)::integer
        ELSE 0
    END AS offset_minutes,
    CASE
        WHEN device_median.device_id = outlier.device_id
         AND abs(device_median.median_minutes - reference.reference_minutes) >= 30
        THEN format(
            'Rostered check-ins on %s are %s minutes from shift start. The other devices are %s minutes from shift start. This clock is fast, so its punch times are moved back %s minutes.',
            device_median.device_id,
            round(device_median.median_minutes::numeric, 1),
            round(reference.reference_minutes::numeric, 1),
            round((device_median.median_minutes - reference.reference_minutes)::numeric)::integer
        )
        ELSE format(
            'Rostered check-ins on %s are %s minutes from shift start, in line with the other devices. No clock correction.',
            device_median.device_id,
            round(device_median.median_minutes::numeric, 1)
        )
    END
FROM device_median
CROSS JOIN reference
LEFT JOIN outlier ON outlier.device_id = device_median.device_id;

CREATE TABLE staging.punch_prepared (
    punch_id text PRIMARY KEY,
    device_id text NOT NULL,
    device_user_id text NOT NULL,
    emp_id text,
    punch_time_raw timestamp NOT NULL,
    punch_time timestamp NOT NULL,
    offset_minutes integer NOT NULL,
    raw_row_hash text NOT NULL UNIQUE
);

INSERT INTO staging.punch_prepared (
    punch_id, device_id, device_user_id, emp_id, punch_time_raw, punch_time,
    offset_minutes, raw_row_hash
)
SELECT
    punch.punch_id,
    punch.device_id,
    punch.device_user_id,
    mapping.emp_id,
    staging.parse_timestamp(punch.punch_time),
    staging.parse_timestamp(punch.punch_time)
        - (coalesce(clock.offset_minutes, 0) * INTERVAL '1 minute'),
    coalesce(clock.offset_minutes, 0),
    punch._row_hash
FROM raw.biometric_punches AS punch
LEFT JOIN staging.device_mapping AS mapping
    ON mapping.device_id = punch.device_id
   AND mapping.device_user_id = punch.device_user_id
LEFT JOIN staging.device_clock_offset AS clock
    ON clock.device_id = punch.device_id;

CREATE TABLE staging.rejected_punches (
    punch_id text PRIMARY KEY,
    device_id text NOT NULL,
    device_user_id text NOT NULL,
    emp_id text,
    punch_time_raw timestamp NOT NULL,
    punch_time timestamp NOT NULL,
    reason text NOT NULL,
    related_punch_id text,
    raw_row_hash text NOT NULL UNIQUE
);

INSERT INTO staging.rejected_punches (
    punch_id, device_id, device_user_id, emp_id, punch_time_raw, punch_time,
    reason, related_punch_id, raw_row_hash
)
SELECT
    punch_id, device_id, device_user_id, NULL, punch_time_raw, punch_time,
    'unmapped device user', NULL, raw_row_hash
FROM staging.punch_prepared
WHERE emp_id IS NULL;

INSERT INTO staging.rejected_punches (
    punch_id, device_id, device_user_id, emp_id, punch_time_raw, punch_time,
    reason, related_punch_id, raw_row_hash
)
WITH ordered AS (
    SELECT
        prepared.*,
        lag(punch_id) OVER (PARTITION BY emp_id ORDER BY punch_time, punch_id) AS previous_punch_id,
        lag(punch_time) OVER (PARTITION BY emp_id ORDER BY punch_time, punch_id) AS previous_punch_time
    FROM staging.punch_prepared AS prepared
    WHERE emp_id IS NOT NULL
)
SELECT
    punch_id, device_id, device_user_id, emp_id, punch_time_raw, punch_time,
    'within 2 minutes of punch ' || previous_punch_id,
    previous_punch_id,
    raw_row_hash
FROM ordered
WHERE previous_punch_time IS NOT NULL
  AND punch_time - previous_punch_time <= INTERVAL '2 minutes';

CREATE TABLE staging.biometric_punches (
    punch_id text PRIMARY KEY,
    device_id text NOT NULL,
    device_user_id text NOT NULL,
    emp_id text NOT NULL REFERENCES staging.employees (emp_id),
    punch_time_raw timestamp NOT NULL,
    punch_time timestamp NOT NULL,
    offset_minutes integer NOT NULL,
    raw_row_hash text NOT NULL UNIQUE
);

INSERT INTO staging.biometric_punches (
    punch_id, device_id, device_user_id, emp_id, punch_time_raw, punch_time,
    offset_minutes, raw_row_hash
)
SELECT
    prepared.punch_id, prepared.device_id, prepared.device_user_id, prepared.emp_id,
    prepared.punch_time_raw, prepared.punch_time, prepared.offset_minutes, prepared.raw_row_hash
FROM staging.punch_prepared AS prepared
WHERE prepared.emp_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM staging.rejected_punches AS rejected
      WHERE rejected.punch_id = prepared.punch_id
  );

CREATE INDEX biometric_punches_emp_time_idx
    ON staging.biometric_punches (emp_id, punch_time);

DROP TABLE staging.punch_prepared;
