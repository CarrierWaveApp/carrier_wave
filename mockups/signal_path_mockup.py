"""Signal Path mockup — geodesic arcs from home QTH to QSO locations."""

import math
import random
from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 800, 600
BG = (18, 18, 24)
ACCENT_BLUE = (60, 130, 255)
GREEN_PULSE = (80, 220, 120)
SUBTLE_GRID = (40, 40, 55)
LABEL_COLOR = (180, 180, 200)
DIM_LAND = (30, 35, 45)

random.seed(42)


def lat_lon_to_xy(lat, lon, center_lat=39.0, center_lon=-98.0):
    scale_x = WIDTH / 360
    scale_y = HEIGHT / 180
    x = (lon - center_lon + 180) * scale_x
    y = (90 - lat + center_lat - 40) * scale_y
    return int(x), int(y)


def draw_arc(draw, start, end, color, width=2, segments=30):
    sx, sy = start
    ex, ey = end
    mx = (sx + ex) / 2
    my = (sy + ey) / 2
    dist = math.sqrt((ex - sx) ** 2 + (ey - sy) ** 2)
    lift = min(dist * 0.3, 80)
    cy = my - lift

    points = []
    for i in range(segments + 1):
        t = i / segments
        bx = (1 - t) ** 2 * sx + 2 * (1 - t) * t * mx + t**2 * ex
        by = (1 - t) ** 2 * sy + 2 * (1 - t) * t * cy + t**2 * ey
        points.append((bx, by))

    for i in range(len(points) - 1):
        alpha = 0.4 + 0.6 * (i / len(points))
        r, g, b = color
        c = (int(r * alpha), int(g * alpha), int(b * alpha))
        draw.line([points[i], points[i + 1]], fill=c, width=width)


def draw_glow_dot(draw, pos, color, radius=5):
    x, y = pos
    for r in range(radius + 6, radius, -1):
        alpha = 0.15
        c = (int(color[0] * alpha), int(color[1] * alpha), int(color[2] * alpha))
        draw.ellipse([x - r, y - r, x + r, y + r], fill=c)
    draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=color)


BAND_COLORS = {
    "160m": (180, 80, 80),
    "80m": (200, 120, 60),
    "40m": (220, 180, 50),
    "20m": ACCENT_BLUE,
    "15m": (100, 200, 100),
    "10m": (180, 100, 220),
    "6m": (220, 80, 180),
}

QSOS_MANY = [
    (51.5, -0.1, "20m", "G4ABC"),
    (48.8, 2.3, "20m", "F5DEF"),
    (52.5, 13.4, "15m", "DL1GH"),
    (35.7, 139.7, "20m", "JA1XYZ"),
    (-33.9, 151.2, "20m", "VK2ABC"),
    (55.7, 37.6, "40m", "RA3DEF"),
    (40.4, -3.7, "15m", "EA4GH"),
    (59.3, 18.1, "20m", "SM0IJK"),
    (-22.9, -43.2, "10m", "PY1LMN"),
    (19.4, -99.1, "10m", "XE1OPQ"),
    (43.6, -79.4, "40m", "VE3RST"),
    (64.1, -21.9, "20m", "TF3UVW"),
    (37.6, 127.0, "15m", "HL1XYZ"),
    (1.3, 103.8, "20m", "9V1ABC"),
    (28.6, 77.2, "20m", "VU2DEF"),
    (-1.3, 36.8, "15m", "5Z4GHI"),
    (33.9, -118.2, "40m", "W6JKL"),
    (47.6, -122.3, "40m", "W7MNO"),
    (25.8, -80.2, "80m", "W4PQR"),
    (41.9, -87.6, "80m", "W9STU"),
    (45.5, -73.6, "40m", "VE2VWX"),
    (53.3, -6.3, "20m", "EI7YZA"),
    (60.2, 25.0, "15m", "OH2BCD"),
    (38.7, -9.1, "20m", "CT1EFG"),
]

QSOS_FEW = QSOS_MANY[:7]

HOME = (39.0, -98.0)
HOME_XY = lat_lon_to_xy(*HOME)


def render(qsos, filename, title):
    img = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(img)

    for lat in range(-60, 90, 30):
        _, y = lat_lon_to_xy(lat, 0)
        draw.line([(0, y), (WIDTH, y)], fill=SUBTLE_GRID, width=1)
    for lon in range(-180, 180, 30):
        x, _ = lat_lon_to_xy(0, lon)
        draw.line([(x, 0), (x, HEIGHT)], fill=SUBTLE_GRID, width=1)

    continents = [
        [(lat_lon_to_xy(50, -130)), (lat_lon_to_xy(25, -65))],
        [(lat_lon_to_xy(12, -82)), (lat_lon_to_xy(-55, -35))],
        [(lat_lon_to_xy(60, -10)), (lat_lon_to_xy(36, 40))],
        [(lat_lon_to_xy(37, -18)), (lat_lon_to_xy(-35, 52))],
        [(lat_lon_to_xy(55, 60)), (lat_lon_to_xy(10, 145))],
        [(lat_lon_to_xy(-10, 110)), (lat_lon_to_xy(-40, 155))],
    ]
    for tl, br in continents:
        draw.rectangle([tl, br], fill=DIM_LAND, outline=(45, 50, 60))

    for lat, lon, band, call in qsos:
        end = lat_lon_to_xy(lat, lon)
        color = BAND_COLORS.get(band, ACCENT_BLUE)
        draw_arc(draw, HOME_XY, end, color, width=2)

    for lat, lon, band, call in qsos:
        pos = lat_lon_to_xy(lat, lon)
        color = BAND_COLORS.get(band, ACCENT_BLUE)
        draw_glow_dot(draw, pos, color, radius=4)

    draw_glow_dot(draw, HOME_XY, GREEN_PULSE, radius=7)

    draw.rectangle([(0, 0), (WIDTH, 36)], fill=(12, 12, 18))
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
        font_small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 11)
    except OSError:
        font = ImageFont.load_default()
        font_small = font
    draw.text((12, 10), title, fill=LABEL_COLOR, font=font)
    draw.text((WIDTH - 180, 10), f"{len(qsos)} QSOs", fill=GREEN_PULSE, font=font_small)

    ly = HEIGHT - 24
    lx = 12
    for band, color in BAND_COLORS.items():
        draw.ellipse([lx, ly, lx + 8, ly + 8], fill=color)
        draw.text((lx + 12, ly - 2), band, fill=LABEL_COLOR, font=font_small)
        lx += 55

    draw.text(
        (WIDTH - 200, HEIGHT - 24),
        "Skin: Carrier Wave Classic",
        fill=(100, 100, 120),
        font=font_small,
    )

    img.save(filename)
    print(f"Saved {filename}")


render(QSOS_MANY, "/home/user/carrier_wave/mockups/signal_path_many.png", "SIGNAL PATH")
render(QSOS_FEW, "/home/user/carrier_wave/mockups/signal_path_few.png", "SIGNAL PATH")
