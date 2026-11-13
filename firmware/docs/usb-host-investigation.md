# USB Host Investigation — ESP32-P4 + FTDI FT231X

**Date:** 2026-04-19 / 2026-04-20
**Hardware:** Waveshare ESP32-P4-Module-DEV-KIT, Elecraft KXUSB cable (FTDI FT231X, VID=0x0403 PID=0x6015)
**Radio:** Elecraft KX2, 38400 baud 8N1 on ACC1 port

## Summary

The ESP32-P4's USB host cannot send data to the FTDI FT231X. Bulk OUT transfers complete successfully at the USB protocol level (correct endpoint 0x02, ESP_OK return), but the FTDI never transmits the data on its UART TX pin. The KX2 receives nothing.

The same cable works perfectly when plugged into a Mac (`screen /dev/cu.usbserial-* 38400` → `FA;` → immediate response).

## What Works

- USB device enumeration (control transfers)
- Reading USB descriptors (VID, PID, interface, endpoints)
- Bulk IN transfers (FTDI 2-byte modem/line status packets arrive every ~16ms)
- FTDI vendor requests: RESET, SET_DATA, SET_FLOW, SET_MODEM (DTR/RTS), SET_BAUD, SET_LATENCY, PURGE — all return ESP_OK
- BLE NUS (NimBLE on C6 via esp_hosted) — fully functional
- CWBP handshake between iOS app and bridge firmware
- OLED display (I2C on GPIO 7/8)

## What Doesn't Work

- **Bulk OUT data never reaches the FTDI's UART TX.** `cdc_acm_host_data_tx_blocking()` returns ESP_OK, the USB transfer completes on the correct endpoint (0x02), but the FTDI chip silently discards the payload. No serial data is transmitted to the radio.

## Peripherals Tested

### FS Peripheral (BIT(1)) — GPIO 26 (D-) / GPIO 27 (D+)

Connected via USB-A breakout board with jumper wires.

- **Enumeration:** Works
- **Bulk IN:** Works (2-byte FTDI status packets)
- **Bulk OUT:** Transfer completes (ESP_OK) but data doesn't reach UART TX
- **Wire length tested:** 8" and <1" — same result
- **FTDI init sequence tested:** Full Mac-equivalent init (RESET → SET_DATA 8N1 → SET_FLOW none → SET_MODEM DTR+RTS → SET_BAUD 38400 → SET_LATENCY 1ms → PURGE RX/TX) — no effect
- **wIndex tested:** Both 0 and 1 (FTDI port number) — no difference

### HS Peripheral (BIT(0)) — On-board USB-A Ports (via CH334F Hub)

- **Hub enumeration:** Works (with `CONFIG_USB_HOST_HUBS_SUPPORTED=y`)
- **FTDI enumeration:** Fails — "Connected device is FS, transaction translator (TT) is not supported"
- **Root cause:** CH334F is an HS hub without Transaction Translator. ESP-IDF does not implement TT (split transactions). Confirmed by Espressif in GitHub issue #17245 — no timeline for support.

### HS Peripheral (BIT(0)) — USB-C "USB" Port (Direct)

- **Result:** Same hub error — the USB-C port appears to route through the same CH334F hub, not directly to the HS peripheral. Also, the USB-C port does not provide VBUS (configured as device/sink).

## Root Cause Hypothesis

The ESP32-P4's DWC OTG FS controller may have a hardware or driver issue with bulk OUT transfers to FTDI vendor-class devices. Possible causes:

1. **DATA0/DATA1 toggle error:** The FS controller may not be correctly toggling the DATA PID on bulk OUT packets. The FTDI would NAK or discard packets with wrong toggle bits, but the host controller might still report the transfer as completed.

2. **Short packet handling:** The FS controller may be sending a zero-length packet (ZLP) after the 3-byte `FA;` payload (since 3 < 64 byte max packet size). Some FTDI firmware versions may mishandle ZLPs.

3. **Endpoint configuration mismatch:** The CDC-ACM driver's `cdc_acm_host_open_vendor_specific` may not correctly configure the bulk OUT endpoint for vendor-class devices, even though it reports the correct endpoint address (0x02).

4. **FS PHY signal integrity:** The internal FS PHY on GPIO 26/27 may have signal quality issues that corrupt bulk OUT data while keeping bulk IN (shorter packets) and control transfers functional. However, <1" wires didn't fix it, making this less likely.

## Alternatives Considered

### USB-C OTG with External VBUS
The board's USB-C "USB" port could potentially bypass the hub if connected directly to the HS peripheral — but testing showed it still routes through the hub. Even with external 5V for VBUS, this path hits the same TT limitation.

### Implementing TT in ESP-IDF
The DWC OTG hardware has `HCSPLT` registers for split transactions, but the ESP-IDF software never programs them. Implementing TT would require HCD-level changes to the split transaction state machine — non-trivial, and Espressif has no timeline.

### Powered USB Hub
A powered hub provides VBUS but introduces another hub layer, recreating the TT problem.

## Resolution (2026-04-20)

### Root Cause: `espressif/usb_host_cdc_acm` Driver Bug

The `cdc_acm_host_data_tx_blocking()` function in the `usb_host_cdc_acm` managed component silently fails for FTDI vendor-class devices on **both** ESP32-P4 and ESP32-S3. The USB transfer reports `USB_TRANSFER_STATUS_COMPLETED` with the correct byte count, but the FTDI chip never forwards the data to its UART TX pin. The same cable works perfectly when connected to a Mac.

The bug affects the CDC-ACM driver's handling of bulk OUT transfers to devices opened via `cdc_acm_host_open_vendor_specific()`. Control transfers (FTDI vendor requests) and bulk IN transfers work correctly through CDC-ACM.

### Fix: Raw USB Host Library

Bypassing the CDC-ACM driver entirely and using the raw ESP-IDF USB Host Library (`usb/usb_host.h`) fixes the issue. The working implementation:

1. Registers a USB host client with `usb_host_client_register()`
2. Opens the device with `usb_host_device_open()` and claims interface 0
3. Parses bulk endpoint addresses from the configuration descriptor
4. Submits bulk IN/OUT transfers directly via `usb_host_transfer_submit()`
5. Sends FTDI vendor requests via `usb_host_transfer_submit_control()`

The key differences from CDC-ACM:
- Device setup runs in a separate task from the event loop (avoids deadlock on control transfer completion)
- FTDI init includes SET_EVENT_CHAR (0x06) and SET_ERROR_CHAR (0x07) disable commands
- 50ms stabilization delay after full FTDI init
- The `usb_host_cdc_acm` component is no longer a dependency

### Hardware: Heltec WiFi Kit 32 v3.1 (ESP32-S3)

Ported from the Waveshare ESP32-P4 dev kit to the Heltec WiFi Kit 32 v3.1:
- ESP32-S3 has built-in BLE 5 — eliminated the ESP32-C6 companion and `esp_hosted` SDIO layer
- USB OTG on GPIO19/20 (header pins, separate from USB-C programming port via CP2102)
- Confirmed working: loopback test (FTDI TX→RX short) and Elecraft KX2 Kenwood detection

## Previous Next Steps (Superseded)

## Files Modified During Investigation

All changes committed in `d57a72a1` ("feat(bridge): add CW Bridge Protocol").

### Firmware (functional, but USB TX blocked by this issue)
- `bridge_protocol.c/h` — CWBP frame parser/builder
- `radio_detect.c/h` — Radio auto-detection state machine
- `usb_cat.c/h` — Multi-chip USB host with full FTDI init
- `main.c` — CWBP dispatch and detection wiring
- `ble_nus.c` — Renamed to "CW Bridge"
- `display.c/h` — Extended status with radio name

### iOS (functional, tested with CWBP handshake)
- `BridgeFrame.swift` — Protocol constants and frame parser
- `BridgeProtocol.swift` — Actor wrapping BLERadioTransport
- `RadioService+Bridge.swift` — Bridge event handling
- `RigProtocolDetector.swift` — Bridge ID mapping tables
- `RadioSettingsView+Sections.swift` — CW Bridge info section
