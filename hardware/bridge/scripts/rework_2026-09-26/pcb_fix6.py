import pcbnew
PCB="/Users/jsvana/projects/carrier_wave/hardware/bridge/cw_bridge.kicad_pcb"
mm=pcbnew.FromMM
def V(x,y): return pcbnew.VECTOR2I(mm(x),mm(y))
b=pcbnew.LoadBoard(PCB); KEEP=[]
def net(n): return b.GetNetInfo().GetNetItem(n)
def track(nn,pts,w,layer=pcbnew.F_Cu,lock=True):
    for (x0,y0),(x1,y1) in zip(pts,pts[1:]):
        t=pcbnew.PCB_TRACK(b); t.SetStart(V(x0,y0)); t.SetEnd(V(x1,y1)); t.SetWidth(mm(w)); t.SetLayer(layer); t.SetNet(net(nn)); t.SetLocked(lock); b.Add(t)
def via(nn,x,y,d=0.6,dr=0.3,lock=True):
    v=pcbnew.PCB_VIA(b); v.SetPosition(V(x,y)); v.SetWidth(mm(d)); v.SetDrill(mm(dr)); v.SetViaType(pcbnew.VIATYPE_THROUGH); v.SetLayerPair(pcbnew.F_Cu,pcbnew.B_Cu); v.SetNet(net(nn)); v.SetLocked(lock); b.Add(v)
def at(t,x,y): return any(abs(p.x/1e6-x)<0.02 and abs(p.y/1e6-y)<0.02 for p in (t.GetStart(),t.GetEnd()))
def rm(pred,label):
    n=0
    for t in list(b.GetTracks()):
        if pred(t): b.Remove(t); KEEP.append(t); n+=1
    print(f"  rm {label}: {n}")
# fences: router-made slow nets, re-routed by freerouting pass 3
for n in ["ENC_CLK","ENC_DT","ESP_EN"]:
    rm(lambda t,n=n: t.GetNetname()==n and not t.IsLocked(), n)
# SCL dead stub west of pin 6
rm(lambda t: t.GetNetname()=="I2C_SCL" and not t.IsLocked() and (at(t,94.9,83.94) or at(t,94.39,84.46)), "SCL dead stub")
# MCLK layer change: move the via west to free the strip
rm(lambda t: t.GetNetname()=="I2S_MCLK" and at(t,94.15,83.88), "MCLK via+segs")
track("I2S_MCLK",[(91.5,83.88),(89.32,83.88)],0.25); via("I2S_MCLK",91.5,83.88)
track("I2S_MCLK",[(91.5,83.88),(100.39,83.88)],0.25,pcbnew.B_Cu)
# DIN: trim the HEAD NE arm at the TP12 junction
rm(lambda t: t.GetNetname()=="I2S_DIN" and (at(t,93.3,85.6) or at(t,93.4,85.5) or at(t,93.5,85.5)), "DIN NE arm tail")
track("I2S_DIN",[(89.7,89.2),(91.15,87.75)],0.25)
# SDA: via on the HEAD chain vertex, up the strip at x94.4 into pin 5
via("I2C_SDA",92.7,87.1)
track("I2C_SDA",[(92.7,87.1),(93.4,86.4),(94.4,86.4),(94.4,82.67),(96.25,82.67)],0.25)
# SCL: TP7 -> via -> B.Cu NE -> via -> up the strip at x95.05 -> pin 6
track("I2C_SCL",[(90.0,91.58),(90.0,93.0),(90.6,93.6)],0.25); via("I2C_SCL",90.6,93.6)
track("I2C_SCL",[(90.6,93.6),(94.95,89.25),(94.95,90.5)],0.25,pcbnew.B_Cu)
rm(lambda t: False,"noop")
# (re)place the B.Cu leg cleanly: straight NE then the via
for t in list(b.GetTracks()):
    if t.GetNetname()=="I2C_SCL" and t.GetLayerName()=="B.Cu" and at(t,94.95,89.25): b.Remove(t); KEEP.append(t)
track("I2C_SCL",[(90.6,93.6),(93.7,90.5),(94.95,90.5)],0.25,pcbnew.B_Cu); via("I2C_SCL",94.95,90.5)
track("I2C_SCL",[(94.95,90.5),(95.05,90.4),(95.05,84.4),(96.25,83.94)],0.25)
# BCLK bridge
track("I2S_BCLK",[(93.5,77.1),(96.09,77.1)],0.25,pcbnew.B_Cu)
pcbnew.ZONE_FILLER(b).Fill(b.Zones()); pcbnew.SaveBoard(PCB,b); print("saved")
