# Sheet 06 — CW Key Routing + PTT + TX Inhibit

## CD4052BE — CW Key Routing (4-position dual mux)

The CD4052 is a dual 4:1 analog mux. Both sections share the same 2-bit address,
so Dit (Tip) and Dah (Ring) always route to the same radio simultaneously.

```
                    CD4052BE (DIP-16)
                    ┌─────────────────────────────────────┐
Key TRS Tip  ──────►│ INX (common A, pin 13)              │
                    │                                     │
                    │ X0 (pin 15) ──[100kΩ]── GND ───────►│── Radio 1 Key Tip (TRS Tip)
                    │ X1 (pin 14) ──[100kΩ]── GND ───────►│── Radio 2 Key Tip
                    │ X2 (pin 12) ──[100kΩ]── GND ───────►│── Radio 3 Key Tip
                    │ X3 (pin 11) ──[100kΩ]── GND ───────►│── Radio 4 Key Tip
                    │                                     │
Key TRS Ring ──────►│ INY (common B, pin  3)              │
                    │                                     │
                    │ Y0 (pin  1) ──[100kΩ]── GND ───────►│── Radio 1 Key Ring (TRS Ring)
                    │ Y1 (pin  5) ──[100kΩ]── GND ───────►│── Radio 2 Key Ring
                    │ Y2 (pin  2) ──[100kΩ]── GND ───────►│── Radio 3 Key Ring
                    │ Y3 (pin  4) ──[100kΩ]── GND ───────►│── Radio 4 Key Ring
                    │                                     │
ESP32 GPIO6 ───────►│ A  (pin  9) — address bit 0        │  ← shared with CD4051 #3
ESP32 GPIO7 ───────►│ B  (pin 10) — address bit 1        │  ← shared with CD4051 #3
GND ───────────────►│ INH (pin 6) — inhibit, active HIGH, tie LOW to always enable
                    │ VDD (pin 16) ── +3V3               │
                    │ VSS (pin  8) ── GND                │
                    │ VEE (pin  7) ── GND (single supply)│
                    └─────────────────────────────────────┘

Address truth table:
  A=0, B=0 → X0/Y0 → Radio 1
  A=1, B=0 → X1/Y1 → Radio 2
  A=0, B=1 → X2/Y2 → Radio 3
  A=1, B=1 → X3/Y3 → Radio 4

Key TRS Input Jack (3.5mm):
  Tip   = Dit (or signal for straight key)
  Ring  = Dah (for paddle; for straight key, may be NC or same as Tip)
  Sleeve = GND

Key TRS Output Jacks (×4, one per radio, 3.5mm):
  Tip   = Radio key Tip
  Ring  = Radio key Ring (or NC)
  Sleeve = GND (common)

Pull-downs (100kΩ to GND on each output):
  Prevents floating inputs on unselected radios' keyer inputs.
  Value is high enough not to load the CD4052 on the active path.

GPIO6 and GPIO7 are shared with CD4051 #3 (mic demux). This means the mic
and CW key always route to the same radio — correct behavior.
```

---

## PTT Foot Switch Input

```
3.5mm TS (mono) PTT Jack (panel mount):
  Tip    = PTT signal
  Sleeve = GND

Circuit:
+3V3 ──[R 10kΩ]──┬──────────────────────────────► ESP32 GPIO3 (INPUT_PULLUP)
                  │
                  ├──[C 100nF]── GND   (debounce)
                  │
              TRS Tip

When foot switch closes: Tip connects to GND via the switch, GPIO reads LOW.
The 10kΩ limits current when the switch closes. 100nF debounces the contact.
```

---

## 74HCT595N — PTT + TX Inhibit Shift Register

All 8 PTT and TX inhibit signals are driven by a single 74**HCT**595 8-bit
shift register. Three GPIO lines (DATA, CLK, LATCH) replace the 8 direct GPIO
lines that would otherwise be needed for 4× PTT + 4× TX inhibit.

> **HCT, not HC.** The 74HC595 has VIH(min) = 0.7 × VCC = 3.5 V at VCC = 5 V.
> ESP32-S3 GPIO drives only 3.3 V — below the threshold; the shift register
> latches unpredictably. **HCT** versions have TTL-compatible thresholds
> (VIH = 2.0 V), so 3.3 V drive is comfortably above the threshold. Same
> DIP-16 pinout, drop-in replacement.

```
                    74HCT595N (DIP-16)
                    ┌──────────────────────────────────────┐
ESP32 GPIO34 ──────►│ SER   (pin 14) — serial data in      │
ESP32 GPIO37 ──────►│ SRCLK (pin 11) — shift register clock│
ESP32 GPIO38 ──────►│ RCLK  (pin 12) — output latch clock  │
GND ───────────────►│ /OE   (pin 13) — output enable, tie LOW (always on)
+5V ───────────────►│ /SRCLR(pin 10) — clear, tie HIGH (clear disabled)
                    │ VCC   (pin 16) ── +5V                │
                    │ GND   (pin  8) ── GND                │
                    │ QH'   (pin  9) ── NC (no daisy-chain)│
                    │                                      │
                    │ QA (pin 15) ──[270Ω]──► PC817 #1 anode → PTT Radio 1
                    │ QB (pin  1) ──[270Ω]──► PC817 #2 anode → PTT Radio 2
                    │ QC (pin  2) ──[270Ω]──► PC817 #3 anode → PTT Radio 3
                    │ QD (pin  3) ──[270Ω]──► PC817 #4 anode → PTT Radio 4
                    │ QE (pin  4) ──[270Ω]──► PC817 #5 anode → TX INH Radio 1
                    │ QF (pin  5) ──[270Ω]──► PC817 #6 anode → TX INH Radio 2
                    │ QG (pin  6) ──[270Ω]──► PC817 #7 anode → TX INH Radio 3
                    │ QH (pin  7) ──[270Ω]──► PC817 #8 anode → TX INH Radio 4
                    └──────────────────────────────────────┘

Shift sequence: clock in 8 bits MSB-first via SER/SRCLK, then pulse RCLK
to latch all outputs simultaneously. This ensures no relay fires during the
shift — all outputs update at once on the RCLK rising edge.

Bit order shifted in (MSB = QH, LSB = QA):
  Bit 7 (first in)  → QH → TX INH Radio 4
  Bit 6             → QG → TX INH Radio 3
  Bit 5             → QF → TX INH Radio 2
  Bit 4             → QE → TX INH Radio 1
  Bit 3             → QD → PTT Radio 4
  Bit 2             → QC → PTT Radio 3
  Bit 1             → QB → PTT Radio 2
  Bit 0 (last in)   → QA → PTT Radio 1

Example: to assert PTT Radio 1 only, shift 0b00000001, then latch.
Example: to assert TX INH Radio 2, shift 0b00100000, then latch.
```

---

## PTT Output — One per Radio (PC817 Optocoupler)

Radio PTT input is typically an open-collector pull-to-ground signal.
The PC817 provides isolation between the 74HC595 output and the radio's PTT circuit.

```
PTT output for Radio N (repeat ×4):

74HCT595 Qn ──[R 270Ω]────────────────────────────►│ Anode  (pin 1)│
                                                    │  PC817        │
GND ──────────────────────────────────────────────── │ Cathode(pin 2)│
                                                    │               │
Radio PTT rail (from radio ACC) ──[R 10kΩ]──────────►│ Collector(pin 4)│──► Radio PTT input
GND ──────────────────────────────────────────────── │ Emitter (pin 3)│
                                                    └───────────────┘

When 74HCT595 output goes HIGH:
  - LED in PC817 turns on (270Ω limits to ~(5V−1.2V)/270Ω ≈ 14mA)
  - Phototransistor conducts (CTR ≥ 50% → IC ≥ 7 mA, comfortably driving radio PTT)
  - Radio PTT input is pulled to GND → radio transmits

The original 470 Ω gave only 8 mA LED current → ~4 mA collector at 50% CTR,
borderline for radios that pull 10–15 mA on PTT (some Yaesu/Icom). 270 Ω
restores margin. R = 270 Ω at 14 mA dissipates 53 mW — well within standard
1/4 W resistor rating.

74HC595 output → PC817 → Radio mapping:
  QA → PC817 #1 → Radio 1 PTT
  QB → PC817 #2 → Radio 2 PTT
  QC → PC817 #3 → Radio 3 PTT
  QD → PC817 #4 → Radio 4 PTT

Check your specific radio's PTT voltage. Most radios have 5–13V on the PTT line
pulled up internally via 10kΩ. The PC817 handles any PTT rail voltage.
```

---

## TX Inhibit Output — One per Radio (PC817 Optocoupler)

TX inhibit prevents the radio from transmitting during RF relay switching.
Connects to the radio's TX INH input on the ACC connector.

```
TX inhibit for Radio N (repeat ×4) — identical circuit to PTT:

74HCT595 Qn ──[R 270Ω]──►│ Anode  │
GND ──────────────────── │ Cathode│  PC817
                         │               │
Radio TX INH rail ──[R 10kΩ]──►│ Collector│──► Radio TX INH input (active LOW)
GND ──────────────────────────── │ Emitter │
                                 └─────────┘

When 74HCT595 output goes HIGH → PC817 conducts → TX INH pulled LOW → radio inhibited.

74HC595 output → PC817 → Radio mapping:
  QE → PC817 #5 → Radio 1 TX INH
  QF → PC817 #6 → Radio 2 TX INH
  QG → PC817 #7 → Radio 3 TX INH
  QH → PC817 #8 → Radio 4 TX INH

Radio TX INH connector locations:
  Kenwood TS-590/890: ACC2 connector, pin labeled "TX INH"
  Yaesu FT-991A/FTDX: BAND DATA / ACC connector
  Icom IC-7300/7610: ACC socket, "SEND" line
  Consult your specific radio manual for the correct pin.

IMPORTANT: TX inhibit must be asserted for ≥25ms BEFORE switching any RF relay,
and held until ≥15ms AFTER relays have settled. See firmware implementation notes.
```

---

## TX Inhibit Timing Diagram

```
Band change detected via CAT:

Time (ms):  0    5    10   15   20   25   30   35   40   45
            │    │    │    │    │    │    │    │    │    │
TX INH:  ───┼────┼───▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼──
               assert ↑ (radio now inhibited)           ↓ release
                                                        │
Relay switch: ───────────────────────►▼▼▼▼▼▼▼▼▼▼◄─────│──────
                                   switch         settle│
                                   relays         (10ms)│
                                   (5ms)                │
                                                  release TX INH

Total inhibit window: ~30ms per band change. Imperceptible in operation.
```
