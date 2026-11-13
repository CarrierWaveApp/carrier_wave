#!/usr/bin/env python3
"""Laser-cut acrylic lid for the CW Bridge enclosure.

Reads the panel geometry (outline, screw holes, OLED window, encoder, button,
LED and switch cutouts) straight from cw_bridge_enclosure.scad so the two stay
in step, adds engraved labels, and writes:

  lid_panel.svg   mm, 1:1 — red = cut, black = engrave (imports anywhere)
  lid_panel.xcs   xTool Studio project (device P2S, 3 mm sheet), one element
                  per shape with cut / fill-engrave processing attached

Run `python3 make_lid_panel.py` (needs fontTools) after changing the .scad.
`--mirror` flips the drawing so you can cut and engrave from the back face
of the sheet (engraving under the surface, protective film left on top).

Drawing orientation: viewed from above, the rear wall (USB-C, antenna) at the
top, front at the bottom. The x/y origin is the panel's top-left corner.
"""
import argparse
import json
import math
import re
import time
import uuid
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

HERE = Path(__file__).resolve().parent
SCAD = HERE / "cw_bridge_enclosure.scad"
FONT = HERE / "fonts" / "routed-gothic.ttf"

CUT, ENGRAVE = "#FF0000", "#000000"
# xTool P2S, 3 mm cast acrylic — starting points; prefer the app's material presets.
CUT_PARAMS = dict(power=100, speed=12, repeat=1)
ENGRAVE_PARAMS = dict(power=25, speed=300, repeat=1)

# ---- Labels (model coordinates: X right, Y front->rear, mm) -----------------
TITLE = ("CW BRIDGE", 45.64, 76.43, 5.0, 1.5)  # text, cx, baseline Y, size, tracking
BTN_LABELS = ["BTN1", "BTN2", "BTN3", "RESET", "BOOT"]
LED_LABELS = ["PWR", "BT", "USB"]
LABEL_SIZE = 3.0
SMALL_SIZE = 2.2
# Free labels placed in xTool Studio (lid_panel.xs, 2026-10-14), reproduced here:
# (name, text, centre X, centre Y, cap height mm, rotation deg (screen, y down: -90 reads
# bottom->top), line pitch mm for multi-line text)
FREE_LABELS = [
    ("lbl-computer", "COMPUTER/\nPOWER", 87.50, 78.27, 2.03, 0, 4.57),    # above J9 USB-C
    ("lbl-radio", "RADIO", 100.12, 50.81, 2.03, -90, 0),                # beside J1 USB-A
    ("lbl-runflash", "RUN - FLASH", 100.12, 67.22, 2.03, -90, 0),       # beside the SW3 wall window
    ("lbl-audio-out", "AUDIO OUT", -4.30, 32.83, 2.03, 90, 0),          # J7
    ("lbl-audio-in", "AUDIO IN", -4.30, 62.09, 2.03, 90, 0),            # J8
]

# ---- Parameters from the .scad ----------------------------------------------
def load_scad_params():
    text = SCAD.read_text().split("// ============================ derived")[0]
    text = re.sub(r"//[^\n]*", "", text)          # strip comments (several statements share lines)
    ns = {"true": True, "false": False}
    for m in re.finditer(r"(\$?\w+)\s*=\s*([^;]+);", text, re.S):
        name, expr = m.group(1), m.group(2).strip()
        if name.startswith("$"):
            continue
        expr = re.sub(r"\btrue\b", "True", expr)
        expr = re.sub(r"\bfalse\b", "False", expr)
        try:
            ns[name] = eval(expr, {"__builtins__": {}}, ns)
        except Exception:
            pass
    return ns


# ---- Path building (absolute SVG commands: M L C Z) -------------------------
K = 0.5522847498  # cubic approximation of a quarter circle

def fmt(v):
    return f"{v:.3f}".rstrip("0").rstrip(".")

def circle_path(cx, cy, d):
    r = d / 2
    k = K * r
    return (f"M{fmt(cx + r)} {fmt(cy)}"
            f"C{fmt(cx + r)} {fmt(cy + k)} {fmt(cx + k)} {fmt(cy + r)} {fmt(cx)} {fmt(cy + r)}"
            f"C{fmt(cx - k)} {fmt(cy + r)} {fmt(cx - r)} {fmt(cy + k)} {fmt(cx - r)} {fmt(cy)}"
            f"C{fmt(cx - r)} {fmt(cy - k)} {fmt(cx - k)} {fmt(cy - r)} {fmt(cx)} {fmt(cy - r)}"
            f"C{fmt(cx + k)} {fmt(cy - r)} {fmt(cx + r)} {fmt(cy - k)} {fmt(cx + r)} {fmt(cy)}Z")

def rrect_path(x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    k = K * r
    x1, y1 = x + w, y + h
    return (f"M{fmt(x + r)} {fmt(y)}L{fmt(x1 - r)} {fmt(y)}"
            f"C{fmt(x1 - r + k)} {fmt(y)} {fmt(x1)} {fmt(y + r - k)} {fmt(x1)} {fmt(y + r)}"
            f"L{fmt(x1)} {fmt(y1 - r)}"
            f"C{fmt(x1)} {fmt(y1 - r + k)} {fmt(x1 - r + k)} {fmt(y1)} {fmt(x1 - r)} {fmt(y1)}"
            f"L{fmt(x + r)} {fmt(y1)}"
            f"C{fmt(x + r - k)} {fmt(y1)} {fmt(x)} {fmt(y1 - r + k)} {fmt(x)} {fmt(y1 - r)}"
            f"L{fmt(x)} {fmt(y + r)}"
            f"C{fmt(x)} {fmt(y + r - k)} {fmt(x + r - k)} {fmt(y)} {fmt(x + r)} {fmt(y)}Z")

_font = TTFont(str(FONT))
_glyphs = _font.getGlyphSet()
_cmap = _font.getBestCmap()
_upem = _font["head"].unitsPerEm

def text_width(s, size, tracking=0.0):
    scale = size / _upem
    return sum(_glyphs[_cmap.get(ord(c), ".notdef")].width for c in s) * scale + tracking * (len(s) - 1)

def text_path(x, y, s, size, anchor="middle", tracking=0.0):
    """Glyph outlines as one absolute path; (x, y) on the baseline, y down."""
    scale = size / _upem
    total = text_width(s, size, tracking)
    x0 = x - total / 2 if anchor == "middle" else x - total if anchor == "end" else x
    pen = SVGPathPen(_glyphs, ntos=fmt)
    adv = x0
    for c in s:
        g = _glyphs[_cmap.get(ord(c), ".notdef")]
        g.draw(TransformPen(pen, (scale, 0, 0, -scale, adv, y)))
        adv += g.width * scale + tracking
    return pen.getCommands()

# ---- Path parsing / transforms ---------------------------------------------
_tok = re.compile(r"[MLCQZHV]|-?\d*\.?\d+(?:e-?\d+)?", re.I)

def parse(d):
    """-> list of (cmd, [numbers]) with absolute M/L/C/Q/Z only (H/V become L)."""
    out, cmd, nums = [], None, []
    cur = [0.0, 0.0]
    def flush():
        if not cmd:
            return
        if cmd == "H":
            for v in nums:
                cur[0] = v; out.append(("L", [cur[0], cur[1]]))
        elif cmd == "V":
            for v in nums:
                cur[1] = v; out.append(("L", [cur[0], cur[1]]))
        else:
            out.append((cmd, nums))
            if nums:
                cur[0], cur[1] = nums[-2], nums[-1]
    for t in _tok.findall(d):
        if t.isalpha():
            flush()
            cmd, nums = t.upper(), []
        else:
            nums.append(float(t))
    flush()
    return out

def serialize(segs):
    return "".join(c + " ".join(fmt(v) for v in n) for c, n in segs)

def transform(segs, fx):
    return [(c, [v for i in range(0, len(n), 2) for v in fx(n[i], n[i + 1])]) for c, n in segs]

def bbox(segs):
    """True bounding box, sampling the curves."""
    xs, ys = [], []
    cur = (0, 0)
    for c, n in segs:
        if c in "ML":
            cur = (n[0], n[1]); xs.append(cur[0]); ys.append(cur[1])
        elif c == "C":
            p0, p1, p2, p3 = cur, (n[0], n[1]), (n[2], n[3]), (n[4], n[5])
            for i in range(17):
                t = i / 16
                u = 1 - t
                xs.append(u**3*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t**3*p3[0])
                ys.append(u**3*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t**3*p3[1])
            cur = p3
        elif c == "Q":
            p0, p1, p2 = cur, (n[0], n[1]), (n[2], n[3])
            for i in range(17):
                t = i / 16
                u = 1 - t
                xs.append(u*u*p0[0] + 2*u*t*p1[0] + t*t*p2[0])
                ys.append(u*u*p0[1] + 2*u*t*p1[1] + t*t*p2[1])
            cur = p2
    return min(xs), min(ys), max(xs), max(ys)

_hb = bbox(parse(text_path(0, 0, "H", 1.0)))
_CAP_RATIO = _hb[3] - _hb[1]   # cap height per unit font size

# ---- Panel geometry ---------------------------------------------------------
class Panel:
    def __init__(self, p, mirror=False):
        self.p = p
        self.ox0 = -p["fit"] - p["gutter_w"] - p["wall"]
        self.ox1 = p["pcb_l"] + p["fit"] + p["wall"]
        self.oy0 = -p["fit"] - p["wall"]
        self.oy1 = p["pcb_w"] + p["fit"] + p["wall"]
        self.w = self.ox1 - self.ox0
        self.h = self.oy1 - self.oy0
        self.mirror = mirror
        self.shapes = []   # (name, layer, d)

    # model (X right, Y front->rear) -> drawing (x right, y down, rear at top)
    def X(self, x):
        x = x - self.ox0
        return self.w - x if self.mirror else x

    def Y(self, y):
        return self.oy1 - y

    def add(self, name, layer, d):
        self.shapes.append((name, layer, d))

    def circle(self, name, layer, cx, cy, d):
        self.add(name, layer, circle_path(self.X(cx), self.Y(cy), d))

    def rect(self, name, layer, cx, cy, w, h, r=0):
        x = self.X(cx) - w / 2
        y = self.Y(cy) - h / 2
        self.add(name, layer, rrect_path(x, y, w, h, r))

    def label(self, name, x, baseline_y, s, size, anchor="middle", tracking=0.0):
        d = text_path(self.X(x), self.Y(baseline_y), s, size, anchor, tracking)
        if self.mirror:   # reverse the glyphs about the anchor so they read right from the front
            segs = transform(parse(d), lambda px, py: (2 * self.X(x) - px, py))
            d = serialize(segs)
        self.add(name, ENGRAVE, d)

    def build(self):
        p = self.p
        # --- cuts ---
        self.add("outline", CUT, rrect_path(0, 0, self.w, self.h, p["corner_r"]))
        for i, (hx, hy) in enumerate(p["holes"]):
            self.circle(f"screw-{i + 1}", CUT, hx, hy, p["screw_d"])
        oc = p["oled_c"]
        self.rect("oled-window", CUT, oc[0], oc[1] + p["oled_win_dy"], p["oled_win"][0], p["oled_win"][1], 0.5)
        for sx in (-1, 1):
            for sy in (-1, 1):
                self.circle(f"oled-m2-{sx}{sy}", CUT, oc[0] + sx * p["oled_holes"][0] / 2,
                            oc[1] + sy * p["oled_holes"][1] / 2, p["oled_m2_d"])
        self.circle("encoder", CUT, p["enc_c"][0], p["enc_c"][1], p["enc_hole_d"])
        for (bx, by), lab in zip(p["btn_pos"], BTN_LABELS):
            self.circle(f"btn-{lab.lower()}", CUT, bx, by, p["btn_ds"][BTN_LABELS.index(lab)])
        for (lx, ly), lab in zip(p["led_pos"], LED_LABELS):
            self.circle(f"led-{lab.lower()}", CUT, lx, ly, p["led_d"])
        if p["sw3_slot_on"]:
            sw, sh = p["sw3_slot"]
            self.rect("sw3-slot", CUT, p["sw3_c"][0], p["sw3_c"][1], sw, sh, sw / 2)
        # --- engraving ---
        t, cx, by, size, track = TITLE
        self.label("title", cx, by, t, size, "middle", track)
        for (bx, by_), lab, bd in zip(p["btn_pos"], BTN_LABELS, p["btn_ds"]):
            # front row: label below (toward the front); rear row: label above
            front = by_ < p["pcb_w"] / 2
            y = by_ - bd / 2 - 1.2 - LABEL_SIZE if front else by_ + bd / 2 + 2.1
            self.label(f"lbl-{lab.lower()}", bx, y, lab, LABEL_SIZE)
        for (lx, ly), lab in zip(p["led_pos"], LED_LABELS):
            self.label(f"lbl-{lab.lower()}", lx - p["led_d"] / 2 - 2.5, ly - LABEL_SIZE * 0.36, lab, LABEL_SIZE * 0.95, "end")
        if p["sw3_slot_on"]:
            sx, sy = p["sw3_c"]
            sh = p["sw3_slot"][1]
            self.label("lbl-flash", sx, sy + sh / 2 + 1.0, "FLASH", SMALL_SIZE)
            self.label("lbl-run", sx, sy - sh / 2 - 1.0 - SMALL_SIZE, "RUN", SMALL_SIZE)
        for name, text, cx, cy, cap, rot, pitch in FREE_LABELS:
            self.free_label(name, text, cx, cy, cap, rot, pitch)
        return self

    def free_label(self, name, text, cx, cy, cap, rot, pitch):
        """Centred (multi-line) label, rotated about its centre; mirror reflects the result."""
        size = cap / _CAP_RATIO
        segs = []
        for i, line in enumerate(text.split("\n")):
            segs += parse(text_path(0, i * pitch, line, size, "middle"))
        x0, y0, x1, y1 = bbox(segs)
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        c, s_ = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        px, py = cx - self.ox0, self.Y(cy)   # unmirrored drawing coords
        segs = transform(segs, lambda x, y: (px + c * (x - mx) - s_ * (y - my), py + s_ * (x - mx) + c * (y - my)))
        if self.mirror:
            segs = transform(segs, lambda x, y: (self.w - x, y))
        self.add(name, ENGRAVE, serialize(segs))

    # --- outputs ---
    def svg(self):
        els = []
        for name, layer, d in self.shapes:
            if layer == CUT:
                els.append(f'<path id="{name}" d="{d}" fill="none" stroke="{CUT}" stroke-width="0.1"/>')
            else:
                els.append(f'<path id="{name}" d="{d}" fill="{ENGRAVE}" stroke="none" fill-rule="nonzero"/>')
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w:.1f}mm" height="{self.h:.1f}mm" '
                f'viewBox="0 0 {self.w:.3f} {self.h:.3f}">\n'
                f'<!-- CW Bridge acrylic lid, mm 1:1. red = cut, black = engrave'
                f'{" (MIRRORED: cut from the back face)" if self.mirror else ""} -->\n'
                + "\n".join(els) + "\n</svg>\n")

    def xcs(self, margin=10.0):
        """xTool Studio / Creative Space project. Elements carry local path
        data with x/y/width/height placing them on the work area."""
        canvas_id = uuid.uuid4().hex
        displays, procs = [], []
        for z, (name, layer, d) in enumerate(self.shapes):
            segs = parse(d)
            x0, y0, x1, y1 = bbox(segs)
            local = serialize(transform(segs, lambda px, py: (px - x0, py - y0)))
            cut = layer == CUT
            eid = uuid.uuid4().hex
            displays.append({
                "id": eid, "type": "PATH", "name": name,
                "x": round(x0 + margin, 3), "y": round(y0 + margin, 3),
                "width": round(x1 - x0, 3), "height": round(y1 - y0, 3),
                "angle": 0, "scale": {"x": 1, "y": 1}, "skew": {"x": 0, "y": 0},
                "pivot": {"x": 0, "y": 0}, "localSkew": {"x": 0, "y": 0},
                "offsetX": round(x0 + margin, 3), "offsetY": round(y0 + margin, 3),
                "lockRatio": True, "isClosePath": True, "zOrder": z,
                "isFill": not cut, "fillRule": "nonzero",
                "lineColor": 0xFF0000 if cut else 0x000000,
                "fillColor": 0x000000,
                "layerColor": CUT if cut else ENGRAVE,
                "layerTag": "cut" if cut else "engrave",
                "visible": True, "lockState": False,
                "dPath": local, "points": [], "graphicX": 0, "graphicY": 0,
            })
            ptype = "VECTOR_CUTTING" if cut else "FILL_VECTOR_ENGRAVING"
            params = CUT_PARAMS if cut else ENGRAVE_PARAMS
            procs.append([eid, {
                "processingType": ptype, "type": "PATH", "isFill": not cut,
                "data": {ptype: {"materialType": "customize", "processIgnore": False,
                                 "parameter": {"customize": dict(params)}}},
            }])
        now = int(time.time() * 1000)
        return {
            "canvasId": canvas_id,
            "canvas": [{"id": canvas_id, "title": "CW Bridge lid", "hidden": False,
                        "displays": displays}],
            "extId": "P2S", "extName": "P2S",
            "device": {
                "id": "", "power": 0,
                "data": {"dataType": "Map", "value": [[canvas_id, {
                    "mode": "LASER_PLANE",
                    "data": {"material": 0, "thickness": 3,
                             "LASER_PLANE": {"material": 0, "thickness": 3}},
                    "displays": {"dataType": "Map", "value": procs},
                }]]},
                "materialList": [], "materialTypeList": [], "customProjectData": {},
            },
            "version": "1.9.11", "created": now, "modify": now,
            "ua": "make_lid_panel.py", "meta": {"source": "carrier_wave/hardware/bridge/enclosure"},
        }


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--mirror", action="store_true", help="flip for cutting from the back face")
    ap.add_argument("--out", default="lid_panel", help="output basename")
    a = ap.parse_args()
    p = load_scad_params()
    p.setdefault("oled_m2_d", 2.2)
    panel = Panel(p, a.mirror).build()
    (HERE / f"{a.out}.svg").write_text(panel.svg())
    (HERE / f"{a.out}.xcs").write_text(json.dumps(panel.xcs(), separators=(",", ":")))
    print(f"{a.out}.svg / .xcs: {panel.w:.1f} x {panel.h:.1f} mm, {len(panel.shapes)} shapes"
          f"{' (mirrored)' if a.mirror else ''}")


if __name__ == "__main__":
    main()
