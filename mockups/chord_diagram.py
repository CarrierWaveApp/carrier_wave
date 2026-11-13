"""Chord Diagram — Band flow between continents."""
import math
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)
W, H = 800, 800
CENTER = (W // 2, H // 2)
RADIUS = 300
BG = (14, 16, 22)
LABEL_COLOR = (140, 150, 180)

REGIONS = [
    ("NA", (60, 130, 255), 180),
    ("EU", (100, 200, 100), 85),
    ("AS", (220, 180, 50), 45),
    ("SA", (200, 120, 60), 20),
    ("OC", (180, 100, 220), 15),
    ("AF", (220, 80, 180), 8),
]

# Flow matrix: region_i -> region_j (QSO counts from your QTH distributed by continent)
# Since it's your QSOs, flows go from "you" to each region, but we model it as inter-region
FLOWS = {
    ("NA", "EU"): 142, ("NA", "AS"): 65, ("NA", "SA"): 38,
    ("NA", "OC"): 22, ("NA", "AF"): 12, ("NA", "NA"): 95,
    ("EU", "AS"): 28, ("EU", "SA"): 8, ("EU", "OC"): 5,
    ("EU", "AF"): 6, ("AS", "OC"): 12, ("AS", "SA"): 3,
}

total = sum(FLOWS.values())

img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
    font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 12)
    font_xs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 10)
except OSError:
    font = font_sm = font_xs = ImageFont.load_default()

# Compute arc sizes proportional to total flow per region
region_totals = {}
for name, _, _ in REGIONS:
    region_total = 0
    for (src, dst), val in FLOWS.items():
        if src == name or dst == name:
            region_total += val
    region_totals[name] = region_total

grand_total = sum(region_totals.values())
GAP_DEG = 4
TOTAL_GAP = GAP_DEG * len(REGIONS)
AVAIL_DEG = 360 - TOTAL_GAP

arcs = []
current_angle = 0
for name, color, _ in REGIONS:
    span = (region_totals[name] / grand_total) * AVAIL_DEG
    arcs.append((name, color, current_angle, current_angle + span))
    current_angle += span + GAP_DEG

arc_map = {name: (start, end, color) for name, color, start, end in arcs}


def angle_to_xy(angle_deg, r=RADIUS):
    rad = math.radians(angle_deg - 90)
    return CENTER[0] + r * math.cos(rad), CENTER[1] + r * math.sin(rad)


# Draw outer arcs
ARC_WIDTH = 24
for name, color, start, end in arcs:
    steps = max(int((end - start) * 2), 10)
    for si in range(steps):
        a1 = start + (end - start) * si / steps
        a2 = start + (end - start) * (si + 1) / steps
        for ri in range(ARC_WIDTH):
            r = RADIUS + ri - ARC_WIDTH // 2
            x1, y1 = angle_to_xy(a1, r)
            x2, y2 = angle_to_xy(a2, r)
            alpha = 0.6 + 0.4 * (1 - abs(ri - ARC_WIDTH // 2) / (ARC_WIDTH // 2))
            c = (int(color[0] * alpha), int(color[1] * alpha), int(color[2] * alpha))
            draw.line([(x1, y1), (x2, y2)], fill=c, width=2)


def draw_ribbon(src_name, dst_name, val):
    src_start, src_end, src_color = arc_map[src_name]
    dst_start, dst_end, dst_color = arc_map[dst_name]

    # Ribbon width proportional to flow
    src_span = (src_end - src_start) * val / max(region_totals[src_name], 1)
    dst_span = (dst_end - dst_start) * val / max(region_totals[dst_name], 1)

    # Use midpoints for now (simplified)
    src_mid = (src_start + src_end) / 2
    dst_mid = (dst_start + dst_end) / 2

    # Draw curved ribbon as series of lines
    steps = 40
    for si in range(steps):
        t = si / steps
        t2 = (si + 1) / steps

        # Bezier through center
        for offset in range(-int(min(src_span, dst_span) * 2), int(min(src_span, dst_span) * 2)):
            a1 = src_mid + offset * 0.3
            a2 = dst_mid + offset * 0.3

            r1 = RADIUS - ARC_WIDTH // 2
            r_mid = RADIUS * 0.15
            r_t = r1 * (1 - t) ** 2 + r_mid * 2 * (1 - t) * t + r1 * t**2
            r_t2 = r1 * (1 - t2) ** 2 + r_mid * 2 * (1 - t2) * t2 + r1 * t2**2

            angle_t = a1 * (1 - t) + a2 * t
            angle_t2 = a1 * (1 - t2) + a2 * t2

            x1, y1 = angle_to_xy(angle_t, r_t)
            x2, y2 = angle_to_xy(angle_t2, r_t2)

            # Blend colors
            cr = int(src_color[0] * (1 - t) + dst_color[0] * t)
            cg = int(src_color[1] * (1 - t) + dst_color[1] * t)
            cb = int(src_color[2] * (1 - t) + dst_color[2] * t)
            alpha = 0.25
            c = (int(cr * alpha), int(cg * alpha), int(cb * alpha))
            draw.line([(x1, y1), (x2, y2)], fill=c, width=1)


# Draw ribbons
for (src, dst), val in sorted(FLOWS.items(), key=lambda x: x[1]):
    if src != dst:
        draw_ribbon(src, dst, val)

# Labels on arcs
for name, color, start, end in arcs:
    mid_angle = (start + end) / 2
    lx, ly = angle_to_xy(mid_angle, RADIUS + 22)
    qso_count = region_totals[name]
    draw.text((lx - 12, ly - 6), name, fill=color, font=font_sm)
    lx2, ly2 = angle_to_xy(mid_angle, RADIUS + 38)
    draw.text((lx2 - 14, ly2 - 5), f"{qso_count}", fill=LABEL_COLOR, font=font_xs)

# Header
draw.rectangle([(0, 0), (W, 38)], fill=(10, 12, 18))
draw.text((12, 10), "BAND FLOW", fill=LABEL_COLOR, font=font)
draw.text((W - 220, 12), f"{total} QSOs across continents", fill=(80, 220, 120), font=font_xs)

# Center label
draw.text((CENTER[0] - 20, CENTER[1] - 8), "W1AW", fill=(80, 220, 120), font=font_sm)

img.save("/home/user/carrier_wave/mockups/chord_diagram.png")
print("Saved chord_diagram.png")
