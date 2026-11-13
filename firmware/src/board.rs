//! CW Bridge rev 2 PCB pin map (ESP32-S3-WROOM-1U-N16R8, `hardware/bridge/`).
//!
//! This is the single source of truth for GPIO numbers on the firmware side.
//! It must stay in lock-step with `hardware/bridge/cw_bridge.kicad_sch` and
//! the pin table in `hardware/bridge/CLAUDE.md`. Anything not listed here is
//! a no-connect on the board — do not bind it.
//!
//! ```text
//!   WROOM pin  GPIO  net          use
//!   39         1     ENC_CLK      rotary encoder phase A (native, polled)
//!   38         2     ENC_DT       rotary encoder phase B
//!   15         3     I2S_DIN      ES8388 ADC data  -> ESP
//!   5          5     I2C_SDA      shared bus: ES8388 0x10, PCAL6416A 0x20, OLED 0x3C
//!   6          6     I2C_SCL
//!   12         8     EXP_INT      PCAL6416A interrupt (open drain, unused: we poll)
//!   13/14      19/20 USB D-/D+    native USB OTG host (no GPIO config needed)
//!   27         0     BOOT         strapping pin, J14 header (firmware never touches it)
//!   32         39    I2S_BCLK
//!   33         40    I2S_LRCK
//!   34         41    DEBUG_TX     console UART TX -> J11 (set in sdkconfig.defaults)
//!   35         42    I2S_DOUT     ESP -> ES8388 DAC data
//!   37         43    I2S_MCLK     256 x fs master clock to the codec
//!   36         44    EXP_RST      PCAL6416A ~RESET (active low, R3 pull-up)
//! ```
//!
//! Slow inputs and the firmware status LEDs live on the PCAL6416A I/O
//! expander (see [`crate::expander`]): BTN1..3 = P0_0..P0_2, ENC_SW = P0_3,
//! BT LED = P0_6, USB LED = P0_7 (both sink, active low; mirrored to the
//! panel header J12 through R27/R28).
//!
//! Not on this board (the Heltec-era firmware assumed them): a VBAT ADC
//! divider, a Vext rail switch, an OLED reset line and TRS jack plug-detect
//! switches. GPIO35/36/37 belong to the module's octal PSRAM — never use them.

/// Rotary encoder phase A (native GPIO, fast edges).
pub const PIN_ENC_CLK: i32 = 1;
/// Rotary encoder phase B.
pub const PIN_ENC_DT: i32 = 2;

/// Shared I²C bus (codec + expander + OLED).
pub const PIN_I2C_SDA: i32 = 5;
pub const PIN_I2C_SCL: i32 = 6;

/// PCAL6416A interrupt output (open drain to the ESP). Currently unused —
/// the buttons task polls the expander instead.
#[allow(dead_code)]
pub const PIN_EXP_INT: i32 = 8;
/// PCAL6416A hardware reset, active low. Driven high once at boot.
pub const PIN_EXP_RST: i32 = 44;

/// I²S link to the ES8388 codec (ESP is the clock master).
pub const PIN_I2S_MCLK: i32 = 43;
pub const PIN_I2S_BCLK: i32 = 39;
pub const PIN_I2S_LRCK: i32 = 40;
pub const PIN_I2S_DOUT: i32 = 42;
pub const PIN_I2S_DIN: i32 = 3;

/// Console UART TX to the J11 debug header. Configured through
/// `CONFIG_ESP_CONSOLE_UART_TX_GPIO` in `sdkconfig.defaults`; listed here
/// only so the map is complete.
#[allow(dead_code)]
pub const PIN_DEBUG_TX: i32 = 41;

/// I²C addresses on the shared bus.
pub const I2C_ADDR_ES8388: u8 = 0x10;
pub const I2C_ADDR_PCAL6416A: u8 = 0x20;
pub const I2C_ADDR_SSD1306: u8 = 0x3C;
