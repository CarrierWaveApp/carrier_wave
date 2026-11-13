"""Small Multiples — per-band sparklines showing 30-day QSO trends."""
import math
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)
W, H = 800, 700
BG = (14, 16, 22)
LABEL_COLOR = (140, 150, 180)
CARD_BG = (22, 25, 35)
CARD_BORDER = (35, 40, 55)

BANDS = [
    ("160m", (180, 80, 80)),
    ("80m", (200, 120, 60)),
    ("40m", (220, 180, 50)),
    ("30m", (180, 200, 80)),
    ("20m", (60, 130, 255)),
    ("17m", (80, 180, 200)),
    ("15m", (100, 200, 100)),
    ("12m", (160, 140, 220)),
    ("10m", (180, 100, 220)),
    ("6m", (220, 80, 180)),
]

DAYS = 30


def generate_band_data(band_name):
    base = {"160m": 2, "80m": 5, "40m": 12, "30m": 4, "20m": 20, "17m": 6, "15m": 15, "12m": 3, "10m": 8, "6m": 2}
    b = base.get(band_name, 5)
    data = []
    for day in range(DAYS):
        # Weekend spikes
        weekend = 1.8 if day % 7 in (5, 6) else 1.0
        # Contest spike
        contest = 4.0 if band_name in ("20m", "15m", "40m") and day in (12, 13) else 1.0
        val = max(0, int(b * weekend * contest * random.uniform(0.2, 1.8)))
        data.append(val)
    return data


img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
    font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 11)
    font_xs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 9)
except OSError:
    font = font_sm = font_xs = ImageFont.load_default()

draw.rectangle([(0, 0), (W, 38)], fill=(10, 12, 18))
draw.text((12, 10), "BAND DASHBOARD", fill=LABEL_COLOR, font=font)
draw.text((W - 260, 12), "30-day QSO trends per band", fill=(80, 220, 120), font=font_sm)

COLS = 2
ROWS = 5
MARGIN = 12
CARD_MARGIN_TOP = 48
card_w = (W - MARGIN * (COLS + 1)) / COLS
card_h = (H - CARD_MARGIN_TOP - MARGIN * (ROWS + 1)) / ROWS

for idx, (band_name, band_color) in enumerate(BANDS):
    col = idx % COLS
    row = idx // COLS
    cx = MARGIN + col * (card_w + MARGIN)
    cy = CARD_MARGIN_TOP + MARGIN + row * (card_h + MARGIN)

    draw.rounded_rectangle([cx, cy, cx + card_w, cy + card_h], radius=6, fill=CARD_BG, outline=CARD_BORDER)

    data = generate_band_data(band_name)
    total = sum(data)
    peak = max(data)

    draw.text((cx + 10, cy + 6), band_name, fill=band_color, font=font_sm)
    draw.text((cx + 55, cy + 8), f"{total} QSOs", fill=LABEL_COLOR, font=font_xs)
    draw.text((cx + card_w - 60, cy + 8), f"peak {peak}", fill=(100, 110, 130), font=font_xs)

    # Sparkline area
    spark_top = cy + 26
    spark_bottom = cy + card_h - 8
    spark_left = cx + 10
    spark_right = cx + card_w - 10
    spark_w = spark_right - spark_left
    spark_h = spark_bottom - spark_top

    max_data = max(max(data), 1)

    # Fill area
    for di in range(len(data) - 1):
        x1 = spark_left + di * spark_w / (DAYS - 1)
        x2 = spark_left + (di + 1) * spark_w / (DAYS - 1)
        y1 = spark_bottom - (data[di] / max_data) * spark_h
        y2 = spark_bottom - (data[di + 1] / max_data) * spark_h
        r, g, b = band_color
        fill_color = (r // 6, g // 6, b // 6)
        draw.polygon([(x1, y1), (x2, y2), (x2, spark_bottom), (x1, spark_bottom)], fill=fill_color)

    # Line
    points = []
    for di, val in enumerate(data):
        x = spark_left + di * spark_w / (DAYS - 1)
        y = spark_bottom - (val / max_data) * spark_h
        points.append((x, y))

    for pi in range(len(points) - 1):
        draw.line([points[pi], points[pi + 1]], fill=band_color, width=2)

    # Weekend markers (subtle dots at bottom)
    for di in range(DAYS):
        if di % 7 in (5, 6):
            x = spark_left + di * spark_w / (DAYS - 1)
            draw.ellipse([x - 1, spark_bottom + 1, x + 1, spark_bottom + 3], fill=(50, 55, 70))

img.save("/home/user/carrier_wave/mockups/band_sparklines.png")
print("Saved band_sparklines.png")
