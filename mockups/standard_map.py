"""Standard Themed Map — World map rendered from simplified SVG-style coordinates."""
import math
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)

# Simplified world coastline coordinates (major landmasses as polygon outlines)
# Format: list of (lat, lon) tuples for each continent outline
COASTLINES = {
    "North America": [
        (72, -168), (71, -156), (70, -142), (68, -136), (64, -140), (60, -140),
        (58, -136), (56, -132), (54, -130), (50, -128), (48, -124), (42, -124),
        (38, -122), (34, -120), (32, -117), (30, -114), (28, -112), (26, -110),
        (24, -106), (22, -100), (20, -97), (18, -96), (16, -92), (18, -88),
        (20, -87), (22, -86), (24, -82), (25, -80), (26, -80), (28, -82),
        (30, -84), (30, -88), (30, -90), (32, -92), (30, -94), (28, -96),
        (26, -98), (28, -96), (30, -94), (34, -76), (36, -76), (38, -74),
        (40, -72), (42, -70), (44, -66), (46, -60), (48, -56), (50, -58),
        (52, -56), (54, -58), (56, -60), (58, -64), (60, -64), (62, -68),
        (64, -68), (66, -72), (68, -80), (70, -86), (72, -96), (74, -100),
        (76, -120), (74, -140), (72, -156), (72, -168),
    ],
    "South America": [
        (12, -72), (10, -62), (6, -60), (4, -52), (2, -50), (0, -50),
        (-4, -44), (-8, -36), (-12, -38), (-16, -40), (-20, -40), (-24, -46),
        (-28, -48), (-32, -52), (-36, -56), (-40, -62), (-44, -66), (-48, -66),
        (-52, -70), (-54, -68), (-54, -72), (-50, -76), (-46, -76), (-42, -72),
        (-38, -72), (-34, -72), (-30, -72), (-26, -70), (-22, -70), (-18, -72),
        (-14, -76), (-10, -78), (-6, -80), (-2, -80), (2, -78), (6, -76),
        (10, -76), (12, -72),
    ],
    "Europe": [
        (36, -8), (38, -8), (42, -8), (44, -2), (46, 0), (48, -4),
        (48, 2), (50, 2), (52, 4), (54, 8), (56, 8), (56, 12),
        (58, 12), (60, 6), (62, 6), (64, 10), (66, 14), (68, 16),
        (70, 20), (70, 28), (68, 28), (66, 26), (64, 24), (62, 22),
        (60, 22), (58, 24), (56, 20), (54, 18), (52, 14), (50, 14),
        (48, 16), (46, 14), (44, 12), (42, 14), (40, 26), (38, 24),
        (36, 28), (36, 22), (38, 20), (40, 20), (38, 14), (36, 12),
        (38, 8), (36, 0), (36, -4), (36, -8),
    ],
    "Africa": [
        (36, -4), (34, -2), (32, 0), (30, 2), (28, 10), (24, 14),
        (20, 18), (16, 16), (14, -16), (12, -16), (8, -14), (6, -10),
        (4, -8), (4, 6), (2, 10), (0, 10), (-2, 12), (-4, 12),
        (-8, 14), (-12, 16), (-16, 18), (-20, 24), (-24, 28), (-26, 32),
        (-30, 30), (-34, 26), (-34, 18), (-32, 18), (-28, 16), (-24, 14),
        (-20, 14), (-16, 12), (-12, 14), (-8, 12), (-4, 8), (0, 4),
        (4, 2), (8, 0), (12, -4), (16, -16), (20, -18), (24, -14),
        (28, -10), (30, -8), (32, -4), (34, -2), (36, -4),
    ],
    "Asia": [
        (42, 28), (44, 40), (42, 44), (40, 44), (38, 48), (36, 52),
        (32, 48), (28, 48), (24, 44), (22, 40), (16, 44), (12, 44),
        (8, 76), (10, 80), (14, 80), (18, 84), (22, 88), (22, 92),
        (20, 96), (16, 100), (10, 104), (6, 100), (2, 104), (-2, 106),
        (-6, 106), (-8, 112), (-8, 116), (-6, 120), (0, 118), (4, 118),
        (8, 116), (12, 110), (18, 108), (22, 108), (24, 112), (28, 120),
        (32, 122), (34, 126), (36, 128), (38, 130), (40, 132), (44, 136),
        (46, 142), (48, 144), (50, 140), (52, 140), (54, 138), (56, 136),
        (58, 136), (60, 132), (62, 128), (64, 120), (66, 100), (68, 80),
        (70, 70), (68, 60), (66, 50), (62, 40), (56, 38), (52, 36),
        (50, 38), (48, 36), (46, 34), (44, 30), (42, 28),
    ],
    "Australia": [
        (-12, 132), (-14, 126), (-18, 122), (-22, 114), (-26, 114),
        (-30, 116), (-34, 118), (-36, 136), (-38, 144), (-38, 148),
        (-34, 152), (-30, 154), (-26, 152), (-22, 150), (-18, 146),
        (-16, 146), (-12, 142), (-12, 136), (-12, 132),
    ],
}

BAND_COLORS = {
    "20m": (60, 130, 255), "40m": (220, 180, 50), "15m": (100, 200, 100),
    "10m": (180, 100, 220), "80m": (200, 120, 60),
}


def render_map(contacts, filename, title, theme):
    """Render a themed map."""
    wi, hi = 800, 480

    if theme == "dark":
        bg = (12, 14, 22)
        ocean = (12, 14, 22)
        land_fill = (25, 32, 45)
        land_stroke = (35, 45, 60)
        grid_color = (18, 22, 32)
        text_color = (140, 150, 180)
        accent = (80, 220, 120)
    elif theme == "midnight":
        bg = (6, 4, 18)
        ocean = (6, 4, 18)
        land_fill = (18, 14, 35)
        land_stroke = (30, 25, 55)
        grid_color = (12, 10, 28)
        text_color = (120, 110, 170)
        accent = (160, 120, 255)
    elif theme == "warm":
        bg = (24, 18, 14)
        ocean = (24, 18, 14)
        land_fill = (40, 30, 22)
        land_stroke = (60, 45, 32)
        grid_color = (30, 24, 18)
        text_color = (180, 150, 120)
        accent = (255, 180, 60)
    else:  # light
        bg = (235, 238, 245)
        ocean = (220, 228, 240)
        land_fill = (200, 208, 218)
        land_stroke = (180, 188, 198)
        grid_color = (210, 215, 225)
        text_color = (80, 85, 100)
        accent = (40, 160, 80)

    img = Image.new("RGB", (wi, hi), bg)
    draw = ImageDraw.Draw(img)

    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
        font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 10)
        font_xs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 8)
    except OSError:
        font = font_sm = font_xs = ImageFont.load_default()

    margin_top = 44
    margin_bottom = 32
    map_w = wi
    map_h = hi - margin_top - margin_bottom

    def to_xy(lat, lon):
        x = (lon + 180) / 360 * map_w
        y = margin_top + (90 - lat) / 180 * map_h
        return x, y

    # Grid lines
    for lat in range(-60, 90, 30):
        _, y = to_xy(lat, 0)
        draw.line([(0, y), (wi, y)], fill=grid_color, width=1)
    for lon in range(-180, 180, 30):
        x, _ = to_xy(0, lon)
        draw.line([(x, margin_top), (x, hi - margin_bottom)], fill=grid_color, width=1)

    # Draw landmasses
    for name, coords in COASTLINES.items():
        points = [to_xy(lat, lon) for lat, lon in coords]
        if len(points) >= 3:
            draw.polygon(points, fill=land_fill, outline=land_stroke)

    # Home QTH
    home = (39.0, -98.0)
    hx, hy = to_xy(*home)

    # Draw QSO arcs
    for lat, lon, band, call in contacts:
        dx, dy = to_xy(lat, lon)
        color = BAND_COLORS.get(band, (60, 130, 255))

        # Bezier arc
        mx = (hx + dx) / 2
        dist = math.sqrt((dx - hx) ** 2 + (dy - hy) ** 2)
        my = (hy + dy) / 2 - min(dist * 0.3, 60)

        steps = 25
        pts = []
        for si in range(steps + 1):
            t = si / steps
            bx = (1 - t) ** 2 * hx + 2 * (1 - t) * t * mx + t**2 * dx
            by = (1 - t) ** 2 * hy + 2 * (1 - t) * t * my + t**2 * dy
            pts.append((bx, by))

        for si in range(len(pts) - 1):
            alpha = 0.3 + 0.5 * math.sin(si / len(pts) * math.pi)
            c = (int(color[0] * alpha), int(color[1] * alpha), int(color[2] * alpha))
            draw.line([pts[si], pts[si + 1]], fill=c, width=2)

        # Endpoint
        draw.ellipse([dx - 3, dy - 3, dx + 3, dy + 3], fill=color)

    # Home glow
    for gr in range(12, 0, -1):
        alpha = 0.05 * (12 - gr) / 12
        gc = (int(accent[0] * alpha * 3), int(accent[1] * alpha * 3), int(accent[2] * alpha * 3))
        draw.ellipse([hx - gr, hy - gr, hx + gr, hy + gr], fill=gc)
    draw.ellipse([hx - 5, hy - 5, hx + 5, hy + 5], fill=accent)

    # Header
    draw.rectangle([(0, 0), (wi, 38)], fill=tuple(max(0, c - 4) for c in bg))
    draw.text((12, 10), title, fill=text_color, font=font)
    draw.text((wi - 200, 12), f"{len(contacts)} QSOs | {theme}", fill=accent, font=font_sm)

    # Legend
    lx = 12
    ly = hi - 24
    for band, color in BAND_COLORS.items():
        draw.ellipse([lx, ly, lx + 8, ly + 8], fill=color)
        draw.text((lx + 12, ly - 1), band, fill=text_color, font=font_xs)
        lx += 48

    img.save(filename)
    print(f"Saved {filename}")


CONTACTS_MANY = [
    (51.5, -0.1, "20m", "G4ABC"), (48.8, 2.3, "20m", "F5DEF"), (52.5, 13.4, "15m", "DL1GH"),
    (35.7, 139.7, "20m", "JA1XYZ"), (-33.9, 151.2, "20m", "VK2ABC"), (55.7, 37.6, "40m", "RA3DEF"),
    (40.4, -3.7, "15m", "EA4GH"), (59.3, 18.1, "20m", "SM0IJK"), (-22.9, -43.2, "10m", "PY1LMN"),
    (19.4, -99.1, "10m", "XE1OPQ"), (43.6, -79.4, "40m", "VE3RST"), (64.1, -21.9, "20m", "TF3UVW"),
    (37.6, 127.0, "15m", "HL1XYZ"), (1.3, 103.8, "20m", "9V1ABC"), (28.6, 77.2, "20m", "VU2DEF"),
    (-1.3, 36.8, "15m", "5Z4GHI"), (33.9, -118.2, "40m", "W6JKL"), (47.6, -122.3, "40m", "W7MNO"),
    (25.8, -80.2, "80m", "W4PQR"), (41.9, -87.6, "80m", "W9STU"),
]

render_map(CONTACTS_MANY, "/home/user/carrier_wave/mockups/standard_map_dark.png", "SIGNAL PATH", "dark")
render_map(CONTACTS_MANY, "/home/user/carrier_wave/mockups/standard_map_midnight.png", "SIGNAL PATH", "midnight")
render_map(CONTACTS_MANY, "/home/user/carrier_wave/mockups/standard_map_warm.png", "SIGNAL PATH", "warm")
render_map(CONTACTS_MANY, "/home/user/carrier_wave/mockups/standard_map_light.png", "SIGNAL PATH", "light")
