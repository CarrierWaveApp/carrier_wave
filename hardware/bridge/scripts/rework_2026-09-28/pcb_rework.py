#!/usr/bin/env python3
"""PCB rework for cw_bridge.kicad_pcb (2026-09-28, rev 2.1) - run with KiCad's python.

- J3 J12 -> JST PH B4B (rot 270: pads run +y like the old pin headers)
- J4 J5 J6 J13 J14 -> JST PH B2B (rot 0: pads run +x; pad 1 stays put)
- J11 -> JST PH B2B moved to (128.4, 75.5) (no room at the old spot); DEBUG_TX re-routed
- SW1 rotary encoder -> J15 JST PH B5B at (60, 112): CLK DT SW +3V3 GND
- header stubs re-targeted to the 2.0 mm pitch, silk labels redone, rev bump
"""
import pcbnew

PCB = "/Users/jsvana/projects/carrier_wave/hardware/bridge/cw_bridge.kicad_pcb"
LIB = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints/Connector_JST.pretty"
B2B = "JST_PH_B2B-PH-K_1x02_P2.00mm_Vertical"
B4B = "JST_PH_B4B-PH-K_1x04_P2.00mm_Vertical"
B5B = "JST_PH_B5B-PH-K_1x05_P2.00mm_Vertical"

b = pcbnew.LoadBoard(PCB)
keep = []  # python refs to removed items (SWIG GC trap, see CLAUDE.md)


def mm(v): return pcbnew.FromMM(v)
def V(x, y): return pcbnew.VECTOR2I(mm(x), mm(y))
def net(n): return b.GetNetInfo().GetNetItem(n)


def swap(ref, fpname, rot, pos=None, nets=None, ref_at=None):
    old = b.FindFootprintByReference(ref)
    new = pcbnew.FootprintLoad(LIB, fpname)
    new.SetReference(ref)
    if old is not None:
        new.SetValue(old.GetValue())
    b.Add(new)
    if pos is None:
        pos = old.GetPosition()
    new.SetPosition(pos)
    new.SetOrientationDegrees(rot)
    for pad in new.Pads():
        num = pad.GetNumber()
        if nets:
            pad.SetNet(net(nets[int(num) - 1]))
        else:
            pad.SetNet(old.FindPadByNumber(num).GetNet())
    for f in new.GetFields():
        if f.GetName() not in ("Reference", "Value"):
            f.SetVisible(False); f.SetLayer(pcbnew.F_Fab)
    new.Reference().SetTextHeight(mm(1.0)); new.Reference().SetTextWidth(mm(1.0))
    new.Reference().SetTextThickness(mm(0.15))
    if ref_at:
        new.Reference().SetPosition(V(*ref_at))
        new.Reference().SetTextAngleDegrees(0)
    if old is not None:
        b.Remove(old); keep.append(old)
    return new


def track(nn, pts, w=0.25, layer=pcbnew.F_Cu):
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        t = pcbnew.PCB_TRACK(b); t.SetStart(V(x0, y0)); t.SetEnd(V(x1, y1))
        t.SetWidth(mm(w)); t.SetLayer(layer); t.SetNet(net(nn)); b.Add(t)


def near(p, x, y): return abs(p.x / 1e6 - x) < 0.02 and abs(p.y / 1e6 - y) < 0.02


def rm_track(nn, x0, y0, x1, y1):
    for t in list(b.GetTracks()):
        if t.Type() != pcbnew.PCB_VIA_T and t.GetNetname() == nn and (
            (near(t.GetStart(), x0, y0) and near(t.GetEnd(), x1, y1)) or
            (near(t.GetStart(), x1, y1) and near(t.GetEnd(), x0, y0))):
            b.Remove(t); keep.append(t); return
    raise RuntimeError(f"track not found {nn} ({x0},{y0})-({x1},{y1})")


def retarget(nn, x_old, y_old, x_new, y_new):
    for t in b.GetTracks():
        if t.Type() != pcbnew.PCB_VIA_T and t.GetNetname() == nn:
            if near(t.GetStart(), x_old, y_old): t.SetStart(V(x_new, y_new)); return
            if near(t.GetEnd(), x_old, y_old): t.SetEnd(V(x_new, y_new)); return
    raise RuntimeError(f"no track end {nn} at ({x_old},{y_old})")


def texts():
    return [d for d in b.GetDrawings() if d.Type() == pcbnew.PCB_TEXT_T]


def rm_text(s, x, y):
    for d in texts():
        if d.GetText() == s and near(d.GetPosition(), x, y):
            b.Remove(d); keep.append(d); return
    raise RuntimeError(f"text not found {s!r} at {x},{y}")


def mv_text(s, x, y, nx, ny):
    for d in texts():
        if d.GetText() == s and near(d.GetPosition(), x, y):
            d.SetPosition(V(nx, ny)); d.SetHorizJustify(pcbnew.GR_TEXT_H_ALIGN_CENTER); return
    raise RuntimeError(f"text not found {s!r} at {x},{y}")


def silk(s, x, y, h=0.8):
    t = pcbnew.PCB_TEXT(b); t.SetText(s); t.SetLayer(pcbnew.F_SilkS); t.SetPosition(V(x, y))
    t.SetTextHeight(mm(h)); t.SetTextWidth(mm(h)); t.SetTextThickness(mm(0.15))
    t.SetHorizJustify(pcbnew.GR_TEXT_H_ALIGN_CENTER); b.Add(t)


# ---------------------------------------------------------------- headers
swap("J3", B4B, 270, ref_at=(137.6, 109.5))
retarget("I2C_SCL", 142.0, 111.08, 142.0, 110.0)
retarget("I2C_SDA", 142.0, 113.62, 142.0, 112.0)
swap("J12", B4B, 270, ref_at=(137.3, 114.8))
retarget("PNL_PWR", 138.0, 120.54, 138.0, 120.0)
retarget("PNL_BT", 138.0, 123.08, 138.0, 122.0)
retarget("PNL_USB", 138.0, 125.62, 138.0, 124.0)
for ref, x in [("J4", 78.0), ("J5", 88.0), ("J6", 98.0), ("J13", 108.0), ("J14", 118.0)]:
    swap(ref, B2B, 0, ref_at=(x + 1.0, 120.9))
# J11: relocate into the pocket between R9 and the +5V run to TP4/C6
swap("J11", B2B, 0, pos=V(128.4, 75.5), ref_at=(131.6, 72.7))
rm_track("DEBUG_TX", 121.7, 72.38, 121.7, 72.0)
rm_track("DEBUG_TX", 121.7, 72.0, 122.5, 72.0)
track("DEBUG_TX", [(121.7, 72.38), (124.82, 75.5), (128.4, 75.5)], layer=pcbnew.B_Cu)

# ---------------------------------------------------------------- encoder -> J15
sw1 = b.FindFootprintByReference("SW1")
b.Remove(sw1); keep.append(sw1)
j15 = swap("J15", B5B, 0, pos=V(60.0, 112.0), nets=["ENC_CLK", "ENC_DT", "ENC_SW", "+3V3", "GND"],
           ref_at=(64.0, 108.6))
j15.SetValue("ENCODER")
rm_track("ENC_DT", 60.0, 117.0, 61.11, 115.89)
rm_track("ENC_DT", 61.11, 115.89, 90.17, 115.89)
track("ENC_DT", [(90.17, 115.89), (62.0, 115.89), (62.0, 112.0)])
rm_track("ENC_SW", 82.96, 103.54, 74.5, 112.0)
track("ENC_SW", [(82.96, 103.54), (76.5, 110.0), (64.0, 110.0), (64.0, 112.0)], layer=pcbnew.B_Cu)

# ---------------------------------------------------------------- silk
for x in (80.3, 90.3, 100.3, 110.3, 120.3):
    rm_text("1", x, 124.0)
rm_text("1", 139.9, 118.0); rm_text("1", 143.9, 106.0); rm_text("1", 124.3, 71.5)
for s, x in [("BTN1", 76.6), ("BTN2", 86.6), ("BTN3", 96.6), ("RESET", 106.6), ("BOOT", 116.6)]:
    mv_text(s, x, 125.27, x + 2.4, 128.4)
for s, y in [("GND", 106.0), ("VCC", 108.54), ("SCL", 111.08), ("SDA", 113.62)]:
    mv_text(s, 140.6, y, 147.2, 106.0 + 2.0 * [106.0, 108.54, 111.08, 113.62].index(y))
for s, y in [("3V3", 118.0), ("PWR", 120.54), ("BT", 123.08), ("USB", 125.62)]:
    mv_text(s, 136.0, y, 141.9, 118.0 + 2.0 * [118.0, 120.54, 123.08, 125.62].index(y))
mv_text("LEDS", 140.7, 118.0, 132.2, 125.6)
mv_text("OLED", 139.4, 103.6, 141.5, 102.5)
mv_text("UART TX", 122.5, 77.0, 129.4, 80.6)
silk("CLK DT SW 3V3 GND", 64.0, 117.4)
for d in texts():
    if d.GetText() == "CW Bridge rev 2.0  W6JY":
        d.SetText("CW Bridge rev 2.1  W6JY")

pcbnew.ZONE_FILLER(b).Fill(b.Zones())
b.Save(PCB)
print("saved; removed", len(keep), "items")
