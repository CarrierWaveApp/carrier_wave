"""Generative Data Art — Radio Bloom. Each QSO grows a petal/branch."""
import math
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)
W, H = 800, 800
CENTER = (W // 2, H // 2)
BG = (8, 8, 14)
LABEL_COLOR = (140, 150, 180)

BAND_PALETTES = {
    "160m": [(140, 50, 50), (180, 70, 70), (160, 60, 60)],
    "80m": [(180, 100, 40), (200, 120, 60), (190, 110, 50)],
    "40m": [(200, 160, 30), (220, 180, 50), (210, 170, 40)],
    "20m": [(40, 100, 220), (60, 130, 255), (50, 115, 240)],
    "15m": [(60, 170, 70), (100, 200, 100), (80, 185, 85)],
    "10m": [(150, 70, 190), (180, 100, 220), (165, 85, 205)],
}

# Generate QSO data: (angle from north, distance_km, band, rst)
QSOS = []
for _ in range(120):
    az = random.uniform(0, 360)
    dist = random.uniform(200, 18000)
    band = random.choice(["20m", "40m", "15m", "10m", "80m", "160m"])
    rst = random.choice([519, 539, 559, 569, 579, 589, 599])
    QSOS.append((az, dist, band, rst))

img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
    font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 10)
    font_xs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 8)
except OSError:
    font = font_sm = font_xs = ImageFont.load_default()

# Background: subtle radial rings
for ring in range(1, 8):
    r = ring * 50
    for angle in range(0, 360, 2):
        rad = math.radians(angle)
        x = CENTER[0] + r * math.cos(rad)
        y = CENTER[1] + r * math.sin(rad)
        draw.ellipse([x - 0.5, y - 0.5, x + 0.5, y + 0.5], fill=(15, 18, 28))


def draw_petal(qso_angle, distance, band, rst):
    """Draw a generative petal for one QSO."""
    palette = BAND_PALETTES.get(band, BAND_PALETTES["20m"])
    color = random.choice(palette)

    # Petal length proportional to distance
    length = 30 + (distance / 18000) * 280
    # Width proportional to RST signal strength
    sig = int(str(rst)[-1])
    width_factor = sig / 9.0
    petal_width = 3 + width_factor * 15

    angle_rad = math.radians(qso_angle - 90)

    # Draw curved petal with multiple segments
    segments = 20
    prev_left = None
    prev_right = None

    for si in range(segments + 1):
        t = si / segments
        # Petal shape: starts narrow, widens, then narrows
        shape = math.sin(t * math.pi) ** 0.6
        current_width = petal_width * shape

        # Position along the petal
        r = 15 + length * t
        # Add slight curve (organic feel)
        curve = math.sin(t * math.pi * 2) * 8 * (distance / 18000)
        x = CENTER[0] + r * math.cos(angle_rad) + curve * math.cos(angle_rad + math.pi / 2)
        y = CENTER[1] + r * math.sin(angle_rad) + curve * math.sin(angle_rad + math.pi / 2)

        # Left and right edges
        perp = angle_rad + math.pi / 2
        lx = x + current_width * math.cos(perp)
        ly = y + current_width * math.sin(perp)
        rx = x - current_width * math.cos(perp)
        ry = y - current_width * math.sin(perp)

        # Alpha fades toward tip
        alpha = 0.15 + 0.6 * shape * width_factor
        cr = int(color[0] * alpha)
        cg = int(color[1] * alpha)
        cb = int(color[2] * alpha)

        if prev_left and prev_right:
            draw.polygon([prev_left, (lx, ly), (rx, ry), prev_right], fill=(cr, cg, cb))

        prev_left = (lx, ly)
        prev_right = (rx, ry)

    # Tip glow for strong signals
    if sig >= 7:
        tip_r = 15 + length
        tip_x = CENTER[0] + tip_r * math.cos(angle_rad)
        tip_y = CENTER[1] + tip_r * math.sin(angle_rad)
        for gr in range(8, 0, -1):
            ga = 0.04 * (8 - gr) / 8
            gc = (int(color[0] * ga), int(color[1] * ga), int(color[2] * ga))
            draw.ellipse([tip_x - gr, tip_y - gr, tip_x + gr, tip_y + gr], fill=gc)


# Draw all petals (sorted by distance so far ones are behind)
for az, dist, band, rst in sorted(QSOS, key=lambda q: -q[1]):
    draw_petal(az, dist, band, rst)

# Center bloom core
for gr in range(25, 0, -1):
    alpha = 0.04 * (25 - gr) / 25
    draw.ellipse([CENTER[0] - gr, CENTER[1] - gr, CENTER[0] + gr, CENTER[1] + gr], fill=(int(80 * alpha * 3), int(220 * alpha * 3), int(120 * alpha * 3)))
draw.ellipse([CENTER[0] - 8, CENTER[1] - 8, CENTER[0] + 8, CENTER[1] + 8], fill=(60, 180, 100))
draw.ellipse([CENTER[0] - 4, CENTER[1] - 4, CENTER[0] + 4, CENTER[1] + 4], fill=(100, 240, 140))

# Header
draw.rectangle([(0, 0), (W, 38)], fill=(5, 5, 10))
draw.text((12, 10), "RADIO BLOOM", fill=LABEL_COLOR, font=font)
draw.text((W - 260, 12), f"{len(QSOS)} QSOs | generative art", fill=(80, 220, 120), font=font_sm)

# Legend
lx = 12
ly = H - 24
for band in ["160m", "80m", "40m", "20m", "15m", "10m"]:
    color = BAND_PALETTES[band][1]
    draw.ellipse([lx, ly, lx + 8, ly + 8], fill=color)
    draw.text((lx + 12, ly - 1), band, fill=LABEL_COLOR, font=font_xs)
    lx += 52

draw.text((lx + 20, ly - 1), "petal width = signal strength", fill=(80, 85, 100), font=font_xs)

img.save("/home/user/carrier_wave/mockups/radio_bloom.png")
print("Saved radio_bloom.png")
