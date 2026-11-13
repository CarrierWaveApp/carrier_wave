#!/usr/bin/env python3
"""Schematic rework for cw_bridge.kicad_sch (2026-09-26):

- J3: 2x04 SPI screen header -> 1x04 I2C OLED header (GND / +3V3 / SCL / SDA)
- SW4/SW5 on-board RESET/BOOT tactiles -> J13/J14 1x02 headers
- J12 1x04 panel LED header (+3V3 common anode; PWR / BT / USB cathodes via R26-R28)
- LED_ST1 -> LED_BT, LED_ST2 -> LED_USB; D9/D10/D7 values renamed
- SCR_CS/SCK/MOSI (U4) and SCR_DC/SCR_RST (U5) become no-connects
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
    """Return index just past the balanced block starting at t[start]=='('."""
    d = 0
    i = start
    in_s = False
    esc = False
    while i < len(t):
        c = t[i]
        if in_s:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_s = False
        else:
            if c == '"':
                in_s = True
            elif c == "(":
                d += 1
            elif c == ")":
                d -= 1
                if d == 0:
                    return i + 1
        i += 1
    raise RuntimeError("unbalanced")


def find_toplevel(t, head_regex, must_contain=None, after=0):
    """Find a top-level element ("\n\t(" + head) whose text matches must_contain."""
    for m in re.finditer(r"\n\t\(" + head_regex, t[after:]):
        s = after + m.start() + 2  # index of '('
        e = block_end(t, s)
        blk = t[s:e]
        if must_contain is None or re.search(must_contain, blk):
            return s, e
    return None


def remove_toplevel(t, head_regex, must_contain):
    r = find_toplevel(t, head_regex, must_contain)
    if not r:
        raise RuntimeError(f"not found: {head_regex} / {must_contain}")
    s, e = r
    # also eat the preceding newline+tab so we don't leave blank lines
    return t[: s - 2] + t[e:]


def fmt(v):
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return s if s != "-0" else "0"


# ---------------------------------------------------------------- templates
def prop(name, val, x, y, a=0, hide=False, justify=None):
    j = f"\n\t\t\t\t(justify {justify})" if justify else ""
    h = "\n\t\t\t(hide yes)" if hide else ""
    return (
        f'\t\t(property "{name}" "{val}"\n'
        f"\t\t\t(at {fmt(x)} {fmt(y)} {a}){h}\n"
        f"\t\t\t(show_name no)\n\t\t\t(do_not_autoplace no)\n"
        f"\t\t\t(effects\n\t\t\t\t(font\n\t\t\t\t\t(size 1.27 1.27)\n\t\t\t\t){j}\n\t\t\t)\n\t\t)\n"
    )


def symbol(lib_id, ref, value, x, y, rot, npins, footprint="", lcsc=None, desc="",
           ref_at=None, val_at=None, prop_angle=0, in_bom=True, pin_uuids=None, sym_uuid=None,
           val_hide=False, extra_props=""):
    rx, ry = ref_at if ref_at else (x, y - 3.81)
    vx, vy = val_at if val_at else (x, y + 6.35)
    s = (
        "\t(symbol\n"
        f'\t\t(lib_id "{lib_id}")\n'
        f"\t\t(at {fmt(x)} {fmt(y)} {rot})\n"
        "\t\t(unit 1)\n\t\t(body_style 1)\n\t\t(exclude_from_sim no)\n"
        f"\t\t(in_bom {'yes' if in_bom else 'no'})\n\t\t(on_board yes)\n\t\t(in_pos_files yes)\n\t\t(dnp no)\n"
        f'\t\t(uuid "{sym_uuid or u()}")\n'
    )
    s += prop("Reference", ref, rx, ry, prop_angle, hide=ref.startswith("#"))
    s += prop("Value", value, vx, vy, prop_angle, hide=val_hide)
    s += prop("Footprint", footprint, x, y, 0, hide=True)
    s += prop("Datasheet", "~" if not ref.startswith("#") else "", x, y, 0, hide=True)
    s += prop("Description", desc, x, y, 0, hide=True)
    if lcsc is not None:
        s += prop("LCSC", lcsc, x, y, 0, hide=True)
        if lcsc:
            s += prop("JLCPCB", f"https://jlcpcb.com/partdetail/{lcsc}", x, y, 0, hide=True)
    s += extra_props
    for i in range(1, npins + 1):
        pu = pin_uuids[i - 1] if pin_uuids else u()
        s += f'\t\t(pin "{i}"\n\t\t\t(uuid "{pu}")\n\t\t)\n'
    s += (
        "\t\t(instances\n\t\t\t(project \"cw_bridge\"\n"
        f'\t\t\t\t(path "{PROJ_PATH}"\n\t\t\t\t\t(reference "{ref}")\n\t\t\t\t\t(unit 1)\n\t\t\t\t)\n\t\t\t)\n\t\t)\n'
        "\t)\n"
    )
    return s


def glabel(name, x, y, a=0, shape="bidirectional"):
    j = "right" if a in (180, 270) else "left"
    return (
        f'\t(global_label "{name}"\n\t\t(shape {shape})\n\t\t(at {fmt(x)} {fmt(y)} {a})\n'
        f"\t\t(effects\n\t\t\t(font\n\t\t\t\t(size 1.27 1.27)\n\t\t\t)\n\t\t\t(justify {j})\n\t\t)\n"
        f'\t\t(uuid "{u()}")\n'
        f'\t\t(property "Intersheetrefs" "${{INTERSHEET_REFS}}"\n\t\t\t(at {fmt(x)} {fmt(y)} {a})\n'
        f"\t\t\t(hide yes)\n\t\t\t(show_name no)\n\t\t\t(do_not_autoplace no)\n"
        f"\t\t\t(effects\n\t\t\t\t(font\n\t\t\t\t\t(size 1.27 1.27)\n\t\t\t\t)\n\t\t\t\t(justify {j})\n\t\t\t)\n\t\t)\n\t)\n"
    )


def noconn(x, y):
    return f'\t(no_connect\n\t\t(at {fmt(x)} {fmt(y)})\n\t\t(uuid "{u()}")\n\t)\n'


def pwr(kind, ref, x, y, rot):
    """power:GND / power:+3V3 with the body pointing right of the pin (rot 90 for GND, 270 for +3V3)."""
    pa = (360 - rot) % 360
    return symbol(f"power:{kind}", ref, kind, x, y, rot, 1, ref_at=(x + 5.5, y + 2.0),
                  val_at=(x + 5.5, y), prop_angle=pa, in_bom=False)


HDR1x02 = "Connector_PinHeader_2.54mm:PinHeader_1x02_P2.54mm_Vertical"
HDR1x04 = "Connector_PinHeader_2.54mm:PinHeader_1x04_P2.54mm_Vertical"
R0603 = "Resistor_SMD:R_0603_1608Metric_Pad0.98x0.95mm_HandSolder"

# ------------------------------------------------ 1. cache Conn_01x04_Pin symbol
lib = open(LIB).read()
i = lib.find('(symbol "Conn_01x04_Pin"')
e = block_end(lib, i)
cached = lib[i:e].replace('(symbol "Conn_01x04_Pin"', '(symbol "Connector:Conn_01x04_Pin"', 1)
cached = "\n".join("\t" + ln if ln else ln for ln in cached.split("\n"))
# library file indents the symbol body by one tab already; we need two for the cache
r = find_toplevel(text, r'lib_symbols')
assert r
ls_s, ls_e = r
assert '"Connector:Conn_01x04_Pin"' not in text
# insert right after the Conn_01x02_Pin cached block
m = text.find('\t\t(symbol "Connector:Conn_01x02_Pin"')
e2 = block_end(text, m)
text = text[:e2] + "\n\t" + cached + text[e2:]

# ------------------------------------------------ 2. remove SCR labels + old J3 power symbols
removals = [
    (r"global_label \"SCR_CS\"", r"\(at 313\.69 194\.31 0\)"),
    (r"global_label \"SCR_DC\"", r"\(at 313\.69 196\.85 0\)"),
    (r"global_label \"SCR_RST\"", r"\(at 300\.99 196\.85 180\)"),
    (r"global_label \"SCR_SCK\"", r"\(at 300\.99 201\.93 180\)"),
    (r"global_label \"SCR_MOSI\"", r"\(at 300\.99 199\.39 180\)"),
    (r"global_label \"SCR_DC\"", r"\(at 354\.33 57\.15 0\)"),
    (r"global_label \"SCR_RST\"", r"\(at 354\.33 59\.69 0\)"),
    (r"global_label \"SCR_CS\"", r"\(at 193\.04 161\.29 180\)"),
    (r"global_label \"SCR_SCK\"", r"\(at 193\.04 168\.91 180\)"),
    (r"global_label \"SCR_MOSI\"", r"\(at 193\.04 173\.99 180\)"),
    (r"symbol\n", r'"Reference" "#PWR05"\n'),
    (r"symbol\n", r'"Reference" "#PWR06"\n'),
    (r"symbol\n", r'"Reference" "#PWR016"\n'),
    (r"global_label \"ESP_EN\"", r"\(at 245\.11 71\.12 0\)"),
    (r"global_label \"BOOT\"", r"\(at 306\.07 71\.12 0\)"),
    (r"symbol\n", r'"Reference" "#PWR115"\n'),
    (r"symbol\n", r'"Reference" "#PWR116"\n'),
]
for head, body in removals:
    text = remove_toplevel(text, head, body)
assert 'global_label "SCR_' not in text

# ------------------------------------------------ 3. replace J3 / SW4 / SW5 symbols
def replace_symbol(t, ref, new_block):
    r = find_toplevel(t, r"symbol\n", rf'\(property "Reference" "{ref}"\n')
    assert r, ref
    s, e = r
    old = t[s:e]
    sym_uuid = re.search(r'\(uuid "([^"]+)"\)', old).group(1)
    pins = re.findall(r'\(pin "\d+"\n\t\t\t\(uuid "([^"]+)"\)', old)
    return t[:s-1] + new_block(sym_uuid, pins).rstrip("\n") + t[e:]


text = replace_symbol(
    text, "J3",
    lambda su, pins: symbol(
        "Connector:Conn_01x04_Pin", "J3", "OLED I2C", 306.07, 196.85, 0, 4, HDR1x04, "C124378",
        "128x64 I2C OLED (SSD1306 @0x3C): GND / VCC / SCL / SDA",
        ref_at=(306.07, 191.77), val_at=(306.07, 204.47), sym_uuid=su, pin_uuids=pins[:4]))
text = replace_symbol(
    text, "SW4",
    lambda su, pins: symbol(
        "Connector:Conn_01x02_Pin", "J13", "RESET", 250.19, 71.12, 0, 2, HDR1x02, "C124375",
        "panel RESET button header (EN to GND)", ref_at=(250.19, 67.31), val_at=(250.19, 77.47),
        sym_uuid=su, pin_uuids=pins[:2]))
text = replace_symbol(
    text, "SW5",
    lambda su, pins: symbol(
        "Connector:Conn_01x02_Pin", "J14", "BOOT", 311.15, 71.12, 0, 2, HDR1x02, "C124375",
        "panel BOOT button header (IO0 to GND)", ref_at=(311.15, 67.31), val_at=(311.15, 77.47),
        sym_uuid=su, pin_uuids=pins[:2]))

# ------------------------------------------------ 4. LED net / value renames
for a, b in [('"LED_ST1"', '"LED_BT"'), ('"LED_ST2"', '"LED_USB"'),
             ('"Value" "ST1 LED"', '"Value" "BT LED"'), ('"Value" "ST2 LED"', '"Value" "USB LED"')]:
    assert a in text, a
    text = text.replace(a, b)
# D7 is the VBUS-present LED; rename so "USB LED" is unambiguous
r = find_toplevel(text, r"symbol\n", r'\(property "Reference" "D7"\n')
s, e = r
text = text[:s] + text[s:e].replace('"Value" "USB LED"', '"Value" "VBUS LED"') + text[e:]

# ------------------------------------------------ 5. new items
new = ""
# no-connects for the freed pins
for x, y in [(354.33, 57.15), (354.33, 59.69), (193.04, 161.29), (193.04, 168.91), (193.04, 173.99)]:
    new += noconn(x, y)
# new J3 pin connections (tips at x=311.15)
new += pwr("GND", "#PWR05", 311.15, 194.31, 90)
new += pwr("+3V3", "#PWR016", 311.15, 196.85, 270)
new += glabel("I2C_SCL", 311.15, 199.39, 0)
new += glabel("I2C_SDA", 311.15, 201.93, 0)
# J13 / J14 connections
new += glabel("ESP_EN", 255.27, 71.12, 0)
new += symbol("power:GND", "#PWR115", "GND", 255.27, 73.66, 0, 1, ref_at=(255.27, 80.01), val_at=(255.27, 77.47), in_bom=False)
new += glabel("BOOT", 316.23, 71.12, 0)
new += symbol("power:GND", "#PWR116", "GND", 316.23, 73.66, 0, 1, ref_at=(316.23, 80.01), val_at=(316.23, 77.47), in_bom=False)
# panel LED header block (below J11 / TP5 on the right side of the sheet)
JX, JY = 378.46, 226.06
new += symbol("Connector:Conn_01x04_Pin", "J12", "PANEL LEDS", JX, JY, 0, 4, HDR1x04, "C124378",
              "front-panel status LEDs: +3V3 common anode, PWR/BT/USB cathodes",
              ref_at=(JX, JY - 5.08), val_at=(JX, JY + 7.62))
new += glabel("+3V3", JX + 5.08, JY - 2.54, 0, shape="input")
new += glabel("PNL_PWR", JX + 5.08, JY, 0)
new += glabel("PNL_BT", JX + 5.08, JY + 2.54, 0)
new += glabel("PNL_USB", JX + 5.08, JY + 5.08, 0)
RX = 403.86
for ref, y, left, right in [("R26", 223.52, "PNL_PWR", "GND"), ("R27", 228.6, "PNL_BT", "LED_BT"),
                            ("R28", 233.68, "PNL_USB", "LED_USB")]:
    new += symbol("Device:R", ref, "1k", RX, y, 90, 2, R0603, "C21190", "panel LED series resistor",
                  ref_at=(RX, y - 2.54), val_at=(RX, y + 2.54), prop_angle=270)
    new += glabel(left, RX - 3.81, y, 180)
    new += glabel(right, RX + 3.81, y, 0, shape="input" if right == "GND" else "bidirectional")

r = find_toplevel(text, r"sheet_instances")
s, e = r
text = text[:s-1] + new + text[s-1:]

assert "SCR_" not in text
open(SCH, "w").write(text)
print("written; new refs: J12 J13 J14 R26 R27 R28; J3 replaced")
