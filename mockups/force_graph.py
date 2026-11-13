"""Force-Directed Graph — QSO Web showing callsign network."""
import math
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)
W, H = 800, 800
CENTER = (W // 2, H // 2)
BG = (14, 16, 22)
LABEL_COLOR = (140, 150, 180)

CONTINENT_COLORS = {
    "NA": (60, 130, 255), "EU": (100, 200, 100), "AS": (220, 180, 50),
    "SA": (200, 120, 60), "OC": (180, 100, 220), "AF": (220, 80, 180),
}

# Simulated nodes: (callsign, continent, qso_count_with_you)
NODES = [
    ("W1AW", "NA", 0),  # You (center)
    ("G4ABC", "EU", 12), ("F5DEF", "EU", 8), ("DL1GH", "EU", 15), ("EA4JK", "EU", 5),
    ("SM0LM", "EU", 7), ("OH2NO", "EU", 4), ("I2PQR", "EU", 3), ("ON4ST", "EU", 6),
    ("JA1XY", "AS", 9), ("JH3AB", "AS", 6), ("HL1CD", "AS", 3), ("VU2EF", "AS", 2),
    ("VK2GH", "OC", 7), ("ZL1IJ", "OC", 3),
    ("PY1KL", "SA", 5), ("LU2MN", "SA", 3), ("CE3OP", "SA", 2),
    ("5Z4QR", "AF", 2), ("ZS6ST", "AF", 4),
    ("W6UV", "NA", 18), ("W9WX", "NA", 14), ("VE3YZ", "NA", 11),
    ("K1AB", "NA", 8), ("N5CD", "NA", 6), ("W7EF", "NA", 9),
]


def simple_force_layout(nodes, iterations=200):
    """Simple force-directed layout."""
    positions = {}
    # Place home at center, others randomly
    for i, (call, cont, qsos) in enumerate(nodes):
        if call == "W1AW":
            positions[call] = [float(CENTER[0]), float(CENTER[1])]
        else:
            angle = random.uniform(0, 2 * math.pi)
            r = random.uniform(50, 300)
            positions[call] = [CENTER[0] + r * math.cos(angle), CENTER[1] + r * math.sin(angle)]

    # Group targets by continent for clustering
    cont_angles = {"NA": 0, "EU": math.pi / 3, "AS": 2 * math.pi / 3, "SA": math.pi, "OC": 4 * math.pi / 3, "AF": 5 * math.pi / 3}

    for iteration in range(iterations):
        forces = {call: [0.0, 0.0] for call, _, _ in nodes}
        damping = 0.85

        # Repulsion between all pairs
        for i, (c1, _, _) in enumerate(nodes):
            for j, (c2, _, _) in enumerate(nodes):
                if i >= j:
                    continue
                dx = positions[c1][0] - positions[c2][0]
                dy = positions[c1][1] - positions[c2][1]
                dist = max(math.sqrt(dx * dx + dy * dy), 1)
                repel = 8000 / (dist * dist)
                fx, fy = repel * dx / dist, repel * dy / dist
                forces[c1][0] += fx
                forces[c1][1] += fy
                forces[c2][0] -= fx
                forces[c2][1] -= fy

        # Attraction to home (proportional to QSO count)
        for call, cont, qsos in nodes:
            if call == "W1AW":
                continue
            dx = positions["W1AW"][0] - positions[call][0]
            dy = positions["W1AW"][1] - positions[call][1]
            dist = max(math.sqrt(dx * dx + dy * dy), 1)
            ideal = 350 - qsos * 12  # More QSOs = closer
            attract = (dist - ideal) * 0.01
            forces[call][0] += attract * dx / dist
            forces[call][1] += attract * dy / dist

        # Continental clustering force
        for call, cont, qsos in nodes:
            if call == "W1AW":
                continue
            angle = cont_angles.get(cont, 0)
            target_x = CENTER[0] + 180 * math.cos(angle)
            target_y = CENTER[1] + 180 * math.sin(angle)
            forces[call][0] += (target_x - positions[call][0]) * 0.005
            forces[call][1] += (target_y - positions[call][1]) * 0.005

        # Apply forces
        for call, _, _ in nodes:
            if call == "W1AW":
                continue
            positions[call][0] += forces[call][0] * damping
            positions[call][1] += forces[call][1] * damping
            # Keep in bounds
            positions[call][0] = max(60, min(W - 60, positions[call][0]))
            positions[call][1] = max(60, min(H - 60, positions[call][1]))

    return positions


positions = simple_force_layout(NODES)

img = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
    font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 10)
    font_xs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 8)
except OSError:
    font = font_sm = font_xs = ImageFont.load_default()

# Draw edges (connections to home)
for call, cont, qsos in NODES:
    if call == "W1AW" or qsos == 0:
        continue
    color = CONTINENT_COLORS.get(cont, (100, 100, 100))
    x1, y1 = positions["W1AW"]
    x2, y2 = positions[call]
    alpha = min(0.15 + qsos * 0.03, 0.6)
    width = max(1, min(qsos // 4, 3))
    c = (int(color[0] * alpha), int(color[1] * alpha), int(color[2] * alpha))
    draw.line([(x1, y1), (x2, y2)], fill=c, width=width)

# Draw same-continent edges (lighter)
for i, (c1, cont1, _) in enumerate(NODES):
    for j, (c2, cont2, _) in enumerate(NODES):
        if i >= j or c1 == "W1AW" or c2 == "W1AW":
            continue
        if cont1 == cont2:
            x1, y1 = positions[c1]
            x2, y2 = positions[c2]
            dist = math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)
            if dist < 150:
                color = CONTINENT_COLORS.get(cont1, (100, 100, 100))
                c = (int(color[0] * 0.08), int(color[1] * 0.08), int(color[2] * 0.08))
                draw.line([(x1, y1), (x2, y2)], fill=c, width=1)

# Draw nodes
for call, cont, qsos in NODES:
    x, y = positions[call]
    color = CONTINENT_COLORS.get(cont, (100, 100, 100))

    if call == "W1AW":
        radius = 12
        color = (80, 220, 120)
    else:
        radius = max(4, min(qsos, 10))

    # Glow
    for gr in range(radius + 8, radius, -1):
        alpha = 0.1
        gc = (int(color[0] * alpha), int(color[1] * alpha), int(color[2] * alpha))
        draw.ellipse([x - gr, y - gr, x + gr, y + gr], fill=gc)

    draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=color)

    # Inner bright core
    cr = max(2, radius // 2)
    bright = (min(255, int(color[0] * 1.4)), min(255, int(color[1] * 1.4)), min(255, int(color[2] * 1.4)))
    draw.ellipse([x - cr, y - cr, x + cr, y + cr], fill=bright)

    # Label
    label_color = (200, 210, 220) if call == "W1AW" else (120, 130, 150)
    font_use = font_sm if call == "W1AW" else font_xs
    draw.text((x + radius + 4, y - 5), call, fill=label_color, font=font_use)

# Header
draw.rectangle([(0, 0), (W, 38)], fill=(10, 12, 18))
draw.text((12, 10), "QSO WEB", fill=LABEL_COLOR, font=font)
draw.text((W - 260, 12), f"{len(NODES) - 1} stations | force-directed", fill=(80, 220, 120), font=font_sm)

# Continent legend
lx = 12
ly = H - 24
for cont, color in CONTINENT_COLORS.items():
    draw.ellipse([lx, ly, lx + 10, ly + 10], fill=color)
    draw.text((lx + 14, ly - 1), cont, fill=LABEL_COLOR, font=font_xs)
    lx += 45

img.save("/home/user/carrier_wave/mockups/force_graph.png")
print("Saved force_graph.png")
