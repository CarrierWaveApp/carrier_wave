#!/usr/bin/env python3
"""PCB prep for the 2026-09-26 rework (run with KiCad's bundled python).

1. LED_ST1/LED_ST2 -> LED_BT/LED_USB (text level, before load)
2. remove SW4, SW5, old J3 + all SCR_* copper
3. place J3 (1x04 OLED), J12 (1x04 panel LEDs), J13/J14 (1x02 RESET/BOOT), R26-R28
4. rotate C48 so its +5V pad faces U11 VIN
5. prune dangling tracks/vias (net-aware, zone-aware) - removes the XIAO-era orphans
6. silk: move U11 / R23 references, add header labels
7. hand-route the buck power loop, FB divider, module GND/3V3 vias
"""
import math
import pcbnew

PCB = "/Users/jsvana/projects/carrier_wave/hardware/bridge/cw_bridge.kicad_pcb"
LIB = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints"
HDR = f"{LIB}/Connector_PinHeader_2.54mm.pretty"
RES = f"{LIB}/Resistor_SMD.pretty"
R0603 = "R_0603_1608Metric_Pad0.98x0.95mm_HandSolder"


def mm(v):
    return pcbnew.FromMM(v)


def V(x, y):
    return pcbnew.VECTOR2I(mm(x), mm(y))


# ---------------------------------------------------------------- 1. net rename
t = open(PCB).read()
KEEP = []  # removed items must stay referenced or the SWIG runtime breaks
t = t.replace('"LED_ST1"', '"LED_BT"').replace('"LED_ST2"', '"LED_USB"')
open(PCB, "w").write(t)

b = pcbnew.LoadBoard(PCB)
info = b.GetNetInfo()


def net(name):
    n = info.GetNetItem(name)
    if n is not None and n.GetNetCode() != 0:
        return n
    n = pcbnew.NETINFO_ITEM(b, name, info.GetNetCount())
    b.Add(n)
    return n


# ---------------------------------------------------------------- 2. removals
for ref in ["SW4", "SW5", "J3"]:
    fp = b.FindFootprintByReference(ref)
    assert fp, ref
    b.Remove(fp)
    KEEP.append(fp)
n_scr = 0
for tr in list(b.GetTracks()):
    if tr.GetNetname().startswith("SCR_"):
        b.Remove(tr)
        KEEP.append(tr)
        n_scr += 1
print(f"removed SW4 SW5 J3 and {n_scr} SCR_* track items")

# ---------------------------------------------------------------- 3. placements
def place(lib, fpname, ref, value, x, y, rot, lcsc, pads, desc=""):
    fp = pcbnew.FootprintLoad(lib, fpname)
    assert fp, fpname
    b.Add(fp)
    fp.SetReference(ref)
    fp.SetValue(value)
    fp.SetPosition(V(x, y))
    fp.SetOrientationDegrees(rot)
    fp.SetField("LCSC", lcsc)
    fp.SetField("JLCPCB", f"https://jlcpcb.com/partdetail/{lcsc}")
    if desc:
        fp.SetField("Description", desc)
    for pad in fp.Pads():
        if pad.GetNumber() in pads:
            pad.SetNet(net(pads[pad.GetNumber()]))
    return fp


place(HDR, "PinHeader_1x04_P2.54mm_Vertical", "J3", "OLED I2C", 142.0, 106.0, 0, "C124378",
      {"1": "GND", "2": "+3V3", "3": "I2C_SCL", "4": "I2C_SDA"}, "128x64 I2C OLED header")
place(HDR, "PinHeader_1x04_P2.54mm_Vertical", "J12", "PANEL LEDS", 138.0, 118.0, 0, "C124378",
      {"1": "+3V3", "2": "PNL_PWR", "3": "PNL_BT", "4": "PNL_USB"}, "front-panel status LEDs")
place(HDR, "PinHeader_1x02_P2.54mm_Vertical", "J13", "RESET", 108.0, 124.0, 0, "C124375",
      {"1": "ESP_EN", "2": "GND"}, "panel RESET button")
place(HDR, "PinHeader_1x02_P2.54mm_Vertical", "J14", "BOOT", 118.0, 124.0, 0, "C124375",
      {"1": "BOOT", "2": "GND"}, "panel BOOT button")
# rot 180 => pad 1 (PNL side) east toward J12, pad 2 west toward U5/D9/D10
place(RES, R0603, "R26", "1k", 132.5, 116.5, 180, "C21190", {"1": "PNL_PWR", "2": "GND"})
place(RES, R0603, "R27", "1k", 132.5, 119.5, 180, "C21190", {"1": "PNL_BT", "2": "LED_BT"})
place(RES, R0603, "R28", "1k", 132.5, 122.5, 180, "C21190", {"1": "PNL_USB", "2": "LED_USB"})

# ---------------------------------------------------------------- 4. C48 flip
c48 = b.FindFootprintByReference("C48")
c48.SetOrientationDegrees(180)
p1 = [p for p in c48.Pads() if p.GetNumber() == "1"][0]
assert abs(p1.GetPosition().x / 1e6 - 96.04) < 0.05, p1.GetPosition()

# ---------------------------------------------------------------- 5. prune dangling
CU = [pcbnew.F_Cu, pcbnew.In1_Cu, pcbnew.In2_Cu, pcbnew.B_Cu]
zones = list(b.Zones())


def in_zone(pt, netcode, layer):
    for z in zones:
        if z.GetNetCode() != netcode or not z.IsOnLayer(layer):
            continue
        poly = z.GetFilledPolysList(layer)
        if poly and poly.Contains(pt):
            return True
    return False


def end_connected(item, pt, layer, tracks, vias, pads):
    nc = item.GetNetCode()
    for p in pads.get(nc, []):
        if p.IsOnLayer(layer) and p.HitTest(pt, 0):
            return True
    for v in vias.get(nc, []):
        if v is not item and v.HitTest(pt, 0):
            return True
    for tr in tracks.get(nc, []):
        if tr is not item and tr.GetLayer() == layer and tr.HitTest(pt, 0):
            return True
    return in_zone(pt, nc, layer)


def prune(skip_locked=True):
    removed_total = 0
    while True:
        tracks, vias, pads = {}, {}, {}
        for tr in b.GetTracks():
            (vias if tr.Type() == pcbnew.PCB_VIA_T else tracks).setdefault(tr.GetNetCode(), []).append(tr)
        for fp in b.GetFootprints():
            for p in fp.Pads():
                if p.GetNetCode():
                    pads.setdefault(p.GetNetCode(), []).append(p)
        dead = []
        for nc, lst in tracks.items():
            for tr in lst:
                if skip_locked and tr.IsLocked():
                    continue
                if tr.GetLength() == 0:
                    dead.append(tr)
                    continue
                for pt in (tr.GetStart(), tr.GetEnd()):
                    if not end_connected(tr, pt, tr.GetLayer(), tracks, vias, pads):
                        dead.append(tr)
                        break
        for nc, lst in vias.items():
            for v in lst:
                if skip_locked and v.IsLocked():
                    continue
                pt = v.GetPosition()
                conns = 0
                for layer in CU:
                    for tr in tracks.get(nc, []):
                        if tr.GetLayer() == layer and tr.HitTest(pt, 0):
                            conns += 1
                    for p in pads.get(nc, []):
                        if p.IsOnLayer(layer) and p.HitTest(pt, 0):
                            conns += 1
                stitched = any(in_zone(pt, nc, layer) for layer in CU)
                if conns == 0 and not stitched:
                    dead.append(v)
                elif conns <= 1 and not stitched:
                    dead.append(v)
        if not dead:
            return removed_total
        for d in dead:
            b.Remove(d)
            KEEP.append(d)
        removed_total += len(dead)


n = prune()
print(f"pruned {n} unlocked dangling track/via items")
# report locked items that are now dangling (handled by hand below)
tracks, vias, pads = {}, {}, {}
for tr in b.GetTracks():
    (vias if tr.Type() == pcbnew.PCB_VIA_T else tracks).setdefault(tr.GetNetCode(), []).append(tr)
for fp in b.GetFootprints():
    for p in fp.Pads():
        if p.GetNetCode():
            pads.setdefault(p.GetNetCode(), []).append(p)
for nc, lst in tracks.items():
    for tr in lst:
        if tr.IsLocked():
            for pt in (tr.GetStart(), tr.GetEnd()):
                if not end_connected(tr, pt, tr.GetLayer(), tracks, vias, pads):
                    print(f"  LOCKED dangling: {tr.GetNetname()} {tr.GetLayerName()} ({tr.GetStart().x/1e6:.2f},{tr.GetStart().y/1e6:.2f})->({tr.GetEnd().x/1e6:.2f},{tr.GetEnd().y/1e6:.2f}) free end ({pt.x/1e6:.2f},{pt.y/1e6:.2f})")

# ---------------------------------------------------------------- 6. silk
b.FindFootprintByReference("U11").Reference().SetPosition(V(100.0, 106.7))
b.FindFootprintByReference("R23").Reference().SetPosition(V(116.9, 110.5))


def silk(text, x, y, size=0.8, halign=None):
    tx = pcbnew.PCB_TEXT(b)
    tx.SetText(text)
    tx.SetLayer(pcbnew.F_SilkS)
    tx.SetPosition(V(x, y))
    tx.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size)))
    tx.SetTextThickness(mm(0.15))
    if halign == "right":
        tx.SetHorizJustify(pcbnew.GR_TEXT_H_ALIGN_RIGHT)
    b.Add(tx)


silk("RESET", 108.0, 128.9)
silk("BOOT", 118.0, 128.9)
for i, lab in enumerate(["GND", "VCC", "SCL", "SDA"]):
    silk(lab, 140.6, 106.0 + 2.54 * i, halign="right")
for i, lab in enumerate(["3V3", "PWR", "BT", "USB"]):
    silk(lab, 136.6, 118.0 + 2.54 * i, halign="right")

# ---------------------------------------------------------------- 7. hand routing
def track(netname, pts, w, layer=pcbnew.F_Cu, lock=True):
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        tr = pcbnew.PCB_TRACK(b)
        tr.SetStart(V(x0, y0))
        tr.SetEnd(V(x1, y1))
        tr.SetWidth(mm(w))
        tr.SetLayer(layer)
        tr.SetNet(net(netname))
        tr.SetLocked(lock)
        b.Add(tr)


def via(netname, x, y, d=0.6, drill=0.3, lock=True):
    v = pcbnew.PCB_VIA(b)
    v.SetPosition(V(x, y))
    v.SetWidth(mm(d))
    v.SetDrill(mm(drill))
    v.SetViaType(pcbnew.VIATYPE_THROUGH)
    v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu)
    v.SetNet(net(netname))
    v.SetLocked(lock)
    b.Add(v)


# buck input: C48.1 -> U11 VIN (pads 2+3)
track("+5V", [(96.04, 104.0), (98.86, 104.0)], 0.5)
track("+5V", [(98.86, 104.0), (98.86, 104.95)], 0.4)
track("GND", [(93.96, 104.0), (92.6, 104.0)], 0.4)
via("GND", 92.6, 104.0)
# U11 GND
track("GND", [(101.14, 104.95), (101.6, 106.3)], 0.4)
via("GND", 101.6, 106.3)
# SW node: U11.5 -> L3.1, BST cap return
track("BUCK_SW", [(101.14, 104.0), (105.15, 104.0)], 0.5)
track("BUCK_SW", [(100.86, 100.5), (102.6, 100.5), (102.6, 104.0)], 0.3)
# BST: C50.1 -> U11.6
track("BUCK_BST", [(99.14, 100.5), (100.2, 101.56), (100.2, 102.2), (101.14, 103.05)], 0.25)
# FB: U11.1 -> R22.2 / R23.1 (runs between the two divider resistors)
track("BUCK_FB", [(98.86, 103.05), (97.7, 103.05), (97.7, 109.25), (112.09, 109.25), (112.09, 110.5)], 0.25)
track("BUCK_FB", [(113.91, 109.25), (113.91, 108.0)], 0.25)
# output: L3.2 -> C49.1 -> +3V3 plane (2 vias) and R22.1
track("+3V3", [(108.85, 104.0), (111.96, 104.0)], 0.6)
track("+3V3", [(111.96, 104.0), (110.7, 106.0)], 0.5)
via("+3V3", 110.7, 106.0, 0.8, 0.4)
track("+3V3", [(111.96, 104.0), (112.9, 106.0)], 0.5)
via("+3V3", 112.9, 106.0, 0.8, 0.4)
track("+3V3", [(112.09, 108.0), (112.9, 106.0)], 0.3)
# output cap / divider grounds
track("GND", [(114.04, 104.0), (115.4, 104.0)], 0.5)
via("GND", 115.4, 104.0, 0.8, 0.4)
track("GND", [(113.91, 110.5), (115.3, 110.5)], 0.3)
via("GND", 115.3, 110.5)
# WROOM GND pins 1/40, 3V3 pin 2, EP vias
track("GND", [(96.25, 77.59), (94.6, 77.59)], 0.4)
via("GND", 94.6, 77.59)
track("GND", [(113.75, 77.59), (115.4, 77.59)], 0.4)
via("GND", 115.4, 77.59)
track("+3V3", [(96.25, 78.86), (94.6, 78.86)], 0.4)
via("+3V3", 94.6, 78.86)
u4 = b.FindFootprintByReference("U4")
ep = [p for p in u4.Pads() if p.GetNumber() == "41"]
holes = [p for p in u4.Pads() if p.GetNumber() == ""]
print("EP pieces:", len(ep), "unnamed:", len(holes),
      "unnamed attr/size/drill:", holes[0].GetAttribute(), holes[0].GetSize().x / 1e6, holes[0].GetDrillSize().x / 1e6)
added = 0
for x, y in [(102.8, 84.61), (104.2, 84.61), (102.8, 86.01), (104.2, 86.01)]:
    if any(p.HitTest(V(x, y), 0) for p in ep):
        via("GND", x, y)
        added += 1
print("EP GND vias added:", added)

pcbnew.SaveBoard(PCB, b)
print("saved")
