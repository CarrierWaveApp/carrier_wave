# CW Bridge — session handoff (paste this into a fresh Claude)

You're picking up an in-progress hardware/firmware project. Here's the full context.

## What this is
**Carrier Wave** is an amateur-radio software/hardware suite (org `CarrierWaveApp`, repo cloned at `~/carrier_wave`). I'm N9HO. We're working on the **CW Bridge**: Rust firmware (ESP-IDF `std`) in `~/carrier_wave/firmware/` that runs on a **Heltec WiFi Kit 32 v3.1 (ESP32-S3)** and bridges **BLE (Nordic UART, protobuf) ⇄ USB-host serial** so the iOS/macOS app does wireless **CAT control** of a radio. Test radio is a **Yaesu FTX-1 Optima** (reports CAT ID `ID0840`, Yaesu/Kenwood-family).

Read `~/carrier_wave/firmware/CLAUDE.md` and the repo `CLAUDE.md` for architecture. The auto-memory files (`MEMORY.md` →
`cw-bridge-heltec-v4-fork.md`, `cw-bridge-espidf-ruamel-fix.md`) also have durable notes — read them.

## Build & flash (firmware)
```bash
cd ~/carrier_wave/firmware && source ~/export-esp.sh
cargo build
# v3.1 enumerates as a CP2102: /dev/cu.usbserial-0001 or /dev/cu.SLAB_USBtoUART
espflash flash --port /dev/cu.SLAB_USBtoUART target/xtensa-esp32s3-espidf/debug/cw-bridge
```
Build gotchas already solved (see `cw-bridge-espidf-ruamel-fix.md`): if the ESP-IDF v5.4 Python dep check fails, pin `ruamel.yaml>=0.17,<0.18` + `ruamel.yaml.clib==0.2.7` into `firmware/.embuild/espressif/python_env/idf5.4_py3.9_env`. Also `cargo install ldproxy` if linking fails.

## Work completed today (PRs)
| PR | What | State |
|---|---|---|
| #370 | OLED Vext (GPIO36) polarity was inverted → drive LOW to enable. Fixed dim OLED. | MERGED |
| #371 | FTX-1 ~3 s USB-hub reconnect loop: enum filter *aborted* the radio's 3rd hub device (CDC/audio), collapsing the S3 hub. Allow CDC (class 0x02/0x0A) to enumerate-but-not-claim. | MERGED |
| #372 | iOS: enable Yaesu slow-polling for ALL 4-digit IDs (was only `ID06`, missed FTX-1's `ID0840`). Fixed BLE command flooding → freq lag/spurious QSY/no mode. | MERGED |
| #373 | **POC firmware** (`poc/encoder-cw-memory`): EC-11 encoder mode-cycle (WPM↔AF gain) + CW-memory pushbuttons. Hardware-validated. | OPEN |
| #374 | iOS: parse Yaesu mode (`MD0<char>;` vs Kenwood `MD<digit>;`) so mode populates; poll frequency every other cycle (~1 s) for snappy dial tracking. | OPEN — needs Xcode build + on-device test |

`main` has #370/#371/#372. The Heltec **V4** was tried and **abandoned** (single native-USB port on GPIO19/20 conflicts with the radio-host pins) — that work is in a local `git stash` on branch `heltec-v4`, never pushed.

## POC hardware (PR #373) — wiring
EC-11 encoder + 3 buttons + USB-A radio host, all hardware-tested on the v3.1. Wiring PDF: `firmware/docs/cw-bridge-poc-wiring.pdf`.
- **Encoder (EC-11, bare, no VCC/resistors):** A→GPIO47, B→GPIO48, SW→GPIO26, commons→GND. Uses internal pull-ups.
- **Buttons:** BTN1→GPIO33, BTN2→GPIO34, BTN3→GPIO38, common→GND.
- All of those are on header **J3** — IMPORTANT: read the **silkscreen GPIO numbers on the back of the board**, don't count pins. On J3 the GND/3V3/3V3 cluster is at one end and the encoder/button pads (26/47/48/33/34) are at the **far** end. USB host is on J2: D−=GPIO19, D+=GPIO20, VBUS=5V, GND.
- POC firmware seeds CW slot1="CQ CQ DE N9HO N9HO K", slot2="TU 73 DE N9HO" (NVS, reprogrammable over BLE).

## Open items / next steps
1. **#374 on-device test (highest priority):** build `fix/yaesu-mode-and-freq-poll` in Xcode, run on the iPhone (theseus), connect to bridge+FTX-1, confirm **mode now reads** and **frequency tracks in ~1 s**. Merge if good.
2. **CW memory doesn't key the FTX-1 (POC open item):** firmware sends Hamlib-canonical Yaesu `KM1<text>;KY6;` — radio takes `KS` (speed) but won't key the message. **The Carrier Wave app keys CW memories a DIFFERENT way — align the bridge firmware with the app's method**, not KM1/KY6. (A timing-split of KM1→KY6 was the suspected patch but deferred.)
3. **Band-change still delayed + "jumps around before landing":** a set/verify path issue (separate from the slow-poll fix). Not yet investigated.
4. **3D-printed field box** for Heltec + USB connector — `.scad` file generated at `firmware/docs/cw-bridge-box.scad`.

## Gotchas / hard-won knowledge
- **Serial monitoring on the v3.1:** opening the CP2102 port resets the board, and *closing* it can drop it into ROM download mode (silent). To test interactively, run ONE long-lived pyserial reader that does an esptool-style reset-into-app on open (DTR=False; pulse RTS) and holds the port for the whole session — the board resets once, then state (e.g. encoder WPM↔AF target) persists across re-wiring. `espflash monitor` needs a TTY (fails in a non-interactive shell).
- Bridge passthrough does NOT log CAT bytes; encoder/button events DO log (`Button N pressed`, `Playing CW memory N`, `Encoder target -> …`).
- **Don't disturb the user's working tree:** as of handoff, the repo is on branch `claude/build-purchase-list-2gCcg` with an **uncommitted change to `docs/schematics/so2r-box/firmware/so2r_poc/so2r_poc.ino`** (a separate so2r-box project — NOT part of the bridge work). If you need to branch, use a `git worktree` off `origin/main` so you don't touch it.
- iOS can't be built in this CLI env (no Xcode). Make code changes; Xcode Cloud CI catches compile/lint; the user builds on device.

## What I want next
(Tell the new Claude what you're doing — e.g. "test #374 on the FTX-1", or "help me fix CW keying to match the app's method", or "iterate on the 3D box".)
