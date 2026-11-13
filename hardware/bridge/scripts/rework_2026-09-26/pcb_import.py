import pcbnew, json
S="$SCRATCH"
PCB="/Users/jsvana/projects/carrier_wave/hardware/bridge/cw_bridge.kicad_pcb"
b=pcbnew.LoadBoard(PCB)
before=len(list(b.GetTracks()))
ok=pcbnew.ImportSpecctraSES(b, S+"/cw_bridge.ses"); print("SES import:", ok, "tracks", before, "->", len(list(b.GetTracks())))
locked=json.load(open(S+"/locked.json"))
def key(kind,layer,s,e): return (kind,layer,tuple(s),tuple(e))
want=set()
for l in locked:
    want.add(key(l['kind'],l['layer'],l['s'],l['e'])); want.add(key(l['kind'],l['layer'],l['e'],l['s']))
n=0; nv=0; nt=0
for t in b.GetTracks():
    kind='via' if t.Type()==pcbnew.PCB_VIA_T else 'trk'
    k=key(kind,t.GetLayerName(),[t.GetStart().x,t.GetStart().y],[t.GetEnd().x,t.GetEnd().y])
    if k in want:
        t.SetLocked(True); n+=1
    if kind=='via': nv+=1
    else: nt+=1
print(f"re-locked {n} of {len(locked)} previously locked items; board now {nt} tracks + {nv} vias")
# any freerouting copper on the inner layers?
inner=[t for t in b.GetTracks() if t.Type()!=pcbnew.PCB_VIA_T and t.GetLayerName() in ('In1.Cu','In2.Cu')]
print("inner-layer tracks:", len(inner))
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(PCB,b); print("saved")
