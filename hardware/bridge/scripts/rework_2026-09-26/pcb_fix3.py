import pcbnew
PCB="/Users/jsvana/projects/carrier_wave/hardware/bridge/cw_bridge.kicad_pcb"
b=pcbnew.LoadBoard(PCB); KEEP=[]
for r in ["J3","J12","J13","J14","R26","R27","R28"]:
    f=b.FindFootprintByReference(r)
    for fl in f.GetFields():
        print(r, fl.GetName(), fl.GetLayerName(), "vis" if fl.IsVisible() else "hidden", f"size {fl.GetTextSize().x/1e6}")
        if fl.GetName() not in ("Reference","Value"):
            fl.SetVisible(False); fl.SetLayer(pcbnew.F_Fab)
        elif fl.GetName()=="Value":
            fl.SetLayer(pcbnew.F_Fab)
n=0
for t in list(b.GetTracks()):
    if t.Type()!=pcbnew.PCB_VIA_T and not t.IsLocked() and t.GetLength()<pcbnew.FromMM(0.01):
        b.Remove(t); KEEP.append(t); n+=1
print("removed micro segments:", n)
pcbnew.SaveBoard(PCB,b); print("saved")
