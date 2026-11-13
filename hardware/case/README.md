# MSP3223 + ElectroCookie + 2×18650 enclosure

Fully-enclosed, screw-lid case. Breadboard flat on the floor; **lid carries the
display (landscape) + rotary encoder**; 2×18650 holder alongside the breadboard.

## Render / export
OpenSCAD is installed (`brew --cask openscad`, 2021.01 + Rosetta 2). If it ever
gets killed on launch by Gatekeeper, clear the quarantine flag once:
`xattr -dr com.apple.quarantine /Applications/OpenSCAD-2021.01.app`. Then open
`case.scad`.

Set the `part` variable at the top, then **F6** (render) → **F7** (export STL):
- `part = "bottom";`   → print the tray
- `part = "lid";`      → print the lid (already flipped to print face-down)
- `part = "assembly";` → on-screen fit check only — **don't print this**

CLI export once OpenSCAD is installed:
```
openscad -D 'part="bottom"' -o bottom.stl case.scad
openscad -D 'part="lid"'    -o lid.stl    case.scad
```

## Outer size (with current defaults)
≈ **185 × 105 × 43 mm** (L×W×H). Fits a 220×220 bed.

## Component dimensions used
| Part | Dims (mm) | Source |
|------|-----------|--------|
| MSP3223 module/PCB | 90.96 × 55.22 × 1.63; total stack 6.22 | measured |
| MSP3223 glass (visible) | 77.88 × 55.22 (full module height) | measured |
| MSP3223 active (lit) area | 64.8 × 48.6 | lcdwiki — **verify** |
| ElectroCookie full board | 172.7 × 52.1 × 1.6 | ElectroCookie spec |
| 2×18650 holder | 75.21 × 38.91 × 20.04; holes 54.39 apart on centreline | measured |

## Display mount
The module drops into the lid from inside: the **glass slides up into a recess**
until its front meets the window frame (`lip_th`), and **4 corner snap-clips hook
over the PCB back** to hold it there. No screws needed. Because the glass is the
full module height, the frame lip is ~5 mm on the sides and ~2 mm top/bottom.

The PCB's own mounting holes were measured at only **0.635 mm (0.025") from each
edge** — too close to put bosses there, so `use_disp_screws` stays **off**. If
that measurement is actually larger, set it `true` and the bosses will appear.

## Controls (right of the screen)
Rotary encoder centred in X between the screen's visible right edge and the right
wall. **3× 12 mm panel-mount buttons** (`btn_hole_d` 12.2) form a horizontal row
directly under it at `btn_pitch` (19 mm) spacing; the encoder+row cluster is
centred top-to-bottom. Set `enc_cx`/`enc_cy` to override the auto-centring; change
`btn_count`/`btn_pitch` to retune.

## Breadboard mounting
- Sits on **3 standoff posts** (`bb_standoff` 5 mm) under its M3 (Ø3.2) centreline
  holes at 7.65 / 86.35 / 165.05 mm; screw down with M3 from above (`bb_post_pilot`
  2.6 self-tap, or 4.0 for heat-sets). The 5 mm lift clears soldered leads.
- The **corner lid-screw bosses now hang from the wall tops** (fused to the corners
  by a gusset) and stop partway down (`boss_h` 20 mm), so the floor corners are
  clear and the board drops fully in — the fix for it not seating before.

## ⚠️ Verify before printing
1. **Active (lit) area** `act_w/act_h` (64.8 × 48.6) — the one number you didn't
   supply; confirm it, and that it's centred on the glass, so the window lines up.
2. **Encoder** `enc_hole_d` (7.4 = EC11 bushing); **button** `btn_hole_d` (12.2).
3. **Battery screw size** `bat_hole_d` (3.2) — matches your holder's holes.
4. **Interior height** `in_h` (38) — increase if breadboard components/jumpers are
   tall; the display body hangs ~13 mm below the lid and clears the battery by ~5 mm.
5. **Button clearance**: the lower two buttons sit over the breadboard's right end —
   keep tall components clear of that area, or shorten `btn_pitch`.

## Fasteners
- Lid→tray: 4× **M3 heat-set inserts** in the wall-hung corner bosses + 4× M3
  screws through the lid counterbores. (Self-tap instead: drop `insert_d` to ~2.5.)
- Breadboard: 3× M3 down into the centreline standoff posts.
- Battery: 2× screws up through the case floor into the holder (heads counterbored
  flush on the underside).
- Optional USB charge-port cutout on the −Y wall (`usb_w=0` to remove).

## Print notes
- 0.2 mm layers, 3 perimeters, 20–30% infill is plenty.
- Tray prints floor-down (no supports). Lid prints outer-face-down — the glass
  recess and clips then face up; the small clip hooks may want light support.
