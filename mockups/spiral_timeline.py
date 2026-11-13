"""Spiral Timeline — Radio Helix showing daily/weekly QSO patterns."""
import math
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)
W, H = 800, 800
CENTER = (W // 2, H // 2)
BG = (10, 12, 20)
LABEL_COLOR = (140, 150, 180)

BAND_COLORS = {
    "160m": (180, 80, 80), "80m": (200, 120, 60), "40m": (220, 180, 50),
    "20m": (60, 130, 255), "15m": (100, 200, 100), "10m": (180, 100, 220),
}

# Generate QSO data for 90 days (3 months)
# Each QSO: (day, hour, band)
QSOS = []
for day in range(90):
    # Number of QSOs per day varies
    is_weekend = day % 7 in (5, 6)
    num = random.randint(3, 15) if is_weekend else random.randint(0, 8)
    for _ in range(num):
        hour = random.gauss(16, 4) % 24  # Peak around 4pm UTC
        band = random.choices(
            ["20m", "40m", "15m", "10m", "80m", "160m"],
            weights=[35, 20, 15, 10, 12, 8],
        )[0]
        # Night bands shift
        if 0 <= hour < 6 or 20 <= hour < 24:
            band = random.choices(
                ["80m", "40m", "160m", "20m"],
                weights=[30, 30, 20, 20],
            )[0]
        QSOS.append((day, hour, band))

img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
    font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 10)
    font_xs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 8)
except OSError:
    font = font_sm = font_xs = ImageFont.load_default()

# Spiral parameters: one revolution = 7 days (one week)
REVOLUTIONS = 90 / 7  # ~13 weeks
MIN_R = 40
MAX_R = 340
TOTAL_ANGLE = REVOLUTIONS * 2 * math.pi


def day_hour_to_spiral(day, hour):
    """Convert day+hour to spiral x,y."""
    # Progress through the 90 days
    t = (day + hour / 24.0) / 90.0
    angle = t * TOTAL_ANGLE - math.pi / 2  # Start at top
    r = MIN_R + (MAX_R - MIN_R) * t
    x = CENTER[0] + r * math.cos(angle)
    y = CENTER[1] + r * math.sin(angle)
    return x, y


# Draw spiral backbone
steps = 2000
for si in range(steps - 1):
    t1 = si / steps
    t2 = (si + 1) / steps
    a1 = t1 * TOTAL_ANGLE - math.pi / 2
    a2 = t2 * TOTAL_ANGLE - math.pi / 2
    r1 = MIN_R + (MAX_R - MIN_R) * t1
    r2 = MIN_R + (MAX_R - MIN_R) * t2
    x1 = CENTER[0] + r1 * math.cos(a1)
    y1 = CENTER[1] + r1 * math.sin(a1)
    x2 = CENTER[0] + r2 * math.cos(a2)
    y2 = CENTER[1] + r2 * math.sin(a2)
    draw.line([(x1, y1), (x2, y2)], fill=(20, 24, 35), width=1)

# Hour markers along the outermost ring
for hour in range(0, 24, 3):
    t = (89 + hour / 24.0) / 90.0
    angle = t * TOTAL_ANGLE - math.pi / 2
    r = MAX_R + 15
    x = CENTER[0] + r * math.cos(angle)
    y = CENTER[1] + r * math.sin(angle)
    draw.text((x - 6, y - 4), f"{hour:02d}", fill=(50, 55, 70), font=font_xs)

# Week labels along the spiral
for week in range(int(REVOLUTIONS)):
    day = week * 7
    t = day / 90.0
    angle = t * TOTAL_ANGLE - math.pi / 2
    r = MIN_R + (MAX_R - MIN_R) * t - 12
    x = CENTER[0] + r * math.cos(angle)
    y = CENTER[1] + r * math.sin(angle)
    if r > 60:
        draw.text((x - 6, y - 4), f"W{week + 1}", fill=(40, 45, 60), font=font_xs)

# Plot QSOs
for day, hour, band in QSOS:
    x, y = day_hour_to_spiral(day, hour)
    color = BAND_COLORS.get(band, (100, 100, 100))

    # Size based on how recent (outer = more recent = larger)
    t = day / 90.0
    size = 2 + int(t * 2)

    # Glow
    for gr in range(size + 4, size, -1):
        alpha = 0.08
        gc = (int(color[0] * alpha), int(color[1] * alpha), int(color[2] * alpha))
        draw.ellipse([x - gr, y - gr, x + gr, y + gr], fill=gc)

    alpha = 0.5 + t * 0.5
    c = (int(color[0] * alpha), int(color[1] * alpha), int(color[2] * alpha))
    draw.ellipse([x - size, y - size, x + size, y + size], fill=c)

# Center info
draw.ellipse([CENTER[0] - MIN_R + 5, CENTER[1] - MIN_R + 5, CENTER[0] + MIN_R - 5, CENTER[1] + MIN_R - 5], fill=(14, 16, 24))
draw.text((CENTER[0] - 16, CENTER[1] - 14), "W1AW", fill=(80, 220, 120), font=font_sm)
draw.text((CENTER[0] - 24, CENTER[1] + 4), f"{len(QSOS)} QSOs", fill=LABEL_COLOR, font=font_xs)
draw.text((CENTER[0] - 18, CENTER[1] + 16), "90 days", fill=(60, 65, 80), font=font_xs)

# Header
draw.rectangle([(0, 0), (W, 38)], fill=(6, 8, 14))
draw.text((12, 10), "RADIO HELIX", fill=LABEL_COLOR, font=font)
draw.text((W - 300, 12), "1 revolution = 1 week | 90 days", fill=(80, 220, 120), font=font_sm)

# Legend
lx = 12
ly = H - 24
for band, color in BAND_COLORS.items():
    draw.ellipse([lx, ly, lx + 8, ly + 8], fill=color)
    draw.text((lx + 12, ly - 1), band, fill=LABEL_COLOR, font=font_xs)
    lx += 52

img.save("/home/user/carrier_wave/mockups/spiral_timeline.png")
print("Saved spiral_timeline.png")
