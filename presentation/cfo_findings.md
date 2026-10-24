# CFO findings — April to September 2026

Payroll paid PKR 19,003,890 of overtime in these six months. The April overtime bill was PKR 2,814,309. The September bill was PKR 3,475,158, up 23%. Paid hours and approved hours are the same number in every department-month: payroll is paying the approval, not the punch. Three places explain the money.

## 1. A few departments approve far more overtime than people worked

In 23 department-months, paid hours exceed punch-computed hours by more than 15%. Those months paid 11,640.5 hours against 7,066.0 hours on the punches, a gap of 4,574.5 hours. Faisalabad Stitching is the trend that matters: the gap was 188.5 hours in May (23% over the punches) and 1,049.0 hours in September, when payroll paid 1,778.5 hours against 729.5 hours worked. Stitching is also the largest overtime cost in the company, PKR 3,771,337. In April, all six SITE Plant departments were 59% to 77% above their punches. Company-wide, paid hours (36,401.5) are still 1,766.5 below punch hours (38,168.0), because from July the other departments worked more than they were paid. The rise in the bill is the approvals concentrated in Stitching and, earlier, SITE.

Evidence: `analytics/q05_overtime_comparison.sql`, `analytics/q06_overtime_gap.sql`, and `SUM(amount)` on `warehouse.fact_payroll_line` where `component = 'OVERTIME'`.

Action: pay the lower of approved hours and punch hours. Hold the next Stitching payroll until each approval matches a punch-computed hour.

## 2. Six employees were absent every working day and were still paid

Six employees have a full attendance row for every day of the six months, and every working day is Absent: about 147 absent days each, with only Sundays and plant holidays besides. None of those days is Present, On Leave, or Missing Punch. Their earnings still total PKR 2,877,075. They are Fatima Chaudhry (SITE Dyeing, PKR 541,125), Sajid Memon (Faisalabad Warehouse, PKR 510,900), Sajid Javed (Faisalabad Packing, PKR 487,650), Sajid Javed (Korangi Weaving, PKR 471,375), Sohail Baig (Faisalabad Cutting, PKR 462,075), and Danish Hashmi (Faisalabad Maintenance, PKR 403,950). Widening the same test to any employee-month with no Present day finds 13 employees, 59 months, and PKR 4,829,312.

Evidence: `analytics/q07_pay_without_attendance.sql`.

Action: do not pay earnings for a month with no Present day unless an approved leave request covers it. Stop these six salaries before the next run.

## 3. Five people were paid after they left

Five former employees received 21 payslips in months after their separation date, worth PKR 1,948,000. The leaving month itself is not in this figure. Umair Baloch (E10471, Head Office Human Resources) last worked on 23 April 2026 and was then paid PKR 132,000 in each of May, June, July, August, and September: PKR 660,000 after his last day. The other four left in May and were paid a full earning from June through September: Sohail Hussain (SITE Finishing, PKR 63,450 a month), Amna Awan (Faisalabad Warehouse, PKR 80,500), Naveed Ansari (SITE Dyeing, PKR 104,525), and Tariq Jatoi (Faisalabad Packing, PKR 73,525).

Evidence: `analytics/q08_pay_after_separation.sql`.

Action: the last payslip is the month of `separation_date`. Close these five records and recover the PKR 1,948,000, starting with the Human Resources payslip that is still open.
