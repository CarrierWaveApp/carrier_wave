#!/usr/bin/env python3
"""Generate JLCPCB assembly files (BOM + CPL) for the CW Bridge board.

Reads `cw_bridge.kicad_sch` (source of truth for LCSC part numbers, stored as a
hidden "LCSC" property on each symbol) and `cw_bridge.kicad_pcb` (positions),
and writes:

    production/cw_bridge_bom.csv   — Comment, Designator, Footprint, LCSC Part #
    production/cw_bridge_cpl.csv   — Designator, Mid X, Mid Y, Layer, Rotation

Usage:  python3 jlcpcb_export.py        (no dependencies beyond stdlib)

Conventions:
- The uploaded BOM and CPL must describe the SAME set of parts: JLCPCB's DFM
  check flags any BOM designator that has no matching CPL row ("designator
  doesn't exist in the CPL file"). So symbols without an LCSC property, with an
  empty/"-" LCSC value, or marked DNP are excluded from BOTH the BOM and the
  CPL. Hand-assembly parts (no LCSC, not DNP) are written to a separate
  cw_bridge_hand_assembly.csv so they stay visible without tripping the check.
- Mid X/Y is the center of the footprint's pad bounding box, not the KiCad
  footprint origin — this matters for U4 (XIAO), whose footprint origin is a
  corner pad. Y is negated (JLCPCB/IPC convention is Y-up; KiCad is Y-down).
- Rotation = KiCad rotation + per-package offset from ROTATION_OVERRIDES
  (JLCPCB's feeder zero-orientation differs from the KiCad library for many
  packages; offsets below come from the JLCKicadTools community database).
  ALWAYS eyeball polarized/keyed parts (U3 U5 U7 U8 U9, D3 D4 D5, J9, SW2) in
  JLCPCB's component-placement preview before paying — the overrides are a
  best effort, the preview render is authoritative.
"""

import csv
import math
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
SCH = os.path.join(HERE, "cw_bridge.kicad_sch")
PCB = os.path.join(HERE, "cw_bridge.kicad_pcb")
OUT_DIR = os.path.join(HERE, "production")

# (footprint-name regex, rotation offset in degrees, added to KiCad rotation)
# Subset of https://github.com/matthewlai/JLCKicadTools cpl_rotations_db.csv
# relevant to this board.
ROTATION_OVERRIDES = [
    (r"^SOT-23", -90),       # U8 MCP73831 (SOT-23-5)
    (r"^TSSOP-", 270),       # U5 PCAL6416APW
    (r"^QFN-28", 270),       # U3 ES8388
    (r"^VSSOP-8_", 180),     # U9 TPS61085 (check preview: some libs need 270)
    # SOT-583 (U7), GCT USB-C (J9), PCM12 (SW2): no community data — verify
    # in the JLCPCB placement preview and fix up there if needed.
]


def parse_sexpr(text):
    toks = re.findall(r'\(|\)|"(?:[^"\\]|\\.)*"|[^\s()"]+', text)
    pos = 0

    def rd():
        nonlocal pos
        t = toks[pos]
        pos += 1
        if t == "(":
            lst = []
            while toks[pos] != ")":
                lst.append(rd())
            pos += 1
            return lst
        return t

    out = []
    while pos < len(toks):
        out.append(rd())
    return out


def unq(s):
    return s[1:-1] if isinstance(s, str) and s.startswith('"') else s


def find_all(node, tag):
    for sub in node:
        if isinstance(sub, list) and sub and sub[0] == tag:
            yield sub


def props(node):
    return {unq(p[1]): unq(p[2]) for p in find_all(node, "property") if len(p) >= 3}


def schematic_parts():
    """Reference -> dict(value, lcsc, dnp) for real components (skip power symbols)."""
    tree = parse_sexpr(open(SCH).read())
    parts = {}
    for sym in find_all(tree[0], "symbol"):
        if not any(find_all(sym, "lib_id")):
            continue
        p = props(sym)
        ref = p.get("Reference", "")
        if not ref or ref.startswith("#"):
            continue
        dnp = any(unq(d[1]) == "yes" for d in find_all(sym, "dnp"))
        if any(unq(d[1]) == "no" for d in find_all(sym, "in_bom")):
            continue  # e.g. test points: copper-only, nothing to order or place
        parts[ref] = {
            "value": p.get("Value", ""),
            "lcsc": p.get("LCSC", "").strip(),
            "dnp": dnp,
        }
    return parts


def pcb_footprints():
    """Yield dicts: ref, fp name, mid x/y (pad-bbox center, mm), layer, rotation."""
    tree = parse_sexpr(open(PCB).read())
    for fp in find_all(tree[0], "footprint"):
        name = unq(fp[1]).split(":")[-1]
        p = props(fp)
        ref = p.get("Reference", "")
        layer = unq(next(find_all(fp, "layer"))[1])
        at = next(find_all(fp, "at"))
        ox, oy = float(at[1]), float(at[2])
        rot = float(at[3]) if len(at) > 3 else 0.0
        # pad-bbox center in footprint-local coords, then rotate into board coords
        xs, ys = [], []
        for pad in find_all(fp, "pad"):
            pat = next(find_all(pad, "at"))
            xs.append(float(pat[1]))
            ys.append(float(pat[2]))
        if xs:
            cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
            a = math.radians(rot)  # KiCad: positive = CCW on a Y-down canvas
            mx = ox + cx * math.cos(a) + cy * math.sin(a)
            my = oy + -cx * math.sin(a) + cy * math.cos(a)
        else:
            mx, my = ox, oy
        yield {"ref": ref, "fp": name, "x": mx, "y": my, "layer": layer, "rot": rot}


def jlc_rotation(fp_name, kicad_rot):
    off = 0
    for pat, o in ROTATION_OVERRIDES:
        if re.match(pat, fp_name):
            off = o
            break
    return (kicad_rot + off) % 360


def main():
    parts = schematic_parts()
    os.makedirs(OUT_DIR, exist_ok=True)

    placements = [f for f in pcb_footprints() if f["ref"] in parts]

    def refkey(r):
        m = re.match(r"([A-Za-z]+)(\d+)", r)
        return (m.group(1), int(m.group(2)))

    def assembled(f):
        """True if JLC places this part: has a real LCSC number and not DNP.

        The uploaded BOM and CPL must cover the same designators, so this is the
        single gate for both files. Everything else goes to the hand-assembly
        list instead."""
        sp = parts[f["ref"]]
        return not sp["dnp"] and sp["lcsc"] not in ("", "-")

    jlc = [f for f in placements if assembled(f)]
    hand = [f for f in placements if not assembled(f)]

    # BOM (JLC-assembled only): one line per LCSC part number. JLC matches on
    # the LCSC #, so the same part must not appear on two lines even when its
    # designators use different footprint pad-variants (e.g. HandSolder vs
    # standard) or carry different net-name Values (0.1uF vs 100nF are one cap).
    # Comment/Footprint on the merged line come from the lowest-numbered ref.
    groups = {}
    for f in jlc:
        groups.setdefault(parts[f["ref"]]["lcsc"], []).append(f["ref"])

    bom_path = os.path.join(OUT_DIR, "cw_bridge_bom.csv")
    with open(bom_path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["Comment", "Designator", "Footprint", "LCSC Part #"])
        by_ref = {f["ref"]: f for f in jlc}
        for lcsc, refs in sorted(
            groups.items(), key=lambda kv: refkey(sorted(kv[1], key=refkey)[0])
        ):
            refs = sorted(refs, key=refkey)
            rep = by_ref[refs[0]]
            w.writerow([parts[rep["ref"]]["value"], ",".join(refs), rep["fp"], lcsc])

    cpl_path = os.path.join(OUT_DIR, "cw_bridge_cpl.csv")
    with open(cpl_path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["Designator", "Mid X", "Mid Y", "Layer", "Rotation"])
        for f in sorted(jlc, key=lambda f: refkey(f["ref"])):
            w.writerow(
                [
                    f["ref"],
                    f"{f['x']:.4f}",
                    f"{-f['y']:.4f}",
                    "Top" if f["layer"] == "F.Cu" else "Bottom",
                    f"{jlc_rotation(f['fp'], f['rot']):g}",
                ]
            )

    # Hand-assembly reference (parts JLC does NOT place): no LCSC / DNP.
    hand_path = os.path.join(OUT_DIR, "cw_bridge_hand_assembly.csv")
    hgroups = {}
    for f in hand:
        sp = parts[f["ref"]]
        key = (sp["value"], f["fp"], sp["dnp"])
        hgroups.setdefault(key, []).append(f["ref"])
    with open(hand_path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["Comment", "Designator", "Footprint"])
        for (value, fp, dnp), refs in sorted(
            hgroups.items(), key=lambda kv: refkey(sorted(kv[1], key=refkey)[0])
        ):
            comment = value + (" [DNP]" if dnp else "")
            w.writerow([comment, ",".join(sorted(refs, key=refkey)), fp])

    print(f"BOM: {bom_path} ({len(groups)} lines, JLC-assembled)")
    print(f"CPL: {cpl_path} ({len(jlc)} parts placed)")
    print(f"Hand assembly: {hand_path} ({len(hand)} parts)")
    if hand:
        print(f"  Excluded from JLC BOM/CPL: {', '.join(sorted((f['ref'] for f in hand), key=refkey))}")


if __name__ == "__main__":
    main()
