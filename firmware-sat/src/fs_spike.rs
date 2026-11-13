//! Dual-USB-host spike driver. The actual FS-controller bring-up lives in the
//! `fs_host` C component (`components/fs_host/fs_host.c`) because the DWC HAL
//! port API is static-inline and invisible to Rust bindgen. This just invokes
//! it and reports. Runs standalone (BLE + HS host disabled) so the FS
//! controller is isolated during bring-up.

use ::log::info;

extern "C" {
    fn fs_host_bringup() -> core::ffi::c_int;
}

/// Blocking — call from `main` when the `fs-spike` feature is on. Never returns.
pub fn run() -> ! {
    info!("=== FS-USB SPIKE: bringing up the Full-Speed OTG on GPIO 27/26 ===");
    // SAFETY: single call into the C FS-host bring-up; it owns the FS OTG.
    let rc = unsafe { fs_host_bringup() };
    if rc == 0 {
        info!("FS-USB SPIKE: bring-up returned OK");
    } else {
        info!("FS-USB SPIKE: bring-up failed (rc={rc})");
    }
    loop {
        crate::rtos::delay_ticks(5_000);
    }
}
