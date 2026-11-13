# SO2R Box — Schematic Overview

8 sheets. Read in order — later sheets assume earlier ones.

| Sheet | File | Contents |
|-------|------|----------|
| 01 | 01-power.md | Power distribution (USB-powered, no wall adapter) |
| 02 | 02-i2c-uart-bus.md | I2C bus + UART routing architecture |
| 03 | 03-audio-routing.md | Radio audio → headphone (CD4051 4:1 mux + NJM4556) |
| 04 | 04-mic-input.md | XLR input (electret, no phantom), INA333P preamp |
| 05 | 05-mic-output.md | CD4051 #3 demux + THAT1646 → 4× XLR male outputs (with phantom-power protection) |
| 06 | 06-key-ptt.md | CW key routing (CD4052) + PTT + TX inhibit (74HCT595 + PC817) |
| 07 | 07-cat-control.md | USB CAT (CP2102N) + RS-232 to radios (SC16IS752 + MAX3232) |
| 08 | 08-buttons-neopixel.md | Illuminated buttons + WS2812B chain (with 74AHCT125 level shifter) |

> **RF / BPF deferred.** The bandpass-filter switching matrix and the BPF-8A
> modification (sheets 09–11 in earlier revisions) are deferred to a later
> phase. The PTT + TX-INH outputs are still presented on the panel as 2-pin
> headers for the future RF box. See `REVIEW.md` for the design review that
> motivated this split.

## Conventions Used in These Schematics

```
──[R 10k]──   Resistor
──[C 100n]──  Capacitor
──[D]──►──    Diode (current flows right)
──[L]──       Inductor / transformer
─────┬─────   Junction / node
     │
    GND        Ground symbol

IC pins shown as: PinName (pin#)
Power rails: +3V3, +5V, −5V, GND
```

## Heltec V3 Master GPIO Table

| GPIO | Direction | Function |
|------|-----------|----------|
| 1    | OUT       | UART1 TX → CP2102N #2 (Radio 3 computer CAT) |
| 2    | IN        | UART1 RX ← CP2102N #2 |
| 3    | IN        | PTT foot switch input (INPUT_PULLUP) |
| 4    | OUT       | UART2 TX → CP2102N #3 (Radio 4 computer CAT) |
| 5    | IN        | UART2 RX ← CP2102N #3 |
| 6    | OUT       | CD4052 A (key address bit 0) + CD4051 #3 A (mic address bit 0) — shared |
| 7    | OUT       | CD4052 B (key address bit 1) + CD4051 #3 B (mic address bit 1) — shared |
| 8    | —         | LoRa SX1262 NSS (Heltec internal — DO NOT USE) |
| 9    | —         | LoRa SCK (internal) |
| 10   | —         | LoRa MOSI (internal) |
| 11   | —         | LoRa MISO (internal) |
| 12   | —         | LoRa RST (internal) |
| 13   | —         | LoRa BUSY (internal) |
| 14   | —         | LoRa DIO1 (internal) |
| 15   | OUT       | CD4051 #1 (Audio L) address pin A |
| 16   | OUT       | CD4051 #1 (Audio L) address pin B |
| 17   | —         | OLED SDA (Heltec internal) |
| 18   | —         | OLED SCL (Heltec internal) |
| 19   | —         | USB D− (internal) |
| 20   | —         | USB D+ (internal) |
| 21   | I/O       | I2C SDA (shared bus: SC16IS752×2) |
| 33   | OUT       | WS2812B NeoPixel data out (via 74AHCT125 level shifter) |
| 34   | OUT       | 74HCT595 DATA (serial shift register in) |
| 35   | —         | PSRAM (internal — DO NOT USE) |
| 36   | —         | PSRAM (internal — DO NOT USE) |
| 37   | OUT       | 74HCT595 CLK (shift register clock) |
| 38   | OUT       | 74HCT595 LATCH (output register clock) |
| 39   | —         | spare |
| 40   | IN        | Button 1 input, Radio 1 (INPUT_PULLUP) |
| 41   | IN        | Button 2 input, Radio 2 (INPUT_PULLUP) |
| 42   | IN        | Button 3 input, Radio 3 (INPUT_PULLUP) |
| 43   | OUT       | UART0 TX → CP2102N #1 (Radio 2 computer CAT) |
| 44   | IN        | UART0 RX ← CP2102N #1 |
| 45   | OUT       | CD4051 #2 (Audio R) address pin A |
| 46   | OUT       | CD4051 #2 (Audio R) address pin B |
| 47   | I/O       | I2C SCL (shared bus) |
| 48   | IN        | Button 4 input, Radio 4 (INPUT_PULLUP) |

## I2C Device Address Map

| Address | Device | Function |
|---------|--------|----------|
| 0x4D    | SC16IS752 #1 | Radio 1 + Radio 2 RS-232 UART |
| 0x4E    | SC16IS752 #2 | Radio 3 + Radio 4 RS-232 UART |

> Future RF box (deferred): MCP23017 ×2 will appear at 0x20 / 0x21 over an
> I2C extension. Reserve those addresses.

## Heltec V3 GPIO sanity check (do this first)

The Heltec WiFi LoRa 32 V3 ships in two flavours: with and without on-module
PSRAM. Externally identical. On the PSRAM variant, **GPIO 33–37 are routed to
the on-module Octal-SPI bus** and are not safely usable as general I/O.

Before committing a layout: with the actual module unpowered, DMM-buzz GPIO
33, 34, 35, 36, 37, 38 against their header pads and against the on-module
flash/PSRAM chip. They should reach the headers with no continuity to
flash/PSRAM. If they don't, swap the Heltec V3 for a bare
**ESP32-S3-WROOM-1U-N16R8** module — full GPIO bank exposed, ~$5, but you
lose the on-module OLED and LoRa radio (neither of which this design uses).

## Audio/Mic/Key Mux GPIO Address Table

All three CD4051 chips and the CD4052 use direct GPIO address lines (no I2C).
CD4051 #3 and the CD4052 share the same address GPIOs so mic and key always
route to the same radio.

| GPIO A | GPIO B | CD4051 #1 (Audio L) | CD4051 #2 (Audio R) | CD4051 #3 (Mic) + CD4052 (Key) |
|--------|--------|---------------------|---------------------|--------------------------------|
| 15=0   | 16=0   | Radio 1             | —                   | —                              |
| 15=1   | 16=0   | Radio 2             | —                   | —                              |
| 15=0   | 16=1   | Radio 3             | —                   | —                              |
| 15=1   | 16=1   | Radio 4             | —                   | —                              |
| —      | —      | —                   | 45=0, 46=0 → R1     | —                              |
| —      | —      | —                   | 45=1, 46=0 → R2     | —                              |
| —      | —      | —                   | 45=0, 46=1 → R3     | —                              |
| —      | —      | —                   | 45=1, 46=1 → R4     | —                              |
| —      | —      | —                   | —                   | 6=0, 7=0 → Radio 1            |
| —      | —      | —                   | —                   | 6=1, 7=0 → Radio 2            |
| —      | —      | —                   | —                   | 6=0, 7=1 → Radio 3            |
| —      | —      | —                   | —                   | 6=1, 7=1 → Radio 4            |

## 74HC595 Shift Register Bit Map

PTT and TX inhibit are driven by a single 74HC595 (3 GPIO lines → 8 outputs).
Shift out MSB first (QH first): byte format = [TX4 TX3 TX2 TX1 PTT4 PTT3 PTT2 PTT1]

| Bit (shift order) | Output | Function |
|-------------------|--------|----------|
| QA (last in)      | Q0     | PTT Radio 1 → PC817 #1 |
| QB                | Q1     | PTT Radio 2 → PC817 #2 |
| QC                | Q2     | PTT Radio 3 → PC817 #3 |
| QD                | Q3     | PTT Radio 4 → PC817 #4 |
| QE                | Q4     | TX Inhibit Radio 1 → PC817 #5 |
| QF                | Q5     | TX Inhibit Radio 2 → PC817 #6 |
| QG                | Q6     | TX Inhibit Radio 3 → PC817 #7 |
| QH (first in)     | Q7     | TX Inhibit Radio 4 → PC817 #8 |
