import pcbnew
PCB="/Users/jsvana/projects/carrier_wave/hardware/bridge/cw_bridge.kicad_pcb"
mm=pcbnew.FromMM
def V(x,y): return pcbnew.VECTOR2I(mm(x),mm(y))
b=pcbnew.LoadBoard(PCB); KEEP=[]
def net(n): return b.GetNetInfo().GetNetItem(n)
def track(nn,pts,w,layer=pcbnew.F_Cu):
    for (x0,y0),(x1,y1) in zip(pts,pts[1:]):
        t=pcbnew.PCB_TRACK(b); t.SetStart(V(x0,y0)); t.SetEnd(V(x1,y1)); t.SetWidth(mm(w)); t.SetLayer(layer); t.SetNet(net(nn)); t.SetLocked(True); b.Add(t)
def via(nn,x,y,d=0.6,dr=0.3):
    v=pcbnew.PCB_VIA(b); v.SetPosition(V(x,y)); v.SetWidth(mm(d)); v.SetDrill(mm(dr)); v.SetViaType(pcbnew.VIATYPE_THROUGH); v.SetLayerPair(pcbnew.F_Cu,pcbnew.B_Cu); v.SetNet(net(nn)); v.SetLocked(True); b.Add(v)
def at(t,x,y): 
    for p in (t.GetStart(),t.GetEnd()):
        if abs(p.x/1e6-x)<0.02 and abs(p.y/1e6-y)<0.02: return True
    return False
def inbox(t,x0,x1,y0,y1):
    return any(x0<=p.x/1e6<=x1 and y0<=p.y/1e6<=y1 for p in (t.GetStart(),t.GetEnd()))
def rm(pred):
    n=0
    for t in list(b.GetTracks()):
        if pred(t): b.Remove(t); KEEP.append(t); n+=1
    return n
# +3V3 pull-up stubs (R24.1 / R25.1): drop freerouting's partial fragments, add plane vias
print("rm 3V3 fragments:", rm(lambda t: t.GetNetname()=="+3V3" and not t.IsLocked() and inbox(t,89.5,96.5,101.5,108.5)))
track("+3V3",[(94.59,107.0),(95.82,108.24)],0.5); via("+3V3",95.82,108.24,0.8,0.4)
track("+3V3",[(90.09,107.0),(90.09,108.6)],0.4); via("+3V3",90.09,108.6,0.8,0.4)
# move U11 GND via out of the +5V lane
print("rm U11 gnd via:", rm(lambda t: t.GetNetname()=="GND" and at(t,101.6,106.3)))
track("GND",[(101.14,104.95),(102.6,105.6)],0.4); via("GND",102.6,105.6)
# R22.1 +3V3: west stub + own via instead of the diagonal to the output via
print("rm R22 diag:", rm(lambda t: t.GetNetname()=="+3V3" and at(t,112.09,108.0) and at(t,112.9,106.0)))
track("+3V3",[(112.09,108.0),(110.0,108.0)],0.3); via("+3V3",110.0,108.0,0.8,0.4)
# +5V feed: tap the J1 VBUS trunk, down the east side, west under the LED row, up into U11 VIN
track("+5V",[(138.4,84.0),(138.4,107.0),(98.86,107.0),(98.86,104.95)],0.5)
# BTN1: U5 stub -> via -> B.Cu 45deg SW parallel to BTN2 -> via -> F.Cu lane above C8/C9 -> C8.1
via("BTN1",116.24,93.39)
track("BTN1",[(116.24,93.39),(92.33,117.3),(89.5,117.3)],0.25,pcbnew.B_Cu)
via("BTN1",89.5,117.3)
track("BTN1",[(89.5,117.3),(77.5,117.3),(77.5,119.0)],0.25)
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(PCB,b); print("saved")
