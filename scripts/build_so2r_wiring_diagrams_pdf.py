#!/usr/bin/env python3
"""
Generate visual wiring diagrams for each SO2R Box POC bench-plan milestone.

v2: landscape pages, larger drawings, dedicated horizontal lanes for wires,
label zones reserved away from wire paths. Each Heltec pin gets a unique
vertical drop; each wire gets its own horizontal lane. No two wires share
a coordinate.
"""

from reportlab.lib import colors
from reportlab.lib.pagesizes import LETTER, landscape
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak,
)
from reportlab.graphics.shapes import (
    Drawing, Rect, Line, String, Circle, PolyLine,
)


# ---------- Style ----------

styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name="Body", parent=styles["BodyText"], fontSize=9.5, leading=12))
styles.add(ParagraphStyle(name="Cell", parent=styles["BodyText"], fontSize=8.5, leading=10.5))
styles.add(ParagraphStyle(name="CellMono", parent=styles["BodyText"], fontSize=8, leading=10, fontName="Courier"))
styles.add(ParagraphStyle(name="H2", parent=styles["Heading2"], fontSize=14, leading=17, spaceBefore=4, spaceAfter=4))

# Wire palette
WIRE_RED    = colors.HexColor("#cc1f1a")
WIRE_ORANGE = colors.HexColor("#dd6611")
WIRE_BLACK  = colors.HexColor("#111111")
WIRE_BLUE   = colors.HexColor("#1a3fcc")
WIRE_GREEN  = colors.HexColor("#1aaa3c")
WIRE_YELLOW = colors.HexColor("#c79900")
WIRE_PURPLE = colors.HexColor("#8a3cb8")
WIRE_GREY   = colors.HexColor("#888888")

# Canvas geometry (all in points). Diagram fills a full landscape page;
# the pin table follows on its own page so the drawing stays roomy.
CW, CH = 720, 530                # drawing width, height
HELTEC_X, HELTEC_W, HELTEC_H = 30, 660, 70
HELTEC_TOP = CH - 10             # 520
HELTEC_BOT = HELTEC_TOP - HELTEC_H  # 450  - pins live here
PIN_Y = HELTEC_BOT

# Lane Y coordinates - horizontal wire channels under the Heltec.
# 12pt apart so adjacent wires never share a Y.
LANE = {n: 440 - (n - 1) * 14 for n in range(1, 11)}
#   LANE[1] = 440  .. LANE[10] = 314

# Heltec pin order (left -> right along the bottom edge)
HELTEC_PINS = [
    "GND", "3V3", "5V",
    "GPIO 2", "GPIO 4", "GPIO 5", "GPIO 6", "GPIO 7",
    "GPIO 39", "GPIO 40", "GPIO 41", "GPIO 42",
]


def _txt(d, x, y, t, *, size=8, anchor="start", color=colors.black, mono=False, bold=False):
    s = String(x, y, t)
    if mono:
        s.fontName = "Courier-Bold" if bold else "Courier"
    else:
        s.fontName = "Helvetica-Bold" if bold else "Helvetica"
    s.fontSize = size
    s.fillColor = color
    s.textAnchor = anchor
    d.add(s)


def _wire(d, points, color, width=1.4):
    pl = PolyLine(points)
    pl.strokeColor = color
    pl.strokeWidth = width
    pl.strokeLineJoin = 1
    d.add(pl)
    d.add(Circle(points[0],  points[1],  1.7, fillColor=color, strokeColor=color))
    d.add(Circle(points[-2], points[-1], 1.7, fillColor=color, strokeColor=color))


def heltec(d):
    """Draws the Heltec module on the canvas, returns {pin_name: (x, y)}."""
    # Body
    d.add(Rect(HELTEC_X, HELTEC_BOT, HELTEC_W, HELTEC_H,
               fillColor=colors.HexColor("#e8e8f4"),
               strokeColor=colors.HexColor("#222"), strokeWidth=1.2))
    # Title
    _txt(d, HELTEC_X + 10, HELTEC_TOP - 14,
         "Heltec WiFi LoRa 32 V3 (ESP32-S3)",
         size=9, color=colors.HexColor("#444"), bold=True)
    # OLED
    ow, oh = 110, 26
    ox = HELTEC_X + (HELTEC_W - ow) / 2
    oy = HELTEC_TOP - oh - 22
    d.add(Rect(ox, oy, ow, oh, fillColor=colors.HexColor("#0a1928"),
               strokeColor=colors.HexColor("#222"), strokeWidth=0.6))
    _txt(d, ox + ow/2, oy + oh/2 - 3, "OLED 128x64",
         size=7.5, anchor="middle", color=colors.white)
    # USB-C
    uw, uh = 22, 9
    d.add(Rect(HELTEC_X - uw/2, HELTEC_BOT + HELTEC_H/2 - uh/2, uw, uh,
               fillColor=colors.HexColor("#888"), strokeColor=colors.black))
    _txt(d, HELTEC_X - uw - 4, HELTEC_BOT + HELTEC_H/2 - 2,
         "USB-C", size=7, anchor="end")
    # Pin dots + labels along the bottom edge.
    # Labels printed INSIDE the body, just above the dot. Wires go straight
    # DOWN from each dot into a lane, so they never cross a label.
    pin_x_start = HELTEC_X + 35
    pin_x_step  = (HELTEC_W - 70) / (len(HELTEC_PINS) - 1)
    pins = {}
    for i, name in enumerate(HELTEC_PINS):
        px = pin_x_start + i * pin_x_step
        d.add(Circle(px, PIN_Y, 2.2, fillColor=colors.HexColor("#222"),
                     strokeColor=colors.HexColor("#222")))
        # Label inside body, above dot - 2-line if name has space
        if " " in name:
            a, b = name.split(" ", 1)
            _txt(d, px, PIN_Y + 4, a,  size=6, anchor="middle", mono=True, bold=True)
            _txt(d, px, PIN_Y + 11, b, size=6, anchor="middle", mono=True, bold=True)
        else:
            _txt(d, px, PIN_Y + 7, name, size=6.5, anchor="middle", mono=True, bold=True)
        pins[name] = (px, PIN_Y)
    return pins


def component_box(d, x, y, w, h, title, fill, stroke, *, title_pos="center"):
    """Component rectangle with title inside the box, centred. Pin labels
    live near the box edges; the title in the middle never collides as
    long as the box is at least 36 pt tall."""
    d.add(Rect(x, y, w, h, fillColor=fill, strokeColor=stroke, strokeWidth=1.0))
    if title_pos == "below":
        _txt(d, x + w/2, y - 12, title, size=9, anchor="middle",
             color=colors.HexColor("#222"), bold=True)
    else:
        _txt(d, x + w/2, y + h/2 - 3, title, size=9.5, anchor="middle",
             color=colors.HexColor("#222"), bold=True)


def comp_pin(d, x, y, name, *, anchor_side="top"):
    """Pin on a component edge. anchor_side picks which side of the dot the
    label sits so it never overlaps the component body or incoming wires."""
    d.add(Circle(x, y, 2.0, fillColor=colors.HexColor("#222"),
                 strokeColor=colors.HexColor("#222")))
    if anchor_side == "top":         # label below the dot (inside body)
        _txt(d, x, y - 9, name, size=6.5, anchor="middle", mono=True, bold=True)
    elif anchor_side == "bottom":    # label above (inside body)
        _txt(d, x, y + 4, name, size=6.5, anchor="middle", mono=True, bold=True)
    elif anchor_side == "left":      # label to the right (inside body)
        _txt(d, x + 5, y - 2, name, size=6.5, anchor="start", mono=True, bold=True)
    elif anchor_side == "right":     # label to the left (inside body)
        _txt(d, x - 5, y - 2, name, size=6.5, anchor="end", mono=True, bold=True)


def color_key(d, x, y):
    items = [("+5V", WIRE_RED), ("+3V3", WIRE_ORANGE), ("GND", WIRE_BLACK),
             ("SDA", WIRE_BLUE), ("SCL/data", WIRE_GREEN), ("signal", WIRE_YELLOW),
             ("UART", WIRE_PURPLE), ("NC", WIRE_GREY)]
    _txt(d, x, y + 12, "wire colour key:", size=7.5,
         color=colors.HexColor("#444"), bold=True)
    cur = x
    for name, col in items:
        d.add(Line(cur, y + 3, cur + 18, y + 3, strokeColor=col, strokeWidth=2.2))
        _txt(d, cur + 22, y, name, size=7, color=colors.HexColor("#444"))
        cur += 22 + max(28, len(name) * 5)


# ---------- Routing helpers ----------

def route_drop(d, pin_xy, lane_y, dest_xy, color, width=1.3):
    """Heltec pin -> drop to lane -> horizontal -> drop to destination."""
    fx, fy = pin_xy
    tx, ty = dest_xy
    pts = [fx, fy, fx, lane_y, tx, lane_y, tx, ty]
    _wire(d, pts, color, width)


def route_straight_down(d, pin_xy, dest_xy, color, width=1.3):
    """Direct vertical drop when source and dest share an X."""
    fx, fy = pin_xy
    tx, ty = dest_xy
    if abs(fx - tx) < 1:
        _wire(d, [fx, fy, fx, ty], color, width)
    else:
        # Z-route: down a bit, jog, then down
        mid_y = (fy + ty) / 2
        _wire(d, [fx, fy, fx, mid_y, tx, mid_y, tx, ty], color, width)


# =============================================================================
# Milestone 1
# =============================================================================

def _ws2812b(d, cx, cy, label_text="WS2812B (5mm through-hole)"):
    """Through-hole WS2812B with 4 leads pointing straight UP. Leads are
    spaced 22 pt apart so labels never collide."""
    d.add(Circle(cx, cy, 20, fillColor=colors.HexColor("#fffacc"),
                 strokeColor=colors.HexColor("#cc9911"), strokeWidth=1.2))
    _txt(d, cx, cy - 30, label_text, size=9, anchor="middle", bold=True)
    leads = ["+5V", "DOUT", "GND", "DIN"]
    lead_x_start = cx - 33
    lead_x_step = 22
    lead_y_top  = cy + 36
    pts = {}
    for i, n in enumerate(leads):
        lx = lead_x_start + i * lead_x_step
        d.add(Line(lx, cy + 12, lx, lead_y_top,
                   strokeColor=colors.HexColor("#aaa"), strokeWidth=1.0))
        d.add(Circle(lx, lead_y_top, 2.2, fillColor=colors.black))
        _txt(d, lx, lead_y_top + 6, n, size=6.5, anchor="middle", mono=True, bold=True)
        pts[n] = (lx, lead_y_top)
    return pts


def _tactile_button(d, cx, cy, label_text="tactile button"):
    """Tactile button with two leads pointing UP, spaced clearly so label
    text under each leg is readable."""
    d.add(Circle(cx, cy, 18, fillColor=colors.HexColor("#222"),
                 strokeColor=colors.black))
    d.add(Circle(cx, cy, 7, fillColor=colors.HexColor("#aaa"),
                 strokeColor=colors.black))
    _txt(d, cx, cy - 30, label_text, size=9, anchor="middle", bold=True)
    leg1 = (cx - 24, cy + 22)
    leg2 = (cx + 24, cy + 22)
    d.add(Line(leg1[0], cy, leg1[0], leg1[1],
               strokeColor=colors.HexColor("#aaa"), strokeWidth=1.2))
    d.add(Line(leg2[0], cy, leg2[0], leg2[1],
               strokeColor=colors.HexColor("#aaa"), strokeWidth=1.2))
    d.add(Circle(*leg1, 2.2, fillColor=colors.black))
    d.add(Circle(*leg2, 2.2, fillColor=colors.black))
    _txt(d, leg1[0], leg1[1] + 6, "leg1", size=6.5, anchor="middle", mono=True, bold=True)
    _txt(d, leg2[0], leg2[1] + 6, "leg2", size=6.5, anchor="middle", mono=True, bold=True)
    return leg1, leg2


def diagram_m1():
    d = Drawing(CW, CH)
    pins = heltec(d)

    leg1, leg2 = _tactile_button(d, 200, 200)
    ws = _ws2812b(d, 540, 200)

    # Five wires, five distinct lanes. Each lane is a unique Y so wires
    # never share a horizontal segment.
    route_drop(d, pins["GPIO 4"], LANE[1], leg1, WIRE_YELLOW)
    route_drop(d, leg2,           LANE[2], pins["GND"], WIRE_BLACK)
    route_drop(d, pins["GPIO 2"], LANE[3], ws["DIN"], WIRE_GREEN)
    route_drop(d, pins["5V"],     LANE[4], ws["+5V"], WIRE_RED)
    route_drop(d, (pins["GND"][0] + 7, pins["GND"][1]),
                                  LANE[5], ws["GND"], WIRE_BLACK)

    color_key(d, 30, 40)
    return d


# =============================================================================
# Milestone 2
# =============================================================================

def diagram_m2():
    d = Drawing(CW, CH)
    pins = heltec(d)

    # MCP23017 - centred in the upper component band
    MCP_X, MCP_Y, MCP_W, MCP_H = 80, 220, 360, 70
    component_box(d, MCP_X, MCP_Y, MCP_W, MCP_H,
                  "MCP23017 breakout (DIP-28, addr 0x20)",
                  colors.HexColor("#fff4dd"), colors.HexColor("#aa6600"))

    # Power/I2C pins on TOP edge - well-spaced
    mcp_top = {}
    for i, n in enumerate(["VDD", "GND", "SDA", "SCL", "A0", "A1", "A2"]):
        px = MCP_X + 30 + i * 50
        py = MCP_Y + MCP_H
        comp_pin(d, px, py, n, anchor_side="top")
        mcp_top[n] = (px, py)

    # GPB0..7 on BOTTOM edge
    mcp_bot = {}
    for i in range(8):
        px = MCP_X + 30 + i * 42
        py = MCP_Y
        comp_pin(d, px, py, f"GPB{i}", anchor_side="bottom")
        mcp_bot[i] = (px, py)

    # Relay module - directly below the MCP so the 8 GPB->IN wires drop straight
    RLY_X, RLY_Y, RLY_W, RLY_H = 60, 90, 620, 80
    component_box(d, RLY_X, RLY_Y, RLY_W, RLY_H,
                  "8-channel 5V relay module (opto-isolated)",
                  colors.HexColor("#dfe9ff"), colors.HexColor("#1a3fcc"))

    # IN1..8 on TOP edge, X-aligned with the MCP's GPB pins
    rly_top = {}
    for i in range(8):
        px = MCP_X + 30 + i * 42
        py = RLY_Y + RLY_H
        comp_pin(d, px, py, f"IN{i+1}", anchor_side="top")
        rly_top[i] = (px, py)

    # VCC/GND/JD-VCC on the right side of the top edge
    for i, n in enumerate(["VCC", "GND", "JD-VCC"]):
        px = RLY_X + RLY_W - 110 + i * 42
        py = RLY_Y + RLY_H
        comp_pin(d, px, py, n, anchor_side="top")
        rly_top[n] = (px, py)

    # JD-VCC note BELOW the relay module, right-anchored so it stays on-page
    _txt(d, RLY_X + RLY_W, RLY_Y - 28,
         "JD-VCC jumper INSTALLED = Option A;  PULLED = Option B",
         size=8, anchor="end", color=colors.HexColor("#445"), bold=True)

    # ---- Wires ----
    route_drop(d, pins["3V3"],     LANE[1], mcp_top["VDD"], WIRE_ORANGE)
    route_drop(d, pins["GND"],     LANE[2], mcp_top["GND"], WIRE_BLACK)
    route_drop(d, pins["GPIO 41"], LANE[3], mcp_top["SDA"], WIRE_BLUE)
    route_drop(d, pins["GPIO 42"], LANE[4], mcp_top["SCL"], WIRE_GREEN)
    # A0/A1/A2 short stubs to GND lane
    for a in ("A0", "A1", "A2"):
        ax, ay = mcp_top[a]
        _wire(d, [ax, ay, ax, LANE[2]], WIRE_BLACK, width=0.9)

    # Heltec 5V -> Relay VCC + JD-VCC (lane 5)
    rly_v = rly_top["VCC"]
    rly_j = rly_top["JD-VCC"]
    route_drop(d, pins["5V"], LANE[5], rly_v, WIRE_RED)
    # Short bridge VCC -> JD-VCC at a Y just above the component edge
    bridge_y = rly_v[1] + 6
    _wire(d, [rly_v[0], rly_v[1], rly_v[0], bridge_y,
              rly_j[0], bridge_y, rly_j[0], rly_j[1]], WIRE_RED, width=1.0)
    # Heltec GND (shifted X) -> Relay GND (lane 6)
    route_drop(d, (pins["GND"][0] + 7, pins["GND"][1]),
               LANE[6], rly_top["GND"], WIRE_BLACK)

    # Eight straight vertical drops MCP GPBn -> Relay INn+1
    for i in range(8):
        a = mcp_bot[i]
        b = rly_top[i]
        _wire(d, [a[0], a[1], b[0], b[1]], WIRE_YELLOW, width=1.0)

    # Pull-up reminder in the empty strip between MCP23017 and relay module
    _txt(d, CW - 20, 195,
         "SDA + SCL each need a 4.7k pull-up to 3V3",
         size=8, anchor="end", color=colors.HexColor("#445"), bold=True)
    _txt(d, CW - 20, 184,
         "(many MCP23017 breakouts include these on-board)",
         size=7.5, anchor="end", color=colors.HexColor("#666"))

    color_key(d, 30, 30)
    return d


# =============================================================================
# Milestone 3
# =============================================================================

def diagram_m3():
    d = Drawing(CW, CH)
    pins = heltec(d)

    # Note band: clearly placed near the bottom, away from the wires.
    NOTE_X, NOTE_Y, NOTE_W, NOTE_H = 30, 65, 660, 22
    d.add(Rect(NOTE_X, NOTE_Y, NOTE_W, NOTE_H,
               fillColor=colors.HexColor("#f5f9f5"),
               strokeColor=colors.HexColor("#9bc"),
               strokeWidth=0.8))
    _txt(d, NOTE_X + 10, NOTE_Y + 8,
         "Milestone 2 wiring (MCP23017 + 8-channel relay module) stays in "
         "place. This page shows ONLY the panel additions.",
         size=8.5, color=colors.HexColor("#345"))

    # Four buttons spread comfortably across the left half
    btn_y = 200
    btn_xs = [80, 150, 220, 290]
    btn_labels = ["RIG 1", "RIG 2", "BAND -", "BAND +"]
    btn_gpios  = ["GPIO 4", "GPIO 5", "GPIO 6", "GPIO 7"]
    btn_leg1, btn_leg2 = {}, {}
    for i, bx in enumerate(btn_xs):
        d.add(Circle(bx, btn_y, 16, fillColor=colors.HexColor("#222"),
                     strokeColor=colors.black))
        d.add(Circle(bx, btn_y, 6, fillColor=colors.HexColor("#aaa"),
                     strokeColor=colors.black))
        _txt(d, bx, btn_y - 28, f"BTN{i+1}", size=9, anchor="middle", bold=True)
        _txt(d, bx, btn_y - 40, btn_labels[i],
             size=7.5, anchor="middle", color=colors.HexColor("#666"))
        leg1 = (bx - 20, btn_y + 22)
        leg2 = (bx + 20, btn_y + 22)
        d.add(Line(leg1[0], btn_y, leg1[0], leg1[1],
                   strokeColor=colors.HexColor("#aaa"), strokeWidth=1.0))
        d.add(Line(leg2[0], btn_y, leg2[0], leg2[1],
                   strokeColor=colors.HexColor("#aaa"), strokeWidth=1.0))
        d.add(Circle(*leg1, 2.0, fillColor=colors.black))
        d.add(Circle(*leg2, 2.0, fillColor=colors.black))
        btn_leg1[i], btn_leg2[i] = leg1, leg2

    # Four WS2812B in a row on the right. Leads spaced 14 pt apart with
    # abbreviated labels so they no longer collide.
    led_y = 200
    led_xs = [420, 490, 560, 630]
    led_pins = {}
    lead_abbrev = ["V+", "DO", "G", "DI"]
    for i, lx in enumerate(led_xs):
        d.add(Circle(lx, led_y, 16, fillColor=colors.HexColor("#fffacc"),
                     strokeColor=colors.HexColor("#cc9911"), strokeWidth=1.0))
        _txt(d, lx, led_y - 28, f"LED{i+1}", size=9, anchor="middle", bold=True)
        for j, n in enumerate(lead_abbrev):
            ly = led_y + 30
            lxx = lx - 21 + j * 14
            d.add(Line(lxx, led_y + 12, lxx, ly,
                       strokeColor=colors.HexColor("#aaa"), strokeWidth=0.9))
            d.add(Circle(lxx, ly, 1.8, fillColor=colors.black))
            _txt(d, lxx, ly + 6, n, size=6.5, anchor="middle", mono=True, bold=True)
            led_pins[(i, n)] = (lxx, ly)

    # Mini key for the LED lead abbreviations - placed under LED1 label area
    _txt(d, led_xs[0] - 40, led_y - 50,
         "V+=+5V  DO=DOUT  G=GND  DI=DIN",
         size=7, color=colors.HexColor("#666"))

    # Buttons: GPIO -> leg1 (four wires, four lanes)
    for i, gpio in enumerate(btn_gpios):
        route_drop(d, pins[gpio], LANE[i+1], btn_leg1[i], WIRE_YELLOW)
    # Shared GND bus across all four button leg2s
    gnd_lane = LANE[5]
    for i in range(4):
        x, y = btn_leg2[i]
        _wire(d, [x, y, x, gnd_lane], WIRE_BLACK, width=0.9)
    d.add(Line(btn_leg2[0][0], gnd_lane, btn_leg2[3][0], gnd_lane,
               strokeColor=WIRE_BLACK, strokeWidth=1.4))
    # GND bus to Heltec GND
    gp = pins["GND"]
    _wire(d, [btn_leg2[3][0], gnd_lane, gp[0], gnd_lane, gp[0], gp[1]],
          WIRE_BLACK, width=1.4)

    # LED chain DIN -> GPIO 2
    din1 = led_pins[(0, "DI")]
    route_drop(d, pins["GPIO 2"], LANE[6], din1, WIRE_GREEN)
    # Cascade DOUT(n) -> DIN(n+1) - short hop between adjacent LEDs
    for i in range(3):
        a = led_pins[(i, "DO")]
        b = led_pins[(i+1, "DI")]
        _wire(d, [a[0], a[1], a[0], a[1] + 8,
                  b[0], a[1] + 8, b[0], b[1]],
              WIRE_GREEN, width=1.0)
    # Shared +5V rail
    p5 = pins["5V"]
    rail_y = LANE[7]
    for i in range(4):
        x, y = led_pins[(i, "V+")]
        _wire(d, [x, y, x, rail_y], WIRE_RED, width=0.8)
    d.add(Line(led_pins[(0, "V+")][0], rail_y,
               led_pins[(3, "V+")][0], rail_y,
               strokeColor=WIRE_RED, strokeWidth=1.4))
    _wire(d, [led_pins[(0, "V+")][0], rail_y, p5[0], rail_y, p5[0], p5[1]],
          WIRE_RED, width=1.4)
    # Shared GND rail
    grail_y = LANE[8]
    for i in range(4):
        x, y = led_pins[(i, "G")]
        _wire(d, [x, y, x, grail_y], WIRE_BLACK, width=0.8)
    d.add(Line(led_pins[(0, "G")][0], grail_y,
               led_pins[(3, "G")][0], grail_y,
               strokeColor=WIRE_BLACK, strokeWidth=1.4))
    gp2 = (pins["GND"][0] + 7, pins["GND"][1])
    _wire(d, [led_pins[(0, "G")][0], grail_y, gp2[0], grail_y, gp2[0], gp2[1]],
          WIRE_BLACK, width=1.4)

    color_key(d, 30, 30)
    return d


# =============================================================================
# Milestone 4
# =============================================================================

def diagram_m4():
    """Milestone 4 - NEW SCOPE (post-pivot).

    All CAT lives on the PC. The box is a USB-CDC peripheral driven over the
    Heltec's onboard CP2102N. No external UART hardware. Radios connect to the
    PC separately, not to the box.
    """
    d = Drawing(CW, CH)
    pins = heltec(d)

    # PC / Mac box - the only thing the box talks to directly
    PC_X, PC_Y, PC_W, PC_H = 110, 200, 240, 90
    component_box(d, PC_X, PC_Y, PC_W, PC_H,
                  "PC running CW Sweep / so2r_client.py",
                  colors.HexColor("#eef5ff"), colors.HexColor("#1a3fcc"))
    _txt(d, PC_X + PC_W/2, PC_Y + 18,
         "(handles all CAT; talks to box over USB-CDC)",
         size=8, anchor="middle", color=colors.HexColor("#445"))
    # USB-C jack on the left edge of the PC, facing the Heltec
    d.add(Rect(PC_X - 8, PC_Y + PC_H/2 - 7, 14, 14,
               fillColor=colors.HexColor("#222"), strokeColor=colors.black))

    # USB-C cable: Heltec USB-C -> PC USB. The Heltec's USB-C is drawn at the
    # left edge of the Heltec by the heltec() helper.
    cable_low_y = min(PC_Y, HELTEC_BOT) - 40
    heltec_usb_x = HELTEC_X - 11   # matches heltec()'s USB-C jack centre
    pc_usb_x    = PC_X - 8
    d.add(PolyLine([heltec_usb_x, HELTEC_BOT + HELTEC_H / 2,
                    heltec_usb_x, cable_low_y,
                    pc_usb_x,    cable_low_y,
                    pc_usb_x,    PC_Y + PC_H / 2],
                   strokeColor=colors.HexColor("#444"), strokeWidth=4.0))
    # Cable label is positioned ABOVE the horizontal cable run with enough
    # vertical clearance that the cable line doesn't intersect any glyphs.
    label_x = heltec_usb_x + 24
    _txt(d, label_x, cable_low_y + 22,
         "USB-C cable - the ONLY link between PC and box",
         size=9, anchor="start", color=colors.HexColor("#333"), bold=True)
    _txt(d, label_x, cable_low_y + 10,
         "(through the Heltec's onboard CP2102N)",
         size=7.5, anchor="start", color=colors.HexColor("#666"))

    # Radio 1 - drawn as a separate island to the right of the PC, with its
    # OWN cable to the PC (not to the box). Greyed out to make clear it's
    # not part of the box's wiring.
    R1_X, R1_Y, R1_W, R1_H = 510, 240, 180, 60
    component_box(d, R1_X, R1_Y, R1_W, R1_H,
                  "Radio 1 (CAT direct to PC)",
                  colors.HexColor("#fafafa"), colors.HexColor("#888"))
    d.add(Rect(R1_X - 8, R1_Y + R1_H/2 - 5, 12, 10,
               fillColor=colors.HexColor("#888"), strokeColor=colors.black))
    # cable from radio 1 to PC's right edge
    d.add(Line(R1_X - 8, R1_Y + R1_H/2, PC_X + PC_W, R1_Y + R1_H/2,
               strokeColor=colors.HexColor("#888"), strokeWidth=2.5))

    R2_X, R2_Y, R2_W, R2_H = 510, 140, 180, 60
    component_box(d, R2_X, R2_Y, R2_W, R2_H,
                  "Radio 2 (CAT direct to PC)",
                  colors.HexColor("#fafafa"), colors.HexColor("#888"))
    d.add(Rect(R2_X - 8, R2_Y + R2_H/2 - 5, 12, 10,
               fillColor=colors.HexColor("#888"), strokeColor=colors.black))
    # cable from radio 2 to PC's right edge - jog around to enter at a
    # different Y so it doesn't overlap radio 1's cable
    d.add(PolyLine([R2_X - 8, R2_Y + R2_H/2,
                    PC_X + PC_W + 18, R2_Y + R2_H/2,
                    PC_X + PC_W + 18, R1_Y - 6,
                    PC_X + PC_W,      R1_Y - 6],
                   strokeColor=colors.HexColor("#888"), strokeWidth=2.5))

    # Caption box at the bottom explaining the architecture
    _txt(d, 30, 80,
         "ARCHITECTURE: the box is a smart USB-CDC peripheral. The PC owns "
         "all CAT and tells the box which", size=9, color=colors.HexColor("#222"), bold=True)
    _txt(d, 30, 68,
         "antenna / PTT / audio routing to apply. Panel button presses on the "
         "box are reported back to the PC as", size=9, color=colors.HexColor("#222"))
    _txt(d, 30, 56,
         "asynchronous events. No external UART hardware on the box; the "
         "Heltec's onboard CP2102N is the link.",
         size=9, color=colors.HexColor("#222"))

    # Deprecation banner directly below the Heltec body, where there's a
    # clear strip with no wires. Red so it can't be missed.
    _txt(d, CW / 2, HELTEC_BOT - 14,
         "PIVOTED FROM ORIGINAL M4 - see bench plan for the topology dead-ends with direct CAT",
         size=9, anchor="middle", color=colors.HexColor("#aa1111"), bold=True)

    color_key(d, 30, 24)
    return d


# =============================================================================
# Milestone 5
# =============================================================================

def diagram_m5():
    d = Drawing(CW, CH)
    pins = heltec(d)

    # CD4051 - drawn vertically; pin 1 top-left, pin 16 top-right.
    IC_X, IC_Y, IC_W, IC_H = 320, 90, 90, 200
    component_box(d, IC_X, IC_Y, IC_W, IC_H,
                  "CD4051BE",
                  colors.HexColor("#fff0f0"), colors.HexColor("#aa2222"))
    # Notch indicator (small white half-circle on top edge)
    d.add(Circle(IC_X + IC_W/2, IC_Y + IC_H - 5, 4,
                 fillColor=colors.white, strokeColor=colors.HexColor("#aa2222")))
    # Caption placed BELOW the IC (outside the wire routing zone)
    _txt(d, IC_X + IC_W/2, IC_Y - 12, "DIP-16 (notch up)",
         size=8, anchor="middle", color=colors.HexColor("#666"), bold=True)

    pin_pitch = (IC_H - 30) / 7
    left_pins  = [("1 X4", 1),  ("2 X6", 2),  ("3 X", 3),    ("4 X7", 4),
                  ("5 X5", 5),  ("6 INH", 6), ("7 VEE", 7),  ("8 VSS", 8)]
    right_pins = [("16 VDD", 1), ("15 X2", 2), ("14 X1", 3), ("13 X0", 4),
                  ("12 X3", 5),  ("11 A", 6),  ("10 B", 7),  ("9 C", 8)]
    cd = {}
    for label_text, slot in left_pins:
        py = IC_Y + IC_H - 14 - (slot - 1) * pin_pitch
        px = IC_X
        d.add(Line(px - 12, py, px, py, strokeColor=colors.black, strokeWidth=1.0))
        d.add(Circle(px - 12, py, 1.8, fillColor=colors.black))
        _txt(d, px - 16, py - 2, label_text, size=6.5, anchor="end", mono=True, bold=True)
        cd[label_text] = (px - 12, py)
    for label_text, slot in right_pins:
        py = IC_Y + IC_H - 14 - (slot - 1) * pin_pitch
        px = IC_X + IC_W
        d.add(Line(px, py, px + 12, py, strokeColor=colors.black, strokeWidth=1.0))
        d.add(Circle(px + 12, py, 1.8, fillColor=colors.black))
        _txt(d, px + 16, py - 2, label_text, size=6.5, anchor="start", mono=True, bold=True)
        cd[label_text] = (px + 12, py)

    # Input jack on the right side (signal flows right -> left)
    IJ_X, IJ_Y, IJ_W, IJ_H = 580, 160, 100, 60
    component_box(d, IJ_X, IJ_Y, IJ_W, IJ_H, "3.5mm IN (phone)",
                  colors.HexColor("#eef"), colors.HexColor("#225"))
    ij_tip = (IJ_X, IJ_Y + 44)
    ij_slv = (IJ_X, IJ_Y + 16)
    comp_pin(d, ij_tip[0], ij_tip[1], "TIP", anchor_side="left")
    comp_pin(d, ij_slv[0], ij_slv[1], "SLV", anchor_side="left")

    # Output jack on the left side
    OJ_X, OJ_Y, OJ_W, OJ_H = 60, 160, 100, 60
    component_box(d, OJ_X, OJ_Y, OJ_W, OJ_H, "3.5mm OUT (headphone)",
                  colors.HexColor("#efe"), colors.HexColor("#252"))
    oj_tip = (OJ_X + OJ_W, OJ_Y + 44)
    oj_slv = (OJ_X + OJ_W, OJ_Y + 16)
    comp_pin(d, oj_tip[0], oj_tip[1], "TIP", anchor_side="right")
    comp_pin(d, oj_slv[0], oj_slv[1], "SLV", anchor_side="right")

    # 10uF coupling cap between phone TIP and pin 13 (X0)
    p13 = cd["13 X0"]
    cap_x = (ij_tip[0] + p13[0]) / 2
    d.add(Line(cap_x - 5, ij_tip[1] - 7, cap_x - 5, ij_tip[1] + 7,
               strokeColor=colors.black, strokeWidth=2.0))
    d.add(Line(cap_x + 5, ij_tip[1] - 7, cap_x + 5, ij_tip[1] + 7,
               strokeColor=colors.black, strokeWidth=2.0))
    _txt(d, cap_x, ij_tip[1] + 14, "10uF", size=7.5, anchor="middle", bold=True)

    # Audio wires - all on different Y values, no shared lanes needed
    _wire(d, [ij_tip[0], ij_tip[1], cap_x - 5, ij_tip[1]], WIRE_YELLOW, 1.2)
    _wire(d, [cap_x + 5, ij_tip[1], p13[0], p13[1]], WIRE_YELLOW, 1.2)
    p3 = cd["3 X"]
    _wire(d, [p3[0], p3[1], oj_tip[0], oj_tip[1]], WIRE_YELLOW, 1.2)

    # Address lines and power - each on its own lane
    route_drop(d, pins["GPIO 39"], LANE[1], cd["11 A"],   WIRE_YELLOW)
    route_drop(d, pins["GPIO 40"], LANE[2], cd["10 B"],   WIRE_YELLOW)
    route_drop(d, pins["GPIO 4"],  LANE[3], cd["9 C"],    WIRE_YELLOW)
    route_drop(d, pins["3V3"],     LANE[4], cd["16 VDD"], WIRE_ORANGE)
    # Grounds - each from a slightly different GND tap so vertical drops don't overlap
    route_drop(d, pins["GND"],                              LANE[5], cd["8 VSS"], WIRE_BLACK)
    route_drop(d, (pins["GND"][0] + 6,  pins["GND"][1]),    LANE[6], cd["6 INH"], WIRE_BLACK)
    route_drop(d, (pins["GND"][0] + 12, pins["GND"][1]),    LANE[7], ij_slv,      WIRE_BLACK)
    route_drop(d, (pins["GND"][0] + 18, pins["GND"][1]),    LANE[8], oj_slv,      WIRE_BLACK)

    color_key(d, 30, 30)
    return d


# =============================================================================
# Build PDF
# =============================================================================

def pin_table(rows):
    head = [Paragraph("<b>From</b>", styles["Cell"]),
            Paragraph("<b>To</b>", styles["Cell"]),
            Paragraph("<b>Wire colour</b>", styles["Cell"]),
            Paragraph("<b>Notes</b>", styles["Cell"])]
    data = [head] + [[Paragraph(a, styles["CellMono"]),
                      Paragraph(b, styles["CellMono"]),
                      Paragraph(c, styles["Cell"]),
                      Paragraph(n, styles["Cell"])] for a, b, c, n in rows]
    t = Table(data, colWidths=[2.4*inch, 2.4*inch, 1.1*inch, 3.6*inch], repeatRows=1)
    t.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.grey),
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e8e8e8")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ]))
    return t


def build(out_path):
    doc = SimpleDocTemplate(
        out_path, pagesize=landscape(LETTER),
        leftMargin=0.4*inch, rightMargin=0.4*inch,
        topMargin=0.35*inch, bottomMargin=0.35*inch,
        title="SO2R Box - POC Wiring Diagrams",
        author="Carrier Wave",
    )
    flow = []

    flow.append(Paragraph(
        "<b>SO2R Box &mdash; POC Wiring Diagrams</b>",
        ParagraphStyle("T", parent=styles["Title"], fontSize=16, leading=18),
    ))
    flow.append(Paragraph(
        "One landscape page per milestone. Heltec pin labels along the bottom "
        "edge of the module match the pin map in <font face='Courier'>so2r_poc.ino</font>. "
        "Wires are colour-coded and use dedicated horizontal lanes (one lane per wire) "
        "so no two routes share a coordinate.",
        styles["Body"],
    ))

    sections = [
        ("Milestone 1 - OLED + 1 button + 1 WS2812B",
         "Toolchain sanity check. No external ICs. The WS2812B is driven direct "
         "from 3.3V GPIO; expect glitches (REVIEW B6 in person).",
         diagram_m1,
         [
            ("Heltec GPIO 4",  "Button leg 1",       "yellow", "INPUT_PULLUP; pressed = LOW."),
            ("Button leg 2",   "Heltec GND",         "black",  "Common ground."),
            ("Heltec GPIO 2",  "WS2812B DIN",        "green",  "Direct 3.3V drive - documented to glitch (REVIEW B6)."),
            ("Heltec 5V",      "WS2812B +5V",        "red",    "Pin VDD on the LED."),
            ("Heltec GND",     "WS2812B GND",        "black",  "Pin GND on the LED."),
            ("WS2812B DOUT",   "(no connection)",    "grey",   "Chain-out; unused for one LED."),
         ]),
        ("Milestone 2 - MCP23017 + 8-channel relay module",
         "The architectural linchpin. MCP23017 sits on the SECONDARY I2C bus "
         "(GPIO 41 / 42) so it doesn't share with the OLED. All eight relay "
         "drives are straight vertical wires between MCP23017 port B and the "
         "relay module's IN1-IN8 header. Coil power = USB 5V (Option A); for "
         "the 60s stress test pull the JD-VCC jumper and feed it from a 5V USB "
         "charger (Option B).",
         diagram_m2,
         [
            ("Heltec 3V3",          "MCP23017 VDD",                 "orange", "Logic supply."),
            ("Heltec GND",          "MCP23017 GND + Relay GND",     "black",  "Single shared ground."),
            ("Heltec GPIO 41",      "MCP23017 SDA",                 "blue",   "+ 4.7k pull-up to 3V3."),
            ("Heltec GPIO 42",      "MCP23017 SCL",                 "green",  "+ 4.7k pull-up to 3V3."),
            ("MCP23017 A0/A1/A2",   "MCP23017 GND (short stubs)",   "black",  "Sets I2C address to 0x20."),
            ("MCP23017 GPB0..GPB7", "Relay IN1..IN8",               "yellow", "Eight straight vertical drops; firmware polarity-aware."),
            ("Heltec 5V",           "Relay VCC + JD-VCC",           "red",    "Option A: JD-VCC jumper installed."),
            ("5V USB charger",      "Relay JD-VCC (jumper pulled)", "red",    "Option B for the stress test."),
         ]),
        ("Milestone 3 - Panel UI (4 buttons + 4 WS2812B chain)",
         "Adds the operator panel on top of M2's MCP23017 / relay wiring (which "
         "is unchanged). Four buttons feed GPIO 4-7 with INPUT_PULLUP and share "
         "a single GND bus. Four WS2812B LEDs daisy-chain DOUT-to-DIN with "
         "shared +5V and GND rails.",
         diagram_m3,
         [
            ("Heltec GPIO 4",  "BTN1 leg 1",     "yellow", "RIG 1 select."),
            ("Heltec GPIO 5",  "BTN2 leg 1",     "yellow", "RIG 2 select."),
            ("Heltec GPIO 6",  "BTN3 leg 1",     "yellow", "Band down."),
            ("Heltec GPIO 7",  "BTN4 leg 1",     "yellow", "Band up."),
            ("All button leg 2",  "Shared GND bus -> Heltec GND", "black", "One bus, one wire to Heltec."),
            ("Heltec GPIO 2",  "LED1 DIN",       "green",  "Chain start."),
            ("LEDn DOUT",      "LED(n+1) DIN",   "green",  "Daisy-chain 3 hops."),
            ("Heltec 5V",      "Shared LED +5V rail", "red", "All four LEDs in parallel."),
            ("Heltec GND",     "Shared LED GND rail", "black", "All four LEDs in parallel."),
         ]),
        ("Milestone 4 - PC <-> box USB-CDC protocol (pivoted)",
         "Original M4 (ESP32 talks CAT directly to the radio via an external "
         "CP2102N) was abandoned on the bench. The radio's USB-CAT port is a "
         "USB device, not a host - two USB devices can't talk without an "
         "intermediate host. The new M4 puts all CAT on the PC and treats the "
         "box as a USB-CDC peripheral. NO external UART hardware on the box.",
         diagram_m4,
         [
            ("Heltec USB-C",   "Mac USB port",   "(USB cable)",
                "Onboard CP2102N is the only PC link. Heltec enumerates as /dev/cu.usbserial-* on macOS."),
            ("Radio 1 CAT",    "Mac (separately)", "(USB or serial)",
                "Each radio's CAT cable goes to the PC, not the box. PC handles all per-vendor CAT (Hamlib / Sweep)."),
            ("Radio 2 CAT",    "Mac (separately)", "(USB or serial)",
                "Same arrangement for the second radio."),
            ("(MCP23017 + relay module)", "(unchanged from M2)", "(prior wiring)",
                "Antenna relay matrix wiring is identical to milestone 2."),
            ("External CP2102N module",  "(removed)",  "(none)",
                "No longer in the runtime path. Keep it for future bench tools."),
         ]),
        ("Milestone 5 - CD4051 audio mux (stretch)",
         "One CD4051BE 8:1 analog mux. Phone audio enters via a 10 uF coupling "
         "cap on X0 (pin 13). Headphone hangs off X (pin 3). Three address "
         "GPIOs choose the channel. INH tied LOW = mux enabled. Single-supply "
         "operation - negative audio peaks will clip; fine for POC.",
         diagram_m5,
         [
            ("Phone audio TIP",  "10 uF cap -> CD4051 pin 13 (X0)", "yellow", "Single channel; either L or R."),
            ("Phone audio SLV",  "Heltec GND",                       "black",  "Mandatory shared ground."),
            ("Heltec GPIO 39",   "CD4051 pin 11 (A)",                "yellow", "Address LSB."),
            ("Heltec GPIO 40",   "CD4051 pin 10 (B)",                "yellow", "Address mid."),
            ("Heltec GPIO 4",    "CD4051 pin 9 (C)",                 "yellow", "Address MSB."),
            ("Heltec 3V3",       "CD4051 pin 16 (VDD)",              "orange", "Single-supply."),
            ("Heltec GND",       "CD4051 pin 8 (VSS)",               "black",  "Ground."),
            ("Heltec GND",       "CD4051 pin 6 (INH)",               "black",  "INH LOW = mux enabled."),
            ("CD4051 pin 3 (X)", "Headphone TIP",                    "yellow", "Common output."),
            ("Headphone SLV",    "Heltec GND",                       "black",  "Closes return path."),
         ]),
    ]

    for i, (title, body, draw_fn, rows) in enumerate(sections):
        if i > 0:
            flow.append(PageBreak())
        flow.append(Paragraph(title, styles["H2"]))
        flow.append(Paragraph(body, styles["Body"]))
        flow.append(Spacer(1, 2))
        flow.append(draw_fn())
        flow.append(Spacer(1, 4))
        flow.append(pin_table(rows))

    doc.build(flow)


if __name__ == "__main__":
    out = "/home/user/carrier_wave/docs/schematics/so2r-box/POC_WIRING_DIAGRAMS.pdf"
    build(out)
    print(f"Wrote {out}")
