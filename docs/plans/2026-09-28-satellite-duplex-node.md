# Satellite Duplex Node: two UV-K5s, one ESP32, one BLE link

**Date:** 2026-09-28
**Status:** High-level spec (sections only, no part-level design yet)

A mounting plate that holds two Quansheng UV-K1 / UV-K5 V3 handhelds (F4HWN CAT
build) and an ESP32-S3 that CAT-controls both over their K1 jacks and exposes them
to Field as one CW Bridge with two radios. Modeled on the AllScan ANF101 plate, but
CAT + BLE to a phone instead of a USB sound card to a Raspberry Pi.

Companion to the two-bridge setup already in the app (`SatelliteDuplexController`),
which stays the way to run FM satellite duplex with existing CW Bridge hardware.

## Goals

- Full-duplex FM satellite operation: uplink radio + downlink radio, Doppler-tuned
  from the phone, one headset.
- One BLE connection, one battery, one plate that goes on a tripod or in a hand.
- No USB host to the radios: CAT over the K1 jack UART at 3.3 V, so the radios
  never draw charge current from the node.
- Reuse the CW Bridge rev 2.1 power and MCU clusters wherever they fit.

## Non-goals (v1)

- SSB / linear transponders (the UV-K5 is FM-only on TX).
- Audio to the phone (no codec on v1; the K5 pass recording keeps using the phone mic).
- CW keying (no keyer, no paddle jack).

## Block diagram

```
  power bank ──USB-C──┐                          ┌── K1 pigtail ── [ UV-K5  A ] (uplink)
  1S LiPo ────JST─────┤  power  ┐                │
                      │  section├─ 3V3 ─┐        │
                      └─────────┘       │        │
                                   ┌────┴─────┐  │
                                   │ ESP32-S3 ├──┤ UART1 (CAT A)
                                   │ WROOM-1U ├──┤ UART2 (CAT B)
                                   │  + BLE   │  │
                                   └────┬─────┘  └── K1 pigtail ── [ UV-K5  B ] (downlink)
                                        │
                     LEDs / buttons / OLED hdr / flash+debug
                                        │
        headset jack ◄── SPK(B) + MIC(A) + PTT button ── audio section
```

## Sections

### 1. Mechanical plate

- One PCB doubles as the plate (ANF101 style): two handheld pockets with strap
  slots or M2.5 standoff holes for printed cradles, the electronics between them.
- Radios sit antenna-up, K1 jacks facing the center so the pigtails stay short.
- Mounting: 1/4-20 tripod insert on the back, plus slots for a wrist/neck strap.
- Headset jack and power switch on the edge that faces the operator.
- Target outline ≈ 200 × 90 mm (two K5 bodies ≈ 60 mm wide each + 60 mm center).
- Open: printed cradles vs. hook-and-loop; whether the phone also mounts on the plate.

### 2. MCU and radio link

- ESP32-S3-WROOM-1U-N16R8 (U.FL antenna), same module as the CW Bridge so the
  firmware target, flash size, PSRAM mode and partition table carry over.
- Reuse the bridge's EN/BOOT network (R24/C53, R25) and RESET/BOOT headers.
- BLE NUS peripheral, Just Works pairing (no display needed).
- Two hardware UARTs to the radios on native GPIO; the third stays the console.
- Native USB pins go to the flash/debug port (section 6), not to a host port.
- I²C bus on a header for an optional SSD1306 (the firmware already drives one).

### 3. Radio interfaces (×2, identical)

Per radio, a 6-pin JST-PH header feeding a K1 pigtail (2.5 mm + 3.5 mm TRS,
12 mm spacing, AIOC-documented pinout):

| Signal | K1 contact | Node side |
|---|---|---|
| CAT data from radio | 2.5 mm ring | ESP32 UART RX via 1 k series + ESD |
| CAT data to radio (shared with PTT1) | 3.5 mm sleeve | ESP32 UART TX via 1 k series + ESD; never driven low except as UART data |
| speaker out | 2.5 mm tip | audio section (downlink radio only in v1) |
| mic in | 3.5 mm ring | audio section (uplink radio only in v1) |
| +V / PTT2 | 3.5 mm tip | not connected |
| ground | 2.5 mm sleeve | GND |

- 38400 8N1, 3.3 V logic both ends (PY32F071 in the radio), no level shifter.
- PTT is done over CAT (`TX;` / `RX;`), so the shared PTT1/RxData contact only
  ever carries UART levels.
- Both radios wired identically; uplink/downlink is a firmware/app role, and the
  plate is symmetric so either pocket can be either role.
- Open: whether to add a per-radio "radio present" sense (e.g. bias on SPK line)
  so the app can show which pocket is populated.

### 4. Audio / headset section

Inserting K1 plugs disables each handheld's internal speaker and mic, so v1 must
give them back through one headset jack:

- 3.5 mm TRRS headset jack (CTIA): L+R ← downlink radio speaker line through a
  simple attenuator (the radio's volume knob still sets level); mic → uplink radio
  mic line with the radio's own bias (pass-through, AC-coupled).
- PTT: a momentary button on the plate (and an optional inline-PTT input on a
  second 3.5 mm jack) read by the ESP32, which issues CAT `TX;` / `RX;`.
  Rationale: keeps the PTT1 contact free for UART, and the app can also key.
- Sidetone/monitor mix and a codec for phone audio are explicitly deferred; leave
  footprints for an ES8388 + I²S if the CW Bridge audio cluster is wanted later.

### 5. Power section

Copy the CW Bridge rev 2.1 topology, minus the 5 V host port:

- Input: USB-C (J9-style: F3 PTC + D3 TVS, CC pull-downs), power only in RUN.
- Battery: 1S LiPo on JST-PH, MCP73831-2 charger (500 mA), protected cell.
- Boost: TPS61085 → 5 V only if something on the board needs 5 V; otherwise drop
  the boost and run the cell straight into the 3.3 V buck (AP63205) — the ESP32
  and the radios' UARTs are all 3.3 V. **Decision pending**, see open questions.
- Mux: TPS2116 USB-priority if the boost stays; otherwise a simple ideal-diode OR.
- Radio charging pass-through (optional, jumper-selectable): two USB-C power-only
  pigtails from the 5 V rail through a current-limited switch (TPS2553, ~500 mA
  each) so both handhelds top up from the same power bank. Off by default so the
  node's own cell is not drained into the radios.
- Budget: ESP32-S3 BLE ≈ 100–150 mA peaks, average < 80 mA; a 2000 mAh cell gives a
  full day of passes without radio charging.

### 6. Flash, debug, and status

- USB-C data pins routed to the module's native USB for flashing (no RUN/FLASH
  switch needed since there is no host port to share the pins with).
- Console UART on a 3-pin header (TX/RX/GND), 115200.
- LEDs: PWR (3V3), BT (paired/connected), RADIO A, RADIO B (CAT alive on each UART).
- Buttons: one user button (pair / mode), plus BOOT and RESET headers.
- OLED header (I²C + 3V3 + GND) for the existing display firmware, optional fit.

### 7. Firmware deltas (`firmware/`)

- `uart_radio.rs`: a second transport beside `usb.rs` — one UART per radio,
  38400, framed into the same detect/verify paths. Detection over UART reuses the
  `FA;` probe added for the Quansheng today.
- Radio index in CWBP: every CAT-data, set-verify, radio-info and status frame
  gains a radio slot (0/1). Protobuf field addition, backward compatible with the
  single-radio bridge (slot defaults to 0).
- Board variant: a `duplex-node` feature or a second `board_*.rs` pin map
  (UART pins, PTT button, LEDs on native GPIO instead of the PCAL6416A).
- PTT button → `TX;`/`RX;` on the uplink slot, with a firmware time-out timer.

### 8. App deltas (`swift/ios`)

- `RadioLink` learns a radio slot; one BLE link exposes two `RadioLink` slots.
- `SatelliteDuplexController` already addresses radios by link; add "one bridge,
  two slots" as a second binding mode next to "two bridges".
- Settings UI: assign slot 0/1 to uplink/downlink, swap button as today.

## Open questions

1. **5 V rail or not.** If nothing but optional radio charging needs 5 V, dropping
   the boost + mux saves ~12 parts and the biggest inductor. Leaning: no 5 V rail
   on the node; radio charging via a separate cable from the power bank.
2. **PTT ownership.** Hardware button on the node vs. app-only vs. inline PTT
   on the headset. Leaning: node button + app, both via CAT.
3. **Audio passthrough level.** Confirm the K5's speaker line can drive 32 Ω
   headphones through an attenuator without a buffer; measure on a bench first.
4. **Radio present sense.** Worth a comparator per radio, or rely on CAT liveness.
5. **Plate vs. cradle.** PCB-as-plate (ANF101) vs. a small PCB in a printed
   carrier. PCB-as-plate is faster to first hardware; the carrier is nicer to hold.

## Phasing

- **v0 (this week):** ESP32-S3 devkit + two K1 pigtails on a perfboard, powered
  from the devkit's UART USB-C. Proves the UART CAT path and the firmware transport
  before any layout. Headset via a passive breakout.
- **v1:** the plate PCB above, hand-assembled, sections 1–6.
- **v2 (if wanted):** ES8388 audio cluster for phone-side recording and a
  digital sidetone/monitor mix.
