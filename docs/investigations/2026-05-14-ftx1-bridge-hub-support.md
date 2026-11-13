# Investigation: CW Bridge Hangs When FTX-1 Plugged In

**Date:** 2026-05-14 (continued 2026-05-15, validated 2026-05-29)
**Status:** RESOLVED — hardware-validated on a Heltec WiFi Kit 32 v3.1 with an FTX-1 Optima
**Outcome:** No freeze (v5.4 + enum filter worked). FTX-1 enumerates and CAT
works end-to-end. One remaining bug — a ~3 s disconnect/reconnect loop — was
root-caused to the enum filter *aborting* the FTX-1's extra non-CAT device, and
fixed by letting such devices enumerate (unclaimed) instead of aborting them.

## Problem Statement

User reports the CW Bridge firmware crashes / freezes after the FTX-1
support fixes in commit `f23ed747`:

> "Seems like our recent fixes for the FTX-1 cause the firmware to crash,
> and not respond to USB. Nothing shows up on the serial monitor and then
> everything freezes up on the bridge and further attempts to reconnect
> over USB from computer to bridge fail."

Refined symptom after partial fixes: bridge boots fully to `Bridge
running`, idles normally with OLED + BLE healthy, then **freezes the
moment the FTX-1 is plugged into the OTG host port**. OLED dies, BLE
goes dark, no further serial output. The FTX-1's CP2105 never
enumerates — no `New USB device` or `Enum filter` log lines fire.

## Hypotheses

### Hypothesis 1: `f23ed747`'s `Mutex<VecDeque<u8>>` queue introduced a deadlock
- **Evidence for:** the freeze regression bisected to that commit; commit
  also changed `try_lock` to a blocking `lock` in the event loop.
- **Evidence against:** the freeze happens at FTX-1 plug-in, not at boot
  with nothing plugged in; the new lock is guarded by `SETUP_IN_PROGRESS`
  so dev_setup and event loop should not contend.
- **Tested:** Indirectly via the v5.4 rebuild plan — if the queue itself
  were the cause, freeze would also happen on a non-hub radio. User has
  not yet reported KX2 / FT-891 regressions on this firmware.
- **Result:** Unlikely root cause.

### Hypothesis 2: ESP-IDF hub-driver init wedges on Heltec V3.1 (no VBUS switching)
- **Evidence for:** Heltec V3.1's OTG header does not switch VBUS; hub
  drivers commonly try to drive PPWR.
- **Evidence against:** with hub support actually OFF (see H3), the freeze
  still happens — so the hub driver isn't even active.
- **Tested:** Confirmed via resolved `sdkconfig` inspection.
- **Result:** Falsified — hub driver wasn't active during the freeze.

### Hypothesis 3 (CONFIRMED): ESP-IDF version mismatch — Kconfig knobs silently dropped
- **Evidence for:** `f23ed747` enabled `CONFIG_USB_HOST_HUBS_SUPPORTED=y`
  and `CONFIG_USB_HOST_HUB_MULTI_LEVEL=y` in `sdkconfig.defaults`. Resolved
  sdkconfig at `target/.../esp-idf-sys-*/out/sdkconfig` did NOT contain
  either flag. Boot log showed `ESP-IDF: v5.2.3`. The v5.2.3 Kconfig has
  no `USB_HOST_HUBS_SUPPORTED` — only `USB_HOST_EXT_HUB_SUPPORT` (gated
  by `IDF_EXPERIMENTAL_FEATURES`, default off, marked "Feature is under
  development"). v5.4 added the stable name we used.
- **Evidence against:** none.
- **Tested:** Yes — `grep` on v5.2.3 and v5.4 Kconfig files in `.embuild`.
- **Result:** Root cause. ESP-IDF v5.2.3 has no external-hub driver
  active, so when the FTX-1 (a class-0x09 hub-class device) appears on
  the root port, the v5.2.3 enumeration path has no driver to hand the
  device to and the host stack wedges.

### Hypothesis 4: HCD-channel exhaustion (ESP32-S3 only has 8 channels)
- **Evidence for:** Even with v5.4's stable hub support, ESP-IDF Issue
  [#14831](https://github.com/espressif/esp-idf/issues/14831) documents
  channel exhaustion when multiple CDC-ACM devices sit behind a hub on
  the S3. The `hub.c` IDF-10044 TODO ("USBH devs add could failed due
  to lack of free hcd channels") is still open. The FTX-1 exposes:
  - Internal hub (~2 channels: ctrl + interrupt IN)
  - USB audio interface (1 ctrl + isoc channels if streamed)
  - CP2105 (3 channels: ctrl + bulk IN + bulk OUT — interface 0 only)
  - HRI device (~3 channels if claimed)

  Without filtering, that's 9–11 channels — over the 8 limit.
- **Evidence against:** N/A — this is the *next* hypothesis to test after
  H3 fix lands.
- **Tested:** Mitigated preemptively via `enum_filter_cb` in `cf9eb0a5`,
  which rejects everything that isn't a hub or a known CAT chip.
- **Result:** Preemptive mitigation in place; will validate on actual
  v5.4 boot with FTX-1.

## Investigation Log

### 2026-05-14 — Initial bisect & defensive fixes (`cf9eb0a5`)

Started by inspecting `f23ed747`. Identified two plausible regressions:

1. `CONFIG_USB_HOST_HUBS_SUPPORTED=y` enabling ESP-IDF's hub driver
   which has known stability issues on S3.
2. `handle_device_connected` would receive a `NEW_DEV` for the hub
   itself and try to claim it as a CAT serial device.

Researched ESP-IDF hub support state via web search + GitHub issue
review:

- [#14831](https://github.com/espressif/esp-idf/issues/14831) — S3 +
  multiple CDC-ACM behind a hub → "No more HCD channels available".
  Marked "Won't Do."
- [#14818](https://github.com/espressif/esp-idf/issues/14818) — S3 +
  multiple HID behind a hub → same channel-exhaustion path. "Won't Do."
- [#14682](https://github.com/espressif/esp-idf/issues/14682) — multi-hub
  → "Won't Do."
- `hub.c` IDF-10044 TODO is still present on master as of writing.
- v5.5 added LS-via-FS-hub support and S3 USB-Serial-JTAG fixes, but the
  channel-exhaustion recovery TODO is still open.

User then confirmed they have an FTX-1 on the bench. Proceeded with
"Option C" — keep hub support, but add the `CONFIG_USB_HOST_ENABLE_ENUM_FILTER_CALLBACK`
knob and reject all devices that aren't hubs or known CAT chips, before
the host stack burns HCD channels.

Implemented in `cf9eb0a5`:

- `enum_filter_cb` in `firmware/src/usb.rs`: returns `true` for class
  0x09 (hub) or known VID/PID in `SUPPORTED_CHIPS`, `false` otherwise.
  Sets `bConfigurationValue = 1` so we don't depend on uninitialised
  output.
- `enum_filter_cb: Some(enum_filter_cb)` wired into `usb_host_config_t`
  passed to `usb_host_install()`.
- Defensive hub-class skip in `handle_device_connected` (close + return
  early on class 0x09) so we never try to claim a hub as a CAT chip.
- `SetupInProgressGuard` Drop guard so panics or early returns in
  `handle_device_connected` can't permanently wedge the event loop with
  `SETUP_IN_PROGRESS` stuck on.
- Spawn-failure handling: clear `SETUP_IN_PROGRESS` if the dev_setup
  thread spawn returns `Err`.
- `dev_setup` stack 4096 → 8192 (hub support enables deeper USB host
  library call paths).

Build clean. User flashed and reported boot reached `Bridge running`,
then froze a second later. Crucial clarification: **freeze was
triggered by plugging in the FTX-1, not spontaneous.**

### 2026-05-14 — Discovered hub flags weren't actually applied

Inspected `target/.../esp-idf-sys-*/out/sdkconfig` (the *resolved* config
the build actually used). Only `CONFIG_USB_HOST_ENABLE_ENUM_FILTER_CALLBACK=y`
made it through; both hub flags were missing. Boot log said `ESP-IDF: v5.2.3`.
Grep on v5.2.3 Kconfig confirmed `USB_HOST_HUBS_SUPPORTED` / `USB_HOST_HUB_MULTI_LEVEL`
do not exist in that version. v5.2.3's equivalent is the experimental
`USB_HOST_EXT_HUB_SUPPORT`.

Conclusion: hub support was *never enabled* in the original `f23ed747`
build either — the bridge's freeze on FTX-1 was always v5.2.3 hitting an
unsupported hub-class device on the root port with no driver.

### 2026-05-15 — Pinned ESP-IDF to v5.4 (`8a4ad0e0`)

Added `ESP_IDF_VERSION = "v5.4"` to `firmware/.cargo/config.toml`'s
`[env]` block. esp-idf-sys 0.37 supports v5.2 / v5.3 / v5.4; default
when unpinned is v5.2.3.

First build attempt failed: stale CMake cache from v5.2.3 conflicted.
Wiped `target/.../esp-idf-sys-*/` and rebuilt.

Second build attempt failed: `Missing esp-mqtt submodule` from
`.embuild/.../esp-idf/v5.4/components/mqtt/CMakeLists.txt`. esp-idf-sys
cloned the v5.4 tree but did not run `git submodule update`. Manually
ran `git submodule update --init --recursive` inside the v5.4 clone.

Third build attempt succeeded. Verified resolved `sdkconfig` now
contains all three knobs:

```
CONFIG_USB_HOST_HUBS_SUPPORTED=y
CONFIG_USB_HOST_HUB_MULTI_LEVEL=y
CONFIG_USB_HOST_ENABLE_ENUM_FILTER_CALLBACK=y
```

**At this point we hand off to device validation.** User needs to flash
and plug in the FTX-1 to confirm the hub enumerates, the filter rejects
audio + HRI, and the CP2105 claims successfully without a freeze.

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `firmware/src/usb.rs` | Site of `f23ed747` regression | Queue + SETUP_IN_PROGRESS architecture sound; hardened in `cf9eb0a5` |
| `firmware/sdkconfig.defaults` | Where hub support is supposed to be enabled | v5.4 Kconfig names; matches now that ESP-IDF is pinned |
| `firmware/.cargo/config.toml` | Build-env knobs | Added `ESP_IDF_VERSION = "v5.4"` in `8a4ad0e0` |
| `firmware/docs/usb-host-investigation.md` | Prior P4 + S3 USB-host investigation | Existing prior art; CH334F hub on the P4 hit TT-not-supported wall |
| `target/.../esp-idf-sys-*/out/sdkconfig` | Resolved sdkconfig the build actually applies | Diagnostic — proved v5.2.3 was silently dropping v5.4 Kconfig names |
| `.embuild/espressif/esp-idf/v5.2.3/components/usb/Kconfig` | v5.2.3 hub Kconfig knobs | Only `USB_HOST_EXT_HUB_SUPPORT` (experimental); no `USB_HOST_HUBS_SUPPORTED` |
| `.embuild/espressif/esp-idf/v5.4/components/usb/Kconfig` | v5.4 hub Kconfig knobs | Stable `USB_HOST_HUBS_SUPPORTED`, `USB_HOST_HUB_MULTI_LEVEL`, downstream port config |
| `.embuild/espressif/esp-idf/v5.4/components/usb/hub.c:178` | IDF-10044 TODO | Channel-exhaustion recovery still not implemented |

## Root Cause

ESP-IDF version mismatch. `firmware/sdkconfig.defaults` used v5.4 Kconfig
names (`USB_HOST_HUBS_SUPPORTED`, `USB_HOST_HUB_MULTI_LEVEL`) but the
build was resolving to ESP-IDF v5.2.3, which doesn't recognize those
names and silently drops them. The v5.2.3 equivalent
(`USB_HOST_EXT_HUB_SUPPORT`, gated by `IDF_EXPERIMENTAL_FEATURES`) was
never enabled either. Result: hub support was completely off, and
plugging in a hub-class device wedged v5.2.3's host stack which has no
external hub driver loaded.

## Resolution (pending validation)

1. `cf9eb0a5` — defensive hardening of `usb.rs`:
   - Enum filter callback (registered, but inert in v5.2.3 where the
     surrounding hub driver wasn't loaded).
   - Hub-class skip in `handle_device_connected`.
   - SETUP_IN_PROGRESS panic-safe Drop guard.
   - dev_setup stack bump to 8192.

2. `8a4ad0e0` — ESP-IDF pin to v5.4 via `firmware/.cargo/config.toml`
   `[env] ESP_IDF_VERSION = "v5.4"`. This is the change that makes the
   hub flags + enum filter callback actually take effect.

## How to Resume This Work

Bridge is ready to flash. Pick up at "validate on hardware":

```bash
cd /Users/jsvana/projects/carrier_wave/firmware
source ~/export-esp.sh
espflash flash --monitor target/xtensa-esp32s3-espidf/debug/cw-bridge
```

Expected boot log:

- `ESP-IDF: v5.4.0` (was `v5.2.3`).
- `USB host daemon started` → `USB client task started` →
  `USB client registered, scanning for devices...`
- `Bridge running. Connect via BLE to "CW Bridge"`.

Expected on FTX-1 plug-in:

- `New USB device (addr=...)` for the FTX-1 root hub and each
  downstream device.
- `Enum filter: allow hub (...)` — radio's internal hub.
- `Enum filter: skip (... class=0x01 ...)` — USB audio interface.
- `Enum filter: skip (...)` — HRI / WIRES-X device.
- `Enum filter: allow CAT chip (VID=0x10C4 PID=0xEA70)` — CP2105.
- `USB device enumerated: VID=... class=0x09` → `Skipping USB hub ...`
  → close.
- `USB device enumerated: VID=0x10C4 PID=0xEA70 class=0x00` →
  `CP2105 matched` → `Bulk IN polling started` → `CAT link ready (CP2105)`.

### Likely failure modes from here

1. **Bridge freezes again** — almost certainly H4 (channel exhaustion)
   despite the enum filter. The filter runs *after* the device descriptor
   read, so each unsupported device still burns one control channel that
   the v5.4 hub driver may not release cleanly (IDF-10044 is still
   open). If this happens:

   - Look for repeated `New USB device (addr=N)` for the same address
     (indicates enum retry loop).
   - Try `CONFIG_USB_HOST_HW_BUFFER_BIAS_IN` to bias buffer towards IN
     endpoints.
   - Try increasing `CONFIG_USB_HOST_SET_ADDR_RECOVERY_MS` /
     `CONFIG_USB_HOST_EXT_PORT_RESET_RECOVERY_DELAY_MS`.
   - As a last resort, consider upgrading the toolchain to ESP-IDF v5.5
     (LS-via-FS-hub additions, more S3 USB fixes), though channel
     recovery is still TODO.

2. **CP2105 enumerates but `interface_claim` fails** — channel-availability
   issue. We claim interface 0; with two CP2105 interfaces present (Standard
   + Enhanced), ESP-IDF may have allocated a channel for the unclaimed
   interface during enum. Mitigation: dump the config descriptor to check
   endpoint addresses and ensure we're claiming the CAT port (Enhanced on
   FTX-1, typically interface 0).

3. **Enum filter runs but `New USB device` never fires for the hub** —
   the v5.4 hub driver didn't start. Check `dmesg`-equivalent ESP-IDF
   log for `USBH` / `HUB:` errors; check VBUS voltage on the OTG header.
   Heltec V3.1 has no VBUS switching, but the FTX-1 is self-powered so
   external VBUS shouldn't matter.

4. **Bridge boots clean, FTX-1 enumerates partially, then disconnects** —
   could be the BLE TX dropped path interfering, or insufficient power.
   Compare boot logs with and without FTX-1.

### Open follow-ups (independent of validation outcome)

- The git submodule init step in `.embuild/espressif/esp-idf/v5.4` is a
  one-time setup. Anyone else picking up this branch will need to run
  `cd firmware/.embuild/espressif/esp-idf/v5.4 && git submodule update
  --init --recursive` after `cargo build` first downloads the tree, or
  hit the `Missing esp-mqtt submodule` error. Worth a note in `firmware/CLAUDE.md`
  or `firmware/README.md` if v5.4 stays.
- `firmware/docs/usb-host-investigation.md` should be updated with v5.4
  + hub findings once we have validated behavior.

## Lessons Learned

- **Verify Kconfig flags actually applied.** Always check the resolved
  `target/.../out/sdkconfig` after a build, not just `sdkconfig.defaults`.
  Unknown Kconfig names are silently dropped on most ESP-IDF versions.
- **Pin ESP-IDF version explicitly in any project using `esp-idf-sys`.**
  The default version drifts and major USB-host APIs (especially hub
  support) gained stable names only in v5.4.
- **Distinguish "boot freeze" vs "post-init freeze" vs "plug-in freeze"
  before changing code.** The original user description ("nothing on
  serial, freezes up") read like a boot crash; the actual symptom was
  always "plug-in freeze on hub-class device". Asking the right
  clarifying questions earlier would have saved one false-start cycle.
- **ESP-IDF hub support has documented "Won't Do" channel-exhaustion bugs
  on the S3.** Even with v5.4 stable, channel math is tight (8 channels
  total). The enum filter callback is essential for hub-behind-radio
  topologies.

## 2026-05-29 — Hardware Validation (RESOLVED)

Flashed to a Heltec **WiFi Kit 32 v3.1** and plugged in an **FTX-1 Optima**
via its own USB cable into the bridge's USB-A host port.

**Result: no freeze.** The v5.4 pin + enum filter held up — H3/H4 mitigations
worked. The enumeration matched the expected sequence:

- `Enum filter: allow hub (VID=0x05E3 PID=0x0610)` — FTX-1 internal hub
  (Genesys Logic), kept enumerated, not claimed.
- `Enum filter: allow CAT chip (VID=0x10C4 PID=0xEA70)` — CP2105.
- `CP2105 matched → CAT link ready → Trying baud 38400 → Radio detected:
  ID0840 (PROTO_KENWOOD)`. `is_yaesu_id("ID0840")` is true, so 9-digit FA
  parsing is selected (correct for the FTX-1).
- CAT verified end-to-end over BLE: frequency read back correctly (set
  14.050 MHz on the dial → app displayed 14.050).

**Remaining bug found and fixed: ~3 s disconnect/reconnect loop.** Right after
detection, `EXT_HUB: Port is gone` + `Bulk IN error: status=7` fired and the
whole tree re-enumerated, repeating every ~3 s. Root cause: the FTX-1 exposes a
**third device behind its hub** — observed as both a CDC interface
(`VID=0x26AA PID=0x0030 class=0x02`) and, in other enumerations, a C-Media USB
audio codec (`VID=0x0D8C PID=0x0016`). The enum filter returned `false` for it,
which triggers ESP-IDF's **enum-abort path**; on the S3 external-hub driver the
aborted device's HCD channel is not released cleanly (the open IDF-10044 TODO),
collapsing the hub port. This is exactly "Likely failure mode #1" predicted
above — it just manifested as a reconnect loop rather than a hard freeze.

**Fix:** in `enum_filter_cb`, allow **CDC** devices (class `0x02` Communications
/ `0x0A` Data) to *enumerate* — they're still never claimed (`match_chip` fails,
so `handle_device_connected` closes them cleanly), but they're no longer
*aborted*. Clean close releases the channel; abort doesn't. Audio (`0x01`) /
HID (`0x03`) stay rejected to conserve HCD channels. After the fix: 20 s of
capture showed **1 detection, 0 `Port is gone` events** — stable link, frequency
reads correct.

> Note: this was validated on the **WiFi Kit 32 v3.1**, not the WiFi LoRa 32 V4.
> The V4 routes its single USB-C port to the ESP32-S3 native USB (GPIO19/20),
> which collides with the radio-host pins and has no spare port for the
> console — it's a poor fit for this firmware. See the `heltec-v4` branch notes.

## Related Commits

- `f23ed747` — original FTX-1 attempt that wedged the bridge.
- `cf9eb0a5` — enum filter + hub-class skip + Drop guard + 8K stack.
- `8a4ad0e0` — ESP-IDF v5.4 pin (the change that makes the rest take
  effect).
- _this branch_ — enum filter allows CDC devices to enumerate (unclaimed)
  instead of aborting them, fixing the FTX-1 reconnect loop.
