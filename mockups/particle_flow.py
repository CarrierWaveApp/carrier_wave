"""Particle Flow — Propagation wind map with flowing particles along QSO paths."""
import math
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)
W, H = 800, 500
BG = (8, 10, 18)
LABEL_COLOR = (140, 150, 180)
DIM_LAND = (18, 22, 30)

BAND_COLORS = {
    "20m": (60, 130, 255), "40m": (220, 180, 50), "15m": (100, 200, 100),
    "10m": (180, 100, 220), "80m": (200, 120, 60),
}

HOME = (39.0, -98.0)
CONTACTS = [
    (51.5, -0.1, "20m", 40), (48.8, 2.3, "20m", 30), (52.5, 13.4, "15m", 25),
    (35.7, 139.7, "20m", 15), (-33.9, 151.2, "20m", 10), (55.7, 37.6, "40m", 20),
    (40.4, -3.7, "15m", 12), (-22.9, -43.2, "10m", 8), (19.4, -99.1, "10m", 15),
    (43.6, -79.4, "40m", 35), (64.1, -21.9, "20m", 6), (33.9, -118.2, "40m", 25),
    (47.6, -122.3, "40m", 20), (25.8, -80.2, "80m", 18), (28.6, 77.2, "20m", 8),
]


def lat_lon_to_xy(lat, lon, center_lat=30.0, center_lon=-40.0):
    x = (lon - center_lon + 180) % 360 * W / 360
    y = (90 - lat) * H / 180
    return x, y


def lerp_point(p1, p2, t):
    return p1[0] + (p2[0] - p1[0]) * t, p1[1] + (p2[1] - p1[1]) * t


img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
    font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 10)
except OSError:
    font = font_sm = ImageFont.load_default()

# Simplified continent shapes
continents = [
    [(120, 80), (280, 80), (280, 220), (200, 280), (120, 220)],  # NA
    [(160, 290), (230, 290), (210, 430), (160, 430)],  # SA
    [(380, 80), (550, 80), (550, 200), (380, 240)],  # EU
    [(380, 200), (500, 200), (500, 380), (380, 380)],  # AF
    [(520, 80), (700, 80), (720, 300), (520, 300)],  # AS
    [(620, 320), (720, 320), (720, 400), (620, 400)],  # OC
]
for points in continents:
    draw.polygon(points, fill=DIM_LAND, outline=(25, 30, 40))

home_xy = lat_lon_to_xy(*HOME)

# Draw particle trails along paths
for lat, lon, band, density in CONTACTS:
    dest_xy = lat_lon_to_xy(lat, lon)
    base_color = BAND_COLORS.get(band, (60, 130, 255))

    # Great circle approximation with arc
    mid_x = (home_xy[0] + dest_xy[0]) / 2
    mid_y = (home_xy[1] + dest_xy[1]) / 2
    dist = math.sqrt((dest_xy[0] - home_xy[0]) ** 2 + (dest_xy[1] - home_xy[1]) ** 2)
    lift = min(dist * 0.15, 40)
    ctrl = (mid_x, mid_y - lift)

    # Draw multiple particle positions along the path
    num_particles = density * 2
    for pi in range(num_particles):
        # Each particle at a random position along the path
        t = random.uniform(0, 1)

        # Quadratic bezier
        bx = (1 - t) ** 2 * home_xy[0] + 2 * (1 - t) * t * ctrl[0] + t**2 * dest_xy[0]
        by = (1 - t) ** 2 * home_xy[1] + 2 * (1 - t) * t * ctrl[1] + t**2 * dest_xy[1]

        # Particle size decreases with distance from home
        size = max(1, int(3 * (1 - t * 0.5)))
        # Alpha fades toward destination
        alpha = 0.3 + 0.7 * (1 - t * 0.6)
        # Add slight random scatter
        bx += random.gauss(0, 2)
        by += random.gauss(0, 2)

        r, g, b = base_color
        c = (int(r * alpha), int(g * alpha), int(b * alpha))

        # Glow
        for gr in range(size + 4, size, -1):
            ga = alpha * 0.15
            gc = (int(r * ga), int(g * ga), int(b * ga))
            draw.ellipse([bx - gr, by - gr, bx + gr, by + gr], fill=gc)
        draw.ellipse([bx - size, by - size, bx + size, by + size], fill=c)

    # Faint path line
    steps = 30
    path_pts = []
    for si in range(steps + 1):
        t = si / steps
        px = (1 - t) ** 2 * home_xy[0] + 2 * (1 - t) * t * ctrl[0] + t**2 * dest_xy[0]
        py = (1 - t) ** 2 * home_xy[1] + 2 * (1 - t) * t * ctrl[1] + t**2 * dest_xy[1]
        path_pts.append((px, py))
    for si in range(len(path_pts) - 1):
        alpha = 0.08
        r, g, b = base_color
        c = (int(r * alpha), int(g * alpha), int(b * alpha))
        draw.line([path_pts[si], path_pts[si + 1]], fill=c, width=1)

# Home station glow
for gr in range(20, 0, -1):
    alpha = 0.03 * (20 - gr) / 20
    draw.ellipse([home_xy[0] - gr, home_xy[1] - gr, home_xy[0] + gr, home_xy[1] + gr], fill=(int(80 * alpha), int(220 * alpha), int(120 * alpha)))
draw.ellipse([home_xy[0] - 4, home_xy[1] - 4, home_xy[0] + 4, home_xy[1] + 4], fill=(80, 220, 120))

# Header
draw.rectangle([(0, 0), (W, 34)], fill=(5, 6, 14))
draw.text((12, 8), "PROPAGATION FLOW", fill=LABEL_COLOR, font=font)
draw.text((W - 160, 10), "Live particle sim", fill=(80, 220, 120), font=font_sm)

# Legend
lx = 12
ly = H - 22
for band, color in BAND_COLORS.items():
    draw.ellipse([lx, ly, lx + 8, ly + 8], fill=color)
    draw.text((lx + 12, ly - 1), band, fill=LABEL_COLOR, font=font_sm)
    lx += 52

img.save("/home/user/carrier_wave/mockups/particle_flow.png")
print("Saved particle_flow.png")
