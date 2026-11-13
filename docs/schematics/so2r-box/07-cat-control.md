# Sheet 07 — CAT Control (USB + RS-232)

See Sheet 02 for the full UART architecture. This sheet shows the physical wiring
for each component in detail.

---

## CP2102N Module Connections (×3, one per Radio 2/3/4)

```
                 CP2102N Pre-built Module
                 ┌──────────────────────────┐
Computer USB ───►│ USB connector            │
                 │                          │
                 │ TXD ─────────────────────►│── ESP32 RX GPIO (see table)
                 │ RXD ◄──────────────────── │── ESP32 TX GPIO
                 │ GND ─────────────────────►│── Main box GND
                 │ VCC (3.3V out) ── NC      │  (do NOT connect to ESP32 3V3)
                 └──────────────────────────┘

                   Add second USB-C connector on panel:
                   Panel USB-C ──[short wire/PCB trace]──► CP2102N USB pads

Module  │ Computer role  │ ESP32 RX │ ESP32 TX │ Panel label
--------|----------------|----------|----------|-------------
#1      │ Radio 2 CAT    │ GPIO43   │ GPIO44   │ "RADIO 2 CAT"
#2      │ Radio 3 CAT    │ GPIO1    │ GPIO2    │ "RADIO 3 CAT"
#3      │ Radio 4 CAT    │ GPIO4    │ GPIO5    │ "RADIO 4 CAT"

Heltec USB-C (built-in) = Radio 1 CAT ("RADIO 1 CAT" label on panel)
```

---

## USB-C Panel Connector Wiring (×3 new connectors)

```
USB-C receptacle (mid-mount on PCB, or panel mount):
  CC1 ──[R 5.1kΩ]── GND   (identifies as USB power sink, required for USB-C)
  CC2 ──[R 5.1kΩ]── GND
  D+  ──────────────────► CP2102N D+ pad
  D−  ──────────────────► CP2102N D− pad
  GND ──────────────────► GND
  VBUS── NC (CP2102N is bus-powered via its own USB connection)

ESD protection (optional but recommended):
  D+ and D− each through PRTR5V0U2X TVS diode to GND before CP2102N.
```

---

## SC16IS752 → MAX3232 Connection Detail

Repeated ×2 (one SC16IS752 serves two radios via its two UARTs):

```
SC16IS752 Breakout Board #1 (addr 0x4D):

  TXDA ──────────────────────────────────────► MAX3232 #1 T1IN (pin 11)
  RXDA ◄────────────────────────────────────── MAX3232 #1 R1OUT (pin 12)
  TXDB ──────────────────────────────────────► MAX3232 #2 T1IN (pin 11)
  RXDB ◄────────────────────────────────────── MAX3232 #2 R1OUT (pin 12)

SC16IS752 Breakout Board #2 (addr 0x4E):

  TXDA ──────────────────────────────────────► MAX3232 #3 T1IN (pin 11)
  RXDA ◄────────────────────────────────────── MAX3232 #3 R1OUT (pin 12)
  TXDB ──────────────────────────────────────► MAX3232 #4 T1IN (pin 11)
  RXDB ◄────────────────────────────────────── MAX3232 #4 R1OUT (pin 12)
```

---

## MAX3232 Full Schematic (×4, identical)

```
                    MAX3232ECPE (DIP-16)
                    ┌─────────────────────────────┐
                    │                             │
+3V3 ──────────────►│ VCC (pin 16)               │
GND ───────────────►│ GND (pin 15)               │
                    │                             │
SC16IS7xx UART TX ─►│ T1IN (pin 11)   T1OUT (p14)├──► DB9 pin 3 (TXD to radio)
SC16IS7xx UART RX ◄─│ R1OUT (pin 12)  R1IN  (p13)├◄── DB9 pin 2 (RXD from radio)
                    │                             │
                    │ C1+ (pin 1) ──[C 100nF]── C1− (pin 3)
                    │ C2+ (pin 4) ──[C 100nF]── C2− (pin 5)
                    │ V+  (pin 2) ──[C 100nF]──► GND  (charge pump output bypass)
                    │ V−  (pin 6) ──[C 100nF]──► GND  (charge pump output bypass)
                    │                             │
                    │ T2IN, T2OUT, R2IN, R2OUT: NC (second channel unused)
                    └─────────────────────────────┘

MAX3232 → Radio mapping:
  MAX3232 #1 → DB9 #1 → Radio 1 ACC (CAT serial)
  MAX3232 #2 → DB9 #2 → Radio 2 ACC
  MAX3232 #3 → DB9 #3 → Radio 3 ACC
  MAX3232 #4 → DB9 #4 → Radio 4 ACC
```

---

## DB9 Female Connector Wiring (×4, identical)

```
DB9 Female (panel mount, solder cup):

  Pin 2 (RXD) ──────────────────────────────► MAX3232 R1IN  (p13) — data from radio
  Pin 3 (TXD) ──────────────────────────────► MAX3232 T1OUT (p14) — data to radio
  Pin 5 (GND) ──────────────────────────────► GND
  Pin 7 (RTS) ──────[wire bridge]──────────── Pin 8 (CTS)  — loopback (no flow ctrl)
  Pin 1, 4, 6, 9: NC

The wire bridge (RTS→CTS loopback) satisfies radios that require RTS before
transmitting serial data. Most modern radios do not require hardware flow control
and work fine with this loopback. Check your radio's CAT documentation.

Label each connector: "RADIO 1 CAT", "RADIO 2 CAT", etc.
Use a DB9 null-modem cable or straight-through cable as appropriate for your radio.
Most radios with DE-9 (DB9) CAT ports use a straight-through cable (DTE-DCE).
```

---

## SC16IS752 Crystal Circuit

```
SC16IS752 Breakout typically has the crystal pre-installed.
If using bare IC:

               1.8432 MHz Crystal
XTAL1 (pin) ──┤             ├── XTAL2 (pin)
              │             │
           [C 22pF]      [C 22pF]
              │             │
             GND           GND

Crystal frequency 1.8432 MHz chosen to produce exact standard baud rates:
  1,843,200 / 16 / 12 = 9,600 baud  (no error)
  1,843,200 / 16 / 3  = 38,400 baud (no error)
```

---

## Firmware CAT Bridge Logic (pseudo-code reference)

```
// For each of the 4 radio channels (run as concurrent tasks):
task radio_cat_bridge(radio_n):
    loop:
        // Forward computer → radio
        if computer_uart[n].available():
            byte = computer_uart[n].read()
            radio_uart[n].write(byte)

            // Sniff PTT commands
            if matches_ptt_command(byte, radio_n):
                if is_transmit_command:
                    trigger_tx_inhibit(radio_n)  // wait, switch filter, release
                    activate_ptt(radio_n)
                else:
                    deactivate_ptt(radio_n)

            // Sniff frequency/band commands
            if matches_frequency_command(byte, radio_n):
                new_band = parse_band(byte)
                if new_band != current_band[n]:
                    switch_filter(radio_n, new_band)  // with TX inhibit interlock

        // Forward radio → computer
        if radio_uart[n].available():
            computer_uart[n].write(radio_uart[n].read())
```
