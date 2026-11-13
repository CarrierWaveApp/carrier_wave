"""Grid Conquest mockup — Maidenhead grid squares as a territory map."""

import random
from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 800, 500
BG = (14, 16, 22)
GRID_LINE = (30, 35, 45)
UNWORKED = (22, 25, 32)
LABEL_COLOR = (140, 150, 180)

random.seed(42)

FIELDS_LON = "ABCDEFGHIJKLMNOPQR"
FIELDS_LAT = "ABCDEFGHIJKLMNOPQR"


def count_to_color(count):
    if count == 0:
        return UNWORKED
    intensity = min(count / 30, 1.0)
    r = int(20 + intensity * 30)
    g = int(40 + intensity * 190)
    b = int(30 + intensity * 50)
    return (r, g, b)


WORKED_MANY = {
    "FN": 45, "FM": 30, "EN": 25, "EM": 20, "DN": 15,
    "DM": 12, "CM": 8, "CN": 10,
    "IO": 18, "JO": 22, "JN": 15, "KO": 8, "KN": 12,
    "IN": 6, "IM": 4,
    "PM": 5, "QM": 3,
    "QF": 4,
    "GG": 7, "GH": 3,
    "KI": 2, "LI": 3,
    "OL": 2, "OM": 3,
    "EL": 8, "FL": 5,
}

WORKED_FEW = {
    "FN": 3, "FM": 2, "EN": 1,
    "IO": 2, "JO": 1,
    "PM": 1,
    "DM": 1,
}


def render(worked, filename, title):
    img = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(img)

    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 14)
        font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 9)
        font_xs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 7)
    except OSError:
        font = ImageFont.load_default()
        font_sm = font
        font_xs = font

    margin_top = 44
    margin_bottom = 36
    margin_left = 20
    margin_right = 20
    grid_w = WIDTH - margin_left - margin_right
    grid_h = HEIGHT - margin_top - margin_bottom

    cell_w = grid_w / 18
    cell_h = grid_h / 18

    total_grids = 18 * 18
    worked_count = len(worked)
    total_qsos = sum(worked.values())

    for li, lon_field in enumerate(FIELDS_LON):
        for ai, lat_field in enumerate(FIELDS_LAT):
            grid_id = lon_field + lat_field
            count = worked.get(grid_id, 0)
            color = count_to_color(count)

            x = margin_left + li * cell_w
            y = margin_top + (17 - ai) * cell_h

            draw.rectangle(
                [x + 1, y + 1, x + cell_w - 1, y + cell_h - 1],
                fill=color,
            )

            if count > 0:
                draw.text(
                    (x + 3, y + 2),
                    grid_id,
                    fill=(200, 220, 200),
                    font=font_xs,
                )
                if count > 1:
                    draw.text(
                        (x + 3, y + cell_h - 11),
                        str(count),
                        fill=(160, 200, 160),
                        font=font_xs,
                    )

    for li in range(19):
        x = margin_left + li * cell_w
        draw.line([(x, margin_top), (x, HEIGHT - margin_bottom)], fill=GRID_LINE, width=1)
    for ai in range(19):
        y = margin_top + ai * cell_h
        draw.line([(margin_left, y), (WIDTH - margin_right, y)], fill=GRID_LINE, width=1)

    draw.rectangle([(0, 0), (WIDTH, 38)], fill=(10, 12, 18))
    draw.text((12, 10), title, fill=LABEL_COLOR, font=font)

    pct = (worked_count / total_grids) * 100
    stats = f"{worked_count}/{total_grids} grids ({pct:.1f}%)  |  {total_qsos} QSOs"
    draw.text((WIDTH - 320, 12), stats, fill=(80, 220, 120), font=font_sm)

    ly = HEIGHT - 28
    draw.text((12, ly), "QSOs:", fill=LABEL_COLOR, font=font_sm)
    legend_counts = [0, 1, 5, 10, 20, 50]
    lx = 60
    for ct in legend_counts:
        color = count_to_color(ct)
        draw.rectangle([lx, ly, lx + 16, ly + 16], fill=color, outline=GRID_LINE)
        label = str(ct) if ct > 0 else "0"
        draw.text((lx + 20, ly + 2), label, fill=LABEL_COLOR, font=font_xs)
        lx += 45

    draw.text(
        (WIDTH - 180, ly),
        "Skin: Grid Conquest",
        fill=(60, 65, 80),
        font=font_sm,
    )

    img.save(filename)
    print(f"Saved {filename}")


render(WORKED_MANY, "/home/user/carrier_wave/mockups/grid_conquest_many.png", "GRID CONQUEST")
render(WORKED_FEW, "/home/user/carrier_wave/mockups/grid_conquest_few.png", "GRID CONQUEST")
