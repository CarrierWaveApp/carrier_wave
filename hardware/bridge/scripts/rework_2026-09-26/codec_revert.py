import pcbnew, re, collections
S="$SCRATCH"
PCB="/Users/jsvana/projects/carrier_wave/hardware/bridge/cw_bridge.kicad_pcb"
b=pcbnew.LoadBoard(PCB); h=pcbnew.LoadBoard(S+"/head.kicad_pcb"); KEEP=[]
X0,X1,Y0,Y1=68e6,93.5e6,70e6,100e6
def inB(p): return X0<=p.x<=X1 and Y0<=p.y<=Y1
def inU4(p): return 95.2e6<=p.x<=114.8e6 and 76.1e6<=p.y<=96.4e6
# 1. delete current unlocked items touching B
rm=collections.Counter()
for t in list(b.GetTracks()):
    if t.IsLocked(): continue
    if inB(t.GetStart()) or inB(t.GetEnd()):
        b.Remove(t); KEEP.append(t); rm[t.GetNetname()]+=1
print("removed in B:", dict(rm))
# 2. add HEAD unlocked items touching B (skip ones reaching into the U4 courtyard)
add=collections.Counter(); skip=collections.Counter()
for t in h.GetTracks():
    if t.IsLocked(): continue
    s,e=t.GetStart(),t.GetEnd()
    if not (inB(s) or inB(e)): continue
    if inU4(s) or inU4(e): skip[t.GetNetname()]+=1; continue
    net=b.GetNetInfo().GetNetItem(t.GetNetname())
    if net is None or net.GetNetCode()==0: skip["nonet:"+t.GetNetname()]+=1; continue
    if t.Type()==pcbnew.PCB_VIA_T:
        v=pcbnew.PCB_VIA(b); v.SetPosition(t.GetPosition()); v.SetWidth(t.GetWidth()); v.SetDrill(t.GetDrillValue()); v.SetViaType(pcbnew.VIATYPE_THROUGH); v.SetLayerPair(pcbnew.F_Cu,pcbnew.B_Cu); v.SetNet(net); b.Add(v)
    else:
        n=pcbnew.PCB_TRACK(b); n.SetStart(s); n.SetEnd(e); n.SetWidth(t.GetWidth()); n.SetLayer(t.GetLayer()); n.SetNet(net); b.Add(n)
    add[t.GetNetname()]+=1
print("added from HEAD:", dict(add)); print("skipped (into U4 area):", dict(skip))
pcbnew.SaveBoard(PCB,b); print("saved")
# ---- read-only info for hand routes
def items(bd,x0,x1,y0,y1,layers=None):
    out=[]
    for t in bd.GetTracks():
        s,e=t.GetStart(),t.GetEnd(); sx,sy,ex,ey=s.x/1e6,s.y/1e6,e.x/1e6,e.y/1e6
        if not ((x0<=sx<=x1 and y0<=sy<=y1) or (x0<=ex<=x1 and y0<=ey<=y1)): continue
        kind='via' if t.Type()==pcbnew.PCB_VIA_T else t.GetLayerName()
        if layers and kind not in layers: continue
        out.append(f"{kind:6} {t.GetNetname():11} ({sx:.2f},{sy:.2f})->({ex:.2f},{ey:.2f}) w{t.GetWidth()/1e6:.2f}{' L' if t.IsLocked() else ''}")
    for f in bd.GetFootprints():
        for p in f.Pads():
            q=p.GetPosition()
            if x0<=q.x/1e6<=x1 and y0<=q.y/1e6<=y1: out.append(f"pad    {f.GetReference()}.{p.GetNumber()} {p.GetNetname()} ({q.x/1e6:.2f},{q.y/1e6:.2f}) sz {p.GetSize().x/1e6:.2f}x{p.GetSize().y/1e6:.2f} {'THT' if p.GetAttribute()==0 else 'SMD'}")
    return out
print("== +5V tap zone x134-139 y82-88 =="); [print(" ",s) for s in items(b,134,139,82,88)]
print("== column x134.6-136.0 y86-101.5 =="); [print(" ",s) for s in items(b,134.6,136.0,86,101.5)]
print("== band y99.6-102.4 x103-136 =="); [print(" ",s) for s in items(b,103,136,99.6,102.4)]
print("== B.Cu hop zone x96-105 y99-108 =="); [print(" ",s) for s in items(b,96,105,99,108,{'B.Cu','via'})]
print("== BTN1 F.Cu lane y116.6-118.2 x76-93 =="); [print(" ",s) for s in items(b,76,93,116.6,118.2)]
print("== SES vias vs board =="); 
ses=open(S+"/cw_bridge.ses").read()
sv=re.findall(r'\(via\s+"?([^\s"]+)"?\s+(-?\d+)\s+(-?\d+)', ses)
print("ses vias:", len(sv), "board vias:", sum(1 for t in b.GetTracks() if t.Type()==pcbnew.PCB_VIA_T))
bv={(round(t.GetPosition().x/1000),round(t.GetPosition().y/1000)) for t in b.GetTracks() if t.Type()==pcbnew.PCB_VIA_T}
miss=[(n,int(x)/1000,-int(y)/1000) for n,x,y in sv if (round(int(x)/1000*1000)/1000 and (int(x)//1, -int(y)//1)) and (int(x), -int(y)) not in {(a*1000,b_*1000) for a,b_ in bv}]
print("ses via padstacks:", collections.Counter(n for n,_,_ in sv))
