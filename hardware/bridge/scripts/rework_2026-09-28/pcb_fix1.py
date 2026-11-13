#!/usr/bin/env python3
"""DRC fixes after pcb_rework.py: BTN3 return re-routed under the front-row pads,
SDA stub back on its 45-degree line, two refdes moved off silk."""
import pcbnew
PCB = "/Users/jsvana/projects/carrier_wave/hardware/bridge/cw_bridge.kicad_pcb"
b = pcbnew.LoadBoard(PCB); keep = []
def mm(v): return pcbnew.FromMM(v)
def V(x, y): return pcbnew.VECTOR2I(mm(x), mm(y))
def net(n): return b.GetNetInfo().GetNetItem(n)
def near(p, x, y): return abs(p.x/1e6-x) < 0.02 and abs(p.y/1e6-y) < 0.02
def rm(nn, x0, y0, x1, y1):
    for t in list(b.GetTracks()):
        if t.Type() != pcbnew.PCB_VIA_T and t.GetNetname() == nn and (
            (near(t.GetStart(),x0,y0) and near(t.GetEnd(),x1,y1)) or (near(t.GetStart(),x1,y1) and near(t.GetEnd(),x0,y0))):
            b.Remove(t); keep.append(t); return
    raise RuntimeError(f"not found {nn} {x0},{y0}-{x1},{y1}")
def track(nn, pts, w=0.25, layer=pcbnew.B_Cu):
    for (x0,y0),(x1,y1) in zip(pts, pts[1:]):
        t = pcbnew.PCB_TRACK(b); t.SetStart(V(x0,y0)); t.SetEnd(V(x1,y1)); t.SetWidth(mm(w)); t.SetLayer(layer); t.SetNet(net(nn)); b.Add(t)

# BTN3: old run hugged y=122.87 / 125.13 between the pin-header pads
for seg in [((98,124),(99.127,124)), ((99.127,124),(100.253,122.873)), ((100.253,122.873),(111.123,122.873)),
            ((111.123,122.873),(113.378,125.128)), ((113.378,125.128),(119.021,125.128)), ((119.021,125.128),(123.835,120.315))]:
    rm("BTN3", *seg[0], *seg[1])
track("BTN3", [(98,124),(98,125.3),(121.2,125.3),(123.835,122.665),(123.835,120.315)])

# SDA: keep the original 45-degree line (clears the +3V3 via at 135.665,106) and finish horizontally
for t in b.GetTracks():
    if t.GetNetname()=="I2C_SDA" and t.Type()!=pcbnew.PCB_VIA_T and near(t.GetStart(),142.0,112.0):
        t.SetStart(V(140.38,112.0)); break
else:
    raise RuntimeError("SDA seg")
track("I2C_SDA", [(140.38,112.0),(142.0,112.0)])

b.FindFootprintByReference("J13").Reference().SetPosition(V(103.9,122.4))
b.FindFootprintByReference("C6").Reference().SetPosition(V(134.0,75.2))
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
b.Save(PCB); print("fix1 saved")
