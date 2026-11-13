# Investigation: SO2R Box POC bench session (milestones 1–5 + native-USB-host CAT)

**Date:** 2026-05-29
**Status:** Resolved (M1–M4 done; M5 in progress at writing)
**Outcome:** All POC milestones validated on the bench. Milestone 4 pivoted from
"box talks CAT to the radio" to "box is a PC-driven control plane" after a USB
topology dead-end. A separate side-investigation proved an ESP32-S3 can host a
USB-only radio and do bidirectional CAT (read freq + write band/mode) via its
native USB peripheral.

## Problem Statement

Bring up the SO2R contest-box proof-of-concept on the bench against the
`POC_BENCH_PLAN.pdf` milestones, using a Heltec WiFi LoRa 32 V3 (ESP32-S3),
an MCP23017 I²C GPIO expander, an 8-channel relay board, panel buttons, an
OLED, and a Yaesu FTX-1 Optima radio. Validate each milestone with real
hardware before committing to the full ~$325 BOM.

Hardware notes that recur below:
- **Heltec V3**: serial/programming runs through an onboard CP2102 on UART0, so
  the ESP32-S3's *native* USB pins (GPIO19 D−, GPIO20 D+) are free.
- Native-GPIO free list (per Heltec docs): GPIO 1, 2, 4, 5, 6, 7, 19, 20, 47, 48.
- Firmware lives **locally** (not committed): `~/so2r_poc/` (Arduino) and
  `~/ftx1_usbhost/` (ESP-IDF). The repo copy under
  `docs/schematics/so2r-box/firmware/so2r_poc/` lags the local working copy.

## Milestone Log

### M1 — toolchain / OLED / serial — RESOLVED
Flashed `so2r_poc` (PlatformIO, `board = heltec_wifi_lora_32_V3`). Boot banner on
serial + OLED status confirmed. Note: the Heltec needs
`ARDUINO_USB_CDC_ON_BOOT=0` so Serial routes through the onboard CP2102, not the
S3 native USB (which isn't wired to the USB-C jack).

### M2 — MCP23017 + 8-relay click test — RESOLVED (two real gotchas)
1. **MCP23017 enumerated at 0x27, not 0x20.** The SEENGREAT SG-IO-E017 breakout
   sets its I²C address via an on-board **DIP switch**, which ships all-high
   (0x27). Fixed by setting the DIP to 0x20. (Also a naming trap: the breakout's
   **PA0/PA1/PA2 are port-A GPIO**, *not* the chip-address pins A0/A1/A2 —
   grounding PA0–2 does nothing to the address.)
2. **Relays wouldn't release.** The MCP runs at 3.3 V; a "HIGH" output is only
   3.3 V. On a 5 V active-low opto-isolated relay board, 3.3 V isn't high enough
   above the opto-LED forward drop to *release* the optocoupler, so relays sat
   marginally engaged. **Fix: drive relays by tri-stating** — `IODIRB` bit = 1
   (input / high-Z) = relay OFF (electrically identical to unplugging the input);
   `IODIRB` bit = 0 + `OLATB` = 0 (output LOW) = relay ON. `relayActiveLow`/`pol`/
   `inv` became no-ops and were removed.

### M3 — panel state machine (4 buttons / OLED) — RESOLVED (LED ring deferred)
Buttons on GPIO 4–7, debounced. State machine + OLED verified. The WS2812B LED
ring was deferred — the LEDs on hand were plain common-cathode RGB, not WS2812B
(REVIEW B6 also notes 3.3 V WS2812B is unreliable; the final BOM's 74AHCT125
level-shifter is genuinely required).

### M4 — CAT control — PIVOTED (this is the big one)
**Original scope:** ESP32 → external CP2102N → radio USB-CAT.
- **Phase A (UART loopback)** passed.
- **Phase B (PC ↔ radio via Hamlib)** passed — `rigctl -m 1051` (FTX-1 backend,
  Beta) read frequency/mode cleanly at 38400 8N1. (The radio answers `ID;` with
  `ID0840;` = the FT-991A model code, for backward compat.)
- **Phase C failed for a topological reason, not a wiring bug:** the radio's
  USB-CAT port is a USB **device** port, not a host. You cannot plug another USB
  device (the CP2102N) into it — two devices can't talk without a host. The
  radio's hardware-serial CAT is **CAT-3** on the TUNER/LINEAR jack, a
  **mini-DIN-10 at 5 V CMOS** (would need a level shifter + custom cable, and the
  ESP32 isn't 5 V tolerant on its inputs).

**Pivot:** the SO2R box will **not** talk CAT to radios. The host PC owns all
CAT; the box becomes a **smart USB-CDC peripheral** the PC commands, reporting
panel events back. New M4 = a **PC ↔ box ASCII protocol** over the Heltec's
existing USB-CDC:
- Commands: `STATE`, `RADIO <1|2>`, `BAND <1|2> <name>`, `RELAYS <0xNN>`,
  `PTT <1|2> <ON|OFF>`, `PING`, `RESET`, `?`.
- Events: `EVT BOOT version=N`, `EVT BTN <1-4> PRESS|RELEASE`,
  `EVT STATE <field>=<value>` (panel-driven only — PC commands stay silent to
  avoid echo loops).
- Per-radio state (`band[2]`, `ptt[2]`); single `\n` line terminator; case-
  insensitive command names; band names case-sensitive (`160m`..`BYP`); `BAND`
  is idempotent (no relay write if unchanged).

PC-side client (`scripts/so2r_client.py`) + firmware both implemented and
**integration-tested** — the client's `--demo` ran clean end-to-end against the
live box, and every command/error path/button event was verified on the bench.

### M5 — CD4051 audio mux click-through — IN PROGRESS
Proving the 8:1 analog mux (CD4051BE) concept. Plan called for native GPIO 8/9/10
for the address lines — **but those are the Heltec's LoRa SX1262 SPI pins**
(plan bug). We instead drive the 3 address lines from **MCP23017 port A**
(GPA0/1/2, push-pull outputs — *not* the port-B relay tri-state scheme), which
also better matches the real architecture (I²C control plane scales to 18+
channels). Added `mux <0-7>` + `muxwalk` commands. Address-write verified at the
I²C level; audio listening test pending CD4051 wiring.

## Side investigation — ESP32 native USB host CAT (the "other project")

The M4 topology dead-end raised: *can an ESP32 host a USB-only radio at all?*
Answer: **yes**, proven on the bench. Three things made it work:

1. **ESP32-S3 native USB host** on GPIO19/20 (free on the Heltec). Framework is
   **ESP-IDF** (the USB host VCP stack lives there), not Arduino. A USB-A female
   breakout (D+→20, D−→19, GND, VBUS→5V) + a USB-A→USB-C cable to the radio.
   USB-A's host role is implicit (no CC resistors).
2. **The FTX-1's bridge is a Silicon Labs CP2105 — vendor-specific, NOT CDC-ACM.**
   Use Espressif's `usb_host_cp210x_vcp` driver; `cp210x_vcp_open(pid, 0, …)` —
   interface **0** is CAT-1 (Enhanced COM), 38400 8N1.
3. **THE KEY FIX: the radio has an internal USB hub** fanning out to the CP2105
   (`0x10C4/0xEA70`), a C-Media USB audio codec (`0x0D8C/0x0016`), and a third
   function (`0x26AA/0x0030`). ESP-IDF disables external-hub support by default,
   so the host saw the hub but couldn't reach the CP2105 behind it (symptom:
   `HUB: External Hubs support disabled` + `open ESP_ERR_NOT_FOUND`). Fixed with
   **`CONFIG_USB_HOST_HUBS_SUPPORTED=y`** (+ `CONFIG_USB_HOST_HUB_MULTI_LEVEL=y`)
   in `sdkconfig.defaults`.

Result: read VFO-A (`FA;` → `FA007032880;` = 7.032880 MHz), then went
**bidirectional** — panel buttons send `FA<9-digit Hz>;` to QSY and `MD0<n>;` to
set mode (`1`=LSB, `2`=USB, `3`=CW-U, … `C`=DATA-U; `MD0` = MAIN-side). Each
press reads both back for confirmation; the radio's physical band + mode
indicators follow the buttons. Project at `~/ftx1_usbhost/` with self-contained
patches (`ftx1_usbhost.patch` read-only; `ftx1_band_mode.patch` read+write).

## Root Cause (M4 pivot)

USB-CAT ports on transceivers are USB **device** ports. Any host-side controller
(ESP32, PC) must be the USB **host**; you can't chain a USB-UART bridge into a
device port. The bench plan's M4 wiring assumed otherwise. Two valid resolutions:
(a) move CAT to the PC (chosen for the SO2R box), or (b) give the controller real
USB-host hardware (proven viable via the side investigation).

## Lessons Learned / reusable gotchas

- **3.3 V can't release a 5 V opto-isolated active-low input** → tri-state the
  driver pin instead of driving it high.
- **MCP23017 breakouts often set address via a DIP switch** (default 0x27, not
  0x20); `PAx` ≠ address pin `Ax`.
- **A radio's USB-CAT port is a device, not a host** — plan host hardware
  accordingly.
- **Modern radios put an internal USB hub** behind their connector; ESP-IDF USB
  host needs `CONFIG_USB_HOST_HUBS_SUPPORTED=y` to see past it.
- **CP210x ≠ CDC-ACM** — needs the vendor VCP driver.
- **Heltec V3 LoRa SPI occupies GPIO 8–14**; don't reuse those for peripherals.
- Prefer driving the I²C expander for control-plane fan-out over scarce native
  GPIO — matches the real design and frees pins.

## Artifacts

| Artifact | Location | Notes |
|---|---|---|
| SO2R box firmware (Arduino) | `~/so2r_poc/` (local) | M1–M3 + PC protocol + M5 `mux` |
| PC-side client | `scripts/so2r_client.py` | this branch; `--demo` / `--mock` |
| USB-host CAT firmware (ESP-IDF) | `~/ftx1_usbhost/` (local) | + `ftx1_usbhost.patch`, `ftx1_band_mode.patch` |
| Bench plan / wiring / parts | `docs/schematics/so2r-box/*.pdf` | M4 section updated for the pivot |

## Open Items

- Sync the local `~/so2r_poc/` firmware into
  `docs/schematics/so2r-box/firmware/so2r_poc/` (repo copy lags).
- Finish M5 audio listening test (CD4051 wiring) and add a buffered virtual
  ground (VDD/2) for the real build so negative half-cycles don't clip.
- WS2812B LED ring pending correct through-hole parts + 74AHCT125 level shifter.
- For the USB-host project: GPIO-controlled VBUS load switch; optionally CAT-2 /
  audio interfaces behind the hub.
