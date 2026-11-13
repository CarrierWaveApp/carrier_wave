# Sheet 01 — Power Distribution

The control box is fully USB-powered. The Heltec V3's USB-C jack supplies
+5 V, the Heltec's onboard LDO produces +3V3, and a **TC7660H** charge pump
generates −5 V for the four THAT1646 balanced line drivers.

There is no wall adapter, no +12 V rail, and no LM7805 — those belonged to
the (deferred) RF box.

## Rails Summary

| Rail | Source | Consumers |
|------|--------|-----------|
| +5V  | USB-C into Heltec | WS2812B VDD (via 74AHCT125 buffer), TC7660H VIN, 74HCT595 VCC, THAT1646 VCC ×4 |
| +3V3 | Heltec onboard LDO | All 3V3 logic + analog ICs |
| −5V  | TC7660H VOUT | THAT1646 VEE ×4 |

---

## Main Box Power Schematic

```
USB-C (from computer)
    │
    │ +5V (via Heltec USB-C input)
    │
    ├─────────────────────────────────────────────────── +5V RAIL
    │         │                │              │            │
 Heltec    WS2812B          TC7660H         74HCT595   THAT1646 ×4
 3V3 pin   (NeoPixels,      VIN             VCC        VCC
    │      via 74AHCT125)    │
    │                        TC7660H
    │                        VOUT
    │                          │
    │                       −5V RAIL ─── THAT1646 ×4 VEE
    │
    └─── +3V3 RAIL
              │
    ┌─────────┼─────────┬──────────┬──────────┬─────────┬──────────┐
    │         │         │          │          │         │          │
 CD4051    CD4051    CD4051    CD4052     SC16IS752  NJM4556    INA333P
 #1(VDD)   #2(VDD)   #3(VDD)   (VDD)      #1+#2 VCC  (VDD)      (V+)
    │         │         │          │          │         │          │
   GND       GND       GND        GND        GND       GND        GND
    │
    │  (also: MAX3232 ×4 VCC, 74AHCT125 VCC = +5V)
```

---

## TC7660H Charge Pump (−5V Generator)

The TC7660H replaces the original ICL7660CPA+. The CPA+ is rated only ~20 mA
output with ~55 Ω output impedance; four THAT1646 line drivers draw ~36 mA
combined and the original would have collapsed below the THAT1646 −2.5 V
minimum. The TC7660H is rated 45 mA with much lower R_out, drops into the
same DIP-8 socket, and uses the same external caps.

```
        +5V
         │
         ├──[C 10µF]── (pin 2: C1+, pin 4: C1−)
         │
    ┌────┴──────────────────────────────┐
    │  TC7660HCPA (DIP-8)               │
    │                                  │
+5V─►│ V+  (pin 8)    VOUT (pin 5) ───►├── −5V RAIL
GND─►│ GND (pin 3)                    │
    │ LV  (pin 6) ── GND (low-V mode) │
    │ OSC (pin 7) ── NC (float)        │
    │                                  │
    │ (pin 2: CAP+) ──[C 10µF]── (pin 4: CAP−)
    └──────────────────────────────────┘

VOUT ──[C 10µF]── GND   (output bypass)
VOUT ──[C 100nF]── GND  (HF bypass, ceramic)

Note: TC7660H with +5V input produces ≈ −4.7V at 36 mA load.
THAT1646 minimum VEE = −2.5V, so this is well within spec.
Tie LV (pin 6) to GND when V+ < +3.5V; safe to leave grounded for +5V supply.
```

---

## Bypass Capacitor Placement (all boards)

Place **one 100nF ceramic cap** between VCC/VDD and GND at every IC, as close
to the power pins as physically possible. No exceptions. THAT1646 needs one
cap on VCC and one on VEE.

Place **one 10µF electrolytic** near each power rail entry point to a board
section.

---

## Mixed-signal grounding

The TC7660H switches at ~10 kHz and injects switching ripple onto its VOUT
return path. Keep the TC7660H ground return separate from the audio
virtual-ground network and the INA333 REF return. Tie the analog and digital
grounds together at exactly one point — a star point at the Heltec's GND pin
or the +5 V entry node. Document this layout rule before any PCB work.
