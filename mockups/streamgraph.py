"""Streamgraph — Band Tides showing band activity over time."""
import math
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)
W, H = 800, 500
BG = (14, 16, 22)
LABEL_COLOR = (140, 150, 180)

BANDS = [
    ("80m", (200, 120, 60)),
    ("40m", (220, 180, 50)),
    ("20m", (60, 130, 255)),
    ("15m", (100, 200, 100)),
    ("10m", (180, 100, 220)),
]

MONTHS = 12
POINTS = MONTHS * 4  # weekly data points


def smooth(data, window=3):
    result = []
    for i in range(len(data)):
        start = max(0, i - window)
        end = min(len(data), i + window + 1)
        result.append(sum(data[start:end]) / (end - start))
    return result


# Generate band activity over a year (simulating solar cycle / seasonal propagation)
band_data = {}
for band_name, color in BANDS:
    raw = []
    for week in range(POINTS):
        month = week / 4
        base = {
            "80m": 8 + 6 * math.cos(2 * math.pi * month / 12),  # winter peak
            "40m": 15 + 5 * math.sin(2 * math.pi * (month - 2) / 12),
            "20m": 25 + 15 * math.sin(2 * math.pi * (month - 1) / 12),  # summer peak
            "15m": 12 + 10 * math.sin(2 * math.pi * (month + 1) / 12),
            "10m": 6 + 8 * math.sin(2 * math.pi * month / 12),
        }[band_name]
        val = max(0, base + random.gauss(0, 3))
        # Contest spikes
        if week % 4 == 2:
            val *= 1.5
        raw.append(val)
    band_data[band_name] = smooth(raw, 2)

img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
    font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 11)
    font_xs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 9)
except OSError:
    font = font_sm = font_xs = ImageFont.load_default()

MARGIN_TOP = 56
MARGIN_BOTTOM = 40
MARGIN_LEFT = 30
MARGIN_RIGHT = 30
plot_w = W - MARGIN_LEFT - MARGIN_RIGHT
plot_h = H - MARGIN_TOP - MARGIN_BOTTOM
center_y = MARGIN_TOP + plot_h / 2

# Compute stream positions (symmetric around center)
# Stack bands, then center the stack
all_totals = []
for wi in range(POINTS):
    total = sum(band_data[name][wi] for name, _ in BANDS)
    all_totals.append(total)

max_total = max(all_totals) if all_totals else 1
scale = (plot_h * 0.8) / max_total

# For each x position, compute cumulative y positions
for wi in range(POINTS - 1):
    x1 = MARGIN_LEFT + wi * plot_w / (POINTS - 1)
    x2 = MARGIN_LEFT + (wi + 1) * plot_w / (POINTS - 1)

    # Center the stream
    total1 = sum(band_data[name][wi] for name, _ in BANDS) * scale
    total2 = sum(band_data[name][wi + 1] for name, _ in BANDS) * scale
    y_start1 = center_y - total1 / 2
    y_start2 = center_y - total2 / 2

    cum1 = y_start1
    cum2 = y_start2
    for band_name, color in BANDS:
        h1 = band_data[band_name][wi] * scale
        h2 = band_data[band_name][wi + 1] * scale

        # Draw filled polygon for this slice
        polygon = [
            (x1, cum1),
            (x2, cum2),
            (x2, cum2 + h2),
            (x1, cum1 + h1),
        ]
        # Darken slightly for depth
        alpha = 0.7
        c = (int(color[0] * alpha), int(color[1] * alpha), int(color[2] * alpha))
        draw.polygon(polygon, fill=c)

        # Top edge highlight
        draw.line([(x1, cum1), (x2, cum2)], fill=color, width=1)

        cum1 += h1
        cum2 += h2

# Band labels (positioned at their widest point)
for band_name, color in BANDS:
    max_wi = max(range(POINTS), key=lambda i: band_data[band_name][i])
    x = MARGIN_LEFT + max_wi * plot_w / (POINTS - 1)

    # Find y position at this x
    total = sum(band_data[name][max_wi] for name, _ in BANDS) * scale
    y_start = center_y - total / 2
    cum_y = y_start
    for bn, bc in BANDS:
        h = band_data[bn][max_wi] * scale
        if bn == band_name:
            label_y = cum_y + h / 2 - 5
            break
        cum_y += h

    draw.text((x - 10, label_y), band_name, fill=(240, 245, 255), font=font_xs)

# Month labels
MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
for mi, name in enumerate(MONTH_NAMES):
    x = MARGIN_LEFT + (mi * 4 + 2) * plot_w / (POINTS - 1)
    draw.text((x - 8, H - MARGIN_BOTTOM + 8), name, fill=(80, 85, 100), font=font_xs)

# Header
draw.rectangle([(0, 0), (W, 38)], fill=(10, 12, 18))
draw.text((12, 10), "BAND TIDES", fill=LABEL_COLOR, font=font)
draw.text((W - 280, 12), "Band activity over 12 months", fill=(80, 220, 120), font=font_sm)

img.save("/home/user/carrier_wave/mockups/streamgraph.png")
print("Saved streamgraph.png")
