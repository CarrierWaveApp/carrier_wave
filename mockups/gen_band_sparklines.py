"""Small Multiples — Per-band sparkline dashboard."""
import math
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)
W, H = 800, 600
BG = (14, 16, 22)
LABEL = (140, 150, 180)

BANDS = ["160m", "80m", "40m", "20m", "15m", "10m", "6m"]
BAND_COLORS = {
    "160m": (180, 80, 80), "80m": (200, 120, 60), "40m": (220, 180, 50),
    "20m": (60, 130, 255), "15m": (100, 200, 100), "10m": (180, 100, 220),
    "6m": (220, 80, 180),
}

DAYS = 90


def gen_data(band):
    base = {"160m": 2, "80m": 4, "40m": 8, "20m": 15, "15m": 10, "10m": 6, "6m": 2}
    b = base.get(band, 5)
    data = []
    val = b
    for day in range(DAYS):
        seasonal = math.sin(day / 90 * math.pi) * b * 0.5
        weekend = 2.0 if day % 7 in (5, 6) else 1.0
        contest = 4.0 if day in (14, 15, 56, 57) else 1.0
        noise = random.gauss(0, b * 0.3)
        val = max(0, b + seasonal + (weekend - 1) * b * 0.3 + (contest - 1) * b + noise)
        data.append(val)
    return data


def render(filename):
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 13)
        font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 10)
        font_xs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 9)
    except OSError:
        font = font_sm = font_xs = ImageFont.load_default()

    draw.rectangle([(0, 0), (W, 38)], fill=(10, 12, 18))
    draw.text((12, 10), "BAND DASHBOARD  —  Last 90 Days", fill=LABEL, font=font)

    ml, mt = 70, 50
    panel_w = W - ml - 20
    panel_h = (H - mt - 20) / len(BANDS)

    all_data = {band: gen_data(band) for band in BANDS}
    global_max = max(max(d) for d in all_data.values())

    for bi, band in enumerate(BANDS):
        data = all_data[band]
        py = mt + bi * panel_h
        color = BAND_COLORS[band]

        draw.text((8, py + panel_h / 2 - 6), band, fill=color, font=font_sm)
        total = int(sum(data))
        draw.text((8, py + panel_h / 2 + 8), f"{total}", fill=(80, 85, 100), font=font_xs)

        draw.line([(ml, py + panel_h - 4), (ml + panel_w, py + panel_h - 4)],
                  fill=(25, 28, 38), width=1)

        chart_h = panel_h - 12
        points = []
        for di, val in enumerate(data):
            x = ml + (di / (DAYS - 1)) * panel_w
            y = py + chart_h - (val / global_max) * (chart_h - 4) + 2
            points.append((x, y))

        fill_points = list(points) + [(ml + panel_w, py + chart_h + 2), (ml, py + chart_h + 2)]
        r, g, b = color
        fill_color = (r // 8, g // 8, b // 8)
        draw.polygon(fill_points, fill=fill_color)

        for idx in range(len(points) - 1):
            draw.line([points[idx], points[idx + 1]], fill=color, width=2)

        peak_val = max(data)
        peak_idx = data.index(peak_val)
        px, py_peak = points[peak_idx]
        draw.ellipse([px - 3, py_peak - 3, px + 3, py_peak + 3], fill=color)

    month_labels = ["Jan", "Feb", "Mar"]
    for mi, label in enumerate(month_labels):
        x = ml + (mi * 30 / DAYS) * panel_w
        draw.text((x, H - 16), label, fill=(60, 65, 80), font=font_xs)

    img.save(filename)
    print(f"Saved {filename}")


render("/home/user/carrier_wave/mockups/band_sparklines.png")
