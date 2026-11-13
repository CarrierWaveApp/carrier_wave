"""Heatmap Matrix — Band x Hour-of-Day propagation grid."""
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)
W, H = 800, 480
BG = (14, 16, 22)
GRID_LINE = (30, 35, 45)
LABEL_COLOR = (140, 150, 180)

BANDS = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m"]
HOURS = list(range(24))

# Simulated propagation: each band has a peak time window
PROFILES = {
    "160m": lambda h: max(0, 8 - abs(h - 4) if h < 12 else 8 - abs(h - 28)) * random.uniform(0.5, 1.2),
    "80m": lambda h: max(0, 10 - abs((h % 24) - 3)) * random.uniform(0.6, 1.3),
    "60m": lambda h: max(0, 6 - abs((h % 24) - 2)) * random.uniform(0.4, 1.1),
    "40m": lambda h: max(0, 12 - abs((h % 24) - 1) if h < 6 else 8 - abs((h % 24) - 22)) * random.uniform(0.5, 1.2),
    "30m": lambda h: max(0, 7 - abs((h % 24) - 20)) * random.uniform(0.5, 1.0),
    "20m": lambda h: max(0, 15 - abs((h % 24) - 16)) * random.uniform(0.6, 1.4),
    "17m": lambda h: max(0, 10 - abs((h % 24) - 15)) * random.uniform(0.5, 1.2),
    "15m": lambda h: max(0, 12 - abs((h % 24) - 14)) * random.uniform(0.6, 1.3),
    "12m": lambda h: max(0, 6 - abs((h % 24) - 13)) * random.uniform(0.4, 1.0),
    "10m": lambda h: max(0, 8 - abs((h % 24) - 12)) * random.uniform(0.5, 1.1),
    "6m": lambda h: max(0, 4 - abs((h % 24) - 14)) * random.uniform(0.3, 1.0),
}

data = {}
max_val = 0
for band in BANDS:
    for hour in HOURS:
        val = int(PROFILES[band](hour))
        data[(band, hour)] = val
        max_val = max(max_val, val)


def val_to_color(val):
    if val == 0:
        return (20, 22, 30)
    t = val / max(max_val, 1)
    if t < 0.33:
        r, g, b = 20 + int(t * 3 * 40), 30 + int(t * 3 * 80), 60 + int(t * 3 * 60)
    elif t < 0.66:
        tt = (t - 0.33) * 3
        r, g, b = 60 + int(tt * 140), 110 + int(tt * 110), 120 - int(tt * 60)
    else:
        tt = (t - 0.66) * 3
        r, g, b = 200 + int(tt * 55), 220 - int(tt * 40), 60 - int(tt * 30)
    return (min(255, r), min(255, g), min(255, b))


img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
    font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 10)
    font_xs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 9)
except OSError:
    font = font_sm = font_xs = ImageFont.load_default()

MARGIN_TOP = 56
MARGIN_LEFT = 52
MARGIN_RIGHT = 20
MARGIN_BOTTOM = 40
grid_w = W - MARGIN_LEFT - MARGIN_RIGHT
grid_h = H - MARGIN_TOP - MARGIN_BOTTOM
cell_w = grid_w / 24
cell_h = grid_h / len(BANDS)

for bi, band in enumerate(BANDS):
    for hi, hour in enumerate(HOURS):
        val = data[(band, hour)]
        color = val_to_color(val)
        x = MARGIN_LEFT + hi * cell_w
        y = MARGIN_TOP + bi * cell_h
        draw.rectangle([x + 1, y + 1, x + cell_w - 1, y + cell_h - 1], fill=color)
        if val > 0:
            draw.text((x + cell_w / 2 - 4, y + cell_h / 2 - 5), str(val), fill=(220, 230, 240), font=font_xs)

for bi, band in enumerate(BANDS):
    y = MARGIN_TOP + bi * cell_h + cell_h / 2 - 6
    draw.text((4, y), band, fill=LABEL_COLOR, font=font_sm)

for hi in range(0, 24, 2):
    x = MARGIN_LEFT + hi * cell_w + cell_w - 2
    draw.text((x, MARGIN_TOP - 14), f"{hi:02d}", fill=LABEL_COLOR, font=font_xs)

draw.text((MARGIN_LEFT + grid_w / 2 - 60, MARGIN_TOP - 28), "Hour (UTC)", fill=LABEL_COLOR, font=font_sm)

draw.rectangle([(0, 0), (W, 38)], fill=(10, 12, 18))
draw.text((12, 10), "PROPAGATION MATRIX", fill=LABEL_COLOR, font=font)
draw.text((W - 240, 12), "Band x Hour | 30-day window", fill=(80, 220, 120), font=font_sm)

lx = MARGIN_LEFT
ly = H - 28
draw.text((lx, ly), "Intensity:", fill=LABEL_COLOR, font=font_xs)
lx += 65
for label, val in [("None", 0), ("Low", 3), ("Med", 7), ("High", 12), ("Peak", 15)]:
    color = val_to_color(val)
    draw.rectangle([lx, ly + 1, lx + 14, ly + 13], fill=color, outline=GRID_LINE)
    draw.text((lx + 18, ly + 1), label, fill=LABEL_COLOR, font=font_xs)
    lx += 55

img.save("/home/user/carrier_wave/mockups/heatmap_matrix.png")
print("Saved heatmap_matrix.png")
