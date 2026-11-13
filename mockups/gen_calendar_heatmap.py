"""Calendar Heatmap — GitHub contribution graph style QSO streak."""
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)
W, H = 800, 260
BG = (14, 16, 22)
LABEL = (140, 150, 180)

WEEKS = 52
DAYS_PER_WEEK = 7
DAY_NAMES = ["Mon", "", "Wed", "", "Fri", "", "Sun"]
MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def val_to_color(val):
    if val == 0:
        return (22, 25, 32)
    if val <= 3:
        return (30, 70, 40)
    if val <= 8:
        return (40, 120, 55)
    if val <= 15:
        return (50, 170, 70)
    return (70, 220, 90)


def gen_year():
    data = []
    for week in range(WEEKS):
        for day in range(DAYS_PER_WEEK):
            is_weekend = day >= 5
            base = 3 if is_weekend else 1
            is_contest = week in (6, 7, 20, 21, 40, 41, 47, 48)
            if is_contest and is_weekend:
                base = 20
            is_vacation = week in (30, 31)
            if is_vacation:
                base = 0
            is_pota = week % 3 == 0 and day == 5
            if is_pota:
                base += 10
            val = max(0, int(random.gauss(base, base * 0.4)))
            data.append(val)
    return data


def render(filename):
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 13)
        font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 10)
        font_xs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 8)
    except OSError:
        font = font_sm = font_xs = ImageFont.load_default()

    draw.rectangle([(0, 0), (W, 38)], fill=(10, 12, 18))
    draw.text((12, 10), "QSO STREAK  —  2025", fill=LABEL, font=font)

    data = gen_year()
    total = sum(data)
    active_days = sum(1 for d in data if d > 0)
    draw.text((W - 250, 12), f"{total} QSOs  |  {active_days} active days",
              fill=(80, 220, 120), font=font_sm)

    ml, mt = 35, 50
    cell = min((W - ml - 20) / WEEKS, (H - mt - 40) / 7)
    gap = 2

    for di, name in enumerate(DAY_NAMES):
        if name:
            y = mt + di * cell + cell / 2 - 4
            draw.text((4, y), name, fill=(60, 65, 80), font=font_xs)

    for wi in range(WEEKS):
        month_idx = min(11, wi * 12 // 52)
        if wi == 0 or (wi * 12 // 52) != ((wi - 1) * 12 // 52):
            x = ml + wi * cell
            draw.text((x, mt - 12), MONTH_NAMES[month_idx], fill=(60, 65, 80), font=font_xs)

    for wi in range(WEEKS):
        for di in range(DAYS_PER_WEEK):
            idx = wi * 7 + di
            if idx >= len(data):
                break
            val = data[idx]
            color = val_to_color(val)
            x = ml + wi * cell
            y = mt + di * cell
            draw.rectangle([x + gap / 2, y + gap / 2, x + cell - gap / 2, y + cell - gap / 2],
                           fill=color)

    ly = H - 22
    lx = W - 220
    draw.text((lx, ly), "Less", fill=(60, 65, 80), font=font_xs)
    lx += 28
    for lv in [0, 2, 6, 12, 25]:
        c = val_to_color(lv)
        draw.rectangle([lx, ly, lx + 10, ly + 10], fill=c)
        lx += 14
    draw.text((lx + 2, ly), "More", fill=(60, 65, 80), font=font_xs)

    img.save(filename)
    print(f"Saved {filename}")


render("/home/user/carrier_wave/mockups/calendar_heatmap.png")
