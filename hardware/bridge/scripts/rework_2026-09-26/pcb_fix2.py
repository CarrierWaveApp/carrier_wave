import pcbnew, math
PCB="/Users/jsvana/projects/carrier_wave/hardware/bridge/cw_bridge.kicad_pcb"
mm=pcbnew.FromMM
def V(x,y): return pcbnew.VECTOR2I(mm(x),mm(y))
b=pcbnew.LoadBoard(PCB); KEEP=[]
def net(n): return b.GetNetInfo().GetNetItem(n)
def track(nn,pts,w,layer=pcbnew.F_Cu):
    for (x0,y0),(x1,y1) in zip(pts,pts[1:]):
        t=pcbnew.PCB_TRACK(b); t.SetStart(V(x0,y0)); t.SetEnd(V(x1,y1)); t.SetWidth(mm(w)); t.SetLayer(layer); t.SetNet(net(nn)); t.SetLocked(True); b.Add(t)
# FB: join the R22 branch to the horizontal run
track("BUCK_FB",[(112.09,109.25),(113.91,109.25)],0.25)

# exact-geometry prune of unlocked dangling tails
def d_pt_seg(p,a,c):
    ax,ay,cx,cy,px,py=a.x,a.y,c.x,c.y,p.x,p.y
    dx,dy=cx-ax,cy-ay; L2=dx*dx+dy*dy
    if L2==0: return math.hypot(px-ax,py-ay)
    t=max(0,min(1,((px-ax)*dx+(py-ay)*dy)/L2))
    return math.hypot(px-(ax+t*dx),py-(ay+t*dy))
TOL=mm(0.01)
zones=list(b.Zones())
def in_zone(pt,nc,layer):
    for z in zones:
        if z.GetNetCode()==nc and z.IsOnLayer(layer):
            poly=z.GetFilledPolysList(layer)
            if poly and poly.Contains(pt): return True
    return False
def connected(item,pt,layer,tracks,vias,pads):
    nc=item.GetNetCode()
    for p in pads.get(nc,[]):
        if p.IsOnLayer(layer) and p.HitTest(pt,0): return True
    for v in vias.get(nc,[]):
        if v is not item and math.hypot(v.GetPosition().x-pt.x,v.GetPosition().y-pt.y)<=v.GetWidth()/2: return True
    for tr in tracks.get(nc,[]):
        if tr is not item and tr.GetLayer()==layer and d_pt_seg(pt,tr.GetStart(),tr.GetEnd())<=TOL: return True
    return in_zone(pt,nc,layer)
total=0
while True:
    tracks,vias,pads={},{},{}
    for tr in b.GetTracks(): (vias if tr.Type()==pcbnew.PCB_VIA_T else tracks).setdefault(tr.GetNetCode(),[]).append(tr)
    for f in b.GetFootprints():
        for p in f.Pads():
            if p.GetNetCode(): pads.setdefault(p.GetNetCode(),[]).append(p)
    dead=[]
    for nc,lst in tracks.items():
        for tr in lst:
            if tr.IsLocked(): continue
            if any(not connected(tr,pt,tr.GetLayer(),tracks,vias,pads) for pt in (tr.GetStart(),tr.GetEnd())): dead.append(tr)
    for nc,lst in vias.items():
        for v in lst:
            if v.IsLocked(): continue
            pt=v.GetPosition(); conns=0
            for tr in tracks.get(nc,[]):
                if math.hypot(tr.GetStart().x-pt.x,tr.GetStart().y-pt.y)<=v.GetWidth()/2 or math.hypot(tr.GetEnd().x-pt.x,tr.GetEnd().y-pt.y)<=v.GetWidth()/2: conns+=1
            for p in pads.get(nc,[]):
                if p.HitTest(pt,0): conns+=1
            if conns<=1 and not any(in_zone(pt,nc,l) for l in (pcbnew.F_Cu,pcbnew.In1_Cu,pcbnew.In2_Cu,pcbnew.B_Cu)): dead.append(v)
    if not dead: break
    for d in dead:
        print("  prune", d.GetNetname(), d.GetLayerName(), f"({d.GetStart().x/1e6:.2f},{d.GetStart().y/1e6:.2f})->({d.GetEnd().x/1e6:.2f},{d.GetEnd().y/1e6:.2f})", f"len {d.GetLength()/1e6:.3f}")
        b.Remove(d); KEEP.append(d)
    total+=len(dead)
print("pruned", total)

# silk: reference moves + widths
def ref(r,x,y,ang=0):
    f=b.FindFootprintByReference(r); t=f.Reference(); t.SetPosition(V(x,y)); t.SetTextAngleDegrees(ang)
ref("C48",95.0,102.3); ref("R23",116.9,109.4); ref("J13",111.3,124.0); ref("J14",121.3,124.0)
ref("R26",129.6,116.5); ref("R27",129.6,119.5); ref("R28",129.6,122.5)
for r in ["J3","J12","J13","J14","R26","R27","R28"]:
    f=b.FindFootprintByReference(r)
    for g in f.GraphicalItems():
        if g.GetLayerName()=="F.Silkscreen" and g.Type()==pcbnew.PCB_SHAPE_T and g.GetWidth()<mm(0.15): g.SetWidth(mm(0.15))
# panel-LED labels: pull left of J12's outline (x<136.62) 
for d in b.GetDrawings():
    if d.Type()==pcbnew.PCB_TEXT_T and d.GetText() in ("3V3","PWR","BT","USB"):
        d.SetPosition(V(136.0,d.GetPosition().y/1e6))
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(PCB,b); print("saved")
