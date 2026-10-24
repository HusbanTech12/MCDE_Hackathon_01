"""Draw the six CFO slides and save presentation/slides.pdf.

    python presentation/build_slides.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH = 1920
HEIGHT = 1080
MARGIN = 96

BG = "#f6f3ee"
INK = "#1c1917"
MUTED = "#57534e"
NAVY = "#1e3a5f"
RUST = "#9a3412"
CARD = "#fffdf9"
LINE = "#e7e5e4"
SOFT = "#efeae3"

FONT = r"C:\Windows\Fonts\segoeuib.ttf"
FONT_REGULAR = r"C:\Windows\Fonts\segoeui.ttf"


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


def wrap(draw: ImageDraw.ImageDraw, text: str, face: ImageFont.FreeTypeFont, width: int) -> list[str]:
    lines: list[str] = []
    current = ""
    for word in text.split():
        trial = word if not current else f"{current} {word}"
        if draw.textlength(trial, font=face) <= width:
            current = trial
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def new_slide(kicker: str) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 14, HEIGHT), fill=NAVY)
    draw.text((MARGIN, 48), kicker.upper(), font=font(FONT, 22), fill=RUST)
    return image, draw


def footer(draw: ImageDraw.ImageDraw, page: int) -> None:
    draw.line((MARGIN, HEIGHT - 72, WIDTH - MARGIN, HEIGHT - 72), fill=LINE, width=2)
    draw.text((MARGIN, HEIGHT - 56), "Indus Weave Textiles  ·  April–September 2026", font=font(FONT_REGULAR, 20), fill=MUTED)
    label = f"{page} / 6"
    face = font(FONT_REGULAR, 20)
    draw.text((WIDTH - MARGIN - draw.textlength(label, font=face), HEIGHT - 56), label, font=face, fill=MUTED)


def paragraph(
    draw: ImageDraw.ImageDraw,
    text: str,
    xy: tuple[int, int],
    face: ImageFont.FreeTypeFont,
    fill: str,
    width: int,
    gap: int,
) -> int:
    y = xy[1]
    for line in wrap(draw, text, face, width):
        draw.text((xy[0], y), line, font=face, fill=fill)
        y += gap
    return y


def slide_title() -> Image.Image:
    image, draw = new_slide("PeopleOps  ·  CFO briefing")
    draw.text((MARGIN, 220), "Why the overtime bill", font=font(FONT, 84), fill=INK)
    draw.text((MARGIN, 320), "keeps rising", font=font(FONT, 84), fill=NAVY)
    paragraph(
        draw,
        "Payroll pays approved overtime. The punches, the absences, and five people who already left tell a different story.",
        (MARGIN, 470),
        font(FONT_REGULAR, 36),
        MUTED,
        1100,
        52,
    )
    draw.rounded_rectangle((MARGIN, 680, 760, 860), radius=16, fill=CARD, outline=LINE, width=2)
    draw.text((MARGIN + 36, 712), "Six-month overtime pay", font=font(FONT_REGULAR, 24), fill=MUTED)
    draw.text((MARGIN + 36, 756), "PKR 19.0 million", font=font(FONT, 48), fill=INK)
    draw.rounded_rectangle((800, 680, 1500, 860), radius=16, fill=NAVY)
    draw.text((836, 712), "April to September", font=font(FONT_REGULAR, 24), fill="#d6d3d1")
    draw.text((836, 756), "Up 23%", font=font(FONT, 48), fill="#fffdf9")
    footer(draw, 1)
    return image


def slide_bill() -> Image.Image:
    image, draw = new_slide("The bill")
    draw.text((MARGIN, 120), "Overtime pay rose even where", font=font(FONT, 56), fill=INK)
    draw.text((MARGIN, 190), "the company was not overpaying.", font=font(FONT, 56), fill=INK)
    cards = [
        ("April", "PKR 2.81 million", "5,525.5 hours paid"),
        ("September", "PKR 3.48 million", "6,418.5 hours paid"),
        ("Paid vs punches", "1,766.5 hours under", "36,401.5 paid, 38,168 worked"),
    ]
    x = MARGIN
    for title, value, note in cards:
        draw.rounded_rectangle((x, 340, x + 540, 640), radius=16, fill=CARD, outline=LINE, width=2)
        draw.text((x + 36, 376), title, font=font(FONT_REGULAR, 26), fill=MUTED)
        draw.text((x + 36, 440), value, font=font(FONT, 40), fill=NAVY)
        paragraph(draw, note, (x + 36, 530), font(FONT_REGULAR, 26), INK, 460, 36)
        x += 576
    paragraph(
        draw,
        "Paid hours equal approved hours in every department-month. From July, most departments worked more overtime than payroll paid. The extra cost sits in a short list of approvals.",
        (MARGIN, 700),
        font(FONT_REGULAR, 30),
        MUTED,
        WIDTH - 2 * MARGIN,
        44,
    )
    footer(draw, 2)
    return image


def slide_finding_one() -> Image.Image:
    image, draw = new_slide("Finding 1  ·  approvals")
    draw.text((MARGIN, 120), "23 department-months paid", font=font(FONT, 52), fill=INK)
    draw.text((MARGIN, 186), "more than 15% above the punches.", font=font(FONT, 52), fill=INK)
    stats = [
        ("4,574.5", "extra hours in those months"),
        ("1,049", "extra hours in Stitching, September"),
        ("PKR 3.77m", "Stitching overtime, six months"),
    ]
    x = MARGIN
    for value, label in stats:
        draw.rounded_rectangle((x, 320, x + 540, 520), radius=16, fill=CARD, outline=LINE, width=2)
        draw.text((x + 32, 352), value, font=font(FONT, 48), fill=RUST)
        paragraph(draw, label, (x + 32, 430), font(FONT_REGULAR, 26), INK, 470, 34)
        x += 576
    paragraph(
        draw,
        "Faisalabad Stitching was 23% over its punches in May and 144% over in September (1,778.5 hours paid, 729.5 worked). In April, all six SITE departments were 59% to 77% over. Action: pay the lower of approved hours and punch hours, and hold the next Stitching close until each approval matches a punch.",
        (MARGIN, 580),
        font(FONT_REGULAR, 30),
        INK,
        WIDTH - 2 * MARGIN,
        44,
    )
    draw.text((MARGIN, 820), "Evidence  analytics/q06_overtime_gap.sql", font=font(FONT_REGULAR, 26), fill=MUTED)
    footer(draw, 3)
    return image


def slide_finding_two() -> Image.Image:
    image, draw = new_slide("Finding 2  ·  attendance")
    draw.text((MARGIN, 120), "Six people were absent every", font=font(FONT, 52), fill=INK)
    draw.text((MARGIN, 186), "working day, and were still paid.", font=font(FONT, 52), fill=INK)
    draw.rounded_rectangle((MARGIN, 320, 760, 560), radius=16, fill=NAVY)
    draw.text((MARGIN + 36, 356), "Paid to the six", font=font(FONT_REGULAR, 26), fill="#d6d3d1")
    draw.text((MARGIN + 36, 420), "PKR 2.88 million", font=font(FONT, 48), fill="#fffdf9")
    draw.rounded_rectangle((800, 320, WIDTH - MARGIN, 560), radius=16, fill=CARD, outline=LINE, width=2)
    draw.text((836, 356), "Any month with no Present day", font=font(FONT_REGULAR, 26), fill=MUTED)
    draw.text((836, 420), "13 people  ·  PKR 4.83 million", font=font(FONT, 40), fill=INK)
    paragraph(
        draw,
        "Each of the six has about 147 Absent days and no Present, On Leave, or Missing Punch day. Sundays and plant holidays are the only other rows. Action: do not pay a month with no Present day unless approved leave covers it. Stop these six salaries before the next run.",
        (MARGIN, 620),
        font(FONT_REGULAR, 30),
        INK,
        WIDTH - 2 * MARGIN,
        44,
    )
    draw.text((MARGIN, 860), "Evidence  analytics/q07_pay_without_attendance.sql", font=font(FONT_REGULAR, 26), fill=MUTED)
    footer(draw, 4)
    return image


def slide_finding_three() -> Image.Image:
    image, draw = new_slide("Finding 3  ·  leavers")
    draw.text((MARGIN, 120), "Five people were paid after", font=font(FONT, 52), fill=INK)
    draw.text((MARGIN, 186), "their last day.", font=font(FONT, 52), fill=INK)
    draw.rounded_rectangle((MARGIN, 330, 900, 780), radius=16, fill=CARD, outline=LINE, width=2)
    draw.text((MARGIN + 40, 370), "Umair Baloch  ·  Human Resources", font=font(FONT, 32), fill=NAVY)
    lines = [
        "Last day worked: 23 April 2026",
        "Payslip after that: PKR 132,000",
        "Months still paid: May through September",
        "Amount after leaving: PKR 660,000",
    ]
    y = 450
    for line in lines:
        draw.text((MARGIN + 40, y), line, font=font(FONT_REGULAR, 30), fill=INK)
        y += 56
    draw.rounded_rectangle((960, 330, WIDTH - MARGIN, 780), radius=16, fill=SOFT)
    draw.text((1000, 370), "All five leavers", font=font(FONT, 32), fill=INK)
    paragraph(
        draw,
        "21 payslips in months after the separation date. PKR 1.95 million. The month they left is not included. Action: the last payslip is the separation month. Close the five records and recover the pay, starting with Human Resources.",
        (1000, 450),
        font(FONT_REGULAR, 30),
        INK,
        760,
        44,
    )
    draw.text((MARGIN, 860), "Evidence  analytics/q08_pay_after_separation.sql", font=font(FONT_REGULAR, 26), fill=MUTED)
    footer(draw, 5)
    return image


def slide_actions() -> Image.Image:
    image, draw = new_slide("This month")
    draw.text((MARGIN, 120), "Three controls before the next payroll.", font=font(FONT, 52), fill=INK)
    actions = [
        ("1", "Cap overtime", "Pay the lower of approved hours and punch hours. Review Faisalabad Stitching first."),
        ("2", "No Present day, no pay", "Hold earnings when the month has no Present day, unless approved leave is on file."),
        ("3", "Close pay on the last day", "The separation month is the last payslip. Recover PKR 1.95 million already paid after exit."),
    ]
    y = 250
    for number, title, body in actions:
        draw.rounded_rectangle((MARGIN, y, WIDTH - MARGIN, y + 180), radius=16, fill=CARD, outline=LINE, width=2)
        draw.ellipse((MARGIN + 28, y + 48, MARGIN + 108, y + 128), fill=NAVY)
        tw = draw.textlength(number, font=font(FONT, 36))
        draw.text((MARGIN + 68 - tw / 2, y + 66), number, font=font(FONT, 36), fill="#fffdf9")
        draw.text((MARGIN + 140, y + 36), title, font=font(FONT, 34), fill=INK)
        paragraph(draw, body, (MARGIN + 140, y + 96), font(FONT_REGULAR, 28), MUTED, 1400, 38)
        y += 204
    footer(draw, 6)
    return image


def main() -> None:
    slides = [
        slide_title(),
        slide_bill(),
        slide_finding_one(),
        slide_finding_two(),
        slide_finding_three(),
        slide_actions(),
    ]
    out = Path(__file__).resolve().parent / "slides.pdf"
    slides[0].save(out, "PDF", save_all=True, append_images=slides[1:], resolution=144.0)
    print(out)


if __name__ == "__main__":
    main()
