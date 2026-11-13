# Sheet 05 — Mic Output (CD4051 #3 Demux + THAT1646 → 4× XLR Male)

## CD4051 #3 — Mic 1:4 Demux

In demux mode the signal enters at Z (common) and exits through the selected
X pin. The CD4051 switches are bidirectional — the same chip used for the audio
mux (sheets 03) works identically in reverse.

```
                    CD4051BE #3 (DIP-16)
                    ┌──────────────────────────────────────┐
                    │                                      │
INA128P out ───────►│ Z   (pin 14) — common input          │
                    │                                      │
                    │ X0  (pin 15) ──[100kΩ]── GND ───────►── Radio 1 mic signal
                    │ X1  (pin  4) ──[100kΩ]── GND ───────►── Radio 2 mic signal
                    │ X2  (pin  3) ──[100kΩ]── GND ───────►── Radio 3 mic signal
                    │ X3  (pin  7) ──[100kΩ]── GND ───────►── Radio 4 mic signal
                    │                                      │
                    │ X4, X5, X6, X7 ── NC (unused)       │
                    │                                      │
ESP32 GPIO6 ───────►│ A   (pin 11) — address bit 0        │  ← shared with CD4052
ESP32 GPIO7 ───────►│ B   (pin 10) — address bit 1        │  ← shared with CD4052
GND ───────────────►│ C   (pin  9) — tie LOW (4-channel)  │
GND ───────────────►│ INH (pin 12) — tie LOW (enabled)    │
                    │ VDD (pin 13) ── +3V3                 │
                    │ VSS (pin  8) ── GND                  │
                    │ VEE (pin 16) ── GND (single supply)  │
                    └──────────────────────────────────────┘

Address truth table (GPIO6 = A, GPIO7 = B) — same as CD4052 key routing:
  A=0, B=0 → X0 → Radio 1
  A=1, B=0 → X1 → Radio 2
  A=0, B=1 → X2 → Radio 3
  A=1, B=1 → X3 → Radio 4

The 100kΩ pull-downs on each output hold unselected THAT1646 inputs at GND,
preventing floating inputs from amplifying noise.
```

---

## THAT1646 Balanced Line Driver (×4, one per radio)

The THAT1646 converts the single-ended mic signal to a balanced differential
output suitable for an XLR line-level connection.

```
CD4051 #3 Xn output ───────────────────────────────►│ IN+ (pin 3)│
                                                     │            │
GND ────────────────────────────────────────────────►│ IN− (pin 4)│
(or connect through 22kΩ to GND for better balance)  │            │
                                                     │  THAT1646  │
                                            +5V ────►│ VCC (pin 8)│
                                            −5V ────►│ VEE (pin 5)│
                                            GND ────►│ GND (pin 2)│
                                                     │            │
                                                     │ OUT+ (pin 7)├──► XLR Pin 2 (hot)
                                                     │ OUT− (pin 6)├──► XLR Pin 3 (cold)
                                                     └────────────┘

THAT1646 DIP-8 pinout:
  Pin 1: NC
  Pin 2: GND
  Pin 3: IN+
  Pin 4: IN−
  Pin 5: VEE (negative supply)
  Pin 6: OUT−
  Pin 7: OUT+
  Pin 8: VCC (positive supply)

Supply: VCC = +5V, VEE = −5V (from ICL7660)
Output impedance: ~50Ω (each leg)
Output level: unity gain (0 dB), balanced
```

---

## 4× THAT1646 → Phantom Protection → 4× XLR Male (NC3MD-LX)

Each THAT1646 OUT+/OUT− goes through a series **47 µF / 63 V bipolar
electrolytic** (DC blocking) and a **5 V bidirectional TVS to GND**
(over-voltage clamp), then to the XLR pin. Both elements protect the chip
from accidental phantom power: if the user ever plugs one of these outputs
into a phantom-supplying mixer or interface, 48 V appears on the cable and
travels backward into the THAT1646 OUT pins (abs-max ±VCC + 0.3 V = ±5.3 V
on this design — instant chip death without protection).

```
THAT1646 #N OUT+ ──[C 47µF/63V bipolar]──┬──► XLR #N Pin 2 (hot)
                                          │
                                       [TVS SMAJ5.0CA]
                                          │
                                         GND

THAT1646 #N OUT− ──[C 47µF/63V bipolar]──┬──► XLR #N Pin 3 (cold)
                                          │
                                       [TVS SMAJ5.0CA]
                                          │
                                         GND

XLR #N Pin 1 ─────────────────────────── GND (chassis)

Repeat for N = 1, 2, 3, 4 (8 caps + 8 TVS total across the 4 outputs).
Label each XLR on the panel: "RADIO N MIC".
```

The bipolar caps are non-polarized — required because audio is AC and can
swing either way at the cap. 63 V rating clears the 48 V phantom potential
with margin. Frequency response: 47 µF into a typical 600 Ω mic input gives
a low-frequency corner at ~5 Hz — well below audio band, no impact on tone.

The TVS is a belt-and-suspenders backup. If a cap fails short (rare but
possible after thermal cycling), the TVS catches the surge at ±5 V before it
reaches the THAT1646. It also absorbs ESD events when XLR cables are
plugged/unplugged hot.

Panel placard recommended: **"DO NOT CONNECT TO PHANTOM-POWERED INPUTS."**

---

## TC7660H Supply for THAT1646

```
See Sheet 01 for the TC7660H circuit. Output rail summary:
  TC7660H VOUT ── −5V RAIL ──┬── THAT1646 #1 VEE (pin 5)
                              ├── THAT1646 #2 VEE (pin 5)
                              ├── THAT1646 #3 VEE (pin 5)
                              └── THAT1646 #4 VEE (pin 5)

  +5V RAIL ─────────────────┬── THAT1646 #1 VCC (pin 8)
                             ├── THAT1646 #2 VCC (pin 8)
                             ├── THAT1646 #3 VCC (pin 8)
                             └── THAT1646 #4 VCC (pin 8)

100nF bypass cap on each THAT1646 VCC pin to GND.
100nF bypass cap on each THAT1646 VEE pin to GND.
```

---

## Note on Radio Mic Impedance

Most HF radios have unbalanced dynamic microphone inputs expecting:
- Signal level: −50 to −20 dBu
- Impedance: 150Ω – 600Ω source (radio input is typically 600Ω to 10kΩ)
- Connection: XLR or proprietary connector with adapter

If the radio has an unbalanced mic input (pin 1 and pin 3 tied together at the
radio end), the balanced output from THAT1646 degrades gracefully — pin 2
becomes the signal, pin 3 and pin 1 connect to radio GND. No damage occurs.

The 47 µF/63 V bipolar caps already on both OUT+ and OUT− (see "Phantom
Protection" above) also block any DC bias on the radio mic line from
back-feeding into the THAT1646 — the same caps cover both threats. Note
that DC blocking caps must be **symmetric** on OUT+ and OUT−: the THAT1646
is a closed-loop balanced driver and asymmetric coupling defeats the
feedback loop and kills CMRR.
