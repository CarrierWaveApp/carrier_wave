//! SSD1306 128x64 OLED display using embedded-graphics.
//!
//! CW Bridge rev 2 PCB: a 4-pin I²C OLED module on header J3
//! (GND / VCC / SCL / SDA) at address 0x3C on the shared bus (GPIO5/6).
//! The module has no reset line and is powered from +3V3 permanently.

use ::log::{info, warn};
use embedded_graphics::{
    mono_font::{
        ascii::{FONT_10X20, FONT_6X10},
        MonoTextStyle, MonoTextStyleBuilder,
    },
    pixelcolor::BinaryColor,
    prelude::*,
    primitives::{Circle, Line, PrimitiveStyle, Rectangle},
    text::{Alignment, Text},
};
use ssd1306::{mode::BufferedGraphicsMode, prelude::*, I2CDisplayInterface, Ssd1306};

use crate::board::I2C_ADDR_SSD1306;
use crate::i2c_bus::SharedI2c;
use crate::protocol::FW_VERSION_SHORT;

/// Which screen the UI is currently rendering.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DisplayView {
    #[default]
    Home,
    Menu,
    Diagnostics,
    Health,
    About,
}

/// Ordered list of menu items. Rendered positions match this order.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MenuItem {
    Diagnostics,
    Health,
    About,
    Back,
}

pub const MENU_ITEMS: [MenuItem; 4] = [
    MenuItem::Diagnostics,
    MenuItem::Health,
    MenuItem::About,
    MenuItem::Back,
];

impl MenuItem {
    fn label(&self) -> &'static str {
        match self {
            MenuItem::Diagnostics => "Diagnostics",
            MenuItem::Health => "Health",
            MenuItem::About => "About",
            MenuItem::Back => "Back",
        }
    }
}

/// Snapshot of bridge state for one frame.
pub struct DisplayState {
    pub usb_connected: bool,
    pub ble_connected: bool,
    pub ble_subscribed: bool,
    pub radio_detecting: bool,
    pub radio_detected: bool,
    pub radio_id: Option<String>,
    pub radio_name: Option<String>,
    /// TODO: render verify status indicator on OLED.
    #[allow(dead_code)]
    pub has_verify_result: bool,
    #[allow(dead_code)]
    pub last_verify_ok: bool,
    /// TODO: render jack plug status icons on OLED.
    #[allow(dead_code)]
    pub mic_plugged: bool,
    #[allow(dead_code)]
    pub phone_plugged: bool,

    // Keyer / UI state
    pub wpm: u32,
    /// Big Home-screen readout reflecting the active encoder target
    /// (e.g. `"22 WPM"` or `"AF 128"`).
    pub encoder_readout: String,
    pub cw_sending: bool,
    pub view: DisplayView,
    pub menu_selection: usize,
    /// `true` while the post-rotate WPM hint should be drawn.
    pub wpm_overlay_active: bool,

    // Diagnostics-only fields
    pub uptime_secs: u32,
    pub usb_vid: u16,
    pub usb_pid: u16,
    pub baud_rate: u32,

    // Health-only fields (BTN3 long-press)
    /// Last RSSI reported by the controller, in dBm. `None` while
    /// disconnected.
    pub rssi_dbm: Option<i8>,
    /// Free heap snapshot in bytes (current).
    pub free_heap_bytes: u32,
    /// Lowest free-heap watermark seen since boot, in bytes.
    pub min_free_heap_bytes: u32,
    /// Persistent BLE bonds in NVS.
    pub nvs_bond_count: u32,
    /// Outcome of the most recent radio auto-detect attempt. `None` until
    /// the first attempt finishes.
    pub last_detect_ok: Option<bool>,
    /// VBAT reading (millivolts) — meaningful only when `battery_present`.
    pub battery_mv: u16,
    /// Estimated state-of-charge in percent. `0` when no battery.
    pub battery_pct: u8,
    /// `true` when the firmware believes a LiPo is connected.
    pub battery_present: bool,

    /// When `Some`, the pairing prompt overrides every other view — the user
    /// needs to see the 6-digit code to complete BLE pairing on their phone.
    pub pairing_passkey: Option<u32>,
}

impl Default for DisplayState {
    fn default() -> Self {
        Self {
            usb_connected: false,
            ble_connected: false,
            ble_subscribed: false,
            radio_detecting: false,
            radio_detected: false,
            radio_id: None,
            radio_name: None,
            has_verify_result: false,
            last_verify_ok: false,
            mic_plugged: false,
            phone_plugged: false,
            wpm: 20,
            encoder_readout: String::new(),
            cw_sending: false,
            view: DisplayView::Home,
            menu_selection: 0,
            wpm_overlay_active: false,
            uptime_secs: 0,
            usb_vid: 0,
            usb_pid: 0,
            baud_rate: 0,
            rssi_dbm: None,
            free_heap_bytes: 0,
            min_free_heap_bytes: 0,
            nvs_bond_count: 0,
            last_detect_ok: None,
            battery_mv: 0,
            battery_pct: 0,
            battery_present: false,
            pairing_passkey: None,
        }
    }
}

/// OLED display wrapper.
pub struct Display {
    driver: Ssd1306<
        I2CInterface<SharedI2c>,
        DisplaySize128x64,
        BufferedGraphicsMode<DisplaySize128x64>,
    >,
}

impl Display {
    /// Configure the SSD1306 on the shared I²C bus.
    ///
    /// Returns `None` if any step fails (I2C bus error, SSD1306 init). The
    /// bridge keeps running headless — display is cosmetic; BLE and USB CAT
    /// must not be taken down by a transient I2C glitch.
    pub fn init(bus: SharedI2c) -> Option<Self> {
        // The OLED module has its own power-on reset; give it time to settle
        // before the first I2C traffic in case we boot faster than it does.
        std::thread::sleep(std::time::Duration::from_millis(100));

        let interface = I2CDisplayInterface::new_custom_address(bus, I2C_ADDR_SSD1306);
        let mut display = Ssd1306::new(interface, DisplaySize128x64, DisplayRotation::Rotate0)
            .into_buffered_graphics_mode();

        if let Err(e) = display.init() {
            warn!("display: SSD1306 init failed: {e:?} — running headless");
            return None;
        }
        display.clear_buffer();
        if let Err(e) = display.flush() {
            warn!("display: initial flush failed: {e:?} — running headless");
            let _ = display.set_display_on(false);
            return None;
        }

        info!("SSD1306 display initialized (128x64 @0x{I2C_ADDR_SSD1306:02X})");
        Some(Self { driver: display })
    }

    /// Render the current view.
    pub fn update(&mut self, state: &DisplayState) {
        let display = &mut self.driver;
        display.clear_buffer();

        let small = MonoTextStyleBuilder::new()
            .font(&FONT_6X10)
            .text_color(BinaryColor::On)
            .build();
        let big = MonoTextStyleBuilder::new()
            .font(&FONT_10X20)
            .text_color(BinaryColor::On)
            .build();

        if let Some(passkey) = state.pairing_passkey {
            render_pairing(display, passkey, &small, &big);
        } else {
            match state.view {
                DisplayView::Home => render_home(display, state, &small, &big),
                DisplayView::Menu => render_menu(display, state, &small),
                DisplayView::Diagnostics => render_diagnostics(display, state, &small),
                DisplayView::Health => render_health(display, state, &small),
                DisplayView::About => render_about(display, &small),
            }
        }

        display.flush().ok();
    }
}

// ---------------------------------------------------------------
// View renderers
// ---------------------------------------------------------------

type Target =
    Ssd1306<I2CInterface<SharedI2c>, DisplaySize128x64, BufferedGraphicsMode<DisplaySize128x64>>;

fn draw_header<D>(display: &mut D, label: &str, text_style: &MonoTextStyle<'_, BinaryColor>)
where
    D: DrawTarget<Color = BinaryColor>,
{
    Text::new(label, Point::new(2, 8), *text_style)
        .draw(display)
        .ok();
    Text::with_alignment(
        FW_VERSION_SHORT,
        Point::new(126, 8),
        *text_style,
        Alignment::Right,
    )
    .draw(display)
    .ok();
    Line::new(Point::new(0, 10), Point::new(127, 10))
        .into_styled(PrimitiveStyle::with_stroke(BinaryColor::On, 1))
        .draw(display)
        .ok();
}

fn render_home(
    display: &mut Target,
    state: &DisplayState,
    small: &MonoTextStyle<'_, BinaryColor>,
    big: &MonoTextStyle<'_, BinaryColor>,
) {
    draw_header(display, "CW BRIDGE", small);

    // Status row (y ≈ 14..24): BLE / USB / RAD
    let ble_on = state.ble_connected || state.ble_subscribed;
    draw_status_icon(display, 10, 14, "BLE", ble_on, small);
    draw_status_icon(display, 50, 14, "USB", state.usb_connected, small);
    draw_status_icon(display, 90, 14, "RAD", state.radio_detected, small);

    // Encoder readout (big, centered around y ≈ 40) — shows the active
    // encoder target's value ("22 WPM", "AF 128", …). Falls back to WPM if
    // the caller didn't populate it.
    let readout = if state.encoder_readout.is_empty() {
        format!("{} WPM", state.wpm)
    } else {
        state.encoder_readout.clone()
    };
    Text::with_alignment(&readout, Point::new(64, 46), *big, Alignment::Center)
        .draw(display)
        .ok();

    // Overlay arrows framing the WPM readout after a recent rotate.
    if state.wpm_overlay_active {
        Text::with_alignment("<", Point::new(8, 46), *big, Alignment::Left)
            .draw(display)
            .ok();
        Text::with_alignment(">", Point::new(120, 46), *big, Alignment::Right)
            .draw(display)
            .ok();
    }

    // Footer (y ≈ 54..64): radio name (left) + TX/RX flag (right).
    let radio_line = if state.radio_detected {
        state
            .radio_name
            .clone()
            .or_else(|| state.radio_id.clone())
            .unwrap_or_else(|| "radio".into())
    } else if state.radio_detecting {
        "detecting…".into()
    } else if !state.usb_connected {
        "no cable".into()
    } else {
        "no radio".into()
    };
    Text::new(truncate(&radio_line, 14), Point::new(2, 62), *small)
        .draw(display)
        .ok();

    let right = if state.cw_sending { "TX" } else { "RX" };
    Text::with_alignment(right, Point::new(126, 62), *small, Alignment::Right)
        .draw(display)
        .ok();
}

fn render_menu(display: &mut Target, state: &DisplayState, small: &MonoTextStyle<'_, BinaryColor>) {
    draw_header(display, "MENU", small);

    let base_y: i32 = 24;
    let row_h: i32 = 12;

    for (i, item) in MENU_ITEMS.iter().enumerate() {
        let y = base_y + (i as i32) * row_h;
        let selected = i == state.menu_selection;

        if selected {
            Rectangle::new(Point::new(0, y - 9), Size::new(128, 11))
                .into_styled(PrimitiveStyle::with_fill(BinaryColor::On))
                .draw(display)
                .ok();
            let inverted = MonoTextStyleBuilder::new()
                .font(&FONT_6X10)
                .text_color(BinaryColor::Off)
                .build();
            Text::new(item.label(), Point::new(8, y), inverted)
                .draw(display)
                .ok();
        } else {
            Text::new(item.label(), Point::new(8, y), *small)
                .draw(display)
                .ok();
        }
    }
}

fn render_diagnostics(
    display: &mut Target,
    state: &DisplayState,
    small: &MonoTextStyle<'_, BinaryColor>,
) {
    draw_header(display, "DIAG", small);

    let usb_line = if state.usb_connected {
        format!("USB {:04X}:{:04X}", state.usb_vid, state.usb_pid)
    } else {
        "USB —".into()
    };
    let baud_line = if state.baud_rate > 0 {
        format!("Baud {}", state.baud_rate)
    } else {
        "Baud —".into()
    };
    let ble_line = if state.ble_subscribed {
        "BLE linked"
    } else if state.ble_connected {
        "BLE connected"
    } else {
        "BLE idle"
    };

    let hh = state.uptime_secs / 3600;
    let mm = (state.uptime_secs / 60) % 60;
    let ss = state.uptime_secs % 60;
    let up_line = format!("Up {:02}:{:02}:{:02}", hh, mm, ss);

    let lines = [
        usb_line.as_str(),
        baud_line.as_str(),
        ble_line,
        up_line.as_str(),
    ];
    for (i, line) in lines.iter().enumerate() {
        let y = 22 + (i as i32) * 10;
        Text::new(line, Point::new(2, y), *small).draw(display).ok();
    }
}

fn render_health(
    display: &mut Target,
    state: &DisplayState,
    small: &MonoTextStyle<'_, BinaryColor>,
) {
    draw_header(display, "HEALTH", small);

    // Line 1: BLE link + RSSI (or "BLE idle" when disconnected).
    let ble_line = match state.rssi_dbm {
        Some(rssi) => format!("BLE {} dBm", rssi),
        None => {
            if state.ble_connected {
                "BLE linked".into()
            } else {
                "BLE idle".into()
            }
        }
    };

    // Line 2: heap (current / minimum). Render in KiB to keep it short.
    let heap_line = format!(
        "Heap {}k / {}k",
        state.free_heap_bytes / 1024,
        state.min_free_heap_bytes / 1024,
    );

    // Line 3: battery — fall back to "no batt" when the LiPo isn't
    // connected so the screen is honest about USB-only operation.
    let batt_line = if state.battery_present {
        format!(
            "Batt {:>3}%  {:.2}V",
            state.battery_pct,
            state.battery_mv as f32 / 1000.0,
        )
    } else {
        "Batt no batt".into()
    };

    // Line 4: bond count + last detect outcome — both reflect persistent
    // state that's awkward to verify any other way without a serial cable.
    let detect_text = match state.last_detect_ok {
        Some(true) => "ok",
        Some(false) => "fail",
        None => "—",
    };
    let info_line = format!("Bond {}  Det {}", state.nvs_bond_count, detect_text);

    // Line 5: USB chip + baud (when attached).
    let usb_line = if state.usb_connected {
        if state.baud_rate > 0 {
            format!("USB {:04X}@{}", state.usb_vid, state.baud_rate)
        } else {
            format!("USB {:04X}:{:04X}", state.usb_vid, state.usb_pid)
        }
    } else {
        "USB —".into()
    };

    let lines = [
        ble_line.as_str(),
        heap_line.as_str(),
        batt_line.as_str(),
        info_line.as_str(),
        usb_line.as_str(),
    ];
    for (i, line) in lines.iter().enumerate() {
        let y = 20 + (i as i32) * 9;
        Text::new(truncate(line, 21), Point::new(2, y), *small)
            .draw(display)
            .ok();
    }
}

fn render_pairing(
    display: &mut Target,
    passkey: u32,
    small: &MonoTextStyle<'_, BinaryColor>,
    big: &MonoTextStyle<'_, BinaryColor>,
) {
    draw_header(display, "PAIRING", small);

    Text::with_alignment(
        "Enter on phone:",
        Point::new(64, 26),
        *small,
        Alignment::Center,
    )
    .draw(display)
    .ok();

    let code = format!("{:06}", passkey % 1_000_000);
    Text::with_alignment(&code, Point::new(64, 50), *big, Alignment::Center)
        .draw(display)
        .ok();

    Text::with_alignment("CW Bridge", Point::new(64, 62), *small, Alignment::Center)
        .draw(display)
        .ok();
}

fn render_about(display: &mut Target, small: &MonoTextStyle<'_, BinaryColor>) {
    draw_header(display, "ABOUT", small);

    Text::with_alignment("CW Bridge", Point::new(64, 28), *small, Alignment::Center)
        .draw(display)
        .ok();
    Text::with_alignment(
        FW_VERSION_SHORT,
        Point::new(64, 42),
        *small,
        Alignment::Center,
    )
    .draw(display)
    .ok();
    Text::with_alignment(
        "carrierwave.app",
        Point::new(64, 58),
        *small,
        Alignment::Center,
    )
    .draw(display)
    .ok();
}

/// Draw a status icon with label and filled/hollow circle.
fn draw_status_icon<D>(
    display: &mut D,
    x_pos: i32,
    y_pos: i32,
    label: &str,
    active: bool,
    text_style: &MonoTextStyle<'_, BinaryColor>,
) where
    D: DrawTarget<Color = BinaryColor>,
{
    // Label above the dot
    Text::with_alignment(
        label,
        Point::new(x_pos + 10, y_pos + 8),
        *text_style,
        Alignment::Center,
    )
    .draw(display)
    .ok();

    // Dot to the right
    let circle_pos = Point::new(x_pos + 20, y_pos);
    if active {
        Circle::new(circle_pos, 6)
            .into_styled(PrimitiveStyle::with_fill(BinaryColor::On))
            .draw(display)
            .ok();
    } else {
        Circle::new(circle_pos, 6)
            .into_styled(PrimitiveStyle::with_stroke(BinaryColor::On, 1))
            .draw(display)
            .ok();
    }
}

/// Clip `s` to `max` chars (byte-safe for ASCII labels we draw).
fn truncate(s: &str, max: usize) -> &str {
    if s.len() <= max {
        s
    } else {
        &s[..max]
    }
}
