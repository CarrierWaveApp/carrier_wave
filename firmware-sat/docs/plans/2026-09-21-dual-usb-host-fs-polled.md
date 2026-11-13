# Dual USB host on the ESP32-P4 — polled HAL host for the FS controller

Status: in progress (2026-09-21). Goal: host TWO physical UV-K1 radios at once
(2m + 70cm) for satellite doppler, with NO hub — one on each of the P4's two
USB-OTG controllers. User rejected hub + UART paths and wired the FS radio's
D+/D- to GPIO 27 (D+) / 26 (D-).

## Why the stock ESP-IDF host can't do it

- Released ESP-IDF (v5.5.x, v6.0.2) USB Host is **single-root-port**: `hub.c`
  has one `root_port_hdl` and selects the peripheral via `& BIT1`.
  `usb_host_config_t.peripheral_map` only CHOOSES which one OTG to host, not
  both. (Espressif docs: "only one can operate as a USB Host at a time… dual
  planned for a future update.")
- Worse, on the P4 the stock host does **not work on the FS controller at all**,
  even alone (`peripheral_map = BIT1`): verified on device — no enumeration.
  Root cause: `soc/esp32p4/usb_dwc_periph.c` gives controller 1 (FS)
  `irq = ETS_USB_OTG11_CH0_INTR_SOURCE` — a per-CHANNEL source, not the global
  core/port interrupt. The hcd hooks that one source and never receives the
  PORT connect interrupt, so the interrupt-driven stock host never sees the
  device. controller 0 (HS) has the full `ETS_USB_OTG_INTR_SOURCE`.

## What works: polling the HAL

The `fs_host` spike (Cargo `fs-spike` feature) brings up the FS PHY + HAL, powers
the port, and **polls** `usb_dwc_hal_port_check_if_connected` — it detects the
K1 on 27/26 (connect + reset + Full speed) every time, no interrupts. Polling
sidesteps the missing FS port interrupt entirely.

## Architecture

- **Radio 0 — HS controller (port 0):** stock ESP-IDF host (interrupt-driven,
  fully supported on controller 0), consumed by the existing `usb.rs` client
  code. `peripheral_map = BIT0`. (Physical: HS OTG connector.)
- **Radio 1 — FS controller (port 1, GPIO 27/26):** hand-rolled **polled** host
  in the `fs_host` C component, driving the DWC HAL directly (no hcd, no ISR),
  in its own FreeRTOS task. This is the new work.

The two are independent controllers with separate HAL contexts; the stock host
owns controller 0, our polled code owns controller 1. No hcd/ISR conflict
(our side never installs an ISR on controller 1).

## Phases (FS polled host)

1. **PHY + port + connect + speed** — DONE (spike Phase 1/2, on device).
2. **Enumeration (control transfers, polled):** alloc a control channel + QTD
   list (DMA mem); GET_DESCRIPTOR(device,8) at addr 0 → bMaxPacketSize0;
   SET_ADDRESS(1); GET_DESCRIPTOR(device,18) → VID/PID (expect 0x36B7:0xFFFF);
   GET_DESCRIPTOR(config) → find the CDC data interface bulk IN/OUT EPs;
   SET_CONFIGURATION(1). Control transfer = 3 QTD stages (SETUP DATA0 / DATA
   DATA1 / STATUS DATA1), poll `usb_dwc_hal_get_chan_pending_intr` +
   `usb_dwc_hal_chan_decode_intr` for CPLT/ERROR. Since the device is known
   (K1 CDC), the EP layout can be hardcoded as a fallback.
3. **Bulk CAT:** bulk OUT (write `FA…;`/`FB…;`) + bulk IN (read replies) on the
   claimed EPs, polled. Expose a C API the Rust side calls per radio.
4. **Integrate:** wire the FS polled host into `usb.rs` as radio slot 1 (the
   existing multi-radio abstraction: send/capture/verify by `radio: usize`),
   alongside the stock-host HS radio as slot 0. A poller task pumps the FS
   host and emits the same per-radio BridgeEvents.
5. **Doppler run:** confirm the sat executor drives FB/FA on both radios.

## Phase 3 status (2026-09-21): WALL — channel enables but transfer never executes

Built a polled control-transfer engine in `fs_host.c` (3-stage SETUP/DATA/STATUS
QTD sequence mirroring `hcd_dwc.c` `_buffer_fill_ctrl` + `_buffer_exec_cont`).
Everything configures without error and is verified on device:
- PHY, port power, connect, reset, **PORT_ENABLED decoded** (polled — no ISR),
  `usb_dwc_hal_port_enable()` → SG-DMA on (`descdma=1`), FSLS clock correct
  (`hsphy_type=0`, `hfir=0xbb80`=48000=FS 1 ms frame).
- `usb_dwc_hal_set_fifo_config` (balanced, 256-line DFIFO), `set_frame_list`
  (32 entries, 512-aligned) + `periodic_enable`, `chan_alloc` (sets HAINTMSK +
  HCINTMSK), `set_ep_char` (CTRL, ep0, mps8→updated, addr0→1).
- QTD list allocated **512-byte aligned** (USB_DWC_QTD_LIST_MEM_ALIGN — a 64-byte
  align was an early bug), data buf cache-aligned; `esp_cache_msync` C2M before,
  M2C after.
- `chan_activate` runs; **`hcchar.chena=1`** confirmed (channel enabled).

**Symptom:** the SETUP stage never completes. Direct probe of the channel's own
`HCINT` register (bypassing GINTSTS/HAINT) = `0x00000000` and `chena` stays 1 for
the full 1 s timeout. GINTSTS is also empty the whole time (`decode_intr` only
returns NONE). So the SG-DMA engine **enables the channel but never fetches/runs
the QTD** — a data-path/scheduling failure, not interrupt visibility.

**Ruled out:** QTD alignment, port-enable/SG-DMA/FSLS-clock/frame-interval, FIFO,
frame list + periodic enable, SCHED_INFO=0xFF (done in `chan_activate`), HCCHAR.MC
(that `mc` field is `dieptsiz` = device mode, irrelevant to host).

**Remaining unknowns (untested):** SG-DMA non-periodic request-queue scheduling
internals on the FS controller; whether the FS controller (OTG1.1) needs
interrupt-driven servicing that polling can't stand in for; P4 FS-controller
silicon errata; DMA reachability/address translation for the QTD memory. This is
original bring-up of an officially-unshipped controller path.

**Options at the wall:** (1) keep grinding the hand-roll (diminishing returns);
(2) USB hub on the HS controller — works today, zero new firmware; (3) park until
Espressif ships FS/dual host (on master, not released).

## Notes / gotchas

- IDF pinned to **v5.5.1** (peripheral_map exists; v5.5.4 bootloader
  illegal-instructions at entry on this P4 rev v1.3; v5.5.5 breaks esp-idf-hal
  0.46.2). Flash bootloader+parttable from the build (bootloader @ 0x2000).
- esp-idf-sys won't recompile a changed `components/fs_host` C file
  incrementally — nuke `target/*/build/esp-idf-sys-*` to force it.
- DWC HAL port fns are static-inline → all HAL work stays in C (`fs_host`),
  Rust calls via `extern "C"`.
- See memory [[project-p4-dual-usb-host]].
