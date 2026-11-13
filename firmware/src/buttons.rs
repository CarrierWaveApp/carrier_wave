//! Front-panel switches: BTN1/BTN2/BTN3 and the rotary encoder's push
//! switch, all read through the PCAL6416A I/O expander (port 0, bits 0..3).
//!
//! Polled from a dedicated thread that forwards events into the main
//! [`BridgeEvent`] channel. The switches are momentary to GND on the J4/J5/J6
//! headers and the encoder body; the expander supplies the pull-ups and the
//! firmware reads active-low. One 2-byte I²C read per poll.
//!
//! Buttons emit [`BridgeEvent::ButtonPress`] on release when held < 1 s and
//! [`BridgeEvent::ButtonLongPress`] (fired once at the threshold, while still
//! held) for ≥ 1 s holds. The release after a long-press does NOT also send a
//! short-press — that lets BTN3 toggle the on-screen Health overlay without
//! double-firing.
//!
//! The encoder switch keeps its original semantics: [`BridgeEvent::EncoderPress`]
//! or [`BridgeEvent::EncoderLongPress`] on release, depending on hold time.
//!
//! Pin map: `src/board.rs` / `src/expander.rs`.

use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex};

use log::{info, warn};

use crate::expander::{Expander, Inputs};
use crate::rtos;
use crate::BridgeEvent;

/// Poll interval in FreeRTOS ticks (≈ ms with `configTICK_RATE_HZ = 1000`).
const POLL_INTERVAL_TICKS: u32 = 5;
/// Debounce threshold in poll cycles (≈ 15 ms).
const DEBOUNCE_POLLS: u32 = 3;
/// Hold duration (poll cycles) that promotes a press into a long-press.
/// 200 cycles × 5 ms = ~1 s.
const LONG_PRESS_POLLS: u32 = 200;

/// Index of the encoder switch in the packed input arrays.
const IDX_ENC_SW: usize = 3;

/// Spawn the switch polling task.
pub fn spawn(expander: Arc<Mutex<Expander>>, tx: Sender<BridgeEvent>) {
    std::thread::Builder::new()
        .stack_size(3072)
        .name("buttons".into())
        .spawn(move || run(expander, tx))
        .expect("buttons thread spawn failed");
}

fn pack(inputs: Inputs) -> [bool; 4] {
    [inputs.btn[0], inputs.btn[1], inputs.btn[2], inputs.enc_sw]
}

fn read(expander: &Mutex<Expander>) -> Option<[bool; 4]> {
    let mut guard = expander
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    guard.read_inputs().ok().map(pack)
}

fn run(expander: Arc<Mutex<Expander>>, tx: Sender<BridgeEvent>) {
    info!("Buttons: polling BTN1-3 + ENC_SW on the PCAL6416A every {POLL_INTERVAL_TICKS} ms");

    let mut pressed: [bool; 4] = read(&expander).unwrap_or_default();
    let mut candidate = pressed;
    let mut debounce: [u32; 4] = [0; 4];
    let mut hold_polls: [u32; 4] = [0; 4];
    // `true` once we've fired a long-press for the current hold; suppresses
    // the short-press on release (buttons only — the encoder switch decides
    // on release).
    let mut long_fired: [bool; 4] = [false; 4];
    let mut read_errors: u32 = 0;

    loop {
        rtos::delay_ticks(POLL_INTERVAL_TICKS);

        let raw = match read(&expander) {
            Some(r) => {
                read_errors = 0;
                r
            }
            None => {
                read_errors = read_errors.saturating_add(1);
                if read_errors == 20 {
                    warn!(
                        "Buttons: expander reads failing (I2C) — inputs frozen until it recovers"
                    );
                }
                continue;
            }
        };

        for i in 0..4 {
            if raw[i] != candidate[i] {
                candidate[i] = raw[i];
                debounce[i] = 0;
            } else if raw[i] != pressed[i] {
                debounce[i] += 1;
                if debounce[i] >= DEBOUNCE_POLLS {
                    pressed[i] = raw[i];
                    debounce[i] = 0;
                    if pressed[i] {
                        hold_polls[i] = 0;
                        long_fired[i] = false;
                    } else if i == IDX_ENC_SW {
                        let event = if hold_polls[i] >= LONG_PRESS_POLLS {
                            BridgeEvent::EncoderLongPress
                        } else {
                            BridgeEvent::EncoderPress
                        };
                        let _ = tx.send(event);
                    } else if !long_fired[i] {
                        // Released before the long-press threshold.
                        let _ = tx.send(BridgeEvent::ButtonPress(i as u8));
                    }
                }
            }

            if pressed[i] {
                hold_polls[i] = hold_polls[i].saturating_add(1);
                if i != IDX_ENC_SW && !long_fired[i] && hold_polls[i] >= LONG_PRESS_POLLS {
                    long_fired[i] = true;
                    let _ = tx.send(BridgeEvent::ButtonLongPress(i as u8));
                }
            }
        }
    }
}
