# Sheet 08 — Illuminated Buttons + WS2812B NeoPixels

## WS2812B LED Chain (with mandatory 74AHCT125 level shifter)

All 4 NeoPixels are daisy-chained on a single data line. The ESP32 sends
a serial data stream; each LED latches its own color data and passes the rest.

WS2812B requires VIH = 0.7 × VDD = **3.5 V** at VDD = +5 V. ESP32-S3 GPIO
outputs only 3.3 V — below the threshold. A 74AHCT125 (advanced-CMOS, TTL
input thresholds, drives rail-to-rail at 5 V) buffers the 3.3 V signal up to
a clean 5 V output. This part is mandatory; the design is not robust without
it.

```
+5V ──[C 100µF]── GND     (bulk capacitor at start of chain)

+5V ──────────────────────────────────────────┬──────┬──────┬──────┐
                                              │      │      │      │
                                           WS2812  WS2812  WS2812  WS2812
                                            #1      #2      #3      #4
                                           VDD     VDD     VDD     VDD
                                              │      │      │      │
GND ─────────────────────────────────────────┴──────┴──────┴──────┘

74AHCT125 (DIP-14, one gate used; tie unused gate inputs + /OE pins to GND):

ESP32 GPIO33 ──► 1A (pin 2)             1Y (pin 3) ──[R 300Ω]──► WS2812B #1 DIN
GND ──────────► 1/OE (pin 1, active LOW: tie LOW to enable)
+5V ──────────► VCC (pin 14)
GND ──────────► GND (pin 7)
GND ──────────► 2A, 3A, 4A, 2/OE, 3/OE, 4/OE (unused)

                             WS2812B #1 DOUT ──► WS2812B #2 DIN
                                                WS2812B #2 DOUT ──► WS2812B #3 DIN
                                                                    WS2812B #3 DOUT ──► WS2812B #4 DIN
                                                                                        WS2812B #4 DOUT ── NC

WS2812B assignment:
  #1 = Radio 1 button LED
  #2 = Radio 2 button LED
  #3 = Radio 3 button LED
  #4 = Radio 4 button LED
```

100 µF bulk cap (was 1000 µF in earlier rev; oversized for 4 LEDs at ~50 mA
all-white). Add a ferrite bead in series with the WS2812B +5 V supply to
keep the LED PWM noise (broadband 500 kHz – 5 MHz) out of the mic preamp.

---

## WS2812B Physical Mounting

```
Panel view:
  ┌─────────────────────────────────────────────────────┐
  │  [RADIO 1]    [RADIO 2]    [RADIO 3]    [RADIO 4]   │
  │  (16mm btn)  (16mm btn)  (16mm btn)  (16mm btn)     │
  └─────────────────────────────────────────────────────┘

Each button:
  - 16mm panel-mount momentary push button with translucent/white cap
  - WS2812B LED mounted BEHIND the button cap (inside the button body or
    in a small 3D-printed holder/ring that centers the LED behind the lens)
  - LED emits through translucent cap for even illumination
  - ~8–10mm clearance between LED and cap face gives good diffusion

LED color scheme (firmware):
  OFF (dark)   = Radio not in use / no connection
  Dim white    = Radio available (connected, idle)
  Bright green = Audio routed to one ear for this radio
  Bright cyan  = Audio routed to both ears
  Bright red   = Active radio (has mic + key routing)
  Yellow       = Active radio + one ear audio
  White        = Active radio + both ears audio
  Flashing red = PTT live (actively transmitting)
```

---

## Button Input Wiring (×4, identical)

```
16mm Momentary Button (one of 4):

  Button NO terminal ──┬──────────────────────────────► ESP32 GPIO (see table)
                       │
                   [NC — not used]
                       
  Button COM terminal ─────────────────────────────────► GND

  ESP32 GPIO configured as INPUT_PULLUP.
  Internal pull-up resistor (~45kΩ) holds GPIO HIGH when button not pressed.
  When pressed: GPIO pulled LOW through the button contact to GND.
  Firmware detects falling edge as button press event.

Button  │ ESP32 GPIO │ Panel label
--------|------------|-------------
#1      │ GPIO40     │ "RADIO 1"
#2      │ GPIO41     │ "RADIO 2"
#3      │ GPIO42     │ "RADIO 3"
#4      │ GPIO48     │ "RADIO 4"

No external pull-up or debounce capacitor needed — use software debouncing
(read stable state over 20ms window).
```

---

## Button Behavior (firmware)

```
Single press:
  → Sets that radio as the active radio (mic/key/PTT routes to it)
  → Updates NeoPixel to show new active radio (red or white)
  → If audio not yet assigned, also routes that radio's audio to both ears
     (can override with software)

Long press (>500ms):
  → Cycles audio routing for that radio through modes:
     Off → Left ear only → Right ear only → Both ears → Off
  → NeoPixel color updates accordingly

Double press:
  → Bypass mode for RF filter on that radio (if RF box connected)
  → LED flashes purple briefly to confirm

Button priority: the last-pressed radio becomes active.
Simultaneously pressing two buttons → undefined (handle in firmware).
```

---

## Complete Button + LED Assembly

```
For each radio N:

+5V ──► WS2812B #N VDD
GND ──► WS2812B #N GND
Data chain ──► WS2812B #N DIN

WS2812B #N physically inside / behind button cap N
Button #N NO terminal ──► ESP32 GPIO (see table above)
Button #N COM terminal ──► GND
```
