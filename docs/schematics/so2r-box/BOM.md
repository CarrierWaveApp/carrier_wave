# SO2R Control Box — Bill of Materials

Simplified control-only revision. The RF / bandpass-filter switching matrix
and the BPF-8A modification are deferred to a later phase — see `REVIEW.md`
for the design review that motivated the split.

All review BLOCKERs are addressed in the parts choices below: INA128 →
INA333, ICL7660 → TC7660H, 74HC595 → 74HCT595, MCP6002 → NJM4556AD, 74AHCT125
added for WS2812B level translation, 47 kΩ INA333 input bias return,
phantom-power protection on XLR outputs, A-taper volume pot, TLE2426 buffered
VGND, 220 µF HP output coupling.

---

## Vendor strategy — two carts

| Vendor | What to order there |
|--------|---------------------|
| **DigiKey** | All ICs, Switchcraft / Neutrik / Amphenol / Bourns connectors, headers, TVS, bipolar electrolytics, precision passives |
| **Amazon**  | Heltec V3, USB-UART modules, breakout boards, WS2812B, illuminated buttons, panel USB-C, resistor / ceramic / electrolytic assortment kits |

Prices are May 2026 single-unit US estimates. Round up ~10% for cart-level
reality.

---

## Cost summary

| Section | Est. Cost |
|---------|-----------|
| DigiKey: Active devices | ~$44 |
| DigiKey: Connectors | ~$53 |
| DigiKey: Phantom protection (XLR-OUT) | ~$10 |
| DigiKey: Specific passives | ~$2 |
| **DigiKey subtotal** | **~$110** |
| Amazon: Modules + breakouts | ~$50 |
| Amazon: WS2812B, buttons, USB-C | ~$28 |
| Amazon: Passive assortment kits | ~$26 |
| **Amazon subtotal** | **~$95** |
| **Grand total (parts only)** | **~$225** |

---

## Cart 1 — DigiKey

### Active devices

| Qty | Mfr P/N | Description / role | Link | Unit | Ext |
|-----|---------|--------------------|------|------|-----|
| 3 | CD4051BE | 8:1 analog mux, DIP-16 | [search](https://www.digikey.com/en/products/search?keywords=CD4051BE) | $0.57 | $1.71 |
| 1 | CD4052BE | dual 4:1 analog mux, DIP-16 | [search](https://www.digikey.com/en/products/search?keywords=CD4052BE) | $0.63 | $0.63 |
| 1 | **SN74HCT595N** | shift register, **HCT** for 3.3 V→5 V drive | [search](https://www.digikey.com/en/products/search?keywords=SN74HCT595N) | $0.85 | $0.85 |
| 1 | **SN74AHCT125N** | quad buffer, level-shift to WS2812B (mandatory) | [search](https://www.digikey.com/en/products/search?keywords=SN74AHCT125N) | $0.65 | $0.65 |
| 1 | **NJM4556AD** | dual op-amp, 70 mA HP driver, DIP-8 | [search](https://www.digikey.com/en/products/search?keywords=NJM4556AD) | $1.50 | $1.50 |
| 1 | **INA333P** | instrumentation amp, 1.8–5.5 V supply, RR-out, DIP-8 | [search](https://www.digikey.com/en/products/search?keywords=INA333P) | $5.50 | $5.50 |
| 4 | THAT1646 (DIP-8) | balanced line driver — pick the `1646L08-U` / DIP-8 variant | [search](https://www.digikey.com/en/products/search?keywords=THAT1646) | $5.20 | $20.80 |
| 1 | **TC7660H** | charge pump, 45 mA, replaces ICL7660 | [search](https://www.digikey.com/en/products/search?keywords=TC7660HCPA) | $1.95 | $1.95 |
| 4 | MAX3232ECPE+ | RS-232 transceiver, DIP-16 | [search](https://www.digikey.com/en/products/search?keywords=MAX3232ECPE%2B) | $2.13 | $8.52 |
| 8 | LTV-817 | optocoupler, DIP-4 (PTT + TX-INH) | [search](https://www.digikey.com/en/products/search?keywords=LTV-817) | $0.23 | $1.84 |
| 1 | TLE2426CLP | rail splitter, buffered VGND, TO-92 | [search](https://www.digikey.com/en/products/search?keywords=TLE2426CLP) | $1.50 | $1.50 |

**Active subtotal: ~$44**

### Connectors and panel hardware

| Qty | Mfr P/N | Description / role | Link | Unit | Ext |
|-----|---------|--------------------|------|------|-----|
| 1 | NC3FD-LX | XLR female panel (J1, mic in) | [search](https://www.digikey.com/en/products/search?keywords=NC3FD-LX) | $3.50 | $3.50 |
| 4 | NC3MD-LX | XLR male panel (J2–J5, mic out) | [search](https://www.digikey.com/en/products/search?keywords=NC3MD-LX) | $3.60 | $14.40 |
| 4 | L77SDE09SOJ4F | DE-9F panel, solder cup (J6–J9, CAT) | [search](https://www.digikey.com/en/products/search?keywords=L77SDE09SOJ4F) | $1.55 | $6.20 |
| 6 | 35RAPC3BH4 | Switchcraft 3.5 mm TRS panel (J13 HP + J18 key in + J19–J22 key out) | [search](https://www.digikey.com/en/products/search?keywords=35RAPC3BH4) | $2.50 | $15.00 |
| 5 | 35RAPC2BH4 | Switchcraft 3.5 mm TS panel (J14–J17 audio in + J23 PTT) | [search](https://www.digikey.com/en/products/search?keywords=35RAPC2BH4) | $2.00 | $10.00 |
| 1 | **PTV09A-4025F-A103** | Bourns 10 kΩ stereo **log** (audio-taper) pot | [search](https://www.digikey.com/en/products/search?keywords=PTV09A-4025F-A103) | $2.75 | $2.75 |
| 8 | 0022232021 | Molex 2-pin header (J25–J32, PTT + TX-INH out) | [search](https://www.digikey.com/en/products/search?keywords=0022232021) | $0.25 | $2.00 |

**Connector subtotal: ~$54**

### Phantom-power protection on 4× XLR mic outputs

8 of each (one per pin 2 and pin 3 of the 4 mic outputs).

| Qty | Mfr P/N | Description / role | Link | Unit | Ext |
|-----|---------|--------------------|------|------|-----|
| 8 | UES1J470MEM | 47 µF / 63 V bipolar electrolytic, in-line on each XLR pin 2/3 | [search](https://www.digikey.com/en/products/search?keywords=UES1J470MEM) | $0.85 | $6.80 |
| 8 | SMAJ5.0CA | 5 V bidirectional TVS, pin-to-GND clamp | [search](https://www.digikey.com/en/products/search?keywords=SMAJ5.0CA) | $0.40 | $3.20 |

**Protection subtotal: ~$10**

### Specific passives that don't fit assortment kits

| Qty | Value | Description / role | Link | Unit | Ext |
|-----|-------|--------------------|------|------|-----|
| 2 | 220 µF / 16 V electrolytic | HP output coupling, fixes 500 Hz HPF | [search](https://www.digikey.com/en/products/search?keywords=UVR1C221MED) | $0.40 | $0.80 |
| 2 | 47 kΩ 1% metal film | INA333 input bias return to GND | [search](https://www.digikey.com/en/products/search?keywords=MFR-25FBF52-47K) | $0.10 | $0.20 |
| 2 | 10 µF / 25 V electrolytic | INA333 input AC coupling (C3, C4) | [search](https://www.digikey.com/en/products/search?keywords=UVR1E100MDD) | $0.30 | $0.60 |
| 1 | 100 µF / 16 V electrolytic | VGND stiffening at TLE2426 output | [search](https://www.digikey.com/en/products/search?keywords=UVR1C101MPD) | $0.30 | $0.30 |

**Passives subtotal: ~$2**

**DigiKey total before shipping/tax: ~$110**
With ~$8 USPS Ground + ~$15 tax: **~$133 out the door.**

---

## Cart 2 — Amazon

| Qty | Item | Search | Unit | Ext |
|-----|------|--------|------|-----|
| 1 | Heltec WiFi LoRa 32 V3 (ESP32-S3, USB-C) — confirm V3, not V2 | [search](https://www.amazon.com/s?k=Heltec+WiFi+LoRa+32+V3+ESP32-S3) | $13.00 | $13.00 |
| 3 | CP2102N USB-UART module (USB-C preferred) | [search](https://www.amazon.com/s?k=CP2102N+USB-C+UART+module) | $4.00 | $12.00 |
| 2 | SC16IS752 dual-UART I²C breakout (CJMCU-752) | [search](https://www.amazon.com/s?k=SC16IS752+CJMCU+breakout) | $8.00 | $16.00 |
| 1 | WS2812B 5 mm through-hole, 10-pack (use 4) | [search](https://www.amazon.com/s?k=WS2812B+5mm+through+hole) | $7.00 | $7.00 |
| 4 | 16 mm momentary push button, illuminated/translucent, panel-mount | [search](https://www.amazon.com/s?k=16mm+momentary+push+button+panel+illuminated) | $2.50 | $10.00 |
| 3 | USB-C panel-mount receptacle with nut + pigtail (true panel-mount, NOT mid-mount SMT) | [search](https://www.amazon.com/s?k=USB-C+panel+mount+receptacle+nut) | $3.50 | $10.50 |
| 1 | 1/4 W resistor assortment kit, 525-pc (300, 270, 4.7k, 5.1k, 10k, 22k, 100k all needed) | [search](https://www.amazon.com/s?k=1%2F4W+resistor+assortment+kit+525) | $8.00 | $8.00 |
| 1 | Ceramic cap assortment, X7R 50 V, 0.1 µF heavy | [search](https://www.amazon.com/s?k=ceramic+capacitor+assortment+50V+0.1uF) | $8.00 | $8.00 |
| 1 | Electrolytic cap assortment, 16/25/50 V mixed | [search](https://www.amazon.com/s?k=electrolytic+capacitor+assortment+kit) | $10.00 | $10.00 |

**Amazon subtotal: ~$95** (Prime ships free)

---

## Grand total (parts only): **~$225**

---

## Consumables to budget separately

Project-specific items I'm not pricing here — order whatever fits your shop.

- **Enclosure** for the control box (~200 × 150 × 50 mm).
  Hammond 1455 series, Bud HM, or repurposed 1U rack chassis.
- **PCB fabrication** — JLCPCB / OSH Park single-sided KiCad design.
  Strongly recommended over perfboard for ~150 nets across ~50 ICs.
- **Standoffs, M3 hardware, panel labels** (Brother PT label, printed vinyl,
  or laser-engraved).
- **Hookup wire** — 22 AWG stranded, several colors, or pre-stripped jumper
  assortment if going point-to-point.
- **Heat-shrink tubing** assortment.
- **Solder** (0.5 / 0.7 mm, leaded SAC or eutectic).
- **Flux pen / no-clean flux**.
- **Perfboard** (if no PCB) — 2× of the largest matrix board you can fit.
- **DIP sockets** (16-pin and 8-pin) — strongly recommended for hand-assembly
  debug.
- **Crimp ferrules** for power & jack pigtails.
- **Ferrite clip-on cores** (FT240-43 or similar) — at least 4× for panel
  jacks of concern.
- **Spare DE-9 hood/shells** if building CAT cables yourself.
- **Headphone splitter / TRS dongles** for testing audio paths.
- **DMM probes, scope probes** if not already on bench.

---

## Notes baked into this revision

### Parts that changed from the earlier BOM

| Original | Replaced with | Reason |
|----------|---------------|--------|
| INA128PA | INA333P | INA128 needs ≥4.5 V supply; design is 3.3 V single-supply. INA128PA also NRND at TI. |
| ICL7660CPA+ | TC7660H | ICL7660 maxes at 20 mA; 4× THAT1646 draws 36 mA → −5 V rail collapses. TC7660H rated 45 mA. |
| SN74HC595N | SN74HCT595N | HC at 5 V VCC has VIH = 3.5 V; ESP32-S3 outputs 3.3 V, below threshold. HCT has TTL thresholds. |
| MCP6002 | NJM4556AD | MCP6002 sources only ~6 mA at low THD; can't drive 32 Ω headphones cleanly. |
| 22 kΩ resistor divider for VGND | TLE2426 | Z_out too high; signal currents modulate VGND, audible crosstalk. |
| 10 µF / 16 V HP coupling | 220 µF / 16 V | 10 µF + 32 Ω = 500 Hz HPF (no bass). 220 µF + 32 Ω = 23 Hz HPF. |
| `…-B103` pot | `…-A103` pot | Bourns convention: B = linear, A = log/audio. Volume pots want audio taper. |
| (none) | 47 kΩ × 2 INA333 bias | Without DC return paths, bias current charges coupling caps and rails the IA output. |
| (none) | 74AHCT125 + DIP-14 | WS2812B requires 3.5 V VIH; ESP32 outputs 3.3 V — below threshold. Mandatory level shift. |
| (none) | 8× UES1J470MEM + 8× SMAJ5.0CA | Phantom-power protection on XLR outputs — without it, one accidental phantom-power patch destroys all 4 THAT1646s. |
| 470 Ω PC817 LED resistor | 270 Ω | 470 Ω → 8 mA LED → ~4 mA collector; borderline for radios pulling 10–15 mA on PTT. |
| 1000 µF WS2812B bulk | 100 µF | 1000 µF was wildly oversized for 4 LEDs (~50 mA peak). |

### Removed parts (deferred RF box)

- 18× Omron G2RL-1-E-CF DC12 ($82)
- 2× MCP23017-E/SP ($3)
- 3× ULN2803AN ($2)
- 1× L7805CV ($0.60)
- 1× 12 V wall adapter ($7)
- 4× SO-239 panel ($10)
- 18× BPF I/O connectors ($18)
- 18× 51 Ω 1 W resistors ($5)
- 2× P82B96D ($2.50)
- 2× RJ45 panel jacks ($3.25)
- 12 V passives + BPF-8A mod parts (~$13)
- All BPF-8A modification hardware (2N7000 ×9, 1N4148 ×9, etc.)

**Total removed: ~$145.**

### Sourcing landmines (already corrected here)

- **Pot taper.** `PTV09A-4025F-B103` is *linear*. The audio-taper version is
  `-A103`.
- **USB-C panel jacks.** `UJ20-AF-3-SMT-TR` (in the original BOM) is
  mid-mount SMT, not panel-mount. Panel-mount with retention nut on Amazon
  is fine.
- **Counterfeits.** Cheap CP2102N modules and CJMCU-752 SC16IS752 breakouts
  are often counterfeit — source from a vendor with returns if reliability
  is essential. LCSC, Adafruit, or Sparkfun are safer than no-name Amazon
  sellers.
- **THAT1646 package.** The earlier BOM listed `THAT1646P14-U` (DIP-14). The
  THAT 1646 is **DIP-8**; correct suffix is `1646L08-U`.
- **Heltec V3 PSRAM.** GPIO 33–38 are reserved on PSRAM-populated V3
  modules. Buzz them out before committing layout, or pivot to a bare
  ESP32-S3-WROOM-1U-N16R8 module.

### Optional Rg for INA333 (R10)

**Omit R10 for initial build.** Unity gain is correct for typical electret
mics. INA333 gain formula: G = 1 + (100,000 / Rg). Add R10 only if the mic
signal is too weak after testing:

- Rg = 100 kΩ → G ≈ 2 (6 dB)
- Rg = 22 kΩ → G ≈ 5.5 (15 dB) — usually too hot for electret
- Rg = 10 kΩ → G ≈ 11 (21 dB) — almost certainly too hot
