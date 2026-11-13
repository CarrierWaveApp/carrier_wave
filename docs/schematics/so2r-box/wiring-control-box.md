# Control Box — Point-to-Point Wiring

## Reference Designators

| Ref | Part | Notes |
|-----|------|-------|
| U1 | Heltec WiFi LoRa 32 V3 | ESP32-S3 MCU |
| U2 | CD4051BE #1 | Audio Left 4:1 mux |
| U3 | CD4051BE #2 | Audio Right 4:1 mux |
| U4 | CD4051BE #3 | Mic 1:4 demux |
| U5 | CD4052BE | CW key dual 4:1 mux |
| U6 | SN74HCT595N | PTT / TX INH shift register (HCT for 3.3V→5V drive) |
| U7 | NJM4556AD | Dual op-amp 70mA headphone driver |
| U8 | INA333P | Mic instrumentation amp (3.3V single-supply, RR-out) |
| U9 | THAT1646 (DIP-8) #1 | Balanced line driver, Radio 1 mic |
| U10 | THAT1646 (DIP-8) #2 | Radio 2 mic |
| U11 | THAT1646 (DIP-8) #3 | Radio 3 mic |
| U12 | THAT1646 (DIP-8) #4 | Radio 4 mic |
| U13 | TC7660H | −5V charge pump (45 mA, replaces ICL7660CPA+) |
| U14 | MAX3232ECPE+ #1 | Radio 1 RS-232 |
| U15 | MAX3232ECPE+ #2 | Radio 2 RS-232 |
| U16 | MAX3232ECPE+ #3 | Radio 3 RS-232 |
| U17 | MAX3232ECPE+ #4 | Radio 4 RS-232 |
| U18 | SC16IS752 breakout #1 | Radio 1+2 UART (addr 0x4D) |
| U19 | SC16IS752 breakout #2 | Radio 3+4 UART (addr 0x4E) |
| U20 | CP2102N module #1 | Radio 2 computer USB-UART |
| U21 | CP2102N module #2 | Radio 3 computer USB-UART |
| U22 | CP2102N module #3 | Radio 4 computer USB-UART |
| U24 | SN74AHCT125N | Quad buffer, level-shift GPIO33 → WS2812B chain |
| OC1–OC4 | PC817 | PTT optocouplers, Radio 1–4 |
| OC5–OC8 | PC817 | TX INH optocouplers, Radio 1–4 |
| D1–D8 | SMAJ5.0CA | TVS, XLR-OUT phantom-power clamp (one per pin 2/3 of J2–J5) |
| LED1–LED4 | WS2812B | NeoPixel status LEDs |
| SW2–SW5 | 16mm momentary | Radio select buttons 1–4 |
| RV1 | Bourns PTV09A-4025F-A103 | 10 kΩ stereo **log** (audio-taper) volume |
| RS1 | TLE2426 | Rail splitter, buffered VGND |
| J1 | NC3FD-LX | XLR female mic input |
| J2–J5 | NC3MD-LX | XLR male mic out, Radio 1–4 (with phantom-power protection) |
| J6–J9 | DE-9F panel | RS-232 CAT, Radio 1–4 |
| J10–J12 | USB-C panel | CAT USB, Radio 2–4 |
| J13 | 3.5mm stereo | Headphone out |
| J14–J17 | 3.5mm TS (mono) | Radio audio in, Radio 1–4 |
| J18 | 3.5mm TRS | CW key in (paddle/straight key) |
| J19–J22 | 3.5mm TRS | CW key out, Radio 1–4 |
| J23 | 3.5mm TS (mono) | PTT foot switch in |
| J25–J28 | 2-pin header | PTT out to radio ACC, Radio 1–4 |
| J29–J32 | 2-pin header | TX INH out to radio ACC, Radio 1–4 |

> J24 (RJ45 panel jack to the RF box) is removed in this revision — the
> RF/BPF box is deferred. PTT and TX-INH headers J25–J32 still go directly to
> each radio's ACC connector and are also a usable interface for the future
> RF box.

**Resistors**

| Ref | Value | Purpose |
|-----|-------|---------|
| R1 | 300Ω | WS2812B data line (after 74AHCT125 output) |
| R2–R9 | 270Ω | PC817 LED anode current limit (OC1–OC8) — was 470Ω |
| R10 | open / Rg | INA333 gain (Rg) — leave open for unity gain on electret mics |
| R11 | 4.7kΩ | I2C SDA pull-up |
| R12 | 4.7kΩ | I2C SCL pull-up |
| R13–R14 | 5.1kΩ | J10 USB-C CC1, CC2 |
| R15–R16 | 5.1kΩ | J11 USB-C CC1, CC2 |
| R17–R18 | 5.1kΩ | J12 USB-C CC1, CC2 |
| R19–R22 | 10kΩ | Radio audio in series resistors (Radio 1–4) |
| R23 | 10kΩ | PTT foot switch pull-up |
| R26–R29 | 22kΩ | Audio bias pull-down to VGND (Radio 1–4) |
| R30–R33 | 100kΩ | CD4051 #3 mic output pull-downs (X0–X3) |
| R34–R37 | 100kΩ | CD4052 Dit output pull-downs (X0–X3) |
| R38–R41 | 100kΩ | CD4052 Dah output pull-downs (Y0–Y3) |
| R42 | 100kΩ | NJM4556 U7A IN+ bias to VGND |
| R43 | 100kΩ | NJM4556 U7B IN+ bias to VGND |
| R44 | 47kΩ 1% | INA333 IN+ DC return to GND (B3 fix) |
| R45 | 47kΩ 1% | INA333 IN− DC return to GND (B3 fix) |

> R24/R25 (the unbuffered 22 kΩ VGND divider) are removed — replaced by RS1
> (TLE2426 rail splitter). VGND is now the TLE2426 COMMON pin.

**Capacitors**

| Ref | Value | Purpose |
|-----|-------|---------|
| C1 | 100µF/16V | WS2812B bulk power (was 1000 µF, oversized) |
| C2 | 100µF/16V | VGND stiffening (at TLE2426 COMMON output) |
| C3 | 10µF/25V | INA333 IN+ coupling (XLR pin 2 → INA333 IN+) |
| C4 | 10µF/25V | INA333 IN− coupling (XLR pin 3 → INA333 IN−) |
| C5–C8 | 10µF/16V | Radio 1–4 audio input AC coupling |
| C9 | 10µF/16V | CD4051 #1 Z → NJM4556 coupling |
| C10 | 10µF/16V | CD4051 #2 Z → NJM4556 coupling |
| C11 | 220µF/16V | HP Left (pot wiper → J13) — was 10 µF, fixes 500 Hz HPF |
| C12 | 220µF/16V | HP Right (pot wiper → J13) |
| C13 | 10µF/16V | TC7660H C1 (pin 2 to pin 4) |
| C14 | 10µF/16V | TC7660H C2 (pin 5 bypass to GND) |
| C15 | 10µF/16V | TC7660H VOUT bypass |
| C16–C19 | 100nF | U2–U5 VDD bypass (CD4051×3, CD4052) |
| C22 | 100nF | U6 VCC bypass (74HCT595) |
| C23 | 100nF | U7 VDD bypass (NJM4556) |
| C24 | 100nF | U8 V+ bypass (INA333) |
| C25–C32 | 100nF | U9–U12 VCC+VEE bypass (THAT1646×4, 2 per chip) |
| C33 | 100nF | U13 V+ bypass (TC7660H) |
| C34–C37 | 100nF | U14–U17 VCC bypass (MAX3232×4) |
| C38–C53 | 100nF | U14–U17 charge pump caps (C1+/C1−/V+/V−, 4 per chip) |
| C54 | 100nF | U18, U19 SC16IS752 breakout VCC bypass |
| C55 | 100nF | PTT debounce (J23 tip to GND) |
| C56–C63 | 47µF/63V bipolar | XLR-OUT phantom-power blocking (one per pin 2/3 of J2–J5) |
| C64 | 100nF | U24 VCC bypass (74AHCT125) |

---

## Wiring by Net

Each net lists every pin that must be connected together.
Wire each net as a star or daisy-chain — keep audio signal wires short.

---

### PWR: +5V

| Point | Location |
|-------|----------|
| U1 5V pin | Heltec V3 regulated output |
| U6 VCC (pin 16) | 74HCT595N power |
| U9–U12 VCC (pin 8) | THAT1646 ×4 positive supply |
| U13 VIN (pin 8) | TC7660H input |
| C1 (+) | WS2812B bulk cap positive |
| LED1–LED4 VDD | WS2812B power |

### PWR: +3V3

| Point | Location |
|-------|----------|
| U1 3V3 pin | Heltec V3 3.3V output |
| U2 VDD (pin 13) | CD4051 #1 |
| U3 VDD (pin 13) | CD4051 #2 |
| U4 VDD (pin 13) | CD4051 #3 |
| U5 VDD (pin 16) | CD4052 |
| U7 VDD (pin 8) | NJM4556 |
| U8 VS+ (pin 7) | INA333P positive supply |
| U14–U17 VCC (pin 16) | MAX3232 ×4 |
| U18 VCC | SC16IS752 breakout #1 |
| U19 VCC | SC16IS752 breakout #2 |
| R11 one end | I2C SDA pull-up |
| R12 one end | I2C SCL pull-up |

### PWR: −5V

| Point | Location |
|-------|----------|
| U13 VOUT (pin 5) | TC7660H negative output |
| U9–U12 VEE (pin 5) | THAT1646 ×4 negative supply |
| C17 (−) | TC7660H VOUT bypass cap negative |

### PWR: VGND (1.65V virtual ground, buffered)

| Point | Location |
|-------|----------|
| RS1 COMMON | TLE2426 mid-rail output |
| C2 (+) | 100µF stiffening cap positive |
| R26–R29 one end each | Audio bias pull-downs to VGND |
| R42 one end | NJM4556 U7A IN+ bias to VGND |
| R43 one end | NJM4556 U7B IN+ bias to VGND |

> RS1 (TLE2426) connections: +3V3 → IN, GND → GND, COMMON → VGND node.
> C2 100µF from VGND to GND at the same node. The original R24/R25 resistive
> divider is removed (Z_out too high; modulated by signal currents).

### PWR: GND

| Point | Location |
|-------|----------|
| U1 GND | Heltec V3 |
| U2 VSS (pin 8), VEE (pin 16) | CD4051 #1 |
| U3 VSS (pin 8), VEE (pin 16) | CD4051 #2 |
| U4 VSS (pin 8), VEE (pin 16) | CD4051 #3 |
| U5 VSS (pin 8), VEE (pin 7) | CD4052 |
| U6 GND (pin 8) | 74HCT595N |
| U7 VSS (pin 4) | NJM4556 |
| U8 VS− (pin 4) | INA333P — tie to GND (single supply) |
| U8 REF (pin 5) | INA333P reference — tie to GND |
| U9–U12 GND (pin 2) | THAT1646 ×4 |
| U13 GND (pin 4) | TC7660H |
| U14–U17 GND (pin 15) | MAX3232 ×4 |
| U18 GND | SC16IS752 breakout #1 |
| U19 GND | SC16IS752 breakout #2 |
| U20–U22 GND | CP2102N modules ×3 |
| U24 GND (pin 7) | 74AHCT125 |
| R44 other end | INA333 IN+ DC return (B3) |
| R45 other end | INA333 IN− DC return (B3) |
| D1–D8 GND end | XLR-OUT TVS clamps |
| OC1–OC8 cathode (pin 2) | All PC817 LED cathodes |
| OC1–OC8 emitter (pin 3) | All PC817 phototransistor emitters |
| J1 pin 1 | XLR female chassis/shield |
| J2–J5 pin 1 | XLR male chassis ×4 |
| J6–J9 pin 5 | DE-9 GND ×4 |
| J10–J12 GND | USB-C CC adapter GND ×3 |
| J13 sleeve | Headphone jack GND |
| J14–J22 sleeve | All 3.5mm jacks GND |
| J23 sleeve | PTT jack GND |
| RS1 GND | TLE2426 ground pin |
| R26–R29 bottom | Audio bias to VGND (via TLE2426; not to GND directly) |
| R32–R43 bottom | All 100kΩ pull-downs to GND |
| C1–C17 (−) | All electrolytic negatives |
| C18–C64 one end | All 100nF bypass caps to GND |
| SW2–SW5 COM | Button COM terminals |

---

### SIG: SDA

| Point | Location |
|-------|----------|
| U1 GPIO21 | ESP32-S3 |
| U18 SDA | SC16IS752 breakout #1 |
| U19 SDA | SC16IS752 breakout #2 |
| R11 other end | 4.7kΩ pull-up to +3V3 |

### SIG: SCL

| Point | Location |
|-------|----------|
| U1 GPIO47 | ESP32-S3 |
| U18 SCL | SC16IS752 breakout #1 |
| U19 SCL | SC16IS752 breakout #2 |
| R12 other end | 4.7kΩ pull-up to +3V3 |

---

### SIG: UART0_TX (Radio 2 computer side → radio)

| Point | Location |
|-------|----------|
| U1 GPIO44 | ESP32-S3 UART0 TX |
| U20 RXD | CP2102N #1 receive |

### SIG: UART0_RX

| Point | Location |
|-------|----------|
| U1 GPIO43 | ESP32-S3 UART0 RX |
| U20 TXD | CP2102N #1 transmit |

### SIG: UART1_TX (Radio 3)

| Point | Location |
|-------|----------|
| U1 GPIO2 | ESP32-S3 |
| U21 RXD | CP2102N #2 |

### SIG: UART1_RX

| Point | Location |
|-------|----------|
| U1 GPIO1 | ESP32-S3 |
| U21 TXD | CP2102N #2 |

### SIG: UART2_TX (Radio 4)

| Point | Location |
|-------|----------|
| U1 GPIO5 | ESP32-S3 |
| U22 RXD | CP2102N #3 |

### SIG: UART2_RX

| Point | Location |
|-------|----------|
| U1 GPIO4 | ESP32-S3 |
| U22 TXD | CP2102N #3 |

### SIG: SC16IS_RADIO1_TX (ESP32 CDC → SC16IS → Radio 1 ACC)

| Point | Location |
|-------|----------|
| U18 TXDA | SC16IS752 #1 UART A transmit |
| U14 T1IN (pin 11) | MAX3232 #1 TTL input |

### SIG: SC16IS_RADIO1_RX

| Point | Location |
|-------|----------|
| U18 RXDA | SC16IS752 #1 UART A receive |
| U14 R1OUT (pin 12) | MAX3232 #1 TTL output |

### SIG: SC16IS_RADIO2_TX

| Point | Location |
|-------|----------|
| U18 TXDB | SC16IS752 #1 UART B |
| U15 T1IN (pin 11) | MAX3232 #2 |

### SIG: SC16IS_RADIO2_RX

| Point | Location |
|-------|----------|
| U18 RXDB | SC16IS752 #1 UART B |
| U15 R1OUT (pin 12) | MAX3232 #2 |

### SIG: SC16IS_RADIO3_TX

| Point | Location |
|-------|----------|
| U19 TXDA | SC16IS752 #2 UART A |
| U16 T1IN (pin 11) | MAX3232 #3 |

### SIG: SC16IS_RADIO3_RX

| Point | Location |
|-------|----------|
| U19 RXDA | SC16IS752 #2 UART A |
| U16 R1OUT (pin 12) | MAX3232 #3 |

### SIG: SC16IS_RADIO4_TX

| Point | Location |
|-------|----------|
| U19 TXDB | SC16IS752 #2 UART B |
| U17 T1IN (pin 11) | MAX3232 #4 |

### SIG: SC16IS_RADIO4_RX

| Point | Location |
|-------|----------|
| U19 RXDB | SC16IS752 #2 UART B |
| U17 R1OUT (pin 12) | MAX3232 #4 |

### SIG: RS232_R1_TX (to Radio 1 DE-9)

| Point | Location |
|-------|----------|
| U14 T1OUT (pin 14) | MAX3232 #1 RS-232 output |
| J6 pin 3 | DE-9F Radio 1, TXD |

### SIG: RS232_R1_RX

| Point | Location |
|-------|----------|
| U14 R1IN (pin 13) | MAX3232 #1 RS-232 input |
| J6 pin 2 | DE-9F Radio 1, RXD |

> Repeat RS232_R2/R3/R4 identically: U15→J7, U16→J8, U17→J9.
> Wire J6–J9 pin 7 (RTS) to pin 8 (CTS) with a short jumper wire on each connector.

---

### SIG: AUDIO_L_SEL_A

| Point | Location |
|-------|----------|
| U1 GPIO15 | ESP32-S3 |
| U2 A (pin 11) | CD4051 #1 address bit 0 |

### SIG: AUDIO_L_SEL_B

| Point | Location |
|-------|----------|
| U1 GPIO16 | ESP32-S3 |
| U2 B (pin 10) | CD4051 #1 address bit 1 |

### SIG: AUDIO_R_SEL_A

| Point | Location |
|-------|----------|
| U1 GPIO45 | ESP32-S3 |
| U3 A (pin 11) | CD4051 #2 address bit 0 |

### SIG: AUDIO_R_SEL_B

| Point | Location |
|-------|----------|
| U1 GPIO46 | ESP32-S3 |
| U3 B (pin 10) | CD4051 #2 address bit 1 |

### SIG: MIC_KEY_SEL_A (shared CD4051 #3 + CD4052)

| Point | Location |
|-------|----------|
| U1 GPIO6 | ESP32-S3 |
| U4 A (pin 11) | CD4051 #3 address bit 0 |
| U5 A (pin 9) | CD4052 address bit 0 |

### SIG: MIC_KEY_SEL_B

| Point | Location |
|-------|----------|
| U1 GPIO7 | ESP32-S3 |
| U4 B (pin 10) | CD4051 #3 address bit 1 |
| U5 B (pin 10) | CD4052 address bit 1 |

---

### SIG: SR_DATA

| Point | Location |
|-------|----------|
| U1 GPIO34 | ESP32-S3 |
| U6 SER (pin 14) | 74HCT595N serial data |

### SIG: SR_CLK

| Point | Location |
|-------|----------|
| U1 GPIO37 | ESP32-S3 |
| U6 SRCLK (pin 11) | 74HCT595N shift clock |

### SIG: SR_LATCH

| Point | Location |
|-------|----------|
| U1 GPIO38 | ESP32-S3 |
| U6 RCLK (pin 12) | 74HCT595N output latch clock |

> U6 /OE (pin 13) → GND (always enabled)
> U6 /SRCLR (pin 10) → +5V (clear disabled)

### SIG: NEOPIXEL_DATA (via 74AHCT125 level shift)

| Point | Location |
|-------|----------|
| U1 GPIO33 | ESP32-S3 (3.3V output) |
| U24 1A (pin 2) | 74AHCT125 input |
| U24 1/OE (pin 1) | tie LOW (enable, active LOW) |
| U24 1Y (pin 3) | 74AHCT125 output (5V swing) |
| R1 one end | 300Ω series resistor |
| R1 other end | LED1 DIN |
| LED1 DOUT | LED2 DIN |
| LED2 DOUT | LED3 DIN |
| LED3 DOUT | LED4 DIN |
| LED4 DOUT | NC |

> U24 unused inputs (2A, 3A, 4A — pins 4, 10, 13) → GND.
> U24 unused /OE pins (2/OE, 3/OE, 4/OE — pins 5, 9, 12) → GND.
> U24 VCC (pin 14) → +5V; GND (pin 7) → GND.

---

### SIG: BTN1 (Radio 1)

| Point | Location |
|-------|----------|
| U1 GPIO40 | ESP32-S3 (INPUT_PULLUP) |
| SW2 NO | Button normally-open terminal |

> SW2 COM → GND. Repeat for SW3→GPIO41, SW4→GPIO42, SW5→GPIO48.

---

### SIG: PTT_FOOTSW (foot switch input)

| Point | Location |
|-------|----------|
| U1 GPIO3 | ESP32-S3 (INPUT_PULLUP) |
| R23 one end | 10kΩ pull-up |
| C55 one end | 100nF debounce cap |
| J23 tip | PTT foot switch jack |

> R23 other end → +3V3. C55 other end → GND.

---

### SIG: AUDIO_R1_BIASED (Radio 1 audio after coupling + bias)

| Point | Location |
|-------|----------|
| C5 (+) | 10µF coupling cap, positive |
| R19 one end | 10kΩ series resistor |
| R26 one end | 22kΩ bias to VGND |
| U2 X0 (pin 15) | CD4051 #1 channel 0 |
| U3 X0 (pin 15) | CD4051 #2 channel 0 |

> C5 (−) → J14 tip (Radio 1 audio jack). R19 other end → C5 (+). R26 other end → VGND.

> Repeat pattern for Radio 2 (C6/R20/R27/X1), Radio 3 (C7/R21/R28/X2), Radio 4 (C8/R22/R29/X3).
> All radios feed both U2 and U3 X inputs (both left and right mux see all 4 sources).

### SIG: AUDIO_LEFT_SWITCHED (CD4051 #1 Z output)

| Point | Location |
|-------|----------|
| U2 Z (pin 14) | CD4051 #1 common output |
| C9 (+) | 10µF coupling cap |

### SIG: AUDIO_LEFT_TO_BUFFER

| Point | Location |
|-------|----------|
| C9 (−) | Coupling cap output side |
| R42 one end | 100kΩ bias |
| U7 IN+ (pin 3) | NJM4556 U7A non-inverting input |

> R42 other end → VGND. U7 IN− (pin 2) connected to OUT (pin 1) — unity gain feedback.

### SIG: AUDIO_LEFT_BUFFERED

| Point | Location |
|-------|----------|
| U7 OUT (pin 1) | NJM4556 U7A output |
| RV1 wiper-L | Left wiper of stereo volume pot |

### SIG: AUDIO_LEFT_TO_HP

| Point | Location |
|-------|----------|
| RV1 wiper-L | (after pot) |
| C11 (+) | 10µF cap |
| C11 (−) | → J13 tip (HP Left) |

> Repeat AUDIO_RIGHT path for U3, R43, pin5/6/7 of U7, RV1 wiper-R, C12, J13 ring.

---

### SIG: XLR_PIN2_HOT

| Point | Location |
|-------|----------|
| J1 pin 2 | XLR female hot |
| C3 (+) | 10µF/25V INA333 coupling cap |

### SIG: XLR_PIN3_COLD

| Point | Location |
|-------|----------|
| J1 pin 3 | XLR female cold |
| C4 (+) | 10µF/25V INA333 coupling cap |

### SIG: INA333_IN_PLUS

| Point | Location |
|-------|----------|
| C3 (−) | INA333 input coupling cap negative |
| U8 IN+ (pin 3) | INA333P non-inverting |

### SIG: INA333_IN_MINUS

| Point | Location |
|-------|----------|
| C4 (−) | INA333 input coupling cap negative |
| U8 IN− (pin 2) | INA333P inverting |

### SIG: INA333_RG (gain set resistor — both terminals)

| Point | Location |
|-------|----------|
| U8 RG− (pin 1) | INA333P gain pin 1 |
| R10 one end | 1kΩ 1% |
| R10 other end | U8 RG+ (pin 8) | INA333P gain pin 8 |

### SIG: MIC_PREAMP_OUT

| Point | Location |
|-------|----------|
| U8 OUT (pin 6) | INA333P output |
| U4 Z (pin 14) | CD4051 #3 common (demux input) |

### SIG: MIC_R1_SIGNAL

| Point | Location |
|-------|----------|
| U4 X0 (pin 15) | CD4051 #3 channel 0 output |
| R32 one end | 100kΩ pull-down |
| U9 IN+ (pin 3) | THAT1646 #1 input |

> R32 other end → GND.

### SIG: MIC_R2_SIGNAL

| Point | Location |
|-------|----------|
| U4 X1 (pin 4) | CD4051 #3 channel 1 |
| R33 one end | 100kΩ pull-down |
| U10 IN+ (pin 3) | THAT1646 #2 |

> Repeat for MIC_R3 (U4 X2/pin3 → R34 → U11) and MIC_R4 (U4 X3/pin7 → R35 → U12).
> IN− (pin 4) of each THAT1646 → GND.

### SIG: MIC_R1_HOT (XLR out)

| Point | Location |
|-------|----------|
| U9 OUT+ (pin 7) | THAT1646 #1 balanced + |
| J2 pin 2 | XLR male Radio 1 hot |

### SIG: MIC_R1_COLD

| Point | Location |
|-------|----------|
| U9 OUT− (pin 6) | THAT1646 #1 balanced − |
| J2 pin 3 | XLR male Radio 1 cold |

> Repeat MIC_R2/R3/R4 output connections: U10→J3, U11→J4, U12→J5.

---

### SIG: KEY_IN_DIT

| Point | Location |
|-------|----------|
| J18 tip | CW key input jack |
| U5 INX (pin 13) | CD4052 common A (Dit) |

### SIG: KEY_IN_DAH

| Point | Location |
|-------|----------|
| J18 ring | CW key input jack ring |
| U5 INY (pin 3) | CD4052 common B (Dah) |

### SIG: KEY_R1_DIT

| Point | Location |
|-------|----------|
| U5 X0 (pin 15) | CD4052 A channel 0 |
| R36 one end | 100kΩ pull-down |
| J19 tip | CW key out Radio 1 |

### SIG: KEY_R1_DAH

| Point | Location |
|-------|----------|
| U5 Y0 (pin 1) | CD4052 B channel 0 |
| R40 one end | 100kΩ pull-down |
| J19 ring | CW key out Radio 1 |

> Repeat KEY_R2 (X1/Y1 → J20), KEY_R3 (X2/Y2 → J21), KEY_R4 (X3/Y3 → J22).
> R36–R43 other ends → GND. U5 INH (pin 6) → GND.

---

### SIG: SR_Q0 → PTT Radio 1

| Point | Location |
|-------|----------|
| U6 QA (pin 15) | 74HCT595N output 0 |
| R2 one end | 470Ω current limit |
| R2 other end | OC1 anode (pin 1) |
| OC1 collector (pin 4) | → J25 pin 1 (Radio 1 PTT signal) |

> J25 pin 2 → GND. Radio PTT rail connects to J25 pin 1 via external 10kΩ pull-up in radio.
> Repeat: U6 QB(pin1)→R3→OC2→J26, QC(pin2)→R4→OC3→J27, QD(pin3)→R5→OC4→J28.

### SIG: SR_Q4 → TX INH Radio 1

| Point | Location |
|-------|----------|
| U6 QE (pin 4) | 74HCT595N output 4 |
| R6 one end | 470Ω |
| R6 other end | OC5 anode (pin 1) |
| OC5 collector (pin 4) | → J29 pin 1 (Radio 1 TX INH signal) |

> Repeat: QF(pin5)→R7→OC6→J30, QG(pin6)→R8→OC7→J31, QH(pin7)→R9→OC8→J32.

---

### SIG: TC7660H_C1 (internal pump cap)

| Point | Location |
|-------|----------|
| U13 pin 2 (C1+) | TC7660H |
| C15 (+) | 10µF cap positive |
| C15 (−) | U13 pin 3 (C1−) |

### SIG: TC7660H_C2

| Point | Location |
|-------|----------|
| U13 pin 1 (C2+) | TC7660H |
| C16 (+) | 10µF cap positive |
| C16 (−) | U13 pin 6 (C2−) |

---

## MAX3232 Charge Pump Caps (repeat ×4, U14–U17)

For each MAX3232 chip, connect locally:

| MAX3232 Pin | → Cap → | MAX3232 Pin |
|-------------|---------|-------------|
| C1+ (pin 1) | 100nF | C1− (pin 3) |
| C2+ (pin 4) | 100nF | C2− (pin 5) |
| V+ (pin 2) | 100nF | GND |
| V− (pin 6) | 100nF | GND |

> VCC (pin 16) → +3V3. GND (pin 15) → GND.
> T2IN, T2OUT, R2IN, R2OUT (second channel) → leave NC.

---

## SC16IS752 Address Straps

| Chip | A0 | A1 | I2C Address |
|------|----|----|-------------|
| U18 | VDD | VDD | 0x4D |
| U19 | GND | VDD | 0x4E |

---

## USB-C Panel Connectors (J10–J12, ×3 identical)

| USB-C Pin | Connection |
|-----------|-----------|
| CC1 | → R13/R15/R17 (5.1kΩ) → GND |
| CC2 | → R14/R16/R18 (5.1kΩ) → GND |
| D+ | → CP2102N D+ pad |
| D− | → CP2102N D− pad |
| GND | → GND |
| VBUS | NC |
