# CW Bridge — Audio Rework Placement Spec

Companion to commits `0dde6687` (symbol cache) and `8038f097` (pin-map docs).
All three new symbols are already in the schematic's `lib_symbols` block and
will appear in KiCad's **Add Symbol** dialog. This doc tells you exactly what
to place and wire.

Pre-existing ERC baseline before you start: **4 errors, 9 warnings** (see
`CLAUDE.md` § Verifying changes). Anything beyond those four errors is a
regression introduced during placement.

---

## 1. Suggested sheet layout

Existing components occupy roughly:

```
+----- (90,95) Power chain ─── (260,110) ─────────────────+
| J2, F2, D1, D2, U2, C2–C5                               |
|                                                         |
|   (134,163) J1 USB-A                                    |
|                          (208,168) XIAO                 |
|   (138,209) SW1 encoder                                 |
|   S1/S2/S3 buttons                       (306,196) Screen
|                                                         |
+---------------------------------------------------------+
```

Free regions for audio rework (all coords in mm, on 1.27 mm grid):

| Region | X range | Y range | Use |
|---|---|---|---|
| Lower-left | 85–115 | 235–280 | TRS jacks J3 + J4 |
| Lower-mid | 140–200 | 220–280 | Codec U3 + analog passives |
| Lower-right | 230–290 | 215–260 | I/O expander U4 + bypass caps |

Snap suggestions below are tab-stops, not commandments — move them as needed
to keep wires short and readable.

---

## 2. Components to place

### 2.1 J3 — Audio IN jack

| Field | Value |
|---|---|
| Symbol | `Connector_Audio:AudioJack2_Switch` |
| Reference | `J3` |
| Value | `PJ-320A` |
| Footprint | `Connector_Audio:Jack_3.5mm_PJ320A_Horizontal` |
| Suggested position | `(90, 240)` rotation 0 |

**Pin connections (AudioJack2_Switch is a 5-pin symbol):**

| Pin | Symbol name | Net |
|---|---|---|
| T (tip) | Audio Left in | `AUDIO_IN_L` |
| R (ring) | Audio Right in | `AUDIO_IN_R` |
| S (sleeve) | Ground | `GND` |
| Sw (switch contact) | Insertion detect | `~` (no-connect, leave open) |

### 2.2 J4 — Audio OUT jack

| Field | Value |
|---|---|
| Symbol | `Connector_Audio:AudioJack2_Switch` |
| Reference | `J4` |
| Value | `PJ-320A` |
| Footprint | `Connector_Audio:Jack_3.5mm_PJ320A_Horizontal` |
| Suggested position | `(90, 270)` rotation 0 |

| Pin | Net |
|---|---|
| T (tip) | `AUDIO_OUT_L` |
| R (ring) | `AUDIO_OUT_R` |
| S (sleeve) | `GND` |
| Sw | `~` |

### 2.3 U3 — ES8388 audio codec

| Field | Value |
|---|---|
| Symbol | `Audio:ES8388` |
| Reference | `U3` |
| Value | `ES8388` |
| Footprint | `Package_QFP:LQFP-28_7x7mm_P0.8mm` (verify against ES8388 datasheet rev — package may also be LQFP-28 5×5) |
| Suggested position | `(170, 245)` rotation 0 |

**Pin connections** (verify pin numbers against the datasheet — KiCad's `ES8388` symbol pin order should match, but always cross-check):

| Function | Net | Notes |
|---|---|---|
| `ASDOUT` | `I2S_DIN` | codec → ESP, ESP pin: GPIO3 |
| `DSDIN` | `I2S_DOUT` | ESP → codec, ESP pin: GPIO42 |
| `LRCK` | `I2S_LRCK` | ESP pin: GPIO40 |
| `BCLK` | `I2S_BCLK` | ESP pin: GPIO39 |
| `MCLK` | `I2S_MCLK` | ESP pin: GPIO43 |
| `CE` (chip enable / I²C addr bit) | `GND` | sets I²C addr to 0x10 |
| `SDA` | `I2C_SDA` | shared bus (GPIO5) |
| `SCL` | `I2C_SCL` | shared bus (GPIO6) |
| `~RESET~` | `CODEC_RST` | ESP pin: GPIO44 (active-low) |
| `LIN1` (or `MIC1P`) | `AIN_LIN_CAP_L` | through C-couple from J3 tip |
| `RIN1` (or `MIC2P`) | `AIN_LIN_CAP_R` | through C-couple from J3 ring |
| `LOUT1` (or `LHPOUT`) | `AOUT_HP_CAP_L` | through DC-block to J4 tip |
| `ROUT1` (or `RHPOUT`) | `AOUT_HP_CAP_R` | through DC-block to J4 ring |
| `AVDD`, `HPVDD`, `DVDD`, `PVDD` | `+3V3` | **separate decoupling each** — do not share caps |
| `AGND`, `DGND`, `HPGND` | `GND` | star-ground at codec |
| `VMID` / `VREF` | (codec ref bypass) | 10 µF to GND |
| `ROM` (if present) | per datasheet | typically GND |

### 2.4 U4 — PCAL6416A I/O expander

| Field | Value |
|---|---|
| Symbol | `Interface_Expansion:PCAL6416APW` |
| Reference | `U4` |
| Value | `PCAL6416APW` |
| Footprint | `Package_SO:TSSOP-24_4.4x7.8mm_P0.65mm` |
| Suggested position | `(255, 230)` rotation 0 |

**Pin connections** (per CLAUDE.md § PCAL6416A port assignment):

| PCAL6416A pin | Net | Origin |
|---|---|---|
| `P00` | `BTN1` | (S1 switch — existing label) |
| `P01` | `BTN2` | (S2 switch — existing label) |
| `P02` | `BTN3` | (S3 switch — existing label) |
| `P03` | `ENC_SW` | (SW1 encoder pushbutton — existing label) |
| `P04` | `SCR_DC` | (screen header — existing label) |
| `P05` | `SCR_RST` | (screen header — existing label) |
| `P06`–`P17` | leave open | spare; consider routing to a 0.1″ test header for future expansion |
| `~INT~` | `EXP_INT` | ESP pin: GPIO8 (open-drain — needs the pull-up below) |
| `ADDR` | `GND` | I²C address = 0x20 |
| `~RESET~` | `+3V3` (via 10 kΩ to +3V3) | tie high through R-RST |
| `SDA` | `I2C_SDA` | shared bus |
| `SCL` | `I2C_SCL` | shared bus |
| `VDD` | `+3V3` | with 0.1 µF decouple |
| `VSS` | `GND` | |

---

## 3. Passives bill

Add these as `Device:C` / `Device:R` instances near the relevant device.
All caps default to `0402` or `0603` size — match the existing project
preference.

### Codec U3 decoupling (place within 5 mm of each pin)

| Ref | Value | Net A | Net B | Purpose |
|---|---|---|---|---|
| C-AVDD | 0.1 µF | `+3V3` | `GND` | AVDD decouple |
| C-AVDD-bulk | 10 µF | `+3V3` | `GND` | AVDD bulk |
| C-HPVDD | 0.1 µF | `+3V3` | `GND` | HPVDD decouple |
| C-DVDD | 0.1 µF | `+3V3` | `GND` | DVDD decouple |
| C-PVDD | 0.1 µF | `+3V3` | `GND` | PVDD decouple (if present on ES8388) |
| C-VMID | 10 µF | VMID/VREF pin | `GND` | analog midrail bypass |
| C-VREF | 0.1 µF | VREF pin | `GND` | reference filter |

### Audio input AC-coupling (J3 → U3)

| Ref | Value | Net A | Net B | Purpose |
|---|---|---|---|---|
| C-AIN-L | 1 µF (non-polarized X7R) | `AUDIO_IN_L` | `AIN_LIN_CAP_L` | DC-block on left input |
| C-AIN-R | 1 µF (non-polarized X7R) | `AUDIO_IN_R` | `AIN_LIN_CAP_R` | DC-block on right input |
| R-AIN-L-pd | 47 kΩ | `AIN_LIN_CAP_L` | `GND` | pull-down to anchor bias |
| R-AIN-R-pd | 47 kΩ | `AIN_LIN_CAP_R` | `GND` | pull-down to anchor bias |

### Audio output anti-pop (U3 → J4)

| Ref | Value | Net A | Net B | Purpose |
|---|---|---|---|---|
| C-AOUT-L | 10 µF (electrolytic + ceramic // OK) | codec LOUT pin | `AOUT_HP_CAP_L` | DC-block + lowpass with load |
| C-AOUT-R | 10 µF | codec ROUT pin | `AOUT_HP_CAP_R` | DC-block + lowpass with load |
| R-AOUT-L | 47 Ω | `AOUT_HP_CAP_L` | `AUDIO_OUT_L` | output series R (headphone safe) |
| R-AOUT-R | 47 Ω | `AOUT_HP_CAP_R` | `AUDIO_OUT_R` | output series R |

> Note on series resistors: 47 Ω is conservative for 32 Ω headphones. Drop to
> 10 Ω if driving line-level inputs only (rig data ports). Keep at 47 Ω if
> users may plug in headphones directly.

### Expander U4 + I²C bus

| Ref | Value | Net A | Net B | Purpose |
|---|---|---|---|---|
| C-U4 | 0.1 µF | `+3V3` | `GND` | VDD decouple |
| R-SDA | 4.7 kΩ | `I2C_SDA` | `+3V3` | bus pull-up (single, not per device) |
| R-SCL | 4.7 kΩ | `I2C_SCL` | `+3V3` | bus pull-up |
| R-INT | 4.7 kΩ | `EXP_INT` | `+3V3` | open-drain pull-up to MCU |
| R-RST | 10 kΩ | `~RESET~` (U4) | `+3V3` | hold expander out of reset |

---

## 4. Global-label renames at the XIAO

The XIAO is at `(208.28, 168.91)`. Six pin nets need to be relabeled
**only on the XIAO side** — the other end of each net (button switch, screen
header, encoder) keeps the original name, and those will now reach the
PCAL6416A's IO0–IO5 instead of the XIAO directly.

Find each label near the XIAO body (Edit → Find may help; sort by Reference
designator next to the XIAO). The pairs are roughly:

| Existing label at XIAO | Replace with | Net's other end (don't touch) |
|---|---|---|
| `BTN1` (near pin 29 / GPIO39) | `I2S_BCLK` | `BTN1` at S1 → now wires to U4 P00 |
| `BTN2` (near pin 28 / GPIO42) | `I2S_DOUT` | `BTN2` at S2 → now wires to U4 P01 |
| `BTN3` (near pin 25 / GPIO40) | `I2S_LRCK` | `BTN3` at S3 → now wires to U4 P02 |
| `ENC_SW` (near pin 3 / GPIO3) | `I2S_DIN` | `ENC_SW` at SW1 → now wires to U4 P03 |
| `SCR_DC` (near pin 7 / GPIO43) | `I2S_MCLK` | `SCR_DC` at screen → now wires to U4 P04 |
| `SCR_RST` (near pin 8 / GPIO44) | `CODEC_RST` | `SCR_RST` at screen → now wires to U4 P05 |

**New label to add at XIAO pin 10 (GPIO8):** `EXP_INT` (was previously NC).

Don't rename labels near S1/S2/S3, SW1, or the screen header — they're the
"client side" of the moved nets and their names stay the same.

---

## 5. Placement order (recommended sequence to keep ERC clean)

1. **Place U4 (expander)** + its VDD decouple + reset pull-up + INT pull-up.
   Add `EXP_INT` global label at XIAO pin 10. Run ERC — should still be
   baseline 4/9 if the new labels match.
2. **Rename the 6 XIAO labels** as in §4. ERC will start showing
   `power_pin_not_driven` or `hierarchical_label_unconnected` for the new
   `I2S_*`/`CODEC_RST` nets — expected.
3. **Place U3 (codec)** + every decouple cap. Wire I²C, I²S, RESET. The
   `I2S_*` labels should now resolve. ERC errors above baseline should be
   only on the analog audio nets (still floating).
4. **Place J3 + J4** with the AC-couple + RC networks. ERC should return to
   baseline 4/9 (plus one new `lib_symbol_issues` warning if the schematic
   doesn't yet know about `Connector_Audio` and `Audio` libraries — clears
   when KiCad re-resolves on next save).
5. **Add I²C pull-ups** (`R-SDA`, `R-SCL`). If KiCad ERC was complaining
   about open-collector I²C pins, this clears it.

---

## 6. Validation

After every placement step, from `hardware/bridge/`:

```bash
# Parens balance (catches truncated/corrupted edits)
python3 -c "import sys; t=open('cw_bridge.kicad_sch').read(); d=0; s=False; e=False
for c in t:
  if e: e=False; continue
  if c=='\\\\': e=True; continue
  if c=='\"': s=not s; continue
  if not s:
    if c=='(': d+=1
    elif c==')': d-=1
print('depth:', d)"
# Expected: depth: 0

# ERC
/opt/homebrew/bin/kicad-cli sch erc cw_bridge.kicad_sch --format report -o /tmp/erc.txt
cat /tmp/erc.txt
```

**Expected final ERC at completion:**

- 4 errors (the baseline four, unchanged: J1 VBUS conflict + 3 power inputs)
- 9 pre-existing warnings (power symbol mismatches, `cw_bridge` lib_symbol_issues)
- Possibly 1–2 new `lib_symbol_issues` warnings for `Audio`, `Connector_Audio`,
  `Interface_Expansion` until KiCad re-resolves libraries on next save —
  these are cosmetic and clear themselves.

Anything else (new `power_pin_not_driven`, `pin_not_connected`,
`endpoint_off_grid`) is a real issue from the placement and needs to be
addressed before commit.

---

## 7. Rollback

Three revertable checkpoints exist:

| Commit | What's there |
|---|---|
| `7bef2acd` | Pre-rework baseline (just before symbol cache) |
| `0dde6687` | Symbol cache added |
| `8038f097` | CLAUDE.md pin map updated for rework |

To undo this whole rework: `git revert 8038f097 0dde6687 7bef2acd`
(in that order — newest first).
