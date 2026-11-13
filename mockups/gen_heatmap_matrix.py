"""Heatmap Matrix — Band x Hour-of-Day propagation grid."""
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)
W, H = 800, 420
BG = (14, 16, 22)
GRID = (30, 35, 45)
LABEL = (140, 150, 180)

BANDS = ["160m", "80m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m"]
HOURS = list(range(24))

# Simulated propagation patterns per band (hour -> relative activity)
PATTERNS = {
    "160m": [8, 9, 9, 8, 6, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 5, 6, 7, 8, 8],
    "80m":  [9, 9, 8, 7, 5, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 4, 6, 7, 8, 9, 9],
    "40m":  [7, 7, 6, 5, 3, 1, 0, 0, 1, 2, 3, 4, 5, 5, 4, 3, 2, 3, 5, 6, 7, 8, 8, 7],
    "30m":  [4, 3, 2, 1, 0, 0, 0, 1, 2, 4, 5, 6, 7, 7, 6, 5, 4, 3, 3, 4, 5, 5, 5, 4],
    "20m":  [2, 1, 0, 0, 0, 0, 1, 2, 4, 6, 8, 9, 9, 9, 8, 7, 5, 4, 3, 2, 2, 2, 2, 2],
    "17m":  [1, 0, 0, 0, 0, 0, 0, 1, 3, 5, 7, 8, 9, 8, 7, 5, 3, 2, 1, 0, 0, 0, 1, 1],
    "15m":  [0, 0, 0, 0, 0, 0, 0, 1, 2, 4, 6, 8, 9, 9, 8, 6, 4, 2, 1, 0, 0, 0, 0, 0],
    "12m":  [0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 5, 7, 8, 8, 7, 5, 3, 1, 0, 0, 0, 0, 0, 0],
    "10m":  [0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 4, 6, 7, 7, 6, 4, 2, 1, 0, 0, 0, 0, 0, 0],
    "6m":   [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0],
}


def val_to_color(val, max_val=9):
    if val == 0:
        return (20, 22, 30)
    t = val / max_val
    r = int(20 + t * 40)
    g = int(60 + t * 170)
    b = int(40 + t * 60)
    return (r, g, b)


def render(filename, title, add_noise=True):
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 13)
        font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 10)
        font_xs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 9)
    except OSError:
        font = font_sm = font_xs = ImageFont.load_default()

    ml, mt, mr, mb = 55, 44, 20, 36
    gw = W - ml - mr
    gh = H - mt - mb
    cw = gw / 24
    ch = gh / 10

    draw.rectangle([(0, 0), (W, 38)], fill=(10, 12, 18))
    draw.text((12, 10), title, fill=LABEL, font=font)

    for bi, band in enumerate(BANDS):
        y = mt + bi * ch
        draw.text((8, y + ch / 2 - 6), band, fill=LABEL, font=font_sm)
        for hi, hour in enumerate(HOURS):
            x = ml + hi * cw
            val = PATTERNS[band][hour]
            if add_noise:
                val = max(0, min(9, val + random.randint(-1, 1)))
            color = val_to_color(val)
            draw.rectangle([x + 1, y + 1, x + cw - 1, y + ch - 1], fill=color)

    for hi in range(25):
        x = ml + hi * cw
        draw.line([(x, mt), (x, H - mb)], fill=GRID, width=1)
    for bi in range(11):
        y = mt + bi * ch
        draw.line([(ml, y), (W - mr, y)], fill=GRID, width=1)

    for hi in range(0, 24, 3):
        x = ml + hi * cw + cw / 2
        draw.text((x - 8, H - mb + 4), f"{hi:02d}", fill=(80, 85, 100), font=font_xs)
    draw.text((W // 2 - 30, H - 16), "UTC Hour", fill=(80, 85, 100), font=font_xs)

    ly = H - 28
    lx = W - 250
    draw.text((lx, ly), "QSOs:", fill=(80, 85, 100), font=font_xs)
    lx += 35
    for lv in [0, 2, 5, 7, 9]:
        c = val_to_color(lv)
        draw.rectangle([lx, ly, lx + 14, ly + 14], fill=c, outline=GRID)
        draw.text((lx + 18, ly + 2), str(lv), fill=(80, 85, 100), font=font_xs)
        lx += 38

    img.save(filename)
    print(f"Saved {filename}")


render("/home/user/carrier_wave/mockups/heatmap_matrix.png", "PROPAGATION GRID  —  Band × Hour")
