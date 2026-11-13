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
    return any(abs(p.x/1e6-x)<0.02 and abs(p.y/1e6-y)<0.02 for p in (t.GetStart(),t.GetEnd()))
def inbox(t,x0,x1,y0,y1): return any(x0<=p.x/1e6<=x1 and y0<=p.y/1e6<=y1 for p in (t.GetStart(),t.GetEnd()))
def rm(pred,label):
    n=0
    for t in list(b.GetTracks()):
        if pred(t): b.Remove(t); KEEP.append(t); n+=1
    print(f"  rm {label}: {n}")
# undo the failed +5V attempt
rm(lambda t: t.GetNetname()=="+5V" and (at(t,138.4,84.0) or at(t,138.4,107.0) or at(t,98.86,107.0)), "old +5V attempt")
# routes in the way of the new feed (unlocked, router-made) -> freerouting pass 2 redoes them
for n in ["BTN2","BTN3","ENC_SW","LED_BT","LED_USB"]:
    rm(lambda t,n=n: t.GetNetname()==n and not t.IsLocked(), n)
rm(lambda t: t.GetNetname()=="I2C_SDA" and not t.IsLocked() and inbox(t,129.5,143,92,115), "I2C_SDA J3 branch")
# +5V feed
track("+5V",[(138.7,91.0),(139.3,91.6),(139.3,100.0),(138.7,100.6),(138.0,100.6)],0.6,pcbnew.B_Cu)
via("+5V",138.0,100.6,0.8,0.4)
track("+5V",[(138.0,100.6),(103.6,100.6)],0.5)
via("+5V",103.6,100.6,0.8,0.4)
track("+5V",[(103.6,100.6),(103.6,104.3),(96.5,104.3),(96.5,105.5)],0.6,pcbnew.B_Cu)
via("+5V",96.5,105.5,0.8,0.4)
track("+5V",[(96.5,105.5),(96.04,104.73),(96.04,104.0)],0.5)
# R24.1 +3V3: move the plane via above the resistor (old stub crossed ESP_EN)
rm(lambda t: t.GetNetname()=="+3V3" and (at(t,90.09,108.6)), "R24 old via/stub")
track("+3V3",[(90.09,107.0),(90.09,106.1),(90.6,105.6)],0.4); via("+3V3",90.6,105.6,0.8,0.4)
# C51.1 / C52.1 plane vias
track("+3V3",[(88.96,100.5),(88.96,98.9)],0.4); via("+3V3",88.96,98.9)
track("+3V3",[(93.64,100.5),(93.64,98.9)],0.4); via("+3V3",93.64,98.9)
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(PCB,b); print("saved")
