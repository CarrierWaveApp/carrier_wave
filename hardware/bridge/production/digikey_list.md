# Parts to buy from Digikey / Mouser — CW Bridge rev 2.1 (JLC order 2026-09-28)

Quantities are for **5 boards**; add spares for the tiny SMD parts.
Digikey part numbers verified live and loaded into a guest cart on 2026-09-28 (Digikey Web ID 377190937, 10 lines; quantities bumped with spares 2026-09-28, ~$62.55 + shipping). Log in on that Chrome profile to keep the cart.
Everything below is either hand-soldered (not on the JLC BOM/CPL) or off-board.

## Hand-soldered on the main board

| Ref | Qty (5 bds) | Part | Package | Digikey / Mouser | Notes |
|---|---|---|---|---|---|
| U11 | 10 (5 + 5 spares) | **AP63301WU-7** (Diodes) 3 A adjustable buck — substitute for AP63200WU-7 | TSOT-23-6 | Digikey `31-AP63301WU-7CT-ND` ($0.69) | AP63200/63201/63203/63300 are all 0 stock at JLC *and* Digikey (32-week lead). AP63301 is pin-identical (FB EN VIN GND SW BST), 0.8 V ref, 500 kHz, 3.8–32 V, forced-PWM; works with the existing R22/R23 divider, L3 and C48/C49. **AP62200/AP62201 are NOT drop-ins** (pinout GND SW VIN FB EN BST). |
| J1 | 7 (5 + 2) | USB-A female, right-angle, THT | Molex 67643 land pattern | Molex 67643-0910, Digikey `WM4993-ND` ($1.76) | Same footprint as the JLC part AF 90 WJDG. Body overhangs the right edge. |
| J10 | 5 | JST PH 2-pin vertical, THT (battery) | B2B-PH-K-S | Digikey `455-1704-ND` | Removed from JLC placement 2026-09-28 along with J1; same part as the other 2-pin headers, so buy 35 total. Pin 1 (square) = VBAT +. |
| J15 | 7 (5 + 2) | JST PH 5-pin vertical, THT | B5B-PH-K-S | Digikey `455-1707-ND` ($0.25) | Encoder header. Pin 1 (square) = CLK. |
| J3, J12 | 12 (10 + 2) | JST PH 4-pin vertical, THT | B4B-PH-K-S | Digikey `455-1706-ND` ($0.17) | J3 pin 1 = GND, J12 pin 1 = +3V3. |
| J4, J5, J6, J11, J13, J14 | 40 in cart (30 + 5 for J10 + 5 spare) | JST PH 2-pin vertical, THT | B2B-PH-K-S | Digikey `455-1704-ND` ($0.10) | Pin 1 = signal, pin 2 = GND. |
| J7, J8 | 12 (10 + 2) | CUI/Same Sky SJ1-3515N 3.5 mm TRS jack | — | Digikey `CP1-3515N-ND` ($1.15) | LCSC 3.5 mm jacks are **not** footprint-compatible. |

## Mating connectors / cables (per board: 1× PHR-5, 2× PHR-4, 6× PHR-2, ~27 contacts)

| Qty (5 bds) | Part | Digikey | Notes |
|---|---|---|---|
| 10 | JST PHR-5 housing | `455-1163-ND` ($0.072 @10, cheaper than 7) | encoder lead |
| 12 | JST PHR-4 housing | `455-1164-ND` ($0.065) | OLED, panel LEDs |
| 40 | JST PHR-2 housing | `455-1165-ND` ($0.05) | buttons, RESET, BOOT, debug UART (+ battery if you re-terminate the cell) |
| 500 | JST SPH-002T-P0.5S crimp contact, 24–30 AWG | `455-1127-500-ND` ($0.037, 500-strip) | the 100-strip (`455-1127-100-ND`) was backordered; 500 is the smallest in-stock pack. Needs a PH-capable crimper (Engineer PA-09 or IWISS IWS-2820). Alternative if you don't want to crimp: pre-crimped PH leads (search "ASPHSPH24K152" PH-to-PH 150 mm, or Adafruit 4714-class single-ended leads). |

## Off-board / panel parts — Amazon cart built 2026-09-28 (16 items, $177.09, guest cart in Browser 1)

| Qty | Item | ASIN | Price | Notes |
|---|---|---|---|---|
| 1 (8 pcs) | WMYCONGCONG KY-040 rotary encoder module w/ knob | B07B68H6R8 | $12.99 | → J15. Module pin order CLK DT SW + GND matches J15 1–5. Module has 10 k pull-ups on CLK/DT. |
| 1 (5 pcs) | Hosyond 0.96" 128×64 I²C OLED SSD1306, white | B09T6SJBV5 | $14.99 | → J3. Check the module's pin order (GND VCC SCL SDA vs VCC GND) against J3 silk before wiring — vendors differ. |
| 3 (30 pcs) | Twidec 12 mm momentary pushbutton, pre-soldered leads, 5 colors | B08JHVZ8VV | $9.99 ea | → J4–J6, J13, J14 (5 per board). Leads crimp straight into PHR-2. |
| 1 (100 pcs) | Chanzon 5 mm LED assortment, 10 colors | B01AUI4VSI | $6.99 | → J12 via on-board R26–R28 (1 k). Plain LEDs, NOT the pre-wired 12 V kind (those carry a 12 V resistor and will be dim at 3.3 V). |
| 1 (100 pcs) | BOJACK 5 mm LED panel bezel holders, black | B09K755LGC | $6.99 | panel mount for the three LEDs |
| 1 (5 pcs) | TUOLNK U.FL (IPX/MHF1) → SMA female bulkhead pigtail, RG178, 30 cm | B098QH631G | $7.99 | U4 U.FL → case wall. Standard SMA (not RP). |
| 1 (4 pcs) + 1 (2 pcs) | Bingfu 2.4/5 GHz 3 dBi SMA **male** antenna | B09J8N8TXW, B09J8Q6TRN | $11.49 + $6.99 | 6 total, 5 + 1 spare |
| 5 | EEMB 3.7 V 1100 mAh LiPo, JST PH 2.0 plug, protection board | B08FD39Y5R | $11.28 ea | → J10. **Check polarity before plugging in**: J10 pin 1 (square pad, `+` silk) = VBAT+. LiPo PH plugs are not standardised; re-pin the housing if red is on pin 2. |
| 1 | iCrimp SN-2549 ratcheting crimper (JST PH/XH/ZH, Dupont) | B01N4L8QMW | $22.29 | for the 500 SPH-002T contacts |

## Still placed by JLC but worth noting

- All status LEDs (D4, D6–D10) were consolidated to **red** KT-0603R (C2286) to use one Basic part. Buy green/blue 0603 LEDs here if you want the original color coding back (D6/D9 green, D7/D10 blue, D4 yellow, D8 red).
- SW1 (Bourns PEC12R encoder) no longer exists on the board — the encoder lives on the KY-040 module.
