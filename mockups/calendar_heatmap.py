"""Calendar Heatmap — GitHub contribution style QSO streak."""
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)
W, H = 800, 320
BG = (14, 16, 22)
LABEL_COLOR = (140, 150, 180)

WEEKS = 52
DAYS_PER_WEEK = 7
DAY_LABELS = ["Mon", "", "Wed", "", "Fri", "", "Sun"]
MONTH_LABELS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

# Generate year of QSO data
data = []
for week in range(WEEKS):
    for day in range(DAYS_PER_WEEK):
        # Base activity
        base = random.uniform(0, 8)
        # Weekend boost
        if day in (5, 6):
            base *= 2.5
        # Contest weekends (every ~4 weeks)
        if week % 4 == 2 and day in (5, 6):
            base *= 3
        # Vacation gap
        if 30 <= week <= 31:
            base *= 0.1
        # Summer activity boost
        if 20 <= week <= 35:
            base *= 1.5
        data.append(max(0, int(base)))

max_val = max(data)


def val_to_color(val):
    if val == 0:
        return (22, 25, 32)
    t = val / max(max_val, 1)
    if t < 0.25:
        return (20, 50 + int(t * 4 * 60), 40)
    elif t < 0.5:
        tt = (t - 0.25) * 4
        return (20, 110 + int(tt * 60), 40 + int(tt * 20))
    elif t < 0.75:
        tt = (t - 0.5) * 4
        return (20 + int(tt * 40), 170 + int(tt * 30), 60 - int(tt * 10))
    else:
        tt = (t - 0.75) * 4
        return (60 + int(tt * 140), 200 + int(tt * 30), 50 + int(tt * 20))


img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
    font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 10)
    font_xs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 8)
except OSError:
    font = font_sm = font_xs = ImageFont.load_default()

# Header
draw.rectangle([(0, 0), (W, 38)], fill=(10, 12, 18))
draw.text((12, 10), "QSO STREAK", fill=LABEL_COLOR, font=font)

total = sum(data)
active_days = sum(1 for d in data if d > 0)
streak = 0
max_streak = 0
for d in reversed(data):
    if d > 0:
        streak += 1
        max_streak = max(max_streak, streak)
    else:
        streak = 0
        max_streak = max(max_streak, streak)

draw.text((W - 380, 12), f"{total} QSOs | {active_days} active days | {max_streak}-day best streak", fill=(80, 220, 120), font=font_sm)

MARGIN_TOP = 60
MARGIN_LEFT = 40
MARGIN_RIGHT = 16
MARGIN_BOTTOM = 40
cell_size = min((W - MARGIN_LEFT - MARGIN_RIGHT) / WEEKS, (H - MARGIN_TOP - MARGIN_BOTTOM) / DAYS_PER_WEEK)
cell_size = int(cell_size)
gap = 2

# Day labels
for di, label in enumerate(DAY_LABELS):
    if label:
        y = MARGIN_TOP + di * (cell_size + gap) + cell_size / 2 - 4
        draw.text((4, y), label, fill=(80, 85, 100), font=font_xs)

# Month labels
for mi, month in enumerate(MONTH_LABELS):
    week_start = int(mi * WEEKS / 12)
    x = MARGIN_LEFT + week_start * (cell_size + gap)
    draw.text((x, MARGIN_TOP - 14), month, fill=(80, 85, 100), font=font_xs)

# Grid cells
for week in range(WEEKS):
    for day in range(DAYS_PER_WEEK):
        idx = week * DAYS_PER_WEEK + day
        if idx >= len(data):
            break
        val = data[idx]
        color = val_to_color(val)
        x = MARGIN_LEFT + week * (cell_size + gap)
        y = MARGIN_TOP + day * (cell_size + gap)
        draw.rounded_rectangle([x, y, x + cell_size, y + cell_size], radius=2, fill=color)

# Legend
lx = MARGIN_LEFT
ly = H - 26
draw.text((lx, ly), "Less", fill=(80, 85, 100), font=font_xs)
lx += 30
for val in [0, 2, 5, 10, 20, 30]:
    color = val_to_color(val)
    draw.rounded_rectangle([lx, ly, lx + 12, ly + 12], radius=2, fill=color)
    lx += 16
draw.text((lx + 4, ly), "More", fill=(80, 85, 100), font=font_xs)

img.save("/home/user/carrier_wave/mockups/calendar_heatmap.png")
print("Saved calendar_heatmap.png")
