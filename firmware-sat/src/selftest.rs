//! Frequency-change bring-up self-test (compile with `--features freq-selftest`).
//!
//! A background poller that waits for radios to enumerate, then sweeps their
//! frequencies to prove the CAT retune path end to end — no app, BLE, or
//! schedule involved. With two radios on the hub (the full-duplex case) it
//! drives them in OPPOSITE directions: radio 0 climbs across 2 m while radio
//! 1 descends across 70 cm, in lockstep, reading each back with `FA;`. With
//! one radio it sweeps that radio's VFO A up and VFO B down instead, so a
//! single-radio bench still exercises both directions.
//!
//! Every step logs to serial; a bench operator watches the two radios' VFOs
//! move in opposite directions.

use ::log::info;

use crate::rtos;
use crate::usb::UsbHost;
use crate::verify::CatSession;

/// 2 m sweep (radio 0 / VFO A), swept upward.
const VHF_START_HZ: u64 = 145_800_000;
/// 70 cm sweep (radio 1 / VFO B), swept downward.
const UHF_START_HZ: u64 = 435_100_000;
const STEP_HZ: u64 = 20_000;
/// Steps each way; up then back down = 2 × this + 1 tunes per radio.
const STEPS: u64 = 6;
/// Dwell per step. Generous because the K1 CAT fork saves EEPROM on every
/// retune — tuning faster than it can save drives readback failures.
const DWELL_MS: u32 = 1_000;
/// Settle window after the connected-radio set stops changing.
const SETTLE_MS: u32 = 3_000;
/// Idle between full sweeps — the K1 saves EEPROM on every retune, so a rest
/// avoids thrashing its flash and lets it keep up.
const REST_MS: u32 = 20_000;

fn set_cmd(vfo: u8, hz: u64) -> Vec<u8> {
    format!("F{}{:011};", if vfo == 0 { 'A' } else { 'B' }, hz).into_bytes()
}

/// Read back one VFO and confirm it matches `expect_hz` (10 Hz resolution).
fn verify_vfo(cat: &CatSession, vfo: u8, expect_hz: u64) -> bool {
    let read: &[u8] = if vfo == 0 { b"FA;" } else { b"FB;" };
    let rx = cat.query(read, 300);
    let prefix: &[u8] = if vfo == 0 { b"FA" } else { b"FB" };
    let Some(start) = rx.windows(2).position(|w| w == prefix) else {
        info!("  readback {}: no response", if vfo == 0 { "FA" } else { "FB" });
        return false;
    };
    let mut val: u64 = 0;
    let mut any = false;
    for &byte in &rx[start + 2..] {
        match byte {
            b'0'..=b'9' => {
                val = val * 10 + u64::from(byte - b'0');
                any = true;
            }
            _ => break,
        }
    }
    let ok = any && val.abs_diff(expect_hz) < 10;
    if !ok {
        let label = if vfo == 0 { "VFO A" } else { "VFO B" };
        info!("  readback {label} = {val} Hz (expected {expect_hz})");
    }
    ok
}

/// Retries per set+readback before giving up (a dropped FA/FB happens
/// occasionally on the rapid CAT path; one resend clears it).
const MAX_TRIES: u32 = 3;

/// Set one VFO and confirm the readback, resending on mismatch.
fn set_and_verify(cat: &CatSession, vfo: u8, hz: u64) -> bool {
    let label = if vfo == 0 { "VFO A" } else { "VFO B" };
    for attempt in 1..=MAX_TRIES {
        cat.send(&set_cmd(vfo, hz));
        rtos::delay_ticks(40);
        if verify_vfo(cat, vfo, hz) {
            if attempt > 1 {
                info!("  OK {label} = {hz} Hz (after {attempt} tries)");
            } else {
                info!("  OK {label} = {hz} Hz");
            }
            return true;
        }
    }
    info!("  FAIL {label} = {hz} Hz after {MAX_TRIES} tries");
    false
}

/// Poll for radios, then sweep continuously while any stay connected. The
/// connected set is re-read each pass, so plugging in a second radio mid-run
/// switches to the two-radio sweep on the next pass.
pub fn run_loop(usb: &UsbHost) {
    info!("FREQ SELF-TEST poller armed");
    loop {
        while usb.connected_radios().is_empty() {
            rtos::delay_ticks(500);
        }
        // Let a second radio finish enumerating before the first pass.
        rtos::delay_ticks(SETTLE_MS);

        loop {
            let radios = usb.connected_radios();
            if radios.is_empty() {
                break;
            }
            run_sweep(usb, &radios);
            // Rest between sweeps. The K1 CAT fork writes EEPROM on every
            // FA/FB, so back-to-back sweeping both saturates the radio (rising
            // readback failures) and wears its flash. A gap keeps the test
            // periodic + visible without abusing the radio; poll for unplug so
            // we still notice a disconnect promptly.
            for _ in 0..(REST_MS / 500) {
                if usb.connected_radios().is_empty() {
                    break;
                }
                rtos::delay_ticks(500);
            }
        }
        info!("FREQ SELF-TEST: all radios gone — re-arming");
    }
}

/// One up-and-back sweep across `radios`, opposite directions.
fn run_sweep(usb: &UsbHost, radios: &[usize]) {
    let two = radios.len() >= 2;
    info!(
        "=== FREQ SELF-TEST: {} — {} 2m up / {} 70cm down ===",
        if two { "two radios" } else { "one radio (both VFOs)" },
        if two { "radio 0" } else { "VFO A" },
        if two { "radio 1" } else { "VFO B" },
    );

    // Mode both links to FM for a sensible display (best-effort).
    for &r in radios {
        let cat = CatSession::open(usb, r);
        cat.send(b"FR0;");
        rtos::delay_ticks(50);
        cat.send(b"MD4;");
        rtos::delay_ticks(50);
    }

    let mut pass = 0u32;
    let mut fail = 0u32;
    let ladder: Vec<u64> = (0..=STEPS).chain((0..STEPS).rev()).collect();

    for offset in ladder {
        let vhf = VHF_START_HZ + offset * STEP_HZ; // up
        let uhf = UHF_START_HZ - offset * STEP_HZ; // down (opposite)
        info!("step +{offset}: 2m -> {:.4} MHz, 70cm -> {:.4} MHz", vhf as f64 / 1e6, uhf as f64 / 1e6);

        if two {
            // Radio 0 climbs on 2m (VFO A); radio 1 descends on 70cm (VFO A).
            {
                let cat = CatSession::open(usb, radios[0]);
                if set_and_verify(&cat, 0, vhf) { pass += 1 } else { fail += 1 }
            }
            {
                let cat = CatSession::open(usb, radios[1]);
                if set_and_verify(&cat, 0, uhf) { pass += 1 } else { fail += 1 }
            }
        } else {
            // One radio: VFO A up on 2m, VFO B down on 70cm.
            let cat = CatSession::open(usb, radios[0]);
            if set_and_verify(&cat, 1, uhf) { pass += 1 } else { fail += 1 }
            if set_and_verify(&cat, 0, vhf) { pass += 1 } else { fail += 1 }
        }
        rtos::delay_ticks(DWELL_MS);
    }

    info!("=== FREQ SELF-TEST DONE: {pass} readbacks OK, {fail} failed ===");
}
