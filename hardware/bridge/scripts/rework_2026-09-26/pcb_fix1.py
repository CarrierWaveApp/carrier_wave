import pcbnew
S="$SCRATCH"
PCB="/Users/jsvana/projects/carrier_wave/hardware/bridge/cw_bridge.kicad_pcb"
mm=pcbnew.FromMM
def V(x,y): return pcbnew.VECTOR2I(mm(x),mm(y))
def near(b,x,y,r=1.2):
    out=[]
    for t in b.GetTracks():
        for p in (t.GetStart(),t.GetEnd()):
            if abs(p.x/1e6-x)<r and abs(p.y/1e6-y)<r:
                out.append(f"{'via' if t.Type()==pcbnew.PCB_VIA_T else t.GetLayerName()} {t.GetNetname()} ({t.GetStart().x/1e6:.2f},{t.GetStart().y/1e6:.2f})->({t.GetEnd().x/1e6:.2f},{t.GetEnd().y/1e6:.2f}) L={t.IsLocked()}"); break
    for f in b.GetFootprints():
        for pd in f.Pads():
            p=pd.GetPosition()
            if abs(p.x/1e6-x)<r and abs(p.y/1e6-y)<r: out.append(f"pad {f.GetReference()}.{pd.GetNumber()} {pd.GetNetname()} ({p.x/1e6:.2f},{p.y/1e6:.2f})")
    return out
h=pcbnew.LoadBoard(S+"/head.kicad_pcb")
print("HEAD near (105.8,59.95):"); [print("  ",s) for s in near(h,105.8,59.95)]
b=pcbnew.LoadBoard(PCB)
print("NOW  near (105.8,59.95):"); [print("  ",s) for s in near(b,105.8,59.95)]
KEEP=[]
def net(n): return b.GetNetInfo().GetNetItem(n)
def track(nn,pts,w,layer=pcbnew.F_Cu):
    for (x0,y0),(x1,y1) in zip(pts,pts[1:]):
        t=pcbnew.PCB_TRACK(b); t.SetStart(V(x0,y0)); t.SetEnd(V(x1,y1)); t.SetWidth(mm(w)); t.SetLayer(layer); t.SetNet(net(nn)); t.SetLocked(True); b.Add(t)
def via(nn,x,y,d=0.6,dr=0.3):
    v=pcbnew.PCB_VIA(b); v.SetPosition(V(x,y)); v.SetWidth(mm(d)); v.SetDrill(mm(dr)); v.SetViaType(pcbnew.VIATYPE_THROUGH); v.SetLayerPair(pcbnew.F_Cu,pcbnew.B_Cu); v.SetNet(net(nn)); v.SetLocked(True); b.Add(v)
def rm(pred):
    n=0
    for t in list(b.GetTracks()):
        if pred(t): b.Remove(t); KEEP.append(t); n+=1
    return n
def at(t,x,y): p=t.GetStart(); q=t.GetEnd(); return (abs(p.x/1e6-x)<0.01 and abs(p.y/1e6-y)<0.01) or (abs(q.x/1e6-x)<0.01 and abs(q.y/1e6-y)<0.01)
# a. pin-1 GND via: move off the I2S_BCLK B.Cu track
print("rm pin1 via/track:", rm(lambda t: t.GetNetname()=="GND" and at(t,94.6,77.59)))
track("GND",[(96.25,77.59),(95.0,76.4)],0.4); via("GND",95.0,76.4)
# b. FB reroute (north corridor, west of C48) + move C48 GND via below its pad
print("rm FB:", rm(lambda t: t.GetNetname()=="BUCK_FB" and t.Type()!=pcbnew.PCB_VIA_T and (at(t,97.7,103.05) or at(t,97.7,109.25))))
print("rm C48 gnd via/track:", rm(lambda t: t.GetNetname()=="GND" and at(t,92.6,104.0)))
track("BUCK_FB",[(98.86,103.05),(97.7,103.05),(97.7,102.2),(93.0,102.2),(93.0,109.25),(112.09,109.25),(112.09,110.5)],0.25)
track("GND",[(93.96,104.0),(93.96,105.6)],0.4); via("GND",93.96,105.6)
# c. silk labels away from the edge
for d in b.GetDrawings():
    if d.Type()==pcbnew.PCB_TEXT_T and d.GetText() in ("RESET","BOOT"):
        x=106.6 if d.GetText()=="RESET" else 116.6
        d.SetPosition(V(x,125.27)); d.SetHorizJustify(pcbnew.GR_TEXT_H_ALIGN_RIGHT)
# d. refill zones
f=pcbnew.ZONE_FILLER(b); f.Fill(b.Zones())
pcbnew.SaveBoard(PCB,b); print("saved")
