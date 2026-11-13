"""Add R15/R16/U10 (USB host port protection) to cw_bridge.kicad_pcb.

Adds the schematic-side USB host protection block to the PCB:
- R15/R16 22Ω 0603 series-R on D-/D+ (controller side).
- U10 USBLC6-2SC6 TVS array on D+/D-/VBUS (connector side).

Placement is constrained by:
1. The XIAO ESP32-S3 module (U4) thermal pad (pin 34, 2.75×2.50 mm) sits at
   the same XY as its USB pins — anything within ~1 mm of the USB pin row is
   either on or directly south of the thermal pad. So R15/R16 are placed
   EAST of the XIAO body (x≥117) rather than directly south.
2. J1 USB-A vertical receptacle has an SMD shield mounting tab at
   (139.22, 80.5) and main THT pads at x=144 — a top-layer TVS within ~5 mm
   of J1's D+/D- pads physically collides with the shield tab. So U10 is
   placed JUST SOUTH of J1's main body (y=91, ~10 mm from J1.D±) on the
   top layer. The bottom-layer alternative (under J1 pads) also failed
   clearance vs the J1 THT pad ring.

Resulting trace lengths from TVS to J1.D±: ~11 mm. Not optimal for ESD
performance — TVS effectiveness drops as trace length grows because the
unprotected trace acts as an antenna — but still a large improvement over
no TVS, and acceptable for a USB FS host port at hobbyist scale.

DRC: no copper/clearance/short errors introduced. Only delta vs
pre-placement is silkscreen (silk_over_copper / silk_overlap) cosmetic
warnings — to be cleaned up during the routing pass.
"""
import pcbnew

BOARD_PATH = "cw_bridge.kicad_pcb"
LIB_ROOT = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints"
R_LIB = f"{LIB_ROOT}/Resistor_SMD.pretty"
R_FP = "R_0603_1608Metric_Pad0.98x0.95mm_HandSolder"
SOT_LIB = f"{LIB_ROOT}/Package_TO_SOT_SMD.pretty"
SOT_FP = "SOT-23-6"


def mm(v):
    return pcbnew.FromMM(v)


def ensure_net(board, name):
    info = board.GetNetInfo()
    net = info.GetNetItem(name)
    if net is not None and net.GetNetCode() != 0:
        return net
    code = info.GetNetCount()
    net = pcbnew.NETINFO_ITEM(board, name, code)
    board.Add(net)
    return net


def load_fp(lib_path, fp_name):
    fp = pcbnew.FootprintLoad(lib_path, fp_name)
    if not fp:
        raise RuntimeError(f"failed to load {fp_name} from {lib_path}")
    return fp


def place(board, lib_path, fp_name, ref, value, x_mm, y_mm, rot_deg, lcsc, pad_nets, description="", back=False):
    if board.FindFootprintByReference(ref):
        print(f"  {ref} already present, skipping")
        return
    fp = load_fp(lib_path, fp_name)
    board.Add(fp)
    fp.SetReference(ref)
    fp.SetValue(value)
    fp.SetPosition(pcbnew.VECTOR2I(mm(x_mm), mm(y_mm)))
    if back:
        fp.Flip(fp.GetPosition(), False)
    fp.SetOrientationDegrees(rot_deg)
    fp.SetField("LCSC", lcsc)
    fp.SetField("JLCPCB", f"https://jlcpcb.com/partdetail/{lcsc}")
    if description:
        fp.SetField("Description", description)
    for pad in fp.Pads():
        pname = pad.GetName()
        if pname in pad_nets:
            net = ensure_net(board, pad_nets[pname])
            pad.SetNet(net)
    print(f"  {ref} placed @ ({x_mm}, {y_mm}) rot={rot_deg}{' [BACK]' if back else ''}")
    for pad in fp.Pads():
        ppos = pad.GetPosition()
        print(f"    pad {pad.GetName()}: ({ppos.x/1e6:.3f}, {ppos.y/1e6:.3f}) net={pad.GetNetname()!r}")


def main():
    board = pcbnew.LoadBoard(BOARD_PATH)

    # R16 (D+ series): east of XIAO body, upper of the R15/R16 pair so the
    # diff pair never crosses on its way to U10/J1 (which have D+ on top).
    place(
        board, R_LIB, R_FP, "R16", "22", 117.0, 89.0, 0,
        lcsc="C23345",
        pad_nets={"1": "USB_DP_RAW", "2": "USB_D+"},
        description="USB host D+ series termination",
    )
    # R15 (D- series): east of XIAO body, lower of the pair.
    place(
        board, R_LIB, R_FP, "R15", "22", 117.0, 91.54, 0,
        lcsc="C23345",
        pad_nets={"1": "USB_DN_RAW", "2": "USB_D-"},
        description="USB host D- series termination",
    )
    # U10 USBLC6-2SC6: TVS array south of J1's main body. Rotated 180° so
    # the D+ pads (pin 4 west, pin 3 east) sit on the upper row (y≈90.05),
    # matching J1.D+ at y=79.5 — keeps the diff pair untangled all the way
    # from XIAO → R → TVS → J1.
    # Schematic pin map: 1=I/O1 D-, 2=GND, 3=I/O2 D+, 4=I/O2 D+, 5=VBUS, 6=I/O1 D-.
    place(
        board, SOT_LIB, SOT_FP, "U10", "USBLC6-2SC6", 141.0, 91.0, 180,
        lcsc="C7519",
        pad_nets={"1": "USB_D-", "2": "GND", "3": "USB_D+", "4": "USB_D+", "5": "+5V", "6": "USB_D-"},
        description="USB host port ESD protection",
    )

    pcbnew.SaveBoard(BOARD_PATH, board)
    print(f"\nsaved {BOARD_PATH}")


if __name__ == "__main__":
    main()
