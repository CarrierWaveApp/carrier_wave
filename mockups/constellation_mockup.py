"""Radio Constellation mockup — QSOs as stars in an abstract polar chart."""

import math
import random
from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 800, 800
CENTER = (WIDTH // 2, HEIGHT // 2)
MAX_RADIUS = 340
BG = (8, 10, 20)
GRID_COLOR = (25, 30, 50)
LABEL_COLOR = (140, 150, 180)
CALLSIGN_COLOR = (100, 120, 160)

random.seed(42)

BAND_COLORS = {
    "160m": (180, 80, 80),
    "80m": (200, 120, 60),
    "40m": (220, 180, 50),
    "20m": (60, 130, 255),
    "15m": (100, 200, 100),
    "10m": (180, 100, 220),
    "6m": (220, 80, 180),
}

QSOS_MANY = [
    (45, 6000, 599, "20m", "G4ABC"),
    (52, 6200, 579, "20m", "F5DEF"),
    (40, 7000, 559, "15m", "DL1GH"),
    (335, 10500, 539, "20m", "JA1XYZ"),
    (250, 16000, 519, "20m", "VK2ABC"),
    (30, 8500, 599, "40m", "RA3DEF"),
    (55, 7200, 579, "15m", "EA4GH"),
    (25, 7000, 569, "20m", "SM0IJK"),
    (165, 8000, 559, "10m", "PY1LMN"),
    (195, 3200, 589, "10m", "XE1OPQ"),
    (0, 1200, 599, "40m", "VE3RST"),
    (30, 4500, 549, "20m", "TF3UVW"),
    (330, 11000, 559, "15m", "HL1XYZ"),
    (320, 15000, 529, "20m", "9V1ABC"),
    (15, 12500, 539, "20m", "VU2DEF"),
    (65, 12000, 559, "15m", "5Z4GHI"),
    (270, 2000, 599, "40m", "W6JKL"),
    (300, 2500, 589, "40m", "W7MNO"),
    (160, 1800, 599, "80m", "W4PQR"),
    (210, 1400, 589, "80m", "W9STU"),
    (12, 900, 599, "40m", "VE2VWX"),
    (45, 5000, 579, "20m", "EI7YZA"),
    (28, 7500, 569, "15m", "OH2BCD"),
    (60, 5800, 579, "20m", "CT1EFG"),
]

QSOS_FEW = QSOS_MANY[:7]


def azimuth_distance_to_xy(az_deg, dist_km, max_dist=18000):
    az_rad = math.radians(az_deg - 90)
    r = (dist_km / max_dist) * MAX_RADIUS
    x = CENTER[0] + r * math.cos(az_rad)
    y = CENTER[1] + r * math.sin(az_rad)
    return int(x), int(y)


def star_brightness(rst):
    sig = int(str(rst)[-1]) if rst else 5
    return 0.3 + (sig / 9) * 0.7


def draw_star(draw, pos, color, rst, radius=None):
    x, y = pos
    brightness = star_brightness(rst)
    r, g, b = color
    c = (int(r * brightness), int(g * brightness), int(b * brightness))

    if radius is None:
        radius = 2 + int(brightness * 4)

    for gr in range(radius + 8, radius, -1):
        alpha = 0.08 * brightness
        gc = (int(r * alpha), int(g * alpha), int(b * alpha))
        draw.ellipse([x - gr, y - gr, x + gr, y + gr], fill=gc)

    draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=c)

    cr = max(1, radius // 2)
    bright = (min(255, int(r * 1.3)), min(255, int(g * 1.3)), min(255, int(b * 1.3)))
    draw.ellipse([x - cr, y - cr, x + cr, y + cr], fill=bright)


def draw_constellation_line(draw, p1, p2, color):
    alpha = 0.15
    c = (int(color[0] * alpha), int(color[1] * alpha), int(color[2] * alpha))
    draw.line([p1, p2], fill=c, width=1)


def render(qsos, filename, title):
    img = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(img)

    for _ in range(200):
        sx = random.randint(0, WIDTH)
        sy = random.randint(0, HEIGHT)
        sb = random.randint(20, 60)
        sr = random.randint(0, 1)
        draw.ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=(sb, sb, sb + 10))

    for ring in range(1, 5):
        r = int(MAX_RADIUS * ring / 4)
        draw.ellipse(
            [CENTER[0] - r, CENTER[1] - r, CENTER[0] + r, CENTER[1] + r],
            outline=GRID_COLOR,
            width=1,
        )

    for az in range(0, 360, 45):
        rad = math.radians(az - 90)
        ex = CENTER[0] + MAX_RADIUS * math.cos(rad)
        ey = CENTER[1] + MAX_RADIUS * math.sin(rad)
        draw.line([CENTER, (int(ex), int(ey))], fill=GRID_COLOR, width=1)

    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 12)
        font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 10)
        font_title = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
    except OSError:
        font = ImageFont.load_default()
        font_sm = font
        font_title = font

    dirs = {"N": -90, "E": 0, "S": 90, "W": 180}
    for label, az in dirs.items():
        rad = math.radians(az)
        lx = CENTER[0] + (MAX_RADIUS + 20) * math.cos(rad)
        ly = CENTER[1] + (MAX_RADIUS + 20) * math.sin(rad)
        draw.text((int(lx) - 4, int(ly) - 6), label, fill=LABEL_COLOR, font=font)

    for ring, dist in [(1, "4500km"), (2, "9000km"), (3, "13500km"), (4, "18000km")]:
        r = int(MAX_RADIUS * ring / 4)
        draw.text(
            (CENTER[0] + 4, CENTER[1] - r - 14), dist, fill=(60, 65, 80), font=font_sm
        )

    positions = []
    for az, dist, rst, band, call in qsos:
        pos = azimuth_distance_to_xy(az, dist)
        positions.append((pos, band))

    for i in range(len(positions)):
        for j in range(i + 1, len(positions)):
            if positions[i][1] == positions[j][1]:
                p1, p2 = positions[i][0], positions[j][0]
                d = math.sqrt((p1[0] - p2[0]) ** 2 + (p1[1] - p2[1]) ** 2)
                if d < 200:
                    color = BAND_COLORS.get(positions[i][1], (60, 130, 255))
                    draw_constellation_line(draw, p1, p2, color)

    for az, dist, rst, band, call in qsos:
        pos = azimuth_distance_to_xy(az, dist)
        color = BAND_COLORS.get(band, (60, 130, 255))
        draw_star(draw, pos, color, rst)

    labels_to_show = qsos if len(qsos) <= 10 else qsos[:8]
    for az, dist, rst, band, call in labels_to_show:
        pos = azimuth_distance_to_xy(az, dist)
        draw.text(
            (pos[0] + 10, pos[1] - 5), call, fill=CALLSIGN_COLOR, font=font_sm
        )

    draw.ellipse(
        [CENTER[0] - 4, CENTER[1] - 4, CENTER[0] + 4, CENTER[1] + 4],
        fill=(80, 220, 120),
    )

    draw.rectangle([(0, 0), (WIDTH, 36)], fill=(5, 6, 14))
    draw.text((12, 10), title, fill=LABEL_COLOR, font=font_title)
    draw.text(
        (WIDTH - 180, 10),
        f"{len(qsos)} QSOs",
        fill=(80, 220, 120),
        font=font_sm,
    )

    ly = HEIGHT - 28
    lx = 12
    for band, color in BAND_COLORS.items():
        draw_star(draw, (lx + 4, ly + 4), color, 599, radius=3)
        draw.text((lx + 14, ly - 2), band, fill=LABEL_COLOR, font=font_sm)
        lx += 60

    draw.text(
        (WIDTH - 200, HEIGHT - 28),
        "Skin: Radio Constellation",
        fill=(60, 65, 80),
        font=font_sm,
    )

    img.save(filename)
    print(f"Saved {filename}")


render(QSOS_MANY, "/home/user/carrier_wave/mockups/constellation_many.png", "RADIO CONSTELLATION")
render(QSOS_FEW, "/home/user/carrier_wave/mockups/constellation_few.png", "RADIO CONSTELLATION")
