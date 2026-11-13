"""3D Globe — Simulated globe with QSO arcs (2D rendering of 3D concept)."""
import math
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)
W, H = 800, 800
CENTER = (W // 2, H // 2)
GLOBE_R = 300
BG = (6, 8, 16)
LABEL_COLOR = (140, 150, 180)
OCEAN = (12, 18, 35)
LAND = (25, 40, 55)

BAND_COLORS = {
    "20m": (60, 130, 255), "40m": (220, 180, 50), "15m": (100, 200, 100),
    "10m": (180, 100, 220), "80m": (200, 120, 60),
}

HOME_LAT, HOME_LON = 39.0, -98.0
ROT_LON = -80.0  # Globe rotation to center on Americas/Atlantic

CONTACTS = [
    (51.5, -0.1, "20m"), (48.8, 2.3, "20m"), (52.5, 13.4, "15m"),
    (35.7, 139.7, "20m"), (55.7, 37.6, "40m"), (40.4, -3.7, "15m"),
    (43.6, -79.4, "40m"), (33.9, -118.2, "40m"), (25.8, -80.2, "80m"),
    (-22.9, -43.2, "10m"), (19.4, -99.1, "10m"), (64.1, -21.9, "20m"),
    (28.6, 77.2, "20m"), (-33.9, 151.2, "20m"),
]


def project_3d(lat, lon):
    """Orthographic projection centered on ROT_LON."""
    lat_r = math.radians(lat)
    lon_r = math.radians(lon - ROT_LON)
    x = GLOBE_R * math.cos(lat_r) * math.sin(lon_r)
    y = -GLOBE_R * math.sin(lat_r)
    z = GLOBE_R * math.cos(lat_r) * math.cos(lon_r)
    return CENTER[0] + x, CENTER[1] + y, z > 0  # visible if z > 0


img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
    font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 10)
except OSError:
    font = font_sm = ImageFont.load_default()

# Globe background (atmosphere glow)
for gr in range(GLOBE_R + 60, GLOBE_R, -1):
    alpha = 0.02 * (GLOBE_R + 60 - gr) / 60
    c = (int(30 * alpha), int(60 * alpha), int(120 * alpha))
    draw.ellipse([CENTER[0] - gr, CENTER[1] - gr, CENTER[0] + gr, CENTER[1] + gr], fill=c)

# Ocean
draw.ellipse([CENTER[0] - GLOBE_R, CENTER[1] - GLOBE_R, CENTER[0] + GLOBE_R, CENTER[1] + GLOBE_R], fill=OCEAN)

# Simplified continent outlines as filled polygons on the globe
CONTINENT_COORDS = [
    # North America (simplified outline)
    [(60, -130), (70, -100), (60, -75), (50, -60), (30, -80), (25, -100), (30, -120), (48, -125)],
    # South America
    [(10, -80), (5, -60), (-10, -40), (-25, -45), (-35, -55), (-50, -70), (-20, -70), (-5, -78)],
    # Europe
    [(70, 0), (65, 30), (55, 40), (45, 30), (38, 0), (42, -8), (48, -5), (55, -5), (60, 10)],
    # Africa
    [(35, -10), (30, 30), (10, 40), (0, 42), (-10, 40), (-30, 30), (-35, 20), (-25, 15), (-5, -5), (15, -15)],
    # Asia (partial, visible part)
    [(60, 40), (65, 80), (55, 100), (40, 120), (25, 105), (10, 100), (20, 70), (35, 45), (45, 38)],
]

for coords in CONTINENT_COORDS:
    points = []
    all_visible = True
    for lat, lon in coords:
        x, y, visible = project_3d(lat, lon)
        points.append((x, y))
        if not visible:
            all_visible = False
    if all_visible and len(points) >= 3:
        draw.polygon(points, fill=LAND, outline=(35, 55, 70))

# Grid lines
for lat in range(-60, 90, 30):
    pts = []
    for lon in range(-180, 181, 5):
        x, y, vis = project_3d(lat, lon)
        if vis:
            pts.append((x, y))
        else:
            if len(pts) > 1:
                draw.line(pts, fill=(18, 28, 42), width=1)
            pts = []
    if len(pts) > 1:
        draw.line(pts, fill=(18, 28, 42), width=1)

for lon in range(-180, 180, 30):
    pts = []
    for lat in range(-90, 91, 5):
        x, y, vis = project_3d(lat, lon)
        if vis:
            pts.append((x, y))
        else:
            if len(pts) > 1:
                draw.line(pts, fill=(18, 28, 42), width=1)
            pts = []
    if len(pts) > 1:
        draw.line(pts, fill=(18, 28, 42), width=1)

# Draw QSO arcs
home_x, home_y, home_vis = project_3d(HOME_LAT, HOME_LON)

for lat, lon, band in CONTACTS:
    dest_x, dest_y, dest_vis = project_3d(lat, lon)
    if not (home_vis and dest_vis):
        continue

    color = BAND_COLORS.get(band, (60, 130, 255))

    # Arc with height proportional to distance
    dist = math.sqrt((dest_x - home_x) ** 2 + (dest_y - home_y) ** 2)
    height = min(dist * 0.4, 120)
    mid_x = (home_x + dest_x) / 2
    mid_y = (home_y + dest_y) / 2 - height

    # Bezier arc
    steps = 30
    pts = []
    for si in range(steps + 1):
        t = si / steps
        bx = (1 - t) ** 2 * home_x + 2 * (1 - t) * t * mid_x + t**2 * dest_x
        by = (1 - t) ** 2 * home_y + 2 * (1 - t) * t * mid_y + t**2 * dest_y
        pts.append((bx, by))

    # Draw with gradient alpha
    for si in range(len(pts) - 1):
        t = si / len(pts)
        alpha = 0.3 + 0.5 * math.sin(t * math.pi)
        c = (int(color[0] * alpha), int(color[1] * alpha), int(color[2] * alpha))
        draw.line([pts[si], pts[si + 1]], fill=c, width=2)

    # Destination dot
    draw.ellipse([dest_x - 3, dest_y - 3, dest_x + 3, dest_y + 3], fill=color)

# Home station
if home_vis:
    for gr in range(15, 0, -1):
        alpha = 0.05 * (15 - gr) / 15
        draw.ellipse([home_x - gr, home_y - gr, home_x + gr, home_y + gr], fill=(int(80 * alpha), int(220 * alpha), int(120 * alpha)))
    draw.ellipse([home_x - 5, home_y - 5, home_x + 5, home_y + 5], fill=(80, 220, 120))

# Ionosphere shell hint
for angle in range(0, 360, 1):
    rad = math.radians(angle)
    iono_r = GLOBE_R + 40
    ix = CENTER[0] + iono_r * math.cos(rad)
    iy = CENTER[1] + iono_r * math.sin(rad)
    alpha = 0.03 + 0.02 * math.sin(angle * 0.1)
    c = (int(40 * alpha), int(80 * alpha), int(180 * alpha))
    draw.ellipse([ix - 1, iy - 1, ix + 1, iy + 1], fill=c)

# Header
draw.rectangle([(0, 0), (W, 38)], fill=(4, 5, 12))
draw.text((12, 10), "GLOBE VIEW", fill=LABEL_COLOR, font=font)
draw.text((W - 220, 12), "SceneKit + ionosphere", fill=(80, 220, 120), font=font_sm)

# Legend
lx = 12
ly = H - 24
for band, color in BAND_COLORS.items():
    draw.ellipse([lx, ly, lx + 8, ly + 8], fill=color)
    draw.text((lx + 12, ly - 1), band, fill=LABEL_COLOR, font=font_sm)
    lx += 52

img.save("/home/user/carrier_wave/mockups/globe_3d.png")
print("Saved globe_3d.png")
