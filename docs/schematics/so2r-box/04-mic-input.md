# Sheet 04 — Microphone Input (XLR Female + INA333P Preamp)

## XLR Female Connector (NC3FD-LX) Pinout

```
XLR Female (panel mount, chassis side — wiring is from the jack's solder pins):
  Pin 1 (chassis/shield) ── GND (chassis ground)
  Pin 2 (hot / +)        ── signal input
  Pin 3 (cold / −)       ── signal input
```

Note: Electret mics contain a built-in capsule and preamp circuit with their own
internal bias supply. No phantom power is needed or applied at the XLR jack.

---

## INA333P Differential Preamp

The INA333 replaces the original INA128P. INA128 has a datasheet minimum
single-supply voltage of 4.5 V; this design runs at 3.3 V single supply, where
the INA128 is out of spec — gain accuracy and offset are not guaranteed and
the output swing window collapses to ~300 mV. The INA333 is rated 1.8 V to
5.5 V single supply with rail-to-rail output, gives nearly 3 V of usable
swing on +3V3, and is current production (the INA128PA is NRND at TI).

```
XLR Pin 2 ──[C3 10µF/25V]──┬───────────────────────────►│IN+ (pin 3)│
                            │                            │           │
                          [R44 47kΩ]                     │           │
                            │                            │           │
                           GND                           │           │
                                                         │           │
XLR Pin 3 ──[C4 10µF/25V]──┬───────────────────────────►│IN− (pin 2)│
                            │                            │           │
                          [R45 47kΩ]                     │           │
                            │                            │           │
                           GND                           │           │
                                                         │           │
                                                         │ RG−(pin 1)│
                                                         │     │     │
                                                      [Rg: see table]│
                                                         │     │     │
                                                         │ RG+(pin 8)│
                                                         │           │
                                            GND ────────►│ REF (pin 5)│
                                           +3V3 ─────────►│ V+  (pin 7)│
                                            GND ─────────►│ V−  (pin 4)│
                                                         │           │
                                                         │ OUT (pin 6)├──► to CD4051 #3 Z input
                                                         └───────────┘

INA333 gain formula:  G = 1 + (100,000 / Rg)  (Rg in ohms — note: differs from INA128)

Electret mic output levels are typically −30 to −10 dBu. Radio mic inputs
expect −50 to −20 dBu. Start at unity gain and add Rg only if the mic signal
is too weak.

Rg values for electret mics:
  Rg = open (pins 1 and 8 unconnected) → G = 1   (0 dB, unity — start here)
  Rg = 200 kΩ                          → G ≈ 1.5 (3 dB)
  Rg = 100 kΩ                          → G ≈ 2   (6 dB)
  Rg = 22 kΩ                           → G ≈ 5.5 (15 dB) — only if mic is weak
  Rg = 10 kΩ                           → G ≈ 11  (21 dB) — likely too hot

Start with Rg = open (omit R10 entirely). Add Rg only if signal is too weak.
Pin 4 (V−): Tie to GND for single-supply operation.
```

> **Bias return resistors are essential.** Without R44/R45, the INA333 input
> bias current (~200 pA typ) has no DC path and would gradually charge C3/C4
> until the IA inputs drift outside common-mode range and the output rails.
> 47 kΩ to GND gives the bias current a path home while still presenting a
> high impedance to the audio signal. This was missing from the original
> INA128 design and would have railed the part within minutes.

---

## INA333P Output to CD4051 #3

```
INA333 OUT (pin 6) ──────────────────────────────►│Z (common input)│
                                                   │   CD4051 #3    │

CD4051 #3 is used as a 1:4 DEMUX (opposite direction from audio mux).
Signal enters at Z and exits through whichever of X0–X3 is addressed.
Address lines A and B are shared with the CD4052 key mux (GPIO6, GPIO7),
so the mic always routes to the same radio as the CW key.

See Sheet 05 for the demux output connections.
```

---

## Complete Mic Input Summary

```
Electret Mic (XLR cable) ──► NC3FD-LX female connector
                                   │
             ┌─────────────────────┼─────────────────────┐
             │                     │                     │
          Pin 1                 Pin 2                 Pin 3
          GND               hot (+)               cold (−)
             │                     │                     │
            GND            [C3 10µF/25V]         [C4 10µF/25V]
                                   │                     │
                              ┬────┴───┐            ┬────┴───┐
                              │        │            │        │
                          INA333    R44 47k     INA333    R45 47k
                          IN+        │           IN−        │
                                    GND                    GND
                                   │
                        [Rg between pin 1 and pin 8 — omit for unity gain]
                                   │
                               INA333 OUT (pin 6)
                                   │
                            CD4051 #3 Z input
```
