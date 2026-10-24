# Indus Weave Textiles — HR pipeline

Six months of HCM exports (1 April–30 September 2026) are loaded into PostgreSQL, cleaned, modeled as a star schema, and used to answer the ten CFO questions.

Python 3 and PostgreSQL. The raw files in this folder are not edited by hand. Every fix is in `ingestion/`, `transform/`, `warehouse/`, `analytics/`, or `quality/`.

## Team

Add each member's name and role here before the repository link is submitted.

## Setup

1. Install PostgreSQL and create an empty database:

```sql
CREATE DATABASE indus_weave;
```

2. Point the scripts at it. The default URL is `postgresql://postgres:hackathon@localhost:5432/indus_weave`. Override it when the local user or password is different:

```text
DATABASE_URL=postgresql://USER:PASSWORD@localhost:5432/indus_weave
```

On PowerShell:

```powershell
$env:DATABASE_URL = "postgresql://USER:PASSWORD@localhost:5432/indus_weave"
```

3. Install the Python packages from the repository root:

```text
python -m pip install -r requirements.txt
```

`psycopg2-binary` talks to PostgreSQL. `Pillow` draws `warehouse/erd.png`.

The twelve export files stay in the repository root. To load them from another folder, set `DATA_DIR` before the raw load.

## Rebuild

One command, from this folder:

```text
python run_pipeline.py
```

That runs the five steps below. Each step commits only when its own reconciliation matches. A mismatch rolls that step back.

```text
python ingestion/load_raw.py
python transform/build_staging.py
python warehouse/build_warehouse.py
python analytics/run_questions.py
python quality/run_checks.py
```

`analytics/results/` receives one CSV per question. Quality results are appended to `quality.dq_results`. The warehouse build also rewrites `warehouse/erd.png`.

Running the raw load a second time inserts nothing for rows already stored. Staging and the warehouse are rebuilt from scratch on every run.

## Layout

```text
ingestion/load_raw.py          Stage 1. Raw schema, all values as text.
transform/sql/                 Stages 2 and 3. Typed staging and attendance.
warehouse/ddl/                 Stage 4. Star schema.
warehouse/erd.png              Stage 4. ER diagram.
analytics/q01_*.sql … q10_*.sql
analytics/results/             One CSV per question.
quality/                       Stage 6. Checks written to quality.dq_results.
presentation/cfo_findings.md   Three findings for the CFO.
presentation/slides.pdf        Six slides.
presentation/build_slides.py   Redraws slides.pdf.
run_pipeline.py                Full rebuild.
```

## Design decisions

**Raw load.** Every column is `TEXT`. Nested leave JSON and the shift file stay as delivered: leave approvals are not exploded in `raw`. Each table has `_source_file`, `_loaded_at`, and `_row_hash`. The hash covers the delivered values only, and a unique constraint on `_row_hash` makes a second load skip rows it already has. `raw.load_audit` records file rows against table rows.

**Employees.** The same `emp_id` keeps the row with the latest `updated_at`. The other row is stored in `staging.employee_dedup_log` with the fields that differed. Names are trimmed. Dates accept `YYYY-MM-DD`, `DD/MM/YYYY`, and `DD-Mon-YYYY`. Department text is matched to the current name or `previous_name` inside the same plant.

**History.** `effective_to` from the export is ignored. A row lasts until the day before that employee's next `effective_from`. The latest row has no end. A same-day row that would end before it starts is marked `is_effective = false` and is left out of `dim_employee`.

**Roster.** A missing week copies the previous delivered shift. Filled weeks are tagged `forward_fill`. Delivered weeks stay one-for-one with `raw.shift_roster`.

**Punches.** A device user is mapped on `device_id` + `device_user_id`. Unmapped punches go to `staging.rejected_punches` with reason `unmapped device user`. For each device, rostered first punches are compared with shift start. `DEV-SITE-01` sits about 44 minutes later than the other three devices, which cluster about 6 minutes early. That clock is fast, so its punch times move back 44 minutes. The note is on `staging.device_clock_offset`. After the correction, two punches by the same employee within two minutes count as one: each punch is compared with the previous punch for that employee, and the later one is rejected.

**Leave.** A request counts only when Manager and HR both approved it and `cancelled_at` is empty. `staging.leave_approvals` is one row per approval step. `staging.leave_days` is one row per approved day, excluding Sundays and that plant's holidays. `days_requested` is kept and is not used to count days.

**Attendance.** One row per employee per day from hire date (or 1 April) through separation date or 30 September. `separation_date` is the last day worked and is included. Status priority is Weekly Off, Holiday, On Leave, Present, Missing Punch, Absent. Check-in is the first punch on the shift date and check-out is the last. Late and early minutes are stored only on Present working days, using the 10-minute grace on the shift. Working-day overtime is minutes after shift end, rounded down to a half hour. Sunday or holiday work is the whole span, rounded the same way.

A punch before 10:00 is placed on the previous day when that day's roster shift is NIGHT, so a night shift that ends at 06:00 stays with the day it started. An evening checkout after midnight stays on the new calendar day, because that shift is not marked as crossing midnight.

**Monthly department.** Headcount uses the employment-history version valid on the month end. An employee is in that headcount when `hire_date` is on or before the month end and `separation_date` is empty or after the month end. Overtime and payroll use the version valid on the month end, or on the separation date when the employee left during that month.

**Warehouse.** `dim_employee` is SCD Type 2. An open version ends on 9999-12-31, so facts join with `work_date BETWEEN valid_from AND valid_to`. Facts are `fact_attendance_daily`, `fact_leave_day`, `fact_overtime_approved` (approved requests only), and `fact_payroll_line`. Payroll cost is the sum of `EARNING` lines. Overtime hours paid are the `OVERTIME` line's `units`.

## Questions

| File | Question |
|---|---|
| `analytics/q01_headcount.sql` | Month-end headcount by plant and department |
| `analytics/q02_attrition.sql` | Monthly attrition by department. Separations divided by the average of the day before the month and the month end |
| `analytics/q03_absenteeism.sql` | Absent days divided by Present, Absent, and Missing Punch. Leave, Sundays, and holidays are excluded |
| `analytics/q04_late_arrivals.sql` | Ten employees with the most late arrivals. Ties at the boundary are kept |
| `analytics/q05_overtime_comparison.sql` | Punch hours, approved hours, and paid hours by department and month |
| `analytics/q06_overtime_gap.sql` | Department-months where paid hours exceed punch hours by more than 15% |
| `analytics/q07_pay_without_attendance.sql` | Paid employees with no Present day that month |
| `analytics/q08_pay_after_separation.sql` | Payslips in a month after the separation date |
| `analytics/q09_payroll_cost.sql` | Payroll cost per employee by department, and the change from the prior month |
| `analytics/q10_leave_overuse.sql` | Approved Annual leave in these six months above the full-year entitlement |

The CFO note is `presentation/cfo_findings.md`. The short deck is `presentation/slides.pdf`.
