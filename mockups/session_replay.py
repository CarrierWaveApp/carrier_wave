"""Session Replay — Static frame of an animated POTA activation replay."""
import math
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)
W, H = 800, 500
BG = (10, 12, 20)
LABEL_COLOR = (140, 150, 180)

BAND_COLORS = {
    "20m": (60, 130, 255), "40m": (220, 180, 50), "15m": (100, 200, 100),
}

HOME = (300, 250)  # Center of simple map

# Simulated activation timeline (minute, callsign, bearing, distance, band, rst)
TIMELINE = [
    (0, "W6UV", 270, 180, "20m", 599),
    (2, "VE3YZ", 30, 120, "20m", 579),
    (3, "K1AB", 60, 90, "40m", 599),
    (5, "W9WX", 350, 100, "20m", 589),
    (7, "G4ABC", 50, 250, "20m", 559),
    (9, "DL1GH", 45, 280, "15m", 579),
    (10, "F5DEF", 48, 260, "20m", 569),
    (12, "EA4JK", 55, 240, "15m", 589),
    (14, "JA1XY", 310, 350, "20m", 539),
    (16, "W4PQ", 160, 80, "40m", 599),
    (18, "VK2GH", 260, 380, "20m", 519),
    (20, "PY1KL", 150, 300, "10m", 559),
    (22, "N5CD", 220, 70, "40m", 599),
    (24, "SM0LM", 40, 270, "20m", 579),
    (26, "W7EF", 280, 150, "40m", 589),
    (28, "OH2NO", 38, 290, "15m", 569),
]

# Current "frame" is at minute 20 — contacts up to that point are visible
CURRENT_MINUTE = 20

img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
    font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 10)
    font_xs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 8)
except OSError:
    font = font_sm = font_xs = ImageFont.load_default()

# Background: subtle grid
for gx in range(0, W, 40):
    draw.line([(gx, 40), (gx, H - 60)], fill=(16, 18, 26), width=1)
for gy in range(40, H - 60, 40):
    draw.line([(0, gy), (W, gy)], fill=(16, 18, 26), width=1)

# Draw contacts
visible_contacts = [(m, c, b, d, band, rst) for m, c, b, d, band, rst in TIMELINE if m <= CURRENT_MINUTE]
future_contacts = [(m, c, b, d, band, rst) for m, c, b, d, band, rst in TIMELINE if m > CURRENT_MINUTE]


def bearing_to_xy(bearing, distance):
    rad = math.radians(bearing - 90)
    scale = 0.8
    x = HOME[0] + distance * scale * math.cos(rad)
    y = HOME[1] + distance * scale * math.sin(rad)
    return x, y


# Draw pulse rings for the most recent contact (expanding circles)
if visible_contacts:
    last = visible_contacts[-1]
    last_x, last_y = bearing_to_xy(last[2], last[3])
    for ring in range(3):
        r = 15 + ring * 20
        alpha = 0.15 - ring * 0.04
        color = BAND_COLORS.get(last[4], (100, 100, 100))
        c = (int(color[0] * alpha), int(color[1] * alpha), int(color[2] * alpha))
        draw.ellipse([HOME[0] - r, HOME[1] - r, HOME[0] + r, HOME[1] + r], outline=c, width=1)

# Draw arcs and dots for visible contacts
for idx, (minute, call, bearing, distance, band, rst) in enumerate(visible_contacts):
    dest = bearing_to_xy(bearing, distance)
    color = BAND_COLORS.get(band, (100, 100, 100))

    # Age-based fade (more recent = brighter)
    age = CURRENT_MINUTE - minute
    recency = max(0.3, 1.0 - age * 0.05)

    # Arc
    mid_x = (HOME[0] + dest[0]) / 2
    mid_y = (HOME[1] + dest[1]) / 2 - distance * 0.15
    steps = 20
    for si in range(steps - 1):
        t1 = si / steps
        t2 = (si + 1) / steps
        x1 = (1 - t1) ** 2 * HOME[0] + 2 * (1 - t1) * t1 * mid_x + t1**2 * dest[0]
        y1 = (1 - t1) ** 2 * HOME[1] + 2 * (1 - t1) * t1 * mid_y + t1**2 * dest[1]
        x2 = (1 - t2) ** 2 * HOME[0] + 2 * (1 - t2) * t2 * mid_x + t2**2 * dest[0]
        y2 = (1 - t2) ** 2 * HOME[1] + 2 * (1 - t2) * t2 * mid_y + t2**2 * dest[1]
        alpha = recency * (0.3 + 0.4 * math.sin(t1 * math.pi))
        c = (int(color[0] * alpha), int(color[1] * alpha), int(color[2] * alpha))
        draw.line([(x1, y1), (x2, y2)], fill=c, width=2)

    # Destination dot
    r = 4
    c = (int(color[0] * recency), int(color[1] * recency), int(color[2] * recency))
    draw.ellipse([dest[0] - r, dest[1] - r, dest[0] + r, dest[1] + r], fill=c)

    # Callsign label
    label_alpha = min(recency, 0.8)
    lc = (int(200 * label_alpha), int(210 * label_alpha), int(220 * label_alpha))
    draw.text((dest[0] + 8, dest[1] - 5), call, fill=lc, font=font_xs)

# Home station
draw.ellipse([HOME[0] - 6, HOME[1] - 6, HOME[0] + 6, HOME[1] + 6], fill=(80, 220, 120))
draw.text((HOME[0] + 10, HOME[1] - 5), "K-1234", fill=(80, 220, 120), font=font_sm)

# Timeline bar at bottom
bar_y = H - 45
bar_x1, bar_x2 = 80, W - 30
draw.line([(bar_x1, bar_y), (bar_x2, bar_y)], fill=(30, 35, 50), width=3)

# Mark contacts on timeline
total_time = max(m for m, *_ in TIMELINE)
for minute, call, bearing, distance, band, rst in TIMELINE:
    tx = bar_x1 + (minute / total_time) * (bar_x2 - bar_x1)
    color = BAND_COLORS.get(band, (100, 100, 100))
    is_past = minute <= CURRENT_MINUTE
    alpha = 0.8 if is_past else 0.2
    c = (int(color[0] * alpha), int(color[1] * alpha), int(color[2] * alpha))
    draw.ellipse([tx - 3, bar_y - 3, tx + 3, bar_y + 3], fill=c)

# Playhead
playhead_x = bar_x1 + (CURRENT_MINUTE / total_time) * (bar_x2 - bar_x1)
draw.polygon([(playhead_x, bar_y - 10), (playhead_x - 5, bar_y - 16), (playhead_x + 5, bar_y - 16)], fill=(80, 220, 120))
draw.line([(playhead_x, bar_y - 10), (playhead_x, bar_y + 4)], fill=(80, 220, 120), width=2)

# Time labels
draw.text((bar_x1 - 35, bar_y - 6), "0:00", fill=(80, 85, 100), font=font_xs)
draw.text((bar_x2 + 4, bar_y - 6), f"0:{total_time:02d}", fill=(80, 85, 100), font=font_xs)
draw.text((playhead_x - 12, bar_y + 8), f"0:{CURRENT_MINUTE:02d}", fill=(80, 220, 120), font=font_xs)

# Play button
draw.polygon([(20, bar_y - 8), (20, bar_y + 8), (36, bar_y)], fill=(80, 220, 120))

# Header
draw.rectangle([(0, 0), (W, 38)], fill=(6, 8, 14))
draw.text((12, 10), "ACTIVATION REPLAY", fill=LABEL_COLOR, font=font)
draw.text((W - 320, 12), f"POTA K-1234 | {len(visible_contacts)}/{len(TIMELINE)} QSOs | 2x speed", fill=(80, 220, 120), font=font_sm)

# Rate indicator
draw.text((12, H - 20), f"Rate: {len(visible_contacts)} QSOs in {CURRENT_MINUTE} min", fill=(80, 85, 100), font=font_xs)

img.save("/home/user/carrier_wave/mockups/session_replay.png")
print("Saved session_replay.png")
