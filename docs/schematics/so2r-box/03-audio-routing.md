# Sheet 03 — Audio Routing (Radio → Headphone)

## Overview

Each radio's audio output (3.5mm TRS) feeds into the box. CD4051 #1 selects
which radio feeds the Left headphone channel; CD4051 #2 selects the Right channel.
Each CD4051 is wired as a 4:1 mux (address pins A and B from ESP32 GPIOs;
C pin tied to GND to limit selection to X0–X3). No I2C — direct GPIO control.

---

## Virtual Ground (Audio Bias Rail)

The CD4051 runs on +3V3 single supply. Audio signals must be biased to VDD/2 = 1.65V
so they stay within the switch's signal range. A virtual ground (VGND) provides this.

```
+3V3 ──► TLE2426 IN (pin 8 of TO-92 / pin 1 of DIP)
GND ───► TLE2426 GND
       TLE2426 COMMON (mid-rail) ─┬───► VGND (1.65V, low-impedance)
                                  │
                              [C 100µF]── GND    (stiffening cap)
```

The TLE2426 is a tiny 3-terminal rail splitter (TO-92 or DIP-8), Z_out
typically ~7.5 Ω across the audio band. It replaces the original 22 kΩ
divider, which would have presented an 11 kΩ Thévenin source feeding four
22 kΩ AC-coupled inputs plus the headphone-buffer bias resistors — that
unbuffered scheme has ~450 mV DC droop and audible inter-channel crosstalk
because signal currents modulate VGND. ~$1 part, removes both problems.

One VGND rail shared by all audio input paths.

---

## Radio Audio Input (×4, identical circuit)

```
Radio N 3.5mm TRS Jack:
  Tip  (L/R audio) ──[C 10µF]──[R 10kΩ]──┬──► CD4051 Xn input
  Ring (if stereo)  ── NC (mono mix)       │
  Sleeve (GND)      ── Signal GND          │
                                        [22kΩ]
                                           │
                                         VGND (1.65V)

The 10kΩ + 22kΩ voltage divider and AC coupling cap form a high-pass filter
(fc ≈ 0.7 Hz) that shifts the signal to VGND midpoint.

Each Radio N input node tees to both CD4051 #1 (Left) and CD4051 #2 (Right)
simultaneously. The mux chip selection determines which radio is heard.
```

---

## CD4051 #1 — Audio Left Channel

```
                    CD4051BE #1 (DIP-16)
                    ┌──────────────────────────────────────┐
                    │                                      │
R1 audio bias ─────►│ X0 (pin 15)                         │
R2 audio bias ─────►│ X1 (pin  4)                         │
R3 audio bias ─────►│ X2 (pin  3)   Z (pin 14) ───────────►── to NJM4556 Left IN+
R4 audio bias ─────►│ X3 (pin  7)                         │
                    │                                      │
                    │ X4, X5, X6, X7 ── NC (unused)       │
                    │                                      │
ESP32 GPIO15 ──────►│ A   (pin 11) — address bit 0        │
ESP32 GPIO16 ──────►│ B   (pin 10) — address bit 1        │
GND ───────────────►│ C   (pin  9) — address bit 2, tied LOW → 4-channel mode
GND ───────────────►│ INH (pin 12) — inhibit, active HIGH, tie LOW to enable
                    │ VDD (pin 13) ── +3V3                 │
                    │ VSS (pin  8) ── GND                  │
                    │ VEE (pin 16) ── GND (single supply)  │
                    └──────────────────────────────────────┘

Address truth table (GPIO15 = A, GPIO16 = B):
  A=0, B=0 → X0 → Radio 1
  A=1, B=0 → X1 → Radio 2
  A=0, B=1 → X2 → Radio 3
  A=1, B=1 → X3 → Radio 4
```

---

## CD4051 #2 — Audio Right Channel

Identical topology to CD4051 #1. Same 4 radio audio input nodes (each tees from
the same AC-coupled bias network), independent address GPIOs for separate control.

```
                    CD4051BE #2 (DIP-16)
                    ┌──────────────────────────────────────┐
                    │                                      │
R1 audio bias ─────►│ X0 (pin 15)                         │
R2 audio bias ─────►│ X1 (pin  4)                         │
R3 audio bias ─────►│ X2 (pin  3)   Z (pin 14) ───────────►── to NJM4556 Right IN+
R4 audio bias ─────►│ X3 (pin  7)                         │
                    │                                      │
ESP32 GPIO45 ──────►│ A   (pin 11) — address bit 0        │
ESP32 GPIO46 ──────►│ B   (pin 10) — address bit 1        │
GND ───────────────►│ C   (pin  9) — tie LOW              │
GND ───────────────►│ INH (pin 12) — tie LOW (enabled)    │
                    │ VDD (pin 13) ── +3V3                 │
                    │ VSS (pin  8) ── GND                  │
                    │ VEE (pin 16) ── GND                  │
                    └──────────────────────────────────────┘

Address truth table (GPIO45 = A, GPIO46 = B):
  A=0, B=0 → X0 → Radio 1
  A=1, B=0 → X1 → Radio 2
  A=0, B=1 → X2 → Radio 3
  A=1, B=1 → X3 → Radio 4

Left and Right channels are independently selectable — SO2R split-ear operation
is achieved by writing different radio addresses to each chip simultaneously.
```

---

## NJM4556AD Headphone Output Buffer

The CD4051 Z output (via AC coupling cap) goes into a unity-gain op-amp buffer.
NJM4556AD is a dual op-amp rated 70 mA per output — actually capable of driving
32 Ω headphones directly, where the original MCP6002 (~6 mA usable at low THD)
clips and distorts at modest listening volumes.

```
CD4051 Z out ──[C 10µF]──┬──────────────────────────────►│IN+ (pin 3)│
                          │                               │           │
                         [100kΩ]── VGND (1.65V bias)     │ NJM4556AD │OUT (pin 1) ──► Volume pot
                                                         │           │
                                                ┌────────│IN− (pin 2)│
                                                │        └───────────┘
                                                └── OUT (feedback, unity gain)

NJM4556AD has two op-amp sections (DIP-8 footprint, drop-in for MCP6002):
  Section 1 (pins 1,2,3) → Left channel buffer
  Section 2 (pins 5,6,7) → Right channel buffer

NJM4556AD power:
  VDD (pin 8) ── +3V3
  VSS (pin 4) ── GND
```

---

## Volume Control + Headphone Jack

```
Left buffer OUT ──► Pot wiper 1 (Left track of stereo 10kΩ A-taper pot)
                    └── Pot wiper ──► [C 220µF/16V] ──► HP jack Tip (Left)

Right buffer OUT ──► Pot wiper 2 (Right track)
                     └── Pot wiper ──► [C 220µF/16V] ──► HP jack Ring (Right)

HP jack Sleeve ── GND

3.5mm TRS Headphone Jack:
  Tip   = Left channel
  Ring  = Right channel
  Sleeve = GND

The output AC coupling caps remove the 1.65V VGND DC offset so headphones
see a true audio signal referenced to GND. 220 µF + 32 Ω = 23 Hz HPF
(full bass response). The original 10 µF gave a 500 Hz HPF — bass gone.

The volume pot is an **A-taper** (audio/log) Bourns PTV09A-4025F-A103.
Linear taper would feel broken: barely audible across the bottom 75% of
rotation, suddenly loud at the top. A-taper produces an even loudness ramp.
```

---

## Audio Routing Modes (software configurable)

| Mode | CD4051 #1 Left | CD4051 #2 Right | Use case |
|------|----------------|-----------------|---------|
| SO2R split | R1 | R2 | Standard SO2R — each ear hears a different radio |
| Radio 1 mono | R1 | R1 | Focus on Radio 1 |
| Radio 2 mono | R2 | R2 | Focus on Radio 2 |
| Radio 3 mono | R3 | R3 | Focus on Radio 3 |
| Radio 4 mono | R4 | R4 | Focus on Radio 4 |
| Custom split | any | any | Any combination of radios per ear |
