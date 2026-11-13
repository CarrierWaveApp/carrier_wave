#!/usr/bin/env python3
"""CW Bridge POC wiring diagram — EC-11 encoder + buttons + USB-A host."""
from reportlab.lib.pagesizes import letter, landscape
from reportlab.pdfgen import canvas
from reportlab.lib import colors

OUT = "/Users/justinrogers/carrier_wave/cw-bridge-poc-wiring.pdf"
W, H = landscape(letter)

NAVY = colors.HexColor("#15233f")
RED = colors.HexColor("#c8102e")
GREEN = colors.HexColor("#1f8b4c")
WHITE = colors.white
GREY = colors.HexColor("#6b7280")
LGREY = colors.HexColor("#e5e7eb")
BLACK = colors.HexColor("#111827")

c = canvas.Canvas(OUT, pagesize=landscape(letter))


def header(title, sub):
    c.setFillColor(NAVY); c.rect(0, H - 56, W, 56, fill=1, stroke=0)
    c.setFillColor(WHITE); c.setFont("Helvetica-Bold", 20); c.drawString(40, H - 36, title)
    c.setFillColor(colors.HexColor("#aab4c5")); c.setFont("Helvetica", 10.5); c.drawString(40, H - 50, sub)


def box(x, y, w, h, title, color=NAVY):
    c.setStrokeColor(color); c.setLineWidth(1.6); c.setFillColor(WHITE)
    c.roundRect(x, y, w, h, 8, fill=1, stroke=1)
    c.setFillColor(color); c.roundRect(x, y + h - 22, w, 22, 8, fill=1, stroke=0)
    c.rect(x, y + h - 22, w, 12, fill=1, stroke=0)
    c.setFillColor(WHITE); c.setFont("Helvetica-Bold", 10.5); c.drawCentredString(x + w / 2, y + h - 16, title)


def dot(x, y, color=NAVY):
    c.setFillColor(color); c.circle(x, y, 2.6, fill=1, stroke=0)


def wire(pts, color=NAVY, width=1.7):
    c.setStrokeColor(color); c.setLineWidth(width); c.setDash()
    p = c.beginPath(); p.moveTo(*pts[0])
    for pt in pts[1:]:
        p.lineTo(*pt)
    c.drawPath(p, stroke=1, fill=0)


def label(x, y, text, size=8.5, color=BLACK, font="Helvetica", center=False, right=False):
    c.setFillColor(color); c.setFont(font, size)
    if center: c.drawCentredString(x, y, text)
    elif right: c.drawRightString(x, y, text)
    else: c.drawString(x, y, text)


# ===================================================================== PAGE 1
header("CW Bridge — POC Control Wiring",
       "Heltec WiFi Kit 32 v3.1 (ESP32-S3)  ·  EC-11 encoder + 3 buttons + USB-A host  ·  header pins as J2-n / J3-n")

bx, by, bw, bh = 322, 96, 168, 410
box(bx, by, bw, bh, "Heltec WiFi Kit 32 v3.1")
label(bx + bw / 2, by + 11, "(OLED + USB-C onboard)", 7.5, GREY, center=True)

# Left edge: EC-11 + buttons (all J3). (gpio, fn, y, jpin)
left_pads = [
    ("GPIO47", "CLK", 466, "J3-6"),
    ("GPIO48", "DT", 442, "J3-5"),
    ("GPIO26", "SW", 418, "J3-4"),
    ("GND", "GND", 394, "J3-1"),    # encoder commons (rotary C + switch leg)
    ("GPIO33", "BTN1", 330, "J3-7"),
    ("GPIO34", "BTN2", 306, "J3-8"),
    ("GPIO38", "BTN3", 282, "J3-12"),
    ("GND", "COM", 258, "J3-1"),    # button common
]
left_anchor = {}
for (gpio, fn, y, jpin) in left_pads:
    dot(bx, y)
    label(bx + 6, y - 3, gpio, 8, NAVY, font="Helvetica-Bold")
    label(bx + 62, y - 3, jpin, 7.2, GREY)
    left_anchor[(gpio, fn)] = (bx, y)

# Right edge: USB-A (J2)
right_pads = [("5V", "VBUS", 438, "J2-2"), ("GPIO20", "D+", 408, "J2-10"),
              ("GPIO19", "D-", 378, "J2-11"), ("GND", "GND", 348, "J2-1")]
right_anchor = {}
for (gpio, fn, y, jpin) in right_pads:
    dot(bx + bw, y)
    label(bx + bw - 6, y - 3, gpio, 8, NAVY, font="Helvetica-Bold", right=True)
    label(bx + bw - 60, y - 3, jpin, 7.2, GREY, right=True)
    right_anchor[(gpio, fn)] = (bx + bw, y)

# EC-11 encoder (top-left)
ex, ey, ew, eh = 34, 376, 150, 122
box(ex, ey, ew, eh, "Rotary Encoder (EC-11)")
enc = [("A  (rotary)", ("GPIO47", "CLK"), NAVY),
       ("B  (rotary)", ("GPIO48", "DT"), NAVY),
       ("SW (switch)", ("GPIO26", "SW"), NAVY),
       ("C  (com)", ("GND", "GND"), NAVY),
       ("SW com", ("GND", "GND"), NAVY)]
ey0 = ey + eh - 36
for i, (pin, key, col) in enumerate(enc):
    yy = ey0 - i * 16; ax = ex + ew
    dot(ax, yy, col); label(ex + 10, yy - 3, pin, 8.3)
    tx, ty = left_anchor[key]; midx = ax + 14 + i * 6
    wire([(ax, yy), (midx, yy), (midx, ty), (tx, ty)], color=col)

# Pushbuttons (mid-left)
pbx, pby, pbw, pbh = 34, 206, 150, 108
box(pbx, pby, pbw, pbh, "Pushbuttons (x3 SPST)")
btn = [("BTN1", ("GPIO33", "BTN1")), ("BTN2", ("GPIO34", "BTN2")),
       ("BTN3", ("GPIO38", "BTN3")), ("COM", ("GND", "COM"))]
by0 = pby + pbh - 36
for i, (pin, key) in enumerate(btn):
    yy = by0 - i * 16; ax = pbx + pbw
    dot(ax, yy); label(pbx + 10, yy - 3, pin, 8.5)
    tx, ty = left_anchor[key]; midx = ax + 12 + i * 6
    wire([(ax, yy), (midx, yy), (midx, ty), (tx, ty)])
label(pbx + 8, pby + 9, "common → GND, active-low", 7, GREY)

# USB-A (upper right)
ux, uy, uw, uh = 596, 322, 156, 150
box(ux, uy, uw, uh, "USB-A Host (to radio)")
usb = [("VBUS (red)", ("5V", "VBUS"), RED), ("D+ (green)", ("GPIO20", "D+"), GREEN),
       ("D− (white)", ("GPIO19", "D-"), GREY), ("GND (black)", ("GND", "GND"), BLACK)]
uy0 = uy + uh - 40
for i, (pin, key, col) in enumerate(usb):
    yy = uy0 - i * 20; ax = ux
    dot(ax, yy, col); label(ux + 12, yy - 3, pin, 8.5)
    tx, ty = right_anchor[key]; midx = ax - 18 - i * 6
    wire([(ax, yy), (midx, yy), (midx, ty), (tx, ty)], color=col)
label(ux + 8, uy + 9, "radio via USB-A→C cable", 7, GREY)

# ---- EC-11 pinout detail (lower right) ----
kx, ky, kw, kh = 560, 92, 200, 184
box(kx, ky, kw, kh, "EC-11 — terminal layout")
# encoder body
mw, mh = 64, 50
mx, my = kx + kw / 2 - mw / 2, ky + 78
c.setFillColor(colors.HexColor("#c9ccd1")); c.setStrokeColor(colors.HexColor("#7a7e85")); c.setLineWidth(1.2)
c.roundRect(mx, my, mw, mh, 4, fill=1, stroke=1)
# shaft
c.setFillColor(colors.HexColor("#9aa0a6")); c.circle(mx + mw / 2, my + mh + 12, 11, fill=1, stroke=0)
label(mx + mw / 2, my + mh + 9, "shaft", 6, WHITE, center=True)
# switch side: 2 pins on TOP edge
sw = [("SW", "GPIO26 · J3-4"), ("com", "GND · J3-1")]
for i, (nm, mp) in enumerate(sw):
    px = mx + (12 if i == 0 else mw - 12)
    c.setStrokeColor(BLACK); c.setLineWidth(1.4); c.line(px, my + mh, px, my + mh + 9)
    dot(px, my + mh + 9)
    label(px, my + mh + 14, nm, 7, BLACK, font="Helvetica-Bold", center=True)
label(kx + kw / 2, my + mh + 24, "switch side (2 pins)", 6.3, GREY, center=True)
# rotary side: 3 pins on BOTTOM edge
rot = [("A", "GPIO47 · J3-6"), ("C", "GND · J3-1"), ("B", "GPIO48 · J3-5")]
for i, (nm, mp) in enumerate(rot):
    px = mx + (i + 0.5) * (mw / 3)
    c.setStrokeColor(BLACK); c.setLineWidth(1.4); c.line(px, my, px, my - 10)
    dot(px, my - 10)
    label(px, my - 20, nm, 7.5, BLACK, font="Helvetica-Bold", center=True)
    label(px, my - 29, mp.split(" · ")[0], 6.0, GREY, center=True)
label(kx + kw / 2, my - 40, "rotary side (3 pins:  A · C(com) · B)", 6.3, GREY, center=True)
c.setFillColor(RED); c.setFont("Helvetica-Bold", 6.8)
c.drawCentredString(kx + kw / 2, ky + 9, "No VCC / no resistors. Common = centre of 3-pin side — verify with a meter.")

# footer
c.setFillColor(GREY); c.setFont("Helvetica-Oblique", 8.3)
c.drawString(34, 34, "EC-11 + all 3 buttons live on header J3; USB-A host on J2. EC-11 has no VCC — both encoder commons and the button COM all tie to J3-1.")
c.drawString(34, 23, "A/B/SW use ESP32-S3 internal pull-ups (no resistors). Optional: 10 nF from A & B to GND tames bounce. USB D−/D+ fixed to GPIO19/20 — keep short & twisted.")
c.setFont("Helvetica", 8); c.drawRightString(W - 34, 23, "Page 1 / 2")
c.showPage()

# ===================================================================== PAGE 2
header("CW Bridge — POC Wiring Tables & Function Map",
       "Pin-for-pin connections (with header pins) and firmware control map")


def table(x, y, title, rows, col_w, headers):
    label(x, y, title, 12, NAVY, font="Helvetica-Bold"); y -= 8
    rowh = 18; tw = sum(col_w); y0 = y - rowh
    c.setFillColor(NAVY); c.rect(x, y0, tw, rowh, fill=1, stroke=0)
    c.setFillColor(WHITE); c.setFont("Helvetica-Bold", 8.3)
    cx = x
    for h, w in zip(headers, col_w):
        c.drawString(cx + 5, y0 + 5, h); cx += w
    for i, row in enumerate(rows):
        ry = y0 - (i + 1) * rowh
        if i % 2 == 0:
            c.setFillColor(LGREY); c.rect(x, ry, tw, rowh, fill=1, stroke=0)
        cx = x
        for j, (cell, w) in enumerate(zip(row, col_w)):
            c.setFillColor(BLACK)
            c.setFont("Helvetica-Bold" if j == 0 else "Helvetica", 8.3)
            c.drawString(cx + 5, ry + 5, cell); cx += w
    c.setStrokeColor(colors.HexColor("#cbd2dc")); c.setLineWidth(0.5)
    c.rect(x, y0 - len(rows) * rowh, tw, (len(rows) + 1) * rowh, fill=0, stroke=1)
    return y0 - len(rows) * rowh


yL = H - 80
yL = table(34, yL, "EC-11 rotary encoder  →  header J3",
           [["A (rotary)", "GPIO47", "J3-6", "channel A (CLK)"],
            ["B (rotary)", "GPIO48", "J3-5", "channel B (DT)"],
            ["SW (switch)", "GPIO26", "J3-4", "push switch"],
            ["C (common)", "GND", "J3-1", "rotary common"],
            ["SW common", "GND", "J3-1", "switch common"]],
           [70, 58, 48, 120], ["EC-11 pin", "GPIO", "Pin", "Note"])
yL -= 24
yL = table(34, yL, "Pushbuttons (3x SPST)  →  header J3",
           [["BTN1", "GPIO33", "J3-7", "CW memory 1 (CQ)"],
            ["BTN2", "GPIO34", "J3-8", "CW memory 2 (TU 73)"],
            ["BTN3", "GPIO38", "J3-12", "Health overlay (long)"],
            ["COM", "GND", "J3-1", "common (shared)"]],
           [70, 58, 48, 120], ["Button", "GPIO", "Pin", "Function"])

yR = H - 80
yR = table(330, yR, "USB-A host → radio  →  header J2",
           [["VBUS (red)", "5V", "J2-2", "bus power to radio"],
            ["D+ (green)", "GPIO20", "J2-10", "USB D+ (fixed)"],
            ["D− (white)", "GPIO19", "J2-11", "USB D− (fixed)"],
            ["GND (black)", "GND", "J2-1", "ground"]],
           [76, 58, 50, 116], ["USB-A pin", "GPIO", "Pin", "Note"])
yR -= 24
yR = table(330, yR, "Firmware control map (POC)",
           [["Encoder press", "cycle", "WPM ↔ AF gain"],
            ["Encoder rotate", "adjust", "active target (KS / AG0nnn;)"],
            ["Encoder long", "menu", "open on-screen menu"],
            ["BTN1 / BTN2", "play", "CW memory slot 1 / 2 (KY)"],
            ["BTN1/2 long", "abort", "stop in-flight CW"]],
           [88, 48, 164], ["Control", "Action", "Detail"])

# warning box (right)
wx, wy, ww, wh = 330, yR - 92, 300, 76
c.setFillColor(colors.HexColor("#fdecee")); c.setStrokeColor(RED); c.setLineWidth(1.4)
c.roundRect(wx, wy, ww, wh, 6, fill=1, stroke=1)
c.setFillColor(RED); c.setFont("Helvetica-Bold", 10)
c.drawString(wx + 12, wy + wh - 18, "!  Memory buttons TRANSMIT")
c.setFillColor(BLACK); c.setFont("Helvetica", 8.2)
for i, ln in enumerate([
        "BTN1/BTN2 key the radio's CW keyer (KY) and transmit on the",
        "current freq/mode. Use a dummy load, set CW mode, be clear",
        "before testing. Long-press the button to abort."]):
    c.drawString(wx + 12, wy + wh - 34 - i * 12, ln)

# notes (left)
ny = yL - 18
label(34, ny, "Notes", 12, NAVY, font="Helvetica-Bold")
c.setFillColor(BLACK); c.setFont("Helvetica", 8.5)
for i, nline in enumerate([
        "• EC-11 is a bare encoder: no VCC pin, no onboard resistors.",
        "• Rotary common (C, centre of 3-pin side) + switch leg + button COM → J3-1.",
        "• A/B/SW use ESP32-S3 internal pull-ups — no external resistors.",
        "• Optional: 10 nF from A & B to GND smooths contact bounce.",
        "• EC-11 clones vary — confirm the common pin with a meter.",
        "• Keep USB D−/D+ short & twisted (full-speed 12 Mbit/s).",
        "• Do NOT wire GPIO 8–14 (reserved on LoRa-equipped boards)."]):
    c.drawString(34, ny - 16 - i * 13, nline)

c.setFillColor(GREY); c.setFont("Helvetica", 8)
c.drawRightString(W - 34, 23, "Page 2 / 2")
c.drawString(34, 23, "branch: poc/encoder-cw-memory")
c.showPage()
c.save()
print("wrote", OUT)
