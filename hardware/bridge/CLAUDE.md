# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

KiCad 10 project for the **CW Bridge** PCB — an ESP32-S3 BLE-to-USB radio control dongle built around a bare **ESP32-S3-WROOM-1U-N16R8** module (U4; it replaced the XIAO ESP32-S3 on 2026-08-09). The companion firmware lives at `firmware/` in the monorepo (Rust on ESP-IDF) and the GPIO mapping in this schematic must stay in lock-step with `firmware/src/board.rs` (the firmware was ported from the Heltec dev-board pin map to this PCB on 2026-09-26: buttons/encoder switch/LEDs on the PCAL6416A, ES8388 over I²S, console on GPIO41).

## Verifying changes

KiCad CLI is at `/opt/homebrew/bin/kicad-cli`. After any schematic edit:

```bash
# ERC: catches shorts, unconnected pins, library mismatches
kicad-cli sch erc cw_bridge.kicad_sch

# Quick S-expression integrity check (parens balance; catches truncated edits)
python3 -c "import sys; t=open('cw_bridge.kicad_sch').read(); d=0; s=False; e=False
for c in t:
  if e: e=False; continue
  if c=='\\\\': e=True; continue
  if c=='\"': s=not s; continue
  if not s:
    if c=='(': d+=1
    elif c==')': d-=1
print('depth:', d)"
```

**The ERC baseline is 0 errors** (as of the 2026-06-11 USB-C rework; re-verified 2026-09-26 after the WROOM/panel-header rework). PWR_FLAGs exist on GND (×2), +3V3, and BOOST_5V; +5V is driven by the TPS2116's VOUT power-output pin; USB_5V is sourced through the J9 USB-C connector and its protection chain (F3 PTC + D3 TVS) without a separate flag; and the project-local `cw_bridge:USB_A_Host` symbol's VBUS pin was changed to power-*in* (the board powers the host port). Any ERC error is a regression introduced by your edit. (The `lib_symbol_mismatch` warnings on power symbols are cosmetic and clear on the next KiCad save.)

For PCB edits, also run DRC and check for new copper/clearance/short errors specifically (the ratsnest dominates the count until routing is done):

```bash
# All errors including ratsnest:
kicad-cli pcb drc cw_bridge.kicad_pcb -o /tmp/drc.rpt --severity-error
# Non-ratsnest errors only — these are the real ones to chase:
grep "^\[" /tmp/drc.rpt | grep -v unconnected | sort | uniq -c | sort -rn
```

**The DRC baseline (with `--severity-error --severity-warning`) is exactly 4 `hole_clearance` errors and 0 warnings** (re-established 2026-09-26) — the 4 errors are the documented J9 footprint-internal NPTH peg clearances (GCT footprint quirk, accepted). All silk warnings were eliminated in the 2026-07-17 JLC-DFM cleanup pass (silk widths ≥ 0.15 mm board-wide, ~30 refdes repositioned off pads/holes/edge, U4's XIAO outline segments through the castellated pad rows deleted, footprint outline segments split around tented vias, J9 shield slots widened 0.6 → 0.65 mm for JLC's min slot). Any new silk warning or `clearance`/`shorting_items`/`solder_mask_bridge`/`courtyards_overlap` hit is a regression. Two known-cosmetic leftovers JLC's DFM tool may still flag: U3/U7 pin-1 marker polygons over *tented* vias (kept — they carry orientation info), and via-in-pad on TP9/TP10 (intentional).

### Deeper analysis (kicad-happy)

Clone `https://github.com/aklofas/kicad-happy.git` once; it's pure-stdlib Python so no install needed. The schematic analyzer catches ESD coverage gaps (EP-AUD), missing USB series resistors (PR-004), and other design-rule findings ERC can't:

```bash
python3 /tmp/kicad-happy/skills/kicad/scripts/analyze_schematic.py cw_bridge.kicad_sch --output /tmp/kh-sch.json
python3 /tmp/kicad-happy/skills/kicad/scripts/analyze_pcb.py cw_bridge.kicad_pcb --output /tmp/kh-pcb.json
```

Triage the JSON output by severity and detector. **Most kicad-happy findings on this board are false positives** — the hit rate was 3/61 on the first run. Confirmed false positives to dismiss without investigation:

- `SS-001` (0% MPN coverage) — we use `LCSC` properties, not `MPN`.
- `VM-001` (5V/3.3V domain crossings) — the WROOM module (U4), ES8388 (U3) and PCAL6416A (U5) are all 3.3V; the only 5V nodes are the USB/mux/buck-input side.
- `NT-001` (single-pin nets) — parser bug on the I²C pullup junction topology. Verify against `kicad-cli sch export netlist` if uncertain.
- `PP-001` (no DC path to power rail) — graph walk gives up; check `kicad-cli sch export netlist` instead.
- `PU-001` for U4's unused GPIOs (no_connect), U7 MODE (TPS2116 priority topology), U9 EN (driven by SW2), U8 STAT (open-drain via LED). U4 EN and IO0 *do* have pull-ups (R24/R25).
- `RS-001` for +3V3 / BOOST_5V (PWR_FLAGs exist — see paragraph above).

Real signals to take seriously: `EP-AUD`/`PR-004` (USB ESD/series-R coverage), `RT-001` for newly added components (means they need routing), and any `clearance`/`shorting_items` from the PCB analyzer that DRC also flags.

## Editing the `.kicad_sch` file directly

The user often has KiCad open while you edit the file. **Always `Read` the file again before each `Edit`** — KiCad rewrites the whole file on save, invalidating prior reads. If you see "File has been modified" errors, re-read and resume.

KiCad caches the symbol library *inline* in the schematic (`(symbol "<lib>:<name>" ...)` blocks near the top of the file). Two consequences:

- Instances using a `lib_id` that isn't cached **will fail ERC** with `pin_not_connected` because the pins have no resolved geometry. When adding a new symbol type, either (a) add the cached symbol definition by copying from KiCad's standard libraries under `/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols/`, or (b) reuse an existing cached symbol with the same pin layout and set `Value` / `Footprint` to the actual part. (The current `D1 SB140` uses approach (b) — it reuses the `Diode:SMAJ15A` cached symbol. Note that cached symbol is the *bidirectional* variant (pins named A1/A2, no cathode marking); polarity is enforced only by the `D_SMA` footprint convention of pad 1 = cathode, so verify D1's band orientation at layout/assembly. `Device:R`, `Device:L`, and `Regulator_Switching:AP63205WU` are also cached inline as of the 2026-06-10 power/audio rework.)
- Indentation is **tabs, not spaces**. Top-level elements (`(symbol …)`, `(wire …)`, `(global_label …)`, `(no_connect …)`, `(junction …)`) are 1 tab deep. The `(version)` field at the top is 8-digit YYYYMMDD.

## Geometry notes when adding components

- Default grid is **1.27 mm**. Off-grid pin tips produce `endpoint_off_grid` warnings. Multiply your intended pin coordinate by `/1.27` and confirm it's an integer.
- Symbol pins are defined in symbol-local coords with **Y axis up**, but schematic Y axis is **down**. For a symbol placed at `(X, Y)` rotation 0, a pin at sym `(px, py)` is at schematic `(X + px, Y − py)`.
- A `global_label "<name>"` placed at a pin tip auto-connects to that net — no wire needed. Same for `power:GND` / `power:+5V` / `power:+3V3` symbols.
- Global labels at angle **180 or 270 need `(justify right)`**; with `(justify left)` the text renders back over the anchor and smushes into whatever it's attached to. Angles 0/90 use `(justify left)`.
- Symbol **property text angle is relative to the symbol's rotation** — for a symbol at rot 90/270, set the Reference/Value property angle to `(360 − rot) % 360` to render horizontal. And never emit `(fields_autoplaced yes)` on hand-positioned fields: kicad-cli re-autoplaces them (rotated with the symbol), ignoring your coordinates.
- The `+3V3` cached symbol was hand-added (KiCad's standard library version differs slightly, hence the `lib_symbol_mismatch` warning — clears on next KiCad save).

## ESP32-S3-WROOM-1U (U4) pin allocation

U4 is a bare SMT module (`RF_Module:ESP32-S3-WROOM-1U` footprint, 41 pads incl. the EP; the `-1U` has a U.FL antenna connector, so there is no PCB-antenna keepout). Unlike the XIAO it needs the carrier to supply 3.3 V (buck U11), the EN reset network (R24 10k + C53 1 µF, RESET header J13) and the IO0 boot strap (R25 10k, BOOT header J14). GPIO **numbers** were kept identical to the XIAO design so no firmware net names changed. Slow inputs and the firmware LEDs live on the PCAL6416A I/O expander (U5); the ES8388 codec's I²S link, the encoder phases and the I²C bus stay on native GPIO.

Note: **ES8388 has no hardware reset pin** (reset is done in software via I²C). GPIO44 drives the PCAL6416A's ~RESET~ line (`EXP_RST`) instead.

| WROOM pin | GPIO | Function | Notes |
|---|---|---|---|
| 1, 40, 41 (EP) | GND | GND | EP stitched to the In1 plane with 4 vias |
| 2 | 3V3 | `+3V3` (input) | from buck U11; C51 10 µF + C50/C52 100 nF at the pin |
| 3 | EN | `ESP_EN` | R24 pull-up, C53 to GND, J13 RESET header to GND |
| 4 | GPIO4 | NC | freed 2026-09-26 (was `SCR_CS`, SPI screen dropped) |
| 5 | GPIO5 | `I2C_SDA` | shared bus: ES8388 (U3) + PCAL6416A (U5) + OLED (J3) |
| 6 | GPIO6 | `I2C_SCL` | shared bus |
| 7 | GPIO7 | NC | freed 2026-09-26 (was `SCR_SCK`) |
| 12 | GPIO8 | `EXP_INT` | PCAL6416A interrupt out (open-drain → ESP) |
| 13 | GPIO19 | `USB_DN_RAW` | native USB host D− (→ R15 22 Ω) |
| 14 | GPIO20 | `USB_DP_RAW` | native USB host D+ (→ R16 22 Ω) |
| 15 | GPIO3 | `I2S_DIN` | codec → ESP (ASDOUT) |
| 17 | GPIO9 | NC | freed 2026-09-26 (was `SCR_MOSI`) |
| 27 | GPIO0 | `BOOT` | R25 pull-up, J14 BOOT header to GND (strapping pin) |
| 32 | GPIO39 | `I2S_BCLK` | bit clock |
| 33 | GPIO40 | `I2S_LRCK` | left/right word select |
| 34 | GPIO41 | `DEBUG_TX` | debug UART TX → J11 (route UART via GPIO matrix) |
| 35 | GPIO42 | `I2S_DOUT` | ESP → codec (DSDIN) |
| 36 | GPIO44 | `EXP_RST` | PCAL6416A hardware reset (active low) |
| 37 | GPIO43 | `I2S_MCLK` | master clock to codec (~12 MHz) |
| 38 | GPIO2 | `ENC_DT` | rotary encoder phase B — must stay native |
| 39 | GPIO1 | `ENC_CLK` | rotary encoder phase A — must stay native (fast edges) |
| all others | — | NC | GPIO35/36/37 are reserved by the octal PSRAM on the N16R8 — never bind them |

**Critical:**
- USB host data lines MUST be on pins 13/14 (GPIO19/20 — the ESP32-S3's native USB peripheral).
- I²S clocks must stay on native GPIO — they cannot move to the expander. Same for the encoder phases (GPIO1/2).
- GPIO4/7/9 are spare native pins now that the screen is I²C; prefer them over expander pins for anything latency-sensitive.

### USB data path: host port (J1) + RUN/FLASH switch (SW3) + flash port (J9)

`U4 pins 13/14 (GPIO19/20) → R15/R16 (22 Ω, 0603) → USB_D-/USB_D+ → U10 USBLC6-2SC6 (SOT-23-6 TVS array) → SW3 (DPDT slide) → J1 (RUN) or J9 data pins (FLASH)`

- Net-name map (2026-07-18 flash-port rework): `USB_DN_RAW`/`USB_DP_RAW` between the module and the series resistors; `USB_D-`/`USB_D+` from the resistors through U10 to SW3's common pins (2/5); `USB1_D-`/`USB1_D+` from SW3 throws 1/4 to J1; `USB9_D-`/`USB9_D+` from SW3 throws 3/6 to J9 pads A6+B6 / A7+B7 (both orientations wired — cable flip works).
- **SW3** = C&K JS202011JCQN (LCSC C221665; JS202011JAQN C221664 is a same-land-pattern substitute), footprint `Button_Switch_SMD:SW_DPDT_CK_JS202011JCQN`, placed at (147.3, 67) rot 90 with silk `RUN` (south, actuator toward pins 1/4) and `FLASH` (north). Cached symbol `Switch:SW_Slide_DPDT`.
- **RUN** (normal): data lines go to the J1 radio host port; J9 is charge-only, so BC1.2 wall-warts (which short D+↔D− at their end) can't disturb CAT.
- **FLASH**: data lines go to J9 — plug a PC into the USB-C port to reach the S3. The PC also powers the board through F3 → mux, so flashing works with SW2 off and no battery. Enter the ROM bootloader first (hold BOOT on the J14 header while pulsing RESET on J13, or while plugging in): once the app firmware boots it claims the PHY for host mode and USB-Serial-JTAG disappears. Firmware follow-up: "hold BTN1 at power-on → `RTC_CNTL_FORCE_DOWNLOAD_BOOT` restart" as a no-BOOT-button escape hatch for enclosed units.
- Never data-connect both ports at once (PC on J9 in FLASH while a radio is on J1 is fine electrically — J1 is simply dead).
- Best-practice topology unchanged: TVS at the connector side, series-R at the controller. U10 sits on the *common* segment so it protects both J1 and J9 paths. U10 VBUS pin (5) → `+5V`, GND pin (2) → `GND`; internally pins 1↔6 / 3↔4 are single I/O nodes.
- LCSC: USBLC6-2SC6 = C7519, 22Ω 0603 1% = C23345 (both JLC Basic).

### PCAL6416A (U5) port assignment

The I/O expander handles all slow inputs and the two firmware status LEDs:

| Expander pin | Net | Role |
|---|---|---|
| IO0 (P00) | `BTN1` | button input (J4 header) |
| IO1 (P01) | `BTN2` | button input (J5 header) |
| IO2 (P02) | `BTN3` | button input (J6 header) |
| IO3 (P03) | `ENC_SW` | encoder pushbutton (off-board module on J15) |
| IO4 (P04) | NC | spare since 2026-09-26 (was `SCR_DC`) |
| IO5 (P05) | NC | spare since 2026-09-26 (was `SCR_RST`) |
| IO6 (P06) | `LED_BT` | Bluetooth status: on-board D9 + panel LED via J12.3/R27 (sink, **active low**; blink = searching, solid = paired) |
| IO7 (P07) | `LED_USB` | USB status: on-board D10 + panel LED via J12.4/R28 (sink, **active low**; blink = connected, solid = identified) |
| IO8–IO15 (P1_0–P1_7) | spare | future I/O; no_connect markers |
| RESET | `EXP_RST` (driven by GPIO44) | hardware reset, active low; pulled up by R3 (10 kΩ) |
| INT | `EXP_INT` (→ GPIO8) | interrupt to MCU on any input change |
| ADDR | GND | I²C address `0x20` |

## Panel headers (rev 2.1, 2026-09-28)

Everything a front panel needs is on **JST PH 2.0 mm top-entry housings** (the same `JST_PH_BxB-PH-K` family as the battery connector J10) along the right, front and left edges; nothing user-facing is soldered to the board any more — the rotary encoder became an off-board module on J15. All of these are **hand-soldered** (LCSC blank, excluded from the JLC BOM/CPL; see `production/cw_bridge_hand_assembly.csv`). Pin 1 is the square pad; the keyed housing makes the `1` silk marks of rev 2.0 redundant, so they were dropped.

| Ref | Header | Pins (1 → n) | Position / rotation | Notes |
|---|---|---|---|---|
| J15 | `ENCODER` B5B 1×05 | CLK, DT, SW, +3V3, GND | (60, 112) rot 0, pads along +x, front-left where SW1 was | KY-040-class encoder module (pin order matches the module's silk). CLK/DT go to native GPIO1/2, SW to expander P03. The module carries its own 10 k pull-ups on CLK/DT; SW relies on the PCAL6416A pull-up. Silk legend `CLK DT SW 3V3 GND` under the housing. |
| J3 | `OLED` B4B 1×04 | GND, VCC (+3V3), SCL, SDA | (142, 106) rot 270, pads along +y | 128×64 SSD1306-class module at I²C `0x3C`. Pin names silk-screened right of the housing. C37 is its decoupling. |
| J12 | `LEDS` B4B 1×04 | +3V3, PWR, BT, USB | (138, 118) rot 270, pads along +y | Common-anode panel LEDs; series R26/R27/R28 (1 kΩ) on-board. |
| J13 | `RESET` B2B 1×02 | ESP_EN, GND | (108, 124) rot 0 | momentary to GND |
| J14 | `BOOT` B2B 1×02 | BOOT, GND | (118, 124) rot 0 | momentary to GND; hold while pulsing RESET for the ROM bootloader |
| J4/J5/J6 | `BTN1`–`BTN3` B2B 1×02 | BTNx, GND | (78/88/98, 124) rot 0 | front row, 10 mm pitch; labels under the housings |
| J11 | `UART TX` B2B 1×02 | DEBUG_TX, GND | **(128.4, 75.5) rot 0** — moved 2026-09-28 from (122.5, 72); the PH housing did not fit between R6/R9/D7/TP4 | DEBUG_TX re-routed on B.Cu: (121.7, 72.38) → (124.82, 75.5) → pad 1 |

Mating side: PHR-2 / PHR-4 / PHR-5 housings with SPH-002T-P0.5S contacts, or pre-crimped PH jumper leads. Rev 2.0 used 2.54 mm pin headers (J3/J12 1×04 at the same origins, J4–J6/J11/J13/J14 1×02) and an on-board Bourns PEC12R encoder SW1 at (60, 112).

Antenna (2026-09-26 decision): **no antenna parts on the PCB.** The WROOM-1U's radio output exists only at the U.FL (IPEX MHF1) socket on top of the module; a U.FL-plug-to-SMA-female-bulkhead pigtail (5–20 cm, 1.13 mm/RG178) runs from U4 to a ~6.5 mm hole in the enclosure wall, and a 2.4 GHz SMA-male antenna screws onto that. An on-board U.FL receptacle + edge SMA pair was tried and removed the same day as pointless duplication (the module already is the U.FL).

Silk (2026-09-28): every header carries a purpose label — `BTN1`–`BTN3`, `RESET`, `BOOT` centred under the front-row housings (refdes above them, J13's shifted left to clear D6); `UART TX` under J11; `OLED` above J3 with GND/VCC/SCL/SDA to its right; `LEDS` left-below J12 with 3V3/PWR/BT/USB to its right; `CLK DT SW 3V3 GND` under J15; `BAT` with `+`/`-` under the J10 JST pads; `AUDIO IN` / `AUDIO OUT` above the TRS jacks. The rev 2.0 `1` pin markers were removed with the move to keyed JST housings. Board minimum silk text height is 0.8 mm (DRC `text_height`) — do not go smaller.

Schematic: the panel-LED block (J12 + R26–R28) sits at the bottom-right of the sheet below J11/TP5; J13/J14 took over the old SW4/SW5 positions in the EN/BOOT block; J3 is at the old screen-header spot with the SCR_* labels replaced by no_connects on U4 pins 4/7/17 and U5 P0_4/P0_5; J15 (`Connector:Conn_01x05_Pin`, cached inline 2026-09-28) sits where SW1 was at (135.89, 209.55) with ENC_CLK/ENC_DT/ENC_SW labels and +3V3/GND on its pins. Scripts for the rev 2.1 rework: `scripts/rework_2026-09-28/`.

## Libraries

The project's `fp-lib-table` and `sym-lib-table` point into `../libraries/`:

- `Seeed_Studio_XIAO_Series` — symlink → `seeed_opl/Seeed Studio XIAO Series Library/`. **Legacy** since the 2026-08-09 WROOM swap: no instance uses it any more, it's only kept so the lib table resolves. Re-clone with `git clone --depth 1 https://github.com/Seeed-Studio/OPL_Kicad_Library.git` if missing.
- `heltec_htit-wb32` — leftover from the v0 design when the bridge was based on a Heltec module. The schematic title block still mentions Heltec; the actual MCU is now the ESP32-S3-WROOM-1U. Don't follow the schematic header's pinout links.
- `cw_bridge.pretty` — project-local footprint overrides at `../libraries/cw_bridge.pretty/`. Contains the legacy `XIAO-ESP32-S3-SMD.kicad_mod` (back-pad numbering remapped 15–25 → 24–34); unused since the WROOM swap. U4 now uses the stock `RF_Module:ESP32-S3-WROOM-1U`.

Project-local symbols (`cw_bridge:USB_A_Host`, `cw_bridge:RotaryEncoder_Switch`) exist only inline in the schematic — `cw_bridge.kicad_sym` is an empty stub. Don't try to register a `cw_bridge` library in `sym-lib-table`.

## Known schematic/footprint mismatch warnings

A single warning persists during "Update PCB from Schematic" that's intentional, not a bug:

- **J2 pad MP (×2)** — the CUI PJ-063AH barrel jack footprint exposes a mechanical mounting tab (pad name `MP`). The `Connector:Conn_01x02_Pin` symbol used for J2 has no MP pin, so KiCad reports "No net found." This is fine — the mounting tab is typically grounded through the chassis, not through the netlist. Swapping to `Conn_01x02_MountingPin` is not viable because that symbol's pin positions differ and would unwire the existing J2 connections.

## Audio signal path

`J8 (3.5 mm TRS, AUDIO IN) → AC-couple (C23/C24, 1 µF) → ES8388 LIN1/RIN1 → I²S → ESP32-S3 → I²S → ES8388 ROUT1/LOUT1 → DC-block (C25/C26, 10 µF) → 10 kΩ bleed to GND (R4/R5, anti-pop) → J7 (3.5 mm TRS, AUDIO OUT)`

- The codec-side nets are `LIN1`/`RIN1`/`LOUT1`/`ROUT1`; the jack-side nets are `AUDIO_IN_*`/`AUDIO_OUT_*`. The coupling caps bridge the two via global labels in the "audio AC-coupling" block right of U3 — there are no wires between the jacks and the codec.
- ES8388 (U3) is controlled over I²C address `0x10` (CE pin tied to GND).
- I²C bus is shared with the PCAL6416A I/O expander (U5 at `0x20`). 4.7 kΩ pull-ups R1/R2 on SDA/SCL to +3V3 (one set on the bus, not per device); R3 (10 kΩ) pulls EXP_RST up so the expander isn't held in reset while GPIO44 floats during boot.
- The codec runs from +3V3 with separate decoupling on AVDD / DVDD / PVDD / HPVDD (C30–C33) plus VREF/ADCVREF/VMID caps (C20–C22). The 3V3 decoupling bank (C30–C37, bottom middle of the sheet) also covers U5 (C35/C36) and the screen header (C37) — place each cap at its annotated pin during layout, they are only grouped on the schematic.
- AudioJack2_Switch symbols are used for both jacks — the shorting switch contact is currently a no-connect; future revisions can wire it as a mute/insertion-detect on a spare expander pin.

## Debug features (2026-07-05)

Status LEDs (all 0603, current-limited from their rail; GND side via to the In1 plane):

| Ref | Silk | Net | Color / LCSC | Meaning |
|---|---|---|---|---|
| D6 | PWR | +3V3 via R17 1k | green C965804 | logic rail up (~0.7 mA always-on battery cost) |
| D7 | VBUS | USB_5V via R18 1k | blue C965807 | USB-C power present past F3/D3 (value renamed from "USB LED" 2026-09-26 to avoid confusion with the USB *status* LED) |
| D8 | BOOST | BOOST_5V via R19 4.7k | red C965799 | boost converter output alive (SW2 on) |
| D9 | BT | +3V3 → R20 1k → `LED_BT` → U5 P0_6 | green C965804 | Bluetooth status, **active low** (expander sinks); mirrored on panel header J12.3 through R27 |
| D10 | USB | +3V3 → R21 1k → `LED_USB` → U5 P0_7 | blue C965807 | USB host status, **active low**; mirrored on J12.4 through R28 |
| — | (panel) | J12.2 → R26 1k → GND | user's choice | panel power LED, always on from +3V3 |

- Net rename 2026-09-26: `LED_ST1` → `LED_BT`, `LED_ST2` → `LED_USB` (schematic + PCB). Firmware convention: BT blink = searching, solid = paired; USB blink = device connected, solid = identified (CAT protocol matched).
- **J11 "DEBUG UART"** (1×02, just east of U4): pin 1 = `DEBUG_TX` (GPIO41, WROOM pin 34 — route a UART TX there via the GPIO matrix), pin 2 = GND. This is the board's **only console**: UART0's default pins (GPIO43/44) carry I2S_MCLK/EXP_RST and the S3's USB-Serial-JTAG (GPIO19/20) is consumed by USB host mode.
- **Test points** (`TestPoint_Pad_D1.5mm`, marked `in_bom no` — the exporter skips them): TP1 VBAT, TP2 USB_5V, TP3 BOOST_5V, TP4 +5V, TP5 +3V3, TP6 SDA, TP7 SCL, TP8 EXP_INT, TP9–TP13 I2S MCLK/BCLK/LRCK/DIN/DOUT. Most sit directly on existing tracks; TP9/TP10 tap B.Cu runs through a via in the pad; TP12 hangs off the I2S_DIN track on a short stub at (92.0, 88.6) — it originally sat flush against the XIAO body edge only 0.24 mm from the SCR_CS pad (probe-slip short risk, moved 2026-07-19).
- Firmware follow-up: drive BT/USB LEDs through the PCAL6416A (configure P0_6/P0_7 as outputs, low = lit) and emit console logs on a GPIO41 UART.

## Power topology

USB-C + onboard 1S LiPo, USB priority (2026-06-11 rework — the 13.8 V barrel/buck input was removed entirely):

- **USB-C input:** `J9 (USB-C 16P, 5.1 kΩ CC pull-downs R6/R7 — mandatory for C-to-C cables) → F3 (2 A PTC, 1206) → USB_5V net (D3 SMAJ5.0A TVS, C38/C39/C40)`. As of 2026-07-18 J9's data pins are also wired (nets `USB9_D±`) as the firmware-flash port behind SW3 — see the USB data path section above.
- **Charger:** `U8 (MCP73831-2, SOT-23-5) — VDD = USB_5V, VBAT → VBAT net, PROG R10 2k → 500 mA charge, STAT drives D4 "CHG" LED via R14 (lit while charging)`
- **Battery:** `J10 (JST-PH) → VBAT net (C41/C44/C45)`. **Use a PROTECTED 1S cell** — there is no under-voltage cutoff on the board (TPS61085 UVLO is 2.2 V, far below safe LiPo discharge).
- **Boost:** `VBAT → SW2 (PCM12 slide, drives EN only — not in the power path) → U9 (TPS61085, VSSOP-8, 650 kHz: FREQ=GND) + L2 6.8 µH + D5 (SS14 rectifier — non-synchronous boost needs it) → BOOST_5V (C46/C47)`. FB divider R11/R12 = 54.9k/18k → 5.01 V; COMP = R13 5.6k + C42 2.7 nF; SS = C43 100 nF. Good for ~1 A at 5 V from a 3.0 V cell.
- **Mux:** `U7 (TPS2116, SOT-583) — VIN1 = USB_5V (priority), VIN2 = BOOST_5V (fallback), VOUT → +5V rail (C4–C7)`. MODE tied to VIN1; PR1 divider R8/R9 (100k/33k) trips at ~4.0 V on USB_5V. Plugged in: system runs from USB while the cell charges. Unplugged (and SW2 on): boost carries the rail. Reverse-current blocking prevents backfeeding the USB source. **No series diode on the USB path** — a Schottky drop would put the J1 host port below USB spec.
- **+3V3 buck (2026-08-09, routed 2026-09-26):** `+5V → C48 22 µF → U11 (AP63200WU, TSOT-23-6, ~2 A sync buck) + L3 3.3 µH → +3V3 (C49 22 µF) → In2 plane`. FB divider R22/R23 = 100k/31.6k → 3.33 V; BST cap C50 100 nF between SW and BST. This replaced the XIAO's on-module LDO as the source of the whole +3V3 rail (codec, expander, OLED, panel LEDs, module). Hand-routed and locked: C48.1 → VIN at 0.5 mm, SW → L3 at 0.5 mm, L3 → C49 → two ⌀0.8 vias into the +3V3 plane, FB on a 0.25 mm run that detours north of C48 and along y≈109.25 between R22 and R23. C48 was rotated 180° so its +5V pad faces the VIN pins.
- Module supply: C51 10 µF + C52 100 nF at WROOM pin 2; EN network R24 10k + C53 1 µF; IO0 pull-up R25 10k. No 5 V reaches the module.
- Power-budget note: the radio on J1 typically draws almost nothing from VBUS (CAT data only), so realistic battery load is ~350 mA at 5 V; worst case (radio pulling its full 500 mA) ~0.9 A — within the boost's capability but check thermals if that ever becomes the norm.

## PCB (cw_bridge.kicad_pcb)

Board populated 2026-06-10 from the schematic netlist via pcbnew scripting (KiCad's bundled Python at `/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3` — `import pcbnew` works headless; the wxApp assert it prints is harmless).

- **Outline:** 100 × 80 mm rectangle at (50,50)–(150,130), M3 mounting holes H1–H4 in the corners. Hand-solder spacing throughout.
- **Stackup:** 4 layers — F.Cu signals, **In1.Cu = GND plane**, **In2.Cu = +3V3 plane**, B.Cu = signals + GND pour. +5V has no plane; route it on the outer layers (buck → J1 VBUS → XIAO pin 14).
- **Placement groups:** rear-left: J10 battery JST + SW2 power switch on the rear edge; boost power row left-to-right in chain order along the rear (C45 → L2 → U9 → D5) with its small-signal row beneath (C44, R13/C42 comp, C43 SS, R11/R12 FB, C46/C47 out); charger cluster (U8, C40/C41, R10, R14, D4) between the audio-in jack and the codec decoupling row; J9 USB-C on the rear edge at top-right (rot 180 — the GCT footprint's opening faces +y at rot 0) with its protection row F3/D3/C38/C39, CC resistors R6/R7 below, mux U7 + divider R8/R9 beneath, rail caps C4/C5 at the mux output; J1 USB-A **horizontal** receptacle on the right edge (SHOU HAN AF 90 WJDG, C456018, on the industry-standard right-angle land pattern `USB_A_Molex_67643_Horizontal`; pin row at x = 138.2, opening toward +x, shell face ~1.2 mm proud of the edge; C5 moved to (139.6, 70.3) to clear its back edge, 2026-09-26) with C6/C7; WROOM U4 at board center (105, 86), pins 1–14 down its west edge, 15–26 along the south, 27–40 up the east edge; R1–R3 pull-ups between U4 and U5; U5 + C35/C36 right; J3 OLED header + C37 on the right edge with J12 panel-LED header and R26–R28 just below; buck cluster (C48 → U11 → L3 → C49 in a row at y = 104, C50 above U11, R22/R23 below C49) directly south of the module with the EN/BOOT parts (C53, R24, R25, C51/C52) to its west; J8/J7 TRS jacks overhang the left edge with the codec cluster (U3, C20–C22, C30–C34, coupling C23–C26, bleed R4/R5) between them; J15 encoder header (front-left, where the SW1 encoder was) + button headers J4–J6 + C8–C10 + RESET/BOOT headers J13/J14 along the front; all panel headers are JST PH since rev 2.1.
- **Connector orientation facts** (rot 0): SJ1-3515N TRS opens toward −x; GCT USB-C opens toward +y; the WROOM footprint origin is the module body centre; 1×0N pin headers have pin 1 at the origin with the row extending +y.
- **Netclass change:** Default and Power clearances are both 0.15 mm in `cw_bridge.kicad_pro` — the VSSOP-8 (0.65 mm pitch, 0.15 mm pad gap) and QFN-28 (0.45 mm pitch, 0.2 mm gap) physically can't satisfy more. 0.15 mm is comfortably above any fab's 4-layer minimum and fine at ≤5 V.
- **State (2026-07-05): fully routed, DRC-clean, 0 unconnected** — including the debug rework (5 status LEDs, J11 debug-UART header, 13 test points; hand-routed same day). Base routing: 942 track segments + 140 vias. Critical nets are hand-routed and **locked** (USB diff pair with B.Cu hops across the XIAO pad field, boost SW node + input/output loops, VBAT/USB_5V/BOOST_5V/+5V at 0.6–1.5 mm); every GND/+3V3 SMD pad is stitched to its inner plane with a via (or bridged into the U3 EPAD); remaining signals were autorouted (freerouting 2.2.4, inner layers excluded) plus a custom grid-router pass for the codec quadrant. The only DRC hits are 4 pre-existing J9 footprint-internal NPTH hole clearances (present before routing; GCT footprint quirk). When editing routes: keep locked tracks locked, never route signals on In1/In2 (planes), and refill zones + re-run DRC after any change.
- **State (2026-09-26): fully routed again, DRC at the 4-hole baseline, 0 unconnected, 0 warnings** — 1025 track segments + 192 vias, 118 footprints. The 2026-08-09 WROOM swap had left every module trace dangling and the buck/EN/BOOT parts unrouted; this pass pruned the XIAO-era orphans, restored the committed codec-quadrant copper (the QFN-28 escapes are too tight for freerouting — never let a prune eat them), and re-routed everything to the WROOM. Hand-routed and **locked**: the buck power loop (C48 → U11 → L3 → C49, SW/BST/FB), the **+5V buck feed** (tapped from the J1-VBUS B.Cu via at (138.7, 91), down the east side on B.Cu at x≈139.8, via to F.Cu at (139.3, 101.5) — the jog around x137–139.3 dates from a since-removed U.FL receptacle and is harmless, across on F.Cu at y = 100.6 under the LED row, B.Cu hop under U11 into C48.1 at 0.5–0.6 mm), BTN1 (B.Cu 45° diagonal parallel to BTN2), the WROOM GND/3V3 pin vias + 4 EP vias, the SDA/SCL columns in the 1.8 mm strip between the codec chains and U4's west pads (SDA x = 94.4, SCL x = 95.05 — the MCLK layer-change via was moved to (91.5, 83.88) to make room; only one 0.25 mm track fits past it otherwise), and the +3V3 plane vias for R22/R24/R25/C51/C52. Everything else was freerouting 2.4.1 (three passes, inner layers marked `(type power)` in the DSN so it never routes on the planes). Scripts + notes: `scripts/rework_2026-09-26/`.
- **Scripting gotchas (2026-09-26):** (1) after `board.Remove(item)` keep a Python reference to `item` until you save — letting it be garbage-collected corrupts the SWIG runtime and every later call returns bare `SwigPyObject`s; (2) `fp.SetField("LCSC", …)` on a footprint loaded via `FootprintLoad` creates a *visible* field on F.Silkscreen — hide it or move it to F.Fab; (3) `kicad-cli pcb drc --format json` is the only report that reliably names both items of a silk violation; (4) freerouting round trips lose lock flags — snapshot locked geometry before `ExportSpecctraDSN` and re-lock by matching endpoints after `ImportSpecctraSES` (which replaces *all* tracks); (5) `--schematic-parity` reports `footprint_symbol_mismatch` on every footprint and `unconnected-(…)` net conflicts on every NC pad because the board was populated by script, not by "Update PCB from Schematic" — pre-existing, ignore.
- **State (2026-09-28, rev 2.1): DRC at the 4-hole baseline, 0 unconnected, 0 warnings.** Panel headers swapped to JST PH (pad 1 kept in place, 2.0 mm pitch: the SCL/SDA and PNL_* stubs were re-targeted, BTN3's B.Cu return now runs under the front-row pads at y = 125.3 instead of between the old 2.54 mm pins, DEBUG_TX re-routed to the relocated J11). SW1 removed; J15 at (60, 112) reuses the ENC_CLK diagonal, ENC_DT along y = 115.89 into pad 2, ENC_SW on B.Cu via (76.5, 110) → (64, 110) into pad 3; +3V3/GND pads pick up the inner planes directly. Title silk says `rev 2.1`.
- **Flash-port rework (2026-07-18), hand-routed + locked, DRC still at the 4-hole baseline:** SW3 at (147.3, 67) rot 90 in the pocket east of the mux; commons run from U10 down the east strip (USB_D− F.Cu x147.35 → via → B.Cu; USB_D+ B.Cu x146.7), USB1 pair drops south to J1's through-hole pads (D+ F.Cu, D− B.Cu into the pad barrel), USB9 pair runs B.Cu along y57.9/y59.5 under the rear corridor to a 4-via fan below J9's interleaved data pads (F.Cu escapes at 0.25 mm, ⌀0.5/0.3 vias, pair-joins dodge on B.Cu). To make room for that fan, **the USB_5V trunk jog moved from y59.35 (north of the D3 row) to y62.6 (south of it)** and the Net-(F3-Pad1) VBUS join now dips to the freed y59.35 lane — both still locked F.Cu at original widths. Silk `RUN`/`FLASH` marks the SW3 positions.

## JLCPCB assembly metadata

Every component symbol carries a hidden **`LCSC`** property with its JLCPCB
part number (verified against JLC's catalog 2026-06-11). `jlcpcb_export.py`
turns the schematic + PCB into `production/cw_bridge_bom.csv` and
`production/cw_bridge_cpl.csv` (JLC upload format). Re-run it after any
schematic or placement change. Rules:

- New/changed components need their `LCSC` field set (or left empty for
  hand-assembly parts). A component with an empty/`-` LCSC (or DNP) is excluded
  from **both** the uploaded BOM and the CPL — they must cover the same
  designators or JLC's DFM flags "designator doesn't exist in the CPL file"
  (2026-07-26). Such parts are written to `production/cw_bridge_hand_assembly.csv`
  (a reference list, not uploaded) so they stay visible.
- Hand-assembly parts (blank LCSC): J7/J8 (CUI SJ1-3515N) and, since rev 2.1
  (2026-09-28), every panel header J3 J4 J5 J6 J11 J12 J13 J14 J15 (JST PH
  B2B/B4B/B5B — JLC stocks the family if you ever want them placed). J1 became
  a JLC-placed horizontal USB-A on 2026-09-26 (C456018). The rev 2.0 2.54 mm
  headers were C124375 (1×02) / C124378 (1×04).
  L2 is Sunlord SWPA5040S6R8MT C36411 (the earlier substitute C326317 was
  dropped 2026-07-26 for stock reasons).
- Footprints added from pcbnew Python get **visible `LCSC`/`JLCPCB` fields
  on F.Silkscreen** when you `SetField()` them — hide them (or move to
  F.Fab) or DRC reports dozens of phantom silk overlaps with no item name.
- Stock/sourcing caveats and the mandatory rotation-check list live in
  `production/README.md` — read it before ordering.

## Backup files

KiCad auto-creates `cw_bridge-backups/` (gitignored via `hardware/.gitignore`) and `_autosave-cw_bridge.kicad_pcb` (also gitignored). The backups are good for recovering after a destructive edit — they're zipped snapshots of the project state. Don't commit them.

## Enclosure (enclosure/)

`enclosure/cw_bridge_enclosure.scad` is the parametric OpenSCAD box for this
board (109.6 × 85.6 × 42.6 mm; printed base with the LiPo under the board;
the top is a laser-cut 3 mm acrylic panel by default — `make_lid_panel.py`
writes `lid_panel.xcs` for xTool Studio (P2S) and `lid_panel.svg` — or a
printed lid with `lid_style = "printed"`). Port positions are derived from the
footprint placements in this file — if J1, J7/J8, J9, SW2 or SW3 move, update
the `*_x`/`*_y` values at the top of the .scad, re-export the STLs and re-run
`make_lid_panel.py` (`enclosure/README.md` has the commands; OpenSCAD is the
`openscad@snapshot` Homebrew cask).
The panel layout (hole positions in `oled_c`, `enc_c`, `btn_pos`, `led_pos`) is
copied from Jay's hand-edited `enclosure/lid_panel.xs` (xTool Studio), anchored
on the four corner screw holes; that .xs is the master for the acrylic sheet.
