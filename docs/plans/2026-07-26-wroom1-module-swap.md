# CW Bridge: replace XIAO ESP32-S3 module with SMT ESP32-S3-WROOM-1

**Date:** 2026-07-26
**Board:** `hardware/bridge/cw_bridge.kicad_{sch,pcb}`
**Decision inputs (user):** WROOM-1-N16R8 module · AP63xx buck for +3V3 · full schematic + PCB in one pass.

## Why / what changes

The XIAO (U4) is a self-contained board-on-board: it brought its own 3.3 V LDO
(sourcing the board's `+3V3` rail from XIAO pin 12), USB PHY exposure, flash,
crystal, antenna, and EN/boot buttons. Swapping to a **bare SMT WROOM-1 module**
means the carrier board must now provide:

1. **Its own +3V3 regulator** — WROOM `3V3` (pin 2) is a power *input*. New
   `AP63205WU` synchronous buck off the `+5V` mux rail feeds `+3V3`.
2. **EN reset circuitry** — 10 kΩ pull-up + 1 µF to GND, + optional RESET button.
3. **Boot strapping** — IO0 10 kΩ pull-up + BOOT button to GND.
4. **Module decoupling** — 10 µF bulk + 100 nF at the 3V3 pins.

The XIAO's former `+5V`→VBUS input goes away (module has no 5 V input); `+5V`
still feeds J1 USB-A host VBUS and now the buck's VIN.

### GPIO preservation (no net renames, firmware-neutral)

Every GPIO the schematic uses is broken out on WROOM-1-N16R8 (none in the
reserved 35/36/37 octal-PSRAM set), so all net names are preserved:

| Function | GPIO | WROOM-1 pin |
|---|---|---|
| ENC_CLK / ENC_DT | 1 / 2 | 39 / 38 |
| I2S_DIN / DOUT / BCLK / LRCK | 3 / 42 / 39 / 40 | 15 / 35 / 32 / 33 |
| I2S_MCLK | 43 | 37 (TXD0) |
| EXP_RST | 44 | 36 (RXD0) |
| SCR_CS / SCK / MOSI | 4 / 7 / 9 | 4 / 7 / 17 |
| I2C_SDA / SCL | 5 / 6 | 5 / 6 |
| EXP_INT | 8 | 12 |
| DEBUG_TX | 41 | 34 |
| USB_D- / D+ | 19 / 20 | 13 / 14 |
| +3V3 | — | 2 |
| GND | — | 1, 40, 41 (EP) |
| EN (new) | — | 3 |
| IO0 / BOOT (new) | — | 27 |

> **Firmware caveat (flagged, out of scope for this pass):** `firmware/src/main.rs`
> still uses Heltec V3.1-era GPIO numbers (gpio17/18/21/26/33/34/36/37/38/47/48
> + "Heltec V3.1 VBAT divider on GPIO1"). It was never migrated to the XIAO map,
> so the CLAUDE.md "lock-step" claim is already stale. This swap keeps the
> **schematic's** GPIO assignments; reconciling firmware is a separate task.

## New parts

| Ref | Part | LCSC | Notes |
|---|---|---|---|
| U4 | ESP32-S3-WROOM-1-N16R8 | C2913202 (verify) | replaces XIAO; 41-pad SMT, PCB antenna keepout |
| U11 | AP63205WU (cached) | (set LCSC) | 5V→3.3V sync buck, SOT-23-6 |
| L3 | ~3.3 µH power inductor | (pick JLC basic) | buck |
| C48/C49 | 22 µF / 22 µF | (JLC basic) | buck Vin / Vout bulk |
| C50 | 0.1 µF | | BST cap (SW↔BST) |
| C51/C52 | 10 µF / 0.1 µF | | WROOM 3V3 decoupling |
| C53 | 1 µF | | EN RC cap |
| R22/R23 | 100 k / 31.6 k | | buck FB divider → 3.33 V |
| R24 | 10 k | | EN pull-up |
| R25 | 10 k | | IO0 pull-up |
| SW4/SW5 | tactile SMD | | RESET (EN→GND) / BOOT (IO0→GND) |

FB: Vout = 0.8·(1+R22/R23) = 0.8·(1+100/31.6) = **3.33 V**. Externals finalized
from the AP63200/205 datasheet during implementation.

## Execution phases (checkpoint after Phase A)

**Phase A — Schematic** (electrical design; review gate here)
1. Instantiate WROOM-1 symbol (cache its lib_symbol inline from RF_Module).
2. Delete U4 XIAO instance + cached XIAO lib_symbol.
3. Place WROOM + global labels on every pin per the table above.
4. Add AP63205 buck subcircuit (U11 + L3 + C48-50 + R22/R23) : `+5V`→`+3V3`.
5. Add EN (R24/C53 + SW4) and BOOT (R25 + SW5) circuits; module decoupling C51/C52.
6. Re-point `+3V3` source: remove XIAO-as-source; buck now drives the rail.
7. Set LCSC on all new parts; ERC → **0 errors** baseline; kicad-happy sanity.

**Phase B — PCB**
8. Remove XIAO footprint + its tracks; add WROOM-1 + new-part footprints.
9. Place: WROOM in the old XIAO center pocket, antenna end to nearest board edge
   with keepout; buck cluster near the +5V/mux rail; buttons at front edge.
10. Route: USB diff pair (pins 13/14) → R15/R16 → U10, I2S/SPI/I2C, buck power
    loop, +3V3 distribution. Refill zones. DRC → 4-hole J9 baseline, 0 new.

**Phase C — Metadata & docs**
11. Re-run `jlcpcb_export.py`; verify BOM/CPL coverage.
12. Update this board's `CLAUDE.md` (pin table, power topology, placement).
13. Update root `CHANGELOG.md` under `[Unreleased]`.

## Verification gates
- Schematic: `kicad-cli sch erc` = 0 errors; paren-balance check = depth 0.
- PCB: `kicad-cli pcb drc --severity-error --severity-warning` = 4 hole_clearance, 0 warnings.
