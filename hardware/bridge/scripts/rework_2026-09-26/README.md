# 2026-09-26 rework scripts (one-shot, kept for provenance)

These are the scripts that turned the half-migrated WROOM board (commit
`ccfd2a33` left every module trace dangling and the new buck/EN/BOOT parts
unrouted) into the routed rev with panel headers. They ran once, in this
order, against the files as they were that day. They are **not** re-runnable
as-is: `$SCRATCH` was a session scratch directory holding `head.kicad_pcb`
(the pre-rework board from git), the Specctra DSN/SES round-trip files and
the freerouting jar. Read them for the approach, not as tooling.

| Script | What it did |
|---|---|
| `sch_rework.py` | schematic: cache `Conn_01x04_Pin`, J3 → 1×04 I²C OLED, SW4/SW5 → J13/J14 headers, add J12 + R26–R28, rename `LED_ST1/2` → `LED_BT/USB`, no_connect the freed SCR_* pins |
| `pcb_prep.py` | PCB: net rename, remove SW4/SW5/old J3 + SCR_* copper, place new footprints, flip C48, prune dangling XIAO-era tracks, silk, hand-route the buck loop + WROOM GND/3V3 vias |
| `pcb_fix1..3.py` | DRC-driven fixes: via/track collisions, FB reroute, hide the auto-created `LCSC`/`JLCPCB` footprint fields (they land visible on F.Silkscreen) |
| `pcb_import.py` | first freerouting session import + re-lock |
| `codec_revert.py` | restore the committed codec-quadrant copper that the prune had eaten (QFN escapes the router could not rebuild) |
| `pcb_fix4..6.py` | hand routes: +5V buck feed, BTN1, pull-up plane vias, the module-west seam (SDA/SCL columns, MCLK via move, BCLK bridge) |
| `pcb_route2.py` | DSN export / SES import + re-lock for freerouting passes 2 and 3 (inner layers patched to `(type power)` in the DSN) |
| `pcb_trim.py` | trim dangling tails at their last junction |
| `drcparse.py` | de-duplicate a kicad-cli DRC text report |

Lessons that made it into `../../CLAUDE.md`: keep Python references to removed
pcbnew items alive, hide `SetField()`-created fields, use the JSON DRC report,
and mark In1/In2 as power layers before handing a DSN to freerouting.
