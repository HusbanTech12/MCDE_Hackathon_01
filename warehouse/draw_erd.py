"""Draw the warehouse star-schema diagram."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH = 1680
HEIGHT = 1080
BACKGROUND = "#f6f3ee"
INK = "#1c1917"
MUTED = "#57534e"
LINE = "#7c6f64"
DIM_HEADER = "#1e3a5f"
FACT_HEADER = "#9a3412"
CARD = "#fffdf9"
RULE = "#e7e5e4"


def draw_erd(path: Path) -> Path:
    image = Image.new("RGB", (WIDTH, HEIGHT), BACKGROUND)
    draw = ImageDraw.Draw(image)
    title_font = ImageFont.truetype(r"C:\Windows\Fonts\segoeuib.ttf", 36)
    subtitle_font = ImageFont.truetype(r"C:\Windows\Fonts\segoeui.ttf", 18)
    header_font = ImageFont.truetype(r"C:\Windows\Fonts\segoeuib.ttf", 20)
    body_font = ImageFont.truetype(r"C:\Windows\Fonts\segoeui.ttf", 16)

    draw.text((48, 28), "Indus Weave HR warehouse", font=title_font, fill=INK)
    draw.text(
        (48, 74),
        "Star schema. Employee history is SCD Type 2: work_date BETWEEN valid_from AND valid_to.",
        font=subtitle_font,
        fill=MUTED,
    )

    dimensions = [
        (
            "dim_date",
            ["date_key  PK", "year, quarter, month", "month_name", "month_start, month_end", "week_start", "is_sunday"],
        ),
        (
            "dim_department",
            ["department_key  PK", "dept_id  UK", "dept_name", "plant_name, plant_code", "cost_center", "previous_name, renamed_on"],
        ),
        (
            "dim_shift",
            ["shift_key  PK", "shift_code  UK", "start_time, end_time", "crosses_midnight", "grace_minutes"],
        ),
        (
            "dim_employee",
            ["employee_key  PK", "emp_id + valid_from  UK", "valid_from, valid_to", "is_current", "dept_id, grade", "designation, basic_salary", "hire_date, separation_date"],
        ),
    ]
    facts = [
        (
            "fact_attendance_daily",
            ["attendance_key  PK", "emp_id + work_date  UK", "employee_key  FK", "work_date  FK", "department_key  FK", "shift_key  FK", "status, worked_minutes", "late_minutes, overtime_hours"],
        ),
        (
            "fact_leave_day",
            ["leave_day_key  PK", "request_id + leave_date", "employee_key  FK", "leave_date  FK", "department_key  FK", "leave_type"],
        ),
        (
            "fact_overtime_approved",
            ["overtime_key  PK", "request_id  UK", "employee_key  FK", "ot_date  FK", "department_key  FK", "approved_hours"],
        ),
        (
            "fact_payroll_line",
            ["payroll_key  PK", "line_id  UK", "employee_key  FK", "pay_date  FK", "department_key  FK", "component, amount"],
        ),
    ]

    boxes = {}
    boxes.update(_place_row(draw, dimensions, y=150, header=DIM_HEADER, header_font=header_font, body_font=body_font))
    boxes.update(_place_row(draw, facts, y=640, header=FACT_HEADER, header_font=header_font, body_font=body_font))

    links = [
        ("fact_attendance_daily", "dim_employee"),
        ("fact_attendance_daily", "dim_date"),
        ("fact_attendance_daily", "dim_department"),
        ("fact_attendance_daily", "dim_shift"),
        ("fact_leave_day", "dim_employee"),
        ("fact_leave_day", "dim_date"),
        ("fact_leave_day", "dim_department"),
        ("fact_overtime_approved", "dim_employee"),
        ("fact_overtime_approved", "dim_date"),
        ("fact_overtime_approved", "dim_department"),
        ("fact_payroll_line", "dim_employee"),
        ("fact_payroll_line", "dim_date"),
        ("fact_payroll_line", "dim_department"),
    ]
    # Lines sit under the cards. Redraw cards after the lines.
    image2 = Image.new("RGB", (WIDTH, HEIGHT), BACKGROUND)
    line_draw = ImageDraw.Draw(image2)
    line_draw.text((48, 28), "Indus Weave HR warehouse", font=title_font, fill=INK)
    line_draw.text(
        (48, 74),
        "Star schema. Employee history is SCD Type 2: work_date BETWEEN valid_from AND valid_to.",
        font=subtitle_font,
        fill=MUTED,
    )
    for fact_name, dim_name in links:
        start = _top_center(boxes[fact_name])
        end = _bottom_center(boxes[dim_name])
        line_draw.line((start[0], start[1], start[0], 590, end[0], 590, end[0], end[1]), fill=LINE, width=2)
    image.paste(image2, (0, 0))
    draw = ImageDraw.Draw(image)
    _place_row(draw, dimensions, y=150, header=DIM_HEADER, header_font=header_font, body_font=body_font)
    _place_row(draw, facts, y=640, header=FACT_HEADER, header_font=header_font, body_font=body_font)
    draw.text((48, 1030), "PK primary key    UK unique key    FK foreign key, enforced", font=subtitle_font, fill=MUTED)

    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG")
    return path


def _place_row(draw, cards, y, header, header_font, body_font):
    gap = 24
    margin = 40
    width = (WIDTH - margin * 2 - gap * (len(cards) - 1)) // len(cards)
    placed = {}
    for index, (title, lines) in enumerate(cards):
        x = margin + index * (width + gap)
        height = 46 + 28 * len(lines) + 16
        _card(draw, x, y, width, height, title, lines, header, header_font, body_font)
        placed[title] = (x, y, width, height)
    return placed


def _card(draw, x, y, width, height, title, lines, header, header_font, body_font):
    draw.rounded_rectangle((x, y, x + width, y + height), radius=12, fill=CARD, outline=RULE, width=2)
    draw.rounded_rectangle((x, y, x + width, y + 44), radius=12, fill=header)
    draw.rectangle((x, y + 28, x + width, y + 44), fill=header)
    draw.text((x + 16, y + 10), title, font=header_font, fill="white")
    for line_index, line in enumerate(lines):
        draw.text((x + 16, y + 56 + line_index * 28), line, font=body_font, fill=INK)


def _top_center(box):
    x, y, width, _height = box
    return (x + width // 2, y)


def _bottom_center(box):
    x, y, width, height = box
    return (x + width // 2, y + height)
