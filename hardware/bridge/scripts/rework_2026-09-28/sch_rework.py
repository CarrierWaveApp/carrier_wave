#!/usr/bin/env python3
"""Schematic rework for cw_bridge.kicad_sch (2026-09-28, rev 2.1):

- SW1 on-board rotary encoder -> J15 1x05 header for an off-board KY-040
  style encoder module (CLK / DT / SW / +3V3 / GND, in the module's pin order)
- every panel/debug header (J3 J4 J5 J6 J11 J12 J13 J14) moves from a 2.54 mm
  pin header to the JST PH 2.0 mm top-entry housing J10 already uses
  (B2B / B4B / B5B). They are hand-soldered: LCSC blanked, JLCPCB link dropped.
- title block brought up to date (rev 2.1, WROOM)
"""
import re
import uuid

SCH = "/Users/jsvana/projects/carrier_wave/hardware/bridge/cw_bridge.kicad_sch"
LIB = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols/Connector.kicad_sym"
PROJ_PATH = "/a1b2c3d4-e5f6-7890-abcd-ef1234567890"

text = open(SCH).read()


def u():
    return str(uuid.uuid4())


def block_end(t, start):
    d = 0; i = start; in_s = False; esc = False
    while i < len(t):
        c = t[i]
        if in_s:
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == '"': in_s = False
        else:
            if c == '"': in_s = True
            elif c == "(": d += 1
            elif c == ")":
                d -= 1
                if d == 0: return i + 1
        i += 1
    raise RuntimeError("unbalanced")


def find_toplevel(t, head_regex, must_contain=None, after=0):
    for m in re.finditer(r"\n\t\(" + head_regex, t[after:]):
        s = after + m.start() + 2
        e = block_end(t, s)
        if must_contain is None or re.search(must_contain, t[s:e]):
            return s, e
    return None


def remove_toplevel(t, head_regex, must_contain):
    r = find_toplevel(t, head_regex, must_contain)
    if not r:
        raise RuntimeError(f"not found: {head_regex} / {must_contain}")
    s, e = r
    return t[: s - 2] + t[e:]


def fmt(v):
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return s if s != "-0" else "0"


def prop(name, val, x, y, a=0, hide=False, justify=None):
    j = f"\n\t\t\t\t(justify {justify})" if justify else ""
    h = "\n\t\t\t(hide yes)" if hide else ""
    return (f'\t\t(property "{name}" "{val}"\n\t\t\t(at {fmt(x)} {fmt(y)} {a}){h}\n'
            f"\t\t\t(show_name no)\n\t\t\t(do_not_autoplace no)\n"
            f"\t\t\t(effects\n\t\t\t\t(font\n\t\t\t\t\t(size 1.27 1.27)\n\t\t\t\t){j}\n\t\t\t)\n\t\t)\n")


def symbol(lib_id, ref, value, x, y, rot, npins, footprint="", lcsc=None, desc="",
           ref_at=None, val_at=None, prop_angle=0, in_bom=True):
    rx, ry = ref_at if ref_at else (x, y - 3.81)
    vx, vy = val_at if val_at else (x, y + 6.35)
    s = ("\t(symbol\n" f'\t\t(lib_id "{lib_id}")\n' f"\t\t(at {fmt(x)} {fmt(y)} {rot})\n"
         "\t\t(unit 1)\n\t\t(body_style 1)\n\t\t(exclude_from_sim no)\n"
         f"\t\t(in_bom {'yes' if in_bom else 'no'})\n\t\t(on_board yes)\n\t\t(in_pos_files yes)\n\t\t(dnp no)\n"
         f'\t\t(uuid "{u()}")\n')
    s += prop("Reference", ref, rx, ry, prop_angle, hide=ref.startswith("#"))
    s += prop("Value", value, vx, vy, prop_angle)
    s += prop("Footprint", footprint, x, y, 0, hide=True)
    s += prop("Datasheet", "~" if not ref.startswith("#") else "", x, y, 0, hide=True)
    s += prop("Description", desc, x, y, 0, hide=True)
    if lcsc is not None:
        s += prop("LCSC", lcsc, x, y, 0, hide=True)
    for i in range(1, npins + 1):
        s += f'\t\t(pin "{i}"\n\t\t\t(uuid "{u()}")\n\t\t)\n'
    s += ("\t\t(instances\n\t\t\t(project \"cw_bridge\"\n"
          f'\t\t\t\t(path "{PROJ_PATH}"\n\t\t\t\t\t(reference "{ref}")\n\t\t\t\t\t(unit 1)\n\t\t\t\t)\n\t\t\t)\n\t\t)\n\t)\n')
    return s


def glabel(name, x, y, a=0, shape="bidirectional"):
    j = "right" if a in (180, 270) else "left"
    return (f'\t(global_label "{name}"\n\t\t(shape {shape})\n\t\t(at {fmt(x)} {fmt(y)} {a})\n'
            f"\t\t(effects\n\t\t\t(font\n\t\t\t\t(size 1.27 1.27)\n\t\t\t)\n\t\t\t(justify {j})\n\t\t)\n"
            f'\t\t(uuid "{u()}")\n'
            f'\t\t(property "Intersheetrefs" "${{INTERSHEET_REFS}}"\n\t\t\t(at {fmt(x)} {fmt(y)} {a})\n'
            f"\t\t\t(hide yes)\n\t\t\t(show_name no)\n\t\t\t(do_not_autoplace no)\n"
            f"\t\t\t(effects\n\t\t\t\t(font\n\t\t\t\t\t(size 1.27 1.27)\n\t\t\t\t)\n\t\t\t\t(justify {j})\n\t\t\t)\n\t\t)\n\t)\n")


def pwr(kind, ref, x, y, rot):
    pa = (360 - rot) % 360
    return symbol(f"power:{kind}", ref, kind, x, y, rot, 1, ref_at=(x + 5.5, y + 2.0),
                  val_at=(x + 5.5, y), prop_angle=pa, in_bom=False)


PH = {2: "Connector_JST:JST_PH_B2B-PH-K_1x02_P2.00mm_Vertical",
      4: "Connector_JST:JST_PH_B4B-PH-K_1x04_P2.00mm_Vertical",
      5: "Connector_JST:JST_PH_B5B-PH-K_1x05_P2.00mm_Vertical"}

# ------------------------------------------------ 1. cache Conn_01x05_Pin
lib = open(LIB).read()
i = lib.find('(symbol "Conn_01x05_Pin"')
e = block_end(lib, i)
cached = lib[i:e].replace('(symbol "Conn_01x05_Pin"', '(symbol "Connector:Conn_01x05_Pin"', 1)
cached = "\n".join("\t" + ln if ln else ln for ln in cached.split("\n"))
assert '"Connector:Conn_01x05_Pin"' not in text
m = text.find('\t\t(symbol "Connector:Conn_01x04_Pin"')
assert m > 0
e2 = block_end(text, m)
text = text[:e2] + "\n\t" + cached + text[e2:]

# ------------------------------------------------ 2. remove SW1 and its wiring
removals = [
    (r"symbol\n", r'"Reference" "SW1"\n'),
    (r"symbol\n", r'"Reference" "#PWR08"\n'),   # GND on the encoder common
    (r"symbol\n", r'"Reference" "#PWR09"\n'),   # GND on the switch return
    (r"global_label \"ENC_DT\"", r"\(at 130\.81 214\.63 180\)"),
    (r"global_label \"ENC_CLK\"", r"\(at 130\.81 204\.47 180\)"),
    (r"global_label \"ENC_SW\"", r"\(at 147\.32 207\.01 0\)"),
    (r"wire\n", r"\(xy 146\.05 212\.09\) \(xy 151\.13 212\.09\)"),
    (r"wire\n", r"\(xy 151\.13 212\.09\) \(xy 151\.13 214\.63\)"),
    (r"wire\n", r"\(xy 147\.32 207\.01\) \(xy 146\.05 207\.01\)"),
    (r"wire\n", r"\(xy 129\.54 209\.55\) \(xy 130\.81 209\.55\)"),
]
for head, body in removals:
    text = remove_toplevel(text, head, body)
assert '"Reference" "SW1"' not in text

# ------------------------------------------------ 3. headers -> JST PH, hand-soldered
def retarget(t, ref, fp):
    r = find_toplevel(t, r"symbol\n", rf'\(property "Reference" "{ref}"\n')
    assert r, ref
    s, e = r
    blk = t[s:e]
    blk, n = re.subn(r'\(property "Footprint" "[^"]*"', f'(property "Footprint" "{fp}"', blk)
    assert n == 1, ref
    blk, n = re.subn(r'\(property "LCSC" "[^"]*"', '(property "LCSC" ""', blk)
    assert n == 1, ref
    # drop the JLCPCB link property block entirely
    j = blk.find('\t\t(property "JLCPCB"')
    if j >= 0:
        je = block_end(blk, j + 2)
        blk = blk[:j] + blk[je + 1:]  # +1 eats the newline
    return t[:s] + blk + t[e:]


for ref in ["J3", "J12"]:
    text = retarget(text, ref, PH[4])
for ref in ["J4", "J5", "J6", "J11", "J13", "J14"]:
    text = retarget(text, ref, PH[2])

# ------------------------------------------------ 4. J15 encoder header where SW1 sat
JX, JY = 135.89, 209.55          # pin tips at x = 140.97, y = 204.47 .. 214.63 (2.54 pitch)
new = symbol("Connector:Conn_01x05_Pin", "J15", "ENCODER", JX, JY, 0, 5, PH[5], "",
             "off-board rotary encoder module (KY-040 pinout): CLK / DT / SW / +3V3 / GND",
             ref_at=(JX, JY - 8.89), val_at=(JX, JY + 8.89))
PX = JX + 5.08
new += glabel("ENC_CLK", PX, JY - 5.08, 0)
new += glabel("ENC_DT", PX, JY - 2.54, 0)
new += glabel("ENC_SW", PX, JY, 0)
new += pwr("+3V3", "#PWR117", PX, JY + 2.54, 270)
new += pwr("GND", "#PWR118", PX, JY + 5.08, 90)

r = find_toplevel(text, r"sheet_instances")
s, e = r
text = text[:s - 1] + new + text[s - 1:]

# ------------------------------------------------ 5. title block
text = text.replace('(rev "1.0")', '(rev "2.1")', 1)
text = text.replace('(date "2026-04-25")', '(date "2026-09-28")', 1)
text = text.replace('(comment 1 "Seeed XIAO ESP32-S3 + ES8388 codec + PCAL6416A I/O expander + USB host")',
                    '(comment 1 "ESP32-S3-WROOM-1U + ES8388 codec + PCAL6416A I/O expander + USB host")', 1)
text = text.replace('(comment 3 "Pinout: https://wiki.seeedstudio.com/xiao_esp32s3_getting_started/")',
                    '(comment 3 "Panel I/O on JST-PH 2.0 mm headers; encoder is an off-board KY-040 module on J15")', 1)

open(SCH, "w").write(text)
print("written: SW1 -> J15 (JST PH 1x05); J3 J12 -> B4B; J4 J5 J6 J11 J13 J14 -> B2B; all hand-solder")
