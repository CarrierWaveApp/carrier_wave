#pragma once
#ifdef __cplusplus
extern "C" {
#endif

// Bring up the P4 Full-Speed OTG (controller 1, D+/D- on GPIO 27/26) as a
// host: PHY + HAL init, port power, wait for a device to connect, reset it,
// and report the negotiated speed. Returns 0 on a detected+reset device,
// negative on failure. Phase 2 of the dual-host spike (no enumeration yet).
int fs_host_bringup(void);

// Create BOTH OTG PHYs in host mode (UTMI = peripheral 0 / High-Speed, INT =
// peripheral 1 / Full-Speed on GPIO 27/26) so the stock USB Host library can
// drive both root ports. Call once before usb_host_install() with
// skip_phy_setup = true and peripheral_map = BIT0 | BIT1. Returns 0 on
// success, negative on failure. Handles are kept alive for the process.
int usb_host_phys_bringup(void);

#ifdef __cplusplus
}
#endif
