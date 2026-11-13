//! Rotary encoder input: quadrature decode of the two phases.
//!
//! Polled from a dedicated thread that forwards events into the main
//! [`BridgeEvent`] channel. The push switch is *not* handled here on the
//! rev 2 board — it sits on the PCAL6416A expander and is polled by
//! [`crate::buttons`], which emits `EncoderPress` / `EncoderLongPress`.
//!
//! Wiring — Bourns PEC12R (SW1) soldered to the board, rotary common to GND,
//! phases on native GPIO with the ESP32-S3 internal pull-ups (fast edges
//! must not go through the I²C expander):
//! ```text
//!   A (ENC_CLK) → GPIO1
//!   B (ENC_DT)  → GPIO2
//! ```
//!
//! Mechanical encoders produce 4 quadrature transitions per detent; we
//! accumulate raw transitions and emit one [`BridgeEvent::EncoderRotate`]
//! per detent.

use std::sync::mpsc::Sender;

use esp_idf_hal::gpio::{Gpio1, Gpio2, PinDriver, Pull};
use log::info;

use crate::board::{PIN_ENC_CLK, PIN_ENC_DT};
use crate::rtos;
use crate::BridgeEvent;

/// Poll interval in FreeRTOS ticks (≈ ms with `configTICK_RATE_HZ = 1000`).
const POLL_INTERVAL_TICKS: u32 = 2;
/// Quadrature transitions per detent on a typical mechanical encoder.
const DETENT_STEPS: i32 = 4;

/// Quadrature transition table: `QUAD_DELTA[(prev << 2) | new]`.
/// +1 = CW step, -1 = CCW step, 0 = no change / invalid jump.
#[rustfmt::skip]
const QUAD_DELTA: [i8; 16] = [
    //  new=00  01   10   11
           0,  -1,   1,   0, // prev=00
           1,   0,   0,  -1, // prev=01
          -1,   0,   0,   1, // prev=10
           0,   1,  -1,   0, // prev=11
];

/// Spawn the encoder polling task. Consumes the two phase pins.
pub fn spawn(pin_clk: Gpio1<'static>, pin_dt: Gpio2<'static>, tx: Sender<BridgeEvent>) {
    std::thread::Builder::new()
        .stack_size(2048)
        .name("encoder".into())
        .spawn(move || run(pin_clk, pin_dt, tx))
        .expect("encoder thread spawn failed");
}

fn run(pin_clk: Gpio1<'static>, pin_dt: Gpio2<'static>, tx: Sender<BridgeEvent>) {
    let clk = PinDriver::input(pin_clk, Pull::Up).expect("encoder CLK input init");
    let dt = PinDriver::input(pin_dt, Pull::Up).expect("encoder DT input init");

    info!(
        "Encoder initialized on GPIO{} (CLK), GPIO{} (DT); switch via expander",
        PIN_ENC_CLK, PIN_ENC_DT
    );

    let mut prev_ab: u8 = ((clk.is_high() as u8) << 1) | (dt.is_high() as u8);
    let mut accum: i32 = 0;

    loop {
        rtos::delay_ticks(POLL_INTERVAL_TICKS);

        // Quadrature decode (CLK = channel A, DT = channel B).
        let ab: u8 = ((clk.is_high() as u8) << 1) | (dt.is_high() as u8);
        if ab != prev_ab {
            let idx = ((prev_ab as usize) << 2) | (ab as usize);
            accum += QUAD_DELTA[idx] as i32;
            prev_ab = ab;

            if accum.abs() >= DETENT_STEPS {
                let detents = accum / DETENT_STEPS;
                accum -= detents * DETENT_STEPS;
                let _ = tx.send(BridgeEvent::EncoderRotate(detents));
            }
        }
    }
}
