import pcbnew, json, sys
S="$SCRATCH"
PCB="/Users/jsvana/projects/carrier_wave/hardware/bridge/cw_bridge.kicad_pcb"
step=sys.argv[1]
b=pcbnew.LoadBoard(PCB); KEEP=[]
if step=="prep":
    n=0
    for t in list(b.GetTracks()):
        pass
    print("rm BOOT:", n)
    locked=[dict(kind='via' if t.Type()==pcbnew.PCB_VIA_T else 'trk', layer=t.GetLayerName(), s=[t.GetStart().x,t.GetStart().y], e=[t.GetEnd().x,t.GetEnd().y]) for t in b.GetTracks() if t.IsLocked()]
    json.dump(locked, open(S+"/locked3.json","w")); print("locked:", len(locked))
    pcbnew.SaveBoard(PCB,b)
    print("DSN:", pcbnew.ExportSpecctraDSN(b, S+"/cw_bridge3.dsn"))
else:
    before=len(list(b.GetTracks()))
    print("SES import:", pcbnew.ImportSpecctraSES(b, S+"/cw_bridge3.ses"), before, "->", len(list(b.GetTracks())))
    want=set()
    for l in json.load(open(S+"/locked3.json")):
        want.add((l['kind'],l['layer'],tuple(l['s']),tuple(l['e']))); want.add((l['kind'],l['layer'],tuple(l['e']),tuple(l['s'])))
    n=0
    for t in b.GetTracks():
        kind='via' if t.Type()==pcbnew.PCB_VIA_T else 'trk'
        if (kind,t.GetLayerName(),(t.GetStart().x,t.GetStart().y),(t.GetEnd().x,t.GetEnd().y)) in want: t.SetLocked(True); n+=1
    print("re-locked", n)
    print("inner tracks:", sum(1 for t in b.GetTracks() if t.Type()!=pcbnew.PCB_VIA_T and t.GetLayerName() in ('In1.Cu','In2.Cu')))
    pcbnew.ZONE_FILLER(b).Fill(b.Zones()); pcbnew.SaveBoard(PCB,b); print("saved")
