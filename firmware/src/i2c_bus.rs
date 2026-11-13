//! Shared I²C bus handle.
//!
//! The rev 2 board hangs three devices off one bus (ES8388 codec, PCAL6416A
//! expander, SSD1306 OLED) and they are driven from different tasks: the
//! display renders from the main loop, the expander is polled from the
//! buttons thread. `esp_idf_hal`'s `I2cDriver` is a single owner, so we wrap
//! it in an `Arc<Mutex<_>>` and hand out cheap clones. Every transaction
//! takes the mutex for its duration, so a 1 KiB OLED frame flush (~25 ms at
//! 400 kHz) delays a button poll by that much at worst — fine for human input.
//!
//! Two APIs are exposed: plain `write` / `write_read` returning `EspError`
//! for our own register-level drivers, and the `embedded_hal::i2c::I2c`
//! trait for third-party crates (the `ssd1306` driver).

use std::sync::{Arc, Mutex, MutexGuard};

use embedded_hal::i2c::{ErrorType, I2c, Operation, SevenBitAddress};
use esp_idf_hal::delay::BLOCK;
use esp_idf_hal::i2c::I2cDriver;
use esp_idf_sys::EspError;

/// Cloneable handle onto the shared bus.
#[derive(Clone)]
pub struct SharedI2c {
    inner: Arc<Mutex<I2cDriver<'static>>>,
}

impl SharedI2c {
    pub fn new(driver: I2cDriver<'static>) -> Self {
        Self {
            inner: Arc::new(Mutex::new(driver)),
        }
    }

    fn lock(&self) -> MutexGuard<'_, I2cDriver<'static>> {
        self.inner
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// Blocking write to a 7-bit address.
    pub fn write(&self, addr: u8, bytes: &[u8]) -> Result<(), EspError> {
        self.lock().write(addr, bytes, BLOCK)
    }

    /// Blocking write-then-read (repeated start) to a 7-bit address.
    pub fn write_read(&self, addr: u8, bytes: &[u8], buffer: &mut [u8]) -> Result<(), EspError> {
        self.lock().write_read(addr, bytes, buffer, BLOCK)
    }
}

impl ErrorType for SharedI2c {
    type Error = <I2cDriver<'static> as ErrorType>::Error;
}

impl I2c<SevenBitAddress> for SharedI2c {
    fn transaction(
        &mut self,
        address: SevenBitAddress,
        operations: &mut [Operation<'_>],
    ) -> Result<(), Self::Error> {
        // Fully qualified: `I2cDriver` also has an inherent 3-argument
        // `transaction(addr, ops, timeout)`, which would shadow the trait.
        <I2cDriver<'static> as I2c<SevenBitAddress>>::transaction(
            &mut *self.lock(),
            address,
            operations,
        )
    }
}
