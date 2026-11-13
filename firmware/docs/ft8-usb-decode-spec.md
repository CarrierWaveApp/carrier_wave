# Spec: on-device FT8 decode from radio USB audio (ESP32-S3 bridge)

**Goal:** decode (and later transmit) FT8 entirely on the bridge — pull RX audio
from the radio, decode with the firmware's bundled CFT8 library, send decoded
messages to the app over BLE. Audio never crosses BLE (only text + metadata).

---

## TL;DR — there are two audio sources; the hard part is the same
The decoder and its **PSRAM requirement are identical** either way; only how the
audio reaches the chip differs:

- **Path A — analog (recommended 80/20).** PSRAM S3 board + the firmware's
  **existing TRS/ADC audio capture**. Essentially *no new audio code* — flip on
  `CONFIG_SPIRAM` and feed the ADC slot buffer (already wired) to the decoder
  (already integrated). Small effort, low risk. Cost: a TRS cable from the
  radio's data/headphone jack + the bias/attenuator the firmware already
  documents in `audio.rs`.
- **Path B — USB audio (what you asked).** PSRAM S3 board + a **USB Audio Class
  (UAC) host** driver pulling isochronous audio off the radio's USB codec. One
  USB cable does CAT *and* audio, no analog wiring — but UAC-host on the S3 is
  new and the **USB host channel budget is the real risk**. Large effort,
  medium-high risk.

**If the aim is "FT8 decode on the bridge soon," do Path A.** Path B is the
elegant end-state. Everything below applies to both unless marked "Path B."

---

## Hardware (both paths)
- **PSRAM is mandatory.** Working set ≈ 120 kB decode waterfall + a 15 s slot
  buffer (12 kHz × 15 s = 180k samples → 360 kB i16 / 720 kB f32) + scratch ≈
  **0.5–1 MB**. The WiFi Kit 32 v3.1 has none.
- Board must have: ESP32-S3 **with PSRAM**, **native USB-OTG free for the host**,
  **and a separate USB-UART for console/power** (the v3.1's winning trait; the
  V4 fails here — its single port is native USB, the exact conflict we hit).
- **Recommended: ESP32-S3-DevKitC-1-N8R8** (8 MB flash + **8 MB PSRAM**). Two
  USB-C ports — native USB → radio host, UART bridge → console/power — i.e. the
  v3.1 topology *plus* PSRAM. No OLED (add an I²C SSD1306). Heltec WiFi LoRa 32
  V4 has PSRAM but the single-native-USB problem; not recommended.

## Audio → decode pipeline (both paths)
1. Capture into a **15 s slot ring buffer @ 12 kHz** in PSRAM (the firmware's
   `FT8_SLOT_SAMPLES` already = 12000×15).
2. Feed the slot to **CFT8 decode** (already integrated; ~120 kB waterfall needs
   PSRAM). **Pin decode to core 1** so it doesn't stall BLE/USB.
3. Emit `Ft8Decode` protobuf (text + SNR + freq + dt) over BLE — message types
   already exist (`Ft8Decode`, `Ft8Status`, `CAP_FT8_CODEC`).

## Slot timing (both paths)
FT8 slots are wall-clock aligned (:00/:15/:30/:45); the bridge has no clock.
Options, simplest first:
- **WiFi NTP** — the S3 has WiFi; cleanest for autonomous decode.
- **Phone pushes time over BLE** at capture start (matches today's app-aligned model).
- **Free-run + decoder `delta_time` tolerance** — what the current design leans on.

## CPU
CFT8 full-slot decode on a 240 MHz S3 is heavy (FFT + sync search over the
waterfall) — expect low single-digit seconds; **must finish within the 15 s
slot**. Cap candidate count / decode depth if needed. Validate on real audio.

---

## Path B specifics — the USB-audio work
1. **UAC host driver:** `espressif/usb_host_uac` (managed component, UAC 1.0
   host; isoc IN/OUT). Enumerate the radio's audio codec — on the FTX-1 that's
   the **C-Media `0x0D8C:0x0016`** device our CAT enum filter *currently
   rejects*; you'd allow it through.
2. **Channel budget — THE go/no-go risk.** The S3 USB-OTG host has **8 HCD
   channels**. Through the radio's internal hub: hub (~2: ctrl + interrupt) +
   CDC CAT chip (3: ctrl + bulk IN + bulk OUT) + UAC (ctrl + isoc IN [+ isoc OUT
   for TX]) ≈ 8, right at the edge — this is the same limit that forced our enum
   filter. Mitigations: **RX-only first** (drop isoc OUT), possibly pause the
   CDC bulk-OUT poll when idle. **Prove enumerate + simultaneous CDC-CAT +
   isoc-IN holds before building anything else.**
3. **Bandwidth:** radio audio is full-speed isoc; 48 kHz/16-bit mono ≈ 0.77 Mbps
   — fine on FS USB, but verify it streams cleanly alongside CAT polling through
   the hub.
4. **Resample:** radio UAC is usually 48 kHz; FT8 wants 12 kHz → decimate-by-4
   with an anti-alias FIR. (Confirm the radio's actual UAC rate — some offer
   12 kHz natively.)

## TX (optional, later — both paths)
- Path A: I²S → external DAC → radio mic/data in (the firmware's existing mic
  path) + PTT via CAT.
- Path B: UAC isoc **OUT** to the codec (12k→48k upsample) + PTT via CAT. Adds
  the isoc-OUT channel → tightest on the budget. Defer until RX is solid.

---

## Milestones / rough effort
| Phase | Work | Effort |
|---|---|---|
| P0 | PSRAM S3 devkit bring-up: port firmware, confirm BLE + USB host + console coexist, add OLED | days |
| **P1 (Path B only)** | UAC enumerate + raw isoc-IN capture **+ prove the 8-channel budget** alongside CDC CAT | **1–2 wk, make-or-break** |
| P2 | resample + slot buffer + CFT8 decode → BLE (decode already exists) | days–1 wk |
| P3 | slot time sync (NTP) | days |
| P4 | TX (optional) | 1–2 wk |

**Path A** skips P1 entirely → P0 + enable `CONFIG_SPIRAM` + reuse the ADC path + P2/P3.

## Risks (ranked)
1. **HCD channel exhaustion** (hub + CDC + UAC isoc on 8 channels) — Path B #1; validate first.
2. UAC host driver maturity / the radio's specific UAC descriptors.
3. Decode CPU within the 15 s slot.
4. Slot time sync without a host app.
5. (Path A) analog level/quality — minor, already-solved territory.

## Bottom line
On-bridge FT8 decode is genuinely feasible **on a PSRAM S3 board** — the decoder
is already in the firmware. The cheap route reuses the **existing analog ADC
path** (Path A). The USB-audio route (Path B) is the clean one-cable end-state
but lives or dies on the **USB-host channel budget**, which must be proven in a
P1 spike before committing.
