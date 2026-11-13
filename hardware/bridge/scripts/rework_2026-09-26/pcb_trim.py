import pcbnew, math
PCB="/Users/jsvana/projects/carrier_wave/hardware/bridge/cw_bridge.kicad_pcb"
b=pcbnew.LoadBoard(PCB); KEEP=[]
TOL=pcbnew.FromMM(0.01)
def d_pt_seg(p,a,c):
    ax,ay,cx,cy,px,py=a.x,a.y,c.x,c.y,p.x,p.y
    dx,dy=cx-ax,cy-ay; L2=dx*dx+dy*dy
    if L2==0: return math.hypot(px-ax,py-ay)
    t=max(0,min(1,((px-ax)*dx+(py-ay)*dy)/L2)); return math.hypot(px-(ax+t*dx),py-(ay+t*dy))
zones=list(b.Zones())
def in_zone(pt,nc,layer):
    for z in zones:
        if z.GetNetCode()==nc and z.IsOnLayer(layer):
            poly=z.GetFilledPolysList(layer)
            if poly and poly.Contains(pt): return True
    return False
def build():
    tracks,vias,pads={},{},{}
    for tr in b.GetTracks(): (vias if tr.Type()==pcbnew.PCB_VIA_T else tracks).setdefault(tr.GetNetCode(),[]).append(tr)
    for f in b.GetFootprints():
        for p in f.Pads():
            if p.GetNetCode(): pads.setdefault(p.GetNetCode(),[]).append(p)
    return tracks,vias,pads
def connected(item,pt,layer,tracks,vias,pads):
    nc=item.GetNetCode()
    for p in pads.get(nc,[]):
        if p.IsOnLayer(layer) and p.HitTest(pt,0): return True
    for v in vias.get(nc,[]):
        if math.hypot(v.GetPosition().x-pt.x,v.GetPosition().y-pt.y)<=v.GetWidth()/2: return True
    for tr in tracks.get(nc,[]):
        if tr is not item and tr.GetLayer()==layer and d_pt_seg(pt,tr.GetStart(),tr.GetEnd())<=TOL: return True
    return in_zone(pt,nc,layer)
def junctions(t,tracks,vias,pads):
    """points on t's centerline (excluding its ends) where same-net items attach"""
    nc=t.GetNetCode(); a,c=t.GetStart(),t.GetEnd(); L=math.hypot(c.x-a.x,c.y-a.y); pts=[]
    def onseg(p):
        return d_pt_seg(p,a,c)<=TOL and math.hypot(p.x-a.x,p.y-a.y)>TOL and math.hypot(p.x-c.x,p.y-c.y)>TOL
    for tr in tracks.get(nc,[]):
        if tr is t or tr.GetLayer()!=t.GetLayer(): continue
        for p in (tr.GetStart(),tr.GetEnd()):
            if onseg(p): pts.append(pcbnew.VECTOR2I(p))
    for v in vias.get(nc,[]):
        if d_pt_seg(v.GetPosition(),a,c)<=v.GetWidth()/2: pts.append(pcbnew.VECTOR2I(v.GetPosition()))
    for p in pads.get(nc,[]):
        if p.IsOnLayer(t.GetLayer()) and d_pt_seg(p.GetPosition(),a,c)<=min(p.GetSize().x,p.GetSize().y)/2: pts.append(pcbnew.VECTOR2I(p.GetPosition()))
    return pts
changed=True; rounds=0
while changed and rounds<50:
    changed=False; rounds+=1
    tracks,vias,pads=build()
    for nc,lst in tracks.items():
        for t in lst:
            ends=[(t.GetStart(),t.GetEnd()),(t.GetEnd(),t.GetStart())]
            for free,other in ends:
                if connected(t,free,t.GetLayer(),tracks,vias,pads): continue
                js=junctions(t,tracks,vias,pads)
                if js:
                    # keep the part from `other` to the junction closest to `free`
                    j=min(js,key=lambda p: math.hypot(p.x-free.x,p.y-free.y))
                    print(f"  trim {t.GetNetname():9} {t.GetLayerName()} free ({free.x/1e6:.2f},{free.y/1e6:.2f}) -> junction ({j.x/1e6:.2f},{j.y/1e6:.2f})")
                    if free==t.GetStart(): t.SetStart(j)
                    else: t.SetEnd(j)
                else:
                    print(f"  drop {t.GetNetname():9} {t.GetLayerName()} ({t.GetStart().x/1e6:.2f},{t.GetStart().y/1e6:.2f})->({t.GetEnd().x/1e6:.2f},{t.GetEnd().y/1e6:.2f}) len {t.GetLength()/1e6:.2f}")
                    b.Remove(t); KEEP.append(t)
                changed=True; break
            if changed: break
        if changed: break
print("rounds:", rounds)
pcbnew.ZONE_FILLER(b).Fill(b.Zones()); pcbnew.SaveBoard(PCB,b)
nt=sum(1 for t in b.GetTracks() if t.Type()!=pcbnew.PCB_VIA_T); nv=sum(1 for t in b.GetTracks() if t.Type()==pcbnew.PCB_VIA_T)
print(f"saved: {nt} track segments, {nv} vias, {len(list(b.GetFootprints()))} footprints")
