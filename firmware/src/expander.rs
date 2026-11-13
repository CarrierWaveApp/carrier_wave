//! PCAL6416A 16-bit I²C I/O expander (U5, address 0x20).
//!
//! Port assignment (see `hardware/bridge/CLAUDE.md`):
//!
//! ```text
//!   P0_0  BTN1     input, internal pull-up, switch to GND (active low)
//!   P0_1  BTN2     input
//!   P0_2  BTN3     input
//!   P0_3  ENC_SW   rotary encoder push switch, input
//!   P0_4  —        spare (was SCR_DC)
//!   P0_5  —        spare (was SCR_RST)
//!   P0_6  LED_BT   output, sinks D9 + panel BT LED  (LOW = lit)
//!   P0_7  LED_USB  output, sinks D10 + panel USB LED (LOW = lit)
//!   P1_x  —        spare, left as pulled-up inputs
//! ```
//!
//! The ESP drives the expander's ~RESET (GPIO44) high at boot; R3 keeps it
//! high while GPIO44 floats during reset. INT (GPIO8) is wired but unused —
//! the buttons task simply polls port 0 every 5 ms, which is one 2-byte
//! transaction on the shared bus.

use esp_idf_hal::gpio::{Gpio44, Output, PinDriver};
use esp_idf_sys::EspError;
use log::info;

use crate::board::{I2C_ADDR_PCAL6416A, PIN_EXP_RST};
use crate::i2c_bus::SharedI2c;

// Register map (PCAL6416A datasheet §7.1).
const REG_INPUT_PORT0: u8 = 0x00;
const REG_OUTPUT_PORT0: u8 = 0x02;
const REG_OUTPUT_PORT1: u8 = 0x03;
const REG_CONFIG_PORT0: u8 = 0x06;
const REG_CONFIG_PORT1: u8 = 0x07;
const REG_PULL_ENABLE_PORT0: u8 = 0x46;
const REG_PULL_ENABLE_PORT1: u8 = 0x47;
const REG_PULL_SELECT_PORT0: u8 = 0x48;
const REG_PULL_SELECT_PORT1: u8 = 0x49;

/// Port-0 bit positions.
pub const BIT_BTN1: u8 = 1 << 0;
pub const BIT_BTN2: u8 = 1 << 1;
pub const BIT_BTN3: u8 = 1 << 2;
pub const BIT_ENC_SW: u8 = 1 << 3;
pub const BIT_LED_BT: u8 = 1 << 6;
pub const BIT_LED_USB: u8 = 1 << 7;

/// Inputs on port 0 (1 = input in the config register).
const PORT0_INPUT_MASK: u8 = 0x3F;
/// Output pins on port 0.
const PORT0_LED_MASK: u8 = BIT_LED_BT | BIT_LED_USB;

/// Which status LED to drive.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Led {
    Bluetooth,
    Usb,
}

impl Led {
    fn bit(self) -> u8 {
        match self {
            Led::Bluetooth => BIT_LED_BT,
            Led::Usb => BIT_LED_USB,
        }
    }
}

/// Snapshot of the debounce-relevant inputs, all `true` = pressed.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Inputs {
    pub btn: [bool; 3],
    pub enc_sw: bool,
}

pub struct Expander {
    bus: SharedI2c,
    /// Shadow of the port-0 output register so LED updates are single writes.
    out0: u8,
    /// Keep the reset line driven for the life of the expander.
    _reset: PinDriver<'static, Output>,
}

impl Expander {
    /// Release the expander from reset and program the port directions,
    /// pull-ups and LED-off defaults.
    pub fn init(bus: SharedI2c, reset_pin: Gpio44<'static>) -> Result<Self, EspError> {
        let mut reset = PinDriver::output(reset_pin)?;
        reset.set_high()?;
        // t_RESET recovery is 1 µs class; give the part a comfortable margin.
        std::thread::sleep(std::time::Duration::from_millis(2));

        let mut exp = Self {
            bus,
            out0: PORT0_LED_MASK, // both LEDs off (outputs high)
            _reset: reset,
        };
        // LEDs off before the pins turn into outputs so they never flash at boot.
        exp.write_reg(REG_OUTPUT_PORT0, exp.out0)?;
        exp.write_reg(REG_OUTPUT_PORT1, 0xFF)?;
        exp.write_reg(REG_CONFIG_PORT0, PORT0_INPUT_MASK)?;
        exp.write_reg(REG_CONFIG_PORT1, 0xFF)?;
        // Internal pull-ups on every input so the spare pins don't float.
        exp.write_reg(REG_PULL_SELECT_PORT0, PORT0_INPUT_MASK)?;
        exp.write_reg(REG_PULL_SELECT_PORT1, 0xFF)?;
        exp.write_reg(REG_PULL_ENABLE_PORT0, PORT0_INPUT_MASK)?;
        exp.write_reg(REG_PULL_ENABLE_PORT1, 0xFF)?;

        info!(
            "Expander: PCAL6416A @0x{:02X} up (reset via GPIO{}; BTN1-3/ENC_SW on P0_0..3, LEDs on P0_6/7)",
            I2C_ADDR_PCAL6416A, PIN_EXP_RST
        );
        Ok(exp)
    }

    /// Read port 0 and decode the switch inputs (pulled up, pressed = low).
    pub fn read_inputs(&mut self) -> Result<Inputs, EspError> {
        let raw = self.read_reg(REG_INPUT_PORT0)?;
        Ok(Inputs {
            btn: [
                raw & BIT_BTN1 == 0,
                raw & BIT_BTN2 == 0,
                raw & BIT_BTN3 == 0,
            ],
            enc_sw: raw & BIT_ENC_SW == 0,
        })
    }

    /// Drive a status LED. `on` sinks the cathode (output low).
    pub fn set_led(&mut self, led: Led, on: bool) -> Result<(), EspError> {
        let next = if on {
            self.out0 & !led.bit()
        } else {
            self.out0 | led.bit()
        };
        if next == self.out0 {
            return Ok(());
        }
        self.write_reg(REG_OUTPUT_PORT0, next)?;
        self.out0 = next;
        Ok(())
    }

    fn write_reg(&mut self, reg: u8, value: u8) -> Result<(), EspError> {
        self.bus.write(I2C_ADDR_PCAL6416A, &[reg, value])
    }

    fn read_reg(&mut self, reg: u8) -> Result<u8, EspError> {
        let mut buf = [0u8; 1];
        self.bus.write_read(I2C_ADDR_PCAL6416A, &[reg], &mut buf)?;
        Ok(buf[0])
    }
}
