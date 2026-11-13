"""Sunburst Chart — Continent > Country > Band drill-down."""
import math
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)
W, H = 800, 800
CENTER = (W // 2, H // 2)
BG = (14, 16, 22)
LABEL_COLOR = (140, 150, 180)

HIERARCHY = {
    "NA": {"US": {"20m": 45, "40m": 30, "15m": 20, "80m": 15}, "CA": {"20m": 18, "40m": 12, "15m": 8}, "MX": {"10m": 5, "20m": 3}},
    "EU": {"DE": {"20m": 22, "15m": 15, "40m": 8}, "UK": {"20m": 18, "15m": 10}, "FR": {"20m": 12, "15m": 6}, "ES": {"20m": 8, "10m": 5}, "IT": {"20m": 6, "15m": 4}},
    "AS": {"JA": {"20m": 15, "15m": 8}, "KR": {"15m": 6, "20m": 4}, "IN": {"20m": 5}},
    "SA": {"BR": {"10m": 8, "20m": 5}, "AR": {"20m": 4}},
    "OC": {"VK": {"20m": 10, "15m": 4}, "ZL": {"20m": 3}},
    "AF": {"ZA": {"20m": 5}, "KE": {"15m": 2}},
}

CONTINENT_COLORS = {
    "NA": (60, 130, 255), "EU": (100, 200, 100), "AS": (220, 180, 50),
    "SA": (200, 120, 60), "OC": (180, 100, 220), "AF": (220, 80, 180),
}

R1_INNER, R1_OUTER = 60, 140
R2_INNER, R2_OUTER = 145, 240
R3_INNER, R3_OUTER = 245, 320

img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
    font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 11)
    font_xs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 9)
except OSError:
    font = font_sm = font_xs = ImageFont.load_default()


def angle_xy(angle_deg, radius):
    rad = math.radians(angle_deg - 90)
    return CENTER[0] + radius * math.cos(rad), CENTER[1] + radius * math.sin(rad)


def draw_arc_segment(start_deg, end_deg, r_inner, r_outer, color, outline=None):
    steps = max(int((end_deg - start_deg) * 2), 8)
    points_outer = []
    points_inner = []
    for si in range(steps + 1):
        a = start_deg + (end_deg - start_deg) * si / steps
        points_outer.append(angle_xy(a, r_outer))
        points_inner.append(angle_xy(a, r_inner))
    points_inner.reverse()
    polygon = points_outer + points_inner
    if len(polygon) >= 3:
        draw.polygon(polygon, fill=color, outline=outline)


def color_variant(base, factor):
    return tuple(min(255, max(0, int(c * factor))) for c in base)


# Compute totals
continent_totals = {}
for cont, countries in HIERARCHY.items():
    continent_totals[cont] = sum(sum(bands.values()) for bands in countries.values())
grand_total = sum(continent_totals.values())

# Draw rings
GAP = 1.5
current = 0

for cont, countries in HIERARCHY.items():
    cont_span = (continent_totals[cont] / grand_total) * 360
    base_color = CONTINENT_COLORS[cont]

    # Ring 1: Continent
    draw_arc_segment(current + GAP / 2, current + cont_span - GAP / 2, R1_INNER, R1_OUTER, base_color, outline=(30, 35, 45))

    # Label continent
    mid = current + cont_span / 2
    lx, ly = angle_xy(mid, (R1_INNER + R1_OUTER) / 2)
    draw.text((lx - 8, ly - 6), cont, fill=(240, 245, 255), font=font_sm)

    # Ring 2: Countries
    country_offset = current
    country_totals = {c: sum(bands.values()) for c, bands in countries.items()}
    for country, bands in countries.items():
        ctry_span = (country_totals[country] / grand_total) * 360
        ctry_color = color_variant(base_color, 0.7)
        draw_arc_segment(country_offset + GAP / 2, country_offset + ctry_span - GAP / 2, R2_INNER, R2_OUTER, ctry_color, outline=(30, 35, 45))

        if ctry_span > 6:
            mid2 = country_offset + ctry_span / 2
            lx2, ly2 = angle_xy(mid2, (R2_INNER + R2_OUTER) / 2)
            draw.text((lx2 - 6, ly2 - 5), country, fill=(220, 230, 240), font=font_xs)

        # Ring 3: Bands
        band_offset = country_offset
        band_total = sum(bands.values())
        BAND_COLORS_MAP = {
            "160m": 0.3, "80m": 0.4, "40m": 0.55, "30m": 0.6,
            "20m": 0.8, "17m": 0.75, "15m": 0.9, "12m": 0.85, "10m": 1.0, "6m": 1.1,
        }
        for band_name, band_val in bands.items():
            bnd_span = (band_val / grand_total) * 360
            bfactor = BAND_COLORS_MAP.get(band_name, 0.5)
            bnd_color = color_variant(base_color, bfactor)
            draw_arc_segment(band_offset + GAP / 4, band_offset + bnd_span - GAP / 4, R3_INNER, R3_OUTER, bnd_color, outline=(30, 35, 45))
            band_offset += bnd_span

        country_offset += ctry_span

    current += cont_span

# Center circle
draw.ellipse([CENTER[0] - R1_INNER + 5, CENTER[1] - R1_INNER + 5, CENTER[0] + R1_INNER - 5, CENTER[1] + R1_INNER - 5], fill=(20, 24, 34))
draw.text((CENTER[0] - 16, CENTER[1] - 14), "W1AW", fill=(80, 220, 120), font=font_sm)
draw.text((CENTER[0] - 22, CENTER[1] + 4), f"{grand_total} QSOs", fill=LABEL_COLOR, font=font_xs)

# Ring labels
for label, r in [("Continent", R1_OUTER + 4), ("Country", R2_OUTER + 4), ("Band", R3_OUTER + 4)]:
    lx, ly = angle_xy(355, r)
    draw.text((lx, ly), label, fill=(60, 65, 80), font=font_xs)

# Header
draw.rectangle([(0, 0), (W, 38)], fill=(10, 12, 18))
draw.text((12, 10), "CONTACT TAXONOMY", fill=LABEL_COLOR, font=font)
draw.text((W - 240, 12), "Tap to drill down", fill=(80, 220, 120), font=font_xs)

img.save("/home/user/carrier_wave/mockups/sunburst_chart.png")
print("Saved sunburst_chart.png")
