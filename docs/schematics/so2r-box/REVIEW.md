# SO2R Box — Multi-Agent Design Review

Cross-disciplinary review of the SO2R box design on the
`claude/so2r-box-design-i5Bj6` branch. Reviewers: power/analog EE, digital EE,
RF/safety EE, parts sourcer, safety & test engineer.

**Verdict:** the architecture and the high-level partitioning (control box / RF
box, I2C extension, mux + demux for audio/mic/key, CAT bridge) are coherent.
The implementation has **8 hard blockers** that prevent the design from working
or risk damaging hardware. None require a rethink of the architecture; all are
fixable with parts swaps and a few topology changes. The realistic delivered
cost is **~$580**, not $297.

---

## Blockers (must fix before any power-on)

### B1. RF relay matrix topology is a short circuit at TX
**Files:** `10-rf-relay-matrix.md:21–48`, `wiring-rf-box.md:194–214`

All nine relay COMs are tied together at the radio's RF-IN bus. Each NC
contact is shunted to GND through 51 Ω/1 W. When relay K_n is energized:

- The other eight relays remain de-energized → eight NC paths to GND active
- 8 × 51 Ω in parallel = 6.4 Ω, in parallel with the selected 50 Ω BPF = **5.65 Ω load**
- VSWR 8.85:1 — radio protection trips or finals blow
- Power into the resistor bank ≈ 89 W → ~11 W per 1 W resistor → resistors detonate

The 50 Ω terminations belong on the **NO** side of the relay (the dead BPF
input stub) or on a single dead rail behind a master bypass relay — not on the
live RF-IN bus.

Additional issue: the BPF **outputs** are also bussed (`10-rf-relay-matrix.md:48`)
with no switching. Out-of-band BPF outputs present low impedance at adjacent
bands, so even after fixing the input matrix the antenna sees the selected BPF
in parallel with eight reactive stubs.

**Fix:** redesign as DPDT-per-band (input + output switched together), an SP9T
tree, or a series chain with bypass relays. Add a single 50 Ω termination on
the dead rail, not per-band shunts on the live bus.

### B2. ICL7660 charge pump cannot supply 4× THAT1646
**Files:** `01-power.md:58–80`, `05-mic-output.md:103–119`

THAT1646 quiescent ≈ 9 mA each → ~36 mA total. ICL7660CPA+ output is rated
20 mA max with ~55 Ω output impedance. At 36 mA load: V_drop ≈ 2 V, so VOUT
collapses to ~−3 V — below the THAT1646 −2.5 V minimum on cold start and under
audio peaks. The note "−5V is adequate" at `01-power.md:78` ignores load
current.

**Fix:** TC7660H (45 mA), LT1054 (100 mA), or a dedicated ±5 V module. Add
~$2 to BOM.

### B3. INA128 inputs have no DC return path
**Files:** `04-mic-input.md:22–37`, `wiring-control-box.md:524–536`

C3/C4 (10 µF) AC-couple the XLR pins straight to IN+/IN−. Nothing else is
connected to those nodes. Bias current (5 nA typ) charges the inputs to a rail
within minutes, asymmetrically — output rails out and stays there.

**Fix:** add 47 kΩ or 100 kΩ from each input to REF (= GND in the
single-supply scheme). Two resistors. Textbook IA biasing.

### B4. INA128 below minimum supply at +3V3
**File:** `04-mic-input.md:34–53`

TI INA128 datasheet specifies V_S ≥ ±2.25 V (4.5 V single-supply minimum).
+3.3 V single supply is out of spec; gain accuracy and offset are not
guaranteed. Output swing window is roughly 1.5–1.8 V — only ~300 mV usable.

**Fix:** switch to **INA333P** (DIP-8, V_S min 1.8 V, rail-to-rail-out, ~$5)
or commit to ±5 V supply for the IA from day one. INA333 is also the
sourcing-recommended part since INA128PA is NRND at TI.

### B5. Heltec V3 GPIO map likely conflicts with on-module PSRAM
**File:** `00-overview.md:34–74`

The plan uses GPIO 33, 34, 37, 38 for NeoPixel + 74HC595. On Heltec V3 boards
populated with PSRAM (most current production), GPIO 33–38 are routed to the
on-module PSRAM/Flash bus and are not safely usable as general I/O.
Additionally, GPIO 3, 45, 46 are ESP32-S3 strapping pins — driving them at
reset can change boot behavior.

**Fix:** buzz out GPIOs 33–38 against the actual Heltec V3 unit before
committing to a layout. If reserved, free up two pins (move CD4051 #2 address
lines onto MCP23017 spare outputs) or swap to a bare ESP32-S3-WROOM-1U-N16R8
that exposes the full GPIO bank.

### B6. 74HC595 at +5V VCC is incompatible with 3.3V GPIO
**File:** `06-key-ptt.md:86–105`

74HC595 at VCC = 5 V has VIH(min) = 0.7 × VCC = **3.5 V**. ESP32-S3 GPIO
drives 3.3 V max. The shift register may latch unpredictably (temperature- and
batch-dependent) — likely intermittent PTT/TX-INH glitches.

**Fix:** drop-in substitute **74HCT595N** (TTL thresholds, VIH = 2.0 V).
Same problem applies to WS2812B at 3.3 V data — make the 74AHCT125 level
shifter mandatory, not optional (`08-buttons-neopixel.md:34–35`).

### B7. KiCad netlist contradicts P82B96 pin numbering
**Files:** `so2r-box.net:604,799`, `wiring-control-box.md:202–215`,
`wiring-rf-box.md:99–122`

`U23 pin 3` is mapped to **both** the +3V3 net (line 604) and the SCL net
(line 799). KiCad ERC will reject this and the board cannot be fabricated as
specified. The pin numbering is wrong throughout — actual P82B96 SO-8/DIP-8
pinout is Sx(1), Rx(2), Tx(3), GND(4), Ty(5), Ly(6), Sy(7), VCC(8). The
wiring docs use invented "Sx2/Sy2" labels that don't match the datasheet.

**Fix:** rewrite the P82B96 wiring against NXP datasheet Fig. 2 ("Bus
expansion application"). Re-spec part as **P82B96PN** (DIP-8) — the BOM's
`P82B96D` suffix is SOIC-8.

### B8. Two safety gaps (cable surge, phantom power)

- **No surge / ESD protection on the I2C cable** between the two
  separately-grounded boxes (`02-i2c-uart-bus.md:32–64`). With 100 W coax
  leaving the same RF box and possibly 2-prong wall-warts, a lightning
  near-strike or AC fault destroys the P82B96 + MCP23017s. **Fix:** TVS array
  (e.g., SP0503BAHTG) at each cable end on SDA2/SCL2.
- **THAT1646 outputs unprotected against accidental phantom power**. The mic
  outputs are standard NC3MD-LX. A user patching one into a phantom-enabled
  mixer applies 48 V backward onto the THAT1646 output — instant chip death
  on all four channels. **Fix:** 47 µF/63 V bipolar caps on each XLR pin,
  bidirectional TVS or back-to-back 5.6 V zeners to GND, and a panel
  placard.

---

## Major issues (fix before contesting)

### Analog / audio

- **Virtual ground too soft** (`03-audio-routing.md:13–25`). 11 kΩ Thévenin
  source feeds 4× 22 kΩ AC-coupled inputs + two 100 kΩ MCP6002 bias resistors
  — DC droop ~450 mV and audible inter-channel crosstalk. Buffer with TLE2426
  or one half of an NJM4580.
- **MCP6002 cannot drive 32 Ω headphones** (`03-audio-routing.md:115–136`).
  ~6 mA usable at low THD vs. ~16 mA needed for comfortable listening. Replace
  with NJM4556AD (DIP-8 drop-in).
- **Headphone coupling caps undersized** (`wiring-control-box.md:82–83`). 10 µF
  into 32 Ω = 500 Hz HPF. Bump to 220–470 µF.
- **Audio path will clip on contest-level signals**
  (`03-audio-routing.md:29–45`). 2.4 V_pk source headroom vs. 3 V_pp typical
  HP-out at full volume — clips on negative peaks. Drop divider ratio for 6 dB
  more headroom.
- **THAT1646 OUT+ series cap note breaks symmetry**
  (`05-mic-output.md:135–137`). Closed-loop balanced driver — caps must be
  symmetric on OUT+ and OUT−. Rewrite the note.
- **Reference-designator clash** (`wiring-control-box.md:64,151`). R26/R27 are
  defined twice (VGND divider and audio bias). Renumber.

### RF / safety

- **Omron G2RL is a GP AC-mains relay, not characterized for HF**. ~44 dB
  isolation at 28 MHz — borderline for SO2R cross-band reception. Substitute
  Axicom IM03/IM43 or Omron G6Y/G6K-2P.
- **TX-INH timing too short and inconsistent**. 10 ms pre-switch
  (`10-rf-relay-matrix.md:101`) contradicts ≥25 ms in `06-key-ptt.md:189`.
  Yaesu/Icom envelope decay can be 20 ms+. Set ≥30 ms pre, ≥10 ms post; add
  hardware one-shot interlock so firmware *cannot* assert PTT during a
  band-change window.
- **BPF-8A mod has no mutual exclusion** (`11-bpf8a-mod.md:38–94`). Stuck I2C
  bit shorts two filters in parallel. Add a 74HC138 1-of-N decoder.
- **No hardware PTT timeout**. ESP32 hang with PTT bit latched = indefinite
  carrier. Add a 555 monostable (e.g., 30 s) on PTT, or repurpose the 74HC595
  /SRCLR (currently tied to +5 V) as a watchdog-driven kill line.

### Digital

- **PC817 PTT current marginal**. 470 Ω → 8 mA LED → ~4 mA collector at 50 %
  CTR. Some radios pull 10–15 mA. Drop to 270 Ω or specify PC817**XB**
  (CTR ≥ 130 %).
- **ULN2803A power-up state indeterminate**. MCP23017 boots with GPIOs as
  inputs (high-Z) → ULN2803A inputs float → relays may chatter for ~10–50 ms.
  Add 10 kΩ pull-downs on each ULN2803A input.
- **Heltec OLED unused**. The Heltec V3 has a built-in OLED on its own I2C
  bus — show band, active radio, PTT state. Zero hardware cost.
- **LoRa SX1262 not explicitly disabled**. Firmware must hold it in reset on
  boot or it may transmit at 868/915 MHz on power-up.

### Sourcing (May 2026 reality)

| Issue | Action |
|---|---|
| `PTV09A-4025F-B103` is **linear** taper (Bourns convention) | Order **`-A103`** for log audio taper |
| `UJ20-AF-3-SMT-TR` is mid-mount SMT, not panel-mount | Substitute GCT `USB4105-GF-A` |
| `54602-908LF` is PCB-mount RJ45, not panel | Substitute Neutrik NE8FDP or L-com ECF504-UAAS |
| `INA128PA` is NRND at TI, ~$12 in 2026 | Switch to `INA333P` (also fixes B4) |
| `THAT1646P14-U` is **DIP-8**, not DIP-14 as BOM states | Doc-only fix |
| `P82B96D` is SOIC-8 | Use **`P82B96PN`** for DIP-8 |
| Cheap CP2102N / CJMCU-752 modules often counterfeit | Source from LCSC/Adafruit/Sparkfun if reliability matters |
| BOM omits enclosures, hardware, PCB fab, shipping, tax | Add ~$180 to total |

**Realistic delivered cost: ~$580**, not $297.

---

## Minor / nice-to-have

- 1000 µF WS2812B bulk cap is oversized (4 LEDs, 50 mA max) — 100 µF is
  enough.
- WS2812B PWM noise (500 kHz – 5 MHz) sits next to the mic preamp; ferrite
  bead on +5 V LED supply recommended.
- Add 10 nF GPIO-to-GND on each panel button input for RF immunity.
- 3.5 mm TS jacks for radio audio in / PTT have poor shielding — clip-on
  ferrites on every panel jack.
- Add a 2 A polyfuse + SMAJ30A TVS at the +12 V barrel jack.
- Specify a 3-prong / earthed 12 V supply, or bond chassis to mains earth.
- DB9 RTS↔CTS loopback won't help Kenwood `PWRON` (DTR-driven).
- Drop the "Q0..Q7" alias for 74HC595 outputs in `00-overview.md:106–120` —
  the datasheet uses QA..QH only; the dual notation invites confusion.
- Heltec V3 build is point-to-point on perfboard with ~150 nets across ~50
  ICs — even a single-sided JLCPCB run (~$30) eliminates 90 % of build
  errors.
- Add a `12-bringup.md` checklist (supply ripple, I2C scan, UART loopback,
  audio sweep, click-test each band relay before connecting an antenna).

---

## What works (verified OK)

- Overall architecture: control-box / RF-box partitioning, I2C extension over
  Cat5e, mux + demux audio path, CAT bridge with three CP2102N + two
  SC16IS752 (+ Heltec native USB CDC) topology.
- I2C address map (no conflicts).
- I2C rise-time analysis: 4.7 kΩ pull-ups, ~40 pF bus → 159 ns rise time, well
  within Fast Mode 300 ns spec.
- ULN2803A current sourcing: 1 active relay per radio = 106 mA total, well
  within 1.5 A package limit; Vce(sat) leaves coils with 11.1 V — within G2RL
  spec.
- LM7805 thermal: ~0.1 W dissipation, no heatsink needed.
- 1N4148 flyback for G2RL coil (53 mA peak) — fine.
- ULN2803A internal flyback to +12 V bus — correct.
- SC16IS752 1.8432 MHz crystal frequency choice (zero baud-rate error).
- Bypass cap discipline (100 nF per IC) is explicit and adequate.
- Bit-order documentation in `00-overview.md` and `06-key-ptt.md` is
  consistent (just confusingly worded).
- MAX3232ECPE+ at 3.3 V is in spec (Vcc min = 3.0 V).
- SO-239 connectors are appropriate for HF 100 W.

---

## Recommended path forward

**Before any power-on:**

1. Redesign the RF matrix topology (B1).
2. Replace ICL7660 with TC7660H or LT1054 (B2).
3. Add 47 kΩ DC return paths on INA128 inputs (B3).
4. Swap INA128 → INA333 (B4 + sourcing).
5. Buzz out Heltec V3 GPIO 33–38 vs. PSRAM; pivot to bare ESP32-S3-WROOM-1U
   if reserved (B5).
6. Swap 74HC595 → 74HCT595, mandate 74AHCT125 ahead of WS2812B chain (B6).
7. Fix P82B96 pin numbering throughout netlist + wiring docs; re-spec to
   `P82B96PN` (B7).
8. Add cable TVS + phantom-power protection caps + zeners (B8).

**Before contest use:**

9. All "Major" items above. Add hardware PTT watchdog + band-change
   one-shot interlock.
10. Spec earthed 12 V supply, +12 V fuse, +12 V TVS.
11. Build a single-sided PCB (KiCad → JLCPCB) instead of perfboard.
12. Write a bring-up procedure with explicit test points.

**Pre-rev2 nice-to-haves:**

13. Hardware 1-of-N decoder for BPF-8A mod (74HC138).
14. Use the Heltec OLED for status display.
15. Switch to RF-characterized relays (Axicom IM43 or similar).
