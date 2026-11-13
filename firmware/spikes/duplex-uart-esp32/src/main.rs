//! Duplex UART spike for a classic ESP32 DevKitC (ESP32-WROOM-32, 30-pin).
//!
//! Bridges the devkit's USB console (UART0, 115200) to two Quansheng UV-K5
//! CAT ports on the K1 jack (38400 8N1, 3.3 V):
//!
//! ```text
//!   radio A: UART2   TX = GPIO17 (silk TX2) -> white, 3.5 mm sleeve
//!                    RX = GPIO16 (silk RX2) <- red,   2.5 mm ring
//!   radio B: UART1   TX = GPIO27 (silk D27) -> white
//!                    RX = GPIO26 (silk D26) <- red
//!   both:    GND                             -- black, 2.5 mm sleeve
//! ```
//!
//! Console protocol (type into `screen /dev/cu.usbserial-* 115200`):
//!
//! ```text
//!   A FA;                    send "FA;" to radio A, reply printed as "A< FA00145880000;"
//!   B MD4;                   send to radio B
//!   * FA;                    send to both
//!   L 145.950 435.850        link: B follows A across an INVERTING transponder.
//!                            Centers are the VHF and UHF passband centers (either
//!                            order); A's band picks its side, B takes the other.
//!   L 145.950 435.850 norm   same, non-inverting
//!   L                        show link status
//!   L off                    stop following
//!   ?                        help
//! ```
//!
//! No BLE, no protocol framing, no Doppler: this exists to prove the jack
//! wiring, the CAT dialect, and the transponder-follow math before the real
//! transport lands.

use esp_idf_hal::delay::FreeRtos;
use esp_idf_hal::peripherals::Peripherals;
use esp_idf_hal::uart::{config::Config, UartDriver};
use esp_idf_hal::units::Hertz;

const HELP: &str = "\r\n\
duplex-uart-spike — console <-> two K1-jack CAT UARTs\r\n\
  A <cat>              send to radio A (UART2: TX GPIO17, RX GPIO16)\r\n\
  B <cat>              send to radio B (UART1: TX GPIO27, RX GPIO26)\r\n\
  * <cat>              send to both\r\n\
  L <vhf> <uhf> [norm] link: B follows A across an inverting (or non-inverting)\r\n\
                       transponder; centers in MHz or Hz, either order. A's band\r\n\
                       picks its side: A in VHF drives B in UHF and vice versa\r\n\
  L                    link status      L off   stop following\r\n\
  ?                    this help\r\n\
CAT commands end with ';' e.g.  A FA;   A FA00145880000;   B MD;\r\n\
Replies print as  A< FA00145880000;   unsolicited traffic too.\r\n\r\n";

/// Poll radio A's frequency this often while a link is active.
const LINK_POLL_TICKS: u32 = 50; // × 5 ms = 250 ms

/// `UartDriver::write` returns as soon as the TX FIFO is full, so anything
/// longer than ~128 bytes was being cut off. Push until every byte is queued.
fn write_all(uart: &UartDriver<'_>, mut bytes: &[u8]) {
    while !bytes.is_empty() {
        match uart.write(bytes) {
            Ok(0) | Err(_) => FreeRtos::delay_ms(1),
            Ok(n) => bytes = &bytes[n..],
        }
    }
}

/// Bytes from a radio are collected until ';' so each reply prints as one line.
struct RadioPort<'d> {
    name: char,
    uart: UartDriver<'d>,
    pending: Vec<u8>,
    /// Complete, printable `;`-terminated responses not yet consumed by main.
    responses: Vec<String>,
    /// Non-printable bytes swallowed since the last noise report.
    noise: usize,
    /// Number of `FA;` polls issued by the link whose replies should not be echoed.
    quiet_fa: u32,
}

impl RadioPort<'_> {
    fn send(&mut self, console: &UartDriver<'_>, cat: &[u8], echo: bool) {
        match self.uart.write(cat) {
            Ok(_) => {
                if echo {
                    write_all(console, format!("{}> {}\r\n", self.name, String::from_utf8_lossy(cat)).as_bytes());
                }
            }
            Err(err) => {
                write_all(console, format!("{}! write failed: {err:?}\r\n", self.name).as_bytes());
            }
        }
    }

    /// Drain whatever the radio has sent and print complete `;`-terminated
    /// responses.
    fn pump(&mut self, console: &UartDriver<'_>) {
        let mut buf = [0u8; 128];
        loop {
            let n = self.uart.read(&mut buf, 0).unwrap_or(0);
            if n == 0 {
                break;
            }
            for &byte in &buf[..n] {
                self.pending.push(byte);
                if byte == b';' {
                    self.flush(console);
                }
            }
        }
        if self.pending.len() > 96 {
            self.flush(console);
        }
    }

    fn flush(&mut self, console: &UartDriver<'_>) {
        if self.pending.is_empty() {
            return;
        }
        let printable = self.pending.iter().all(|b| (0x20..0x7f).contains(b));
        if printable {
            let text = String::from_utf8_lossy(&self.pending).into_owned();
            let is_quiet_fa = self.quiet_fa > 0 && text.starts_with("FA") && text.len() == 14;
            if is_quiet_fa {
                self.quiet_fa -= 1;
            } else {
                write_all(console, format!("{}< {}\r\n", self.name, text).as_bytes());
            }
            self.responses.push(text);
        } else {
            // Binary or line noise: count it instead of flooding the console.
            self.noise += self.pending.len();
        }
        self.pending.clear();
    }

    /// Summarize any non-printable bytes so a floating or mis-wired RX shows
    /// up as one line every couple of seconds instead of a flood.
    fn report_noise(&mut self, console: &UartDriver<'_>) {
        if self.noise > 0 {
            write_all(
                console,
                format!("{}< {} non-CAT bytes dropped (RX floating or mis-wired?)\r\n", self.name, self.noise)
                    .as_bytes(),
            );
            self.noise = 0;
        }
    }
}

/// VHF/UHF split used to decide which transponder side radio A is on.
const BAND_SPLIT_HZ: u64 = 300_000_000;

/// Transponder link: radio B follows radio A across the transponder.
///
/// The two centers are the transponder's VHF and UHF passband centers, in
/// either order. Whichever band A is tuned in is A's side; B takes the other,
/// so tuning A in VHF drives B in UHF and vice versa.
///
/// Inverting: f_b = center_b + (center_a − f_a), so f_a + f_b is constant.
/// Non-inverting: f_b = center_b + (f_a − center_a).
struct Link {
    active: bool,
    center_1_hz: u64,
    center_2_hz: u64,
    inverting: bool,
    last_a_hz: Option<u64>,
    last_b_hz: Option<u64>,
    ticks: u32,
}

impl Link {
    const fn idle() -> Self {
        Self {
            active: false,
            center_1_hz: 0,
            center_2_hz: 0,
            inverting: true,
            last_a_hz: None,
            last_b_hz: None,
            ticks: 0,
        }
    }

    /// (A's center, B's center) for the band A is currently in. If the two
    /// centers are on the same band the first one given is A's.
    fn centers_for(&self, a_hz: u64) -> (u64, u64) {
        let a_is_vhf = a_hz < BAND_SPLIT_HZ;
        let c1_is_vhf = self.center_1_hz < BAND_SPLIT_HZ;
        let c2_is_vhf = self.center_2_hz < BAND_SPLIT_HZ;
        if c1_is_vhf != c2_is_vhf && c2_is_vhf == a_is_vhf {
            (self.center_2_hz, self.center_1_hz)
        } else {
            (self.center_1_hz, self.center_2_hz)
        }
    }

    fn b_for(&self, a_hz: u64) -> Option<u64> {
        let (center_a, center_b) = self.centers_for(a_hz);
        let offset = i64::try_from(a_hz).ok()? - i64::try_from(center_a).ok()?;
        let b = i64::try_from(center_b).ok()? + if self.inverting { -offset } else { offset };
        u64::try_from(b).ok().map(|hz| (hz / 10) * 10)
    }

    fn status(&self) -> String {
        if !self.active {
            return "link: off\r\n".to_string();
        }
        let side = match self.last_a_hz {
            Some(a_hz) => {
                let (center_a, center_b) = self.centers_for(a_hz);
                format!("A side {} / B side {}", fmt_mhz(center_a), fmt_mhz(center_b))
            }
            None => format!("centers {} / {}", fmt_mhz(self.center_1_hz), fmt_mhz(self.center_2_hz)),
        };
        format!(
            "link: on ({}), {}, last A {} -> B {}\r\n",
            if self.inverting { "inverting" } else { "non-inverting" },
            side,
            self.last_a_hz.map(fmt_mhz).unwrap_or_else(|| "?".into()),
            self.last_b_hz.map(fmt_mhz).unwrap_or_else(|| "?".into()),
        )
    }
}

fn fmt_mhz(hz: u64) -> String {
    format!("{}.{:06}", hz / 1_000_000, hz % 1_000_000)
}

/// Parse "435.850" (MHz) or "435850000" (Hz).
fn parse_freq_hz(text: &str) -> Option<u64> {
    if let Some((whole, frac)) = text.split_once('.') {
        let whole: u64 = whole.parse().ok()?;
        let frac_digits: String = frac.chars().take(6).collect();
        if !frac_digits.chars().all(|c| c.is_ascii_digit()) {
            return None;
        }
        let frac: u64 = format!("{frac_digits:0<6}").parse().ok()?;
        Some(whole * 1_000_000 + frac)
    } else {
        text.parse().ok()
    }
}

fn parse_fa(text: &str) -> Option<u64> {
    let body = text.strip_prefix("FA")?.strip_suffix(';')?;
    if body.len() != 11 || !body.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    body.parse().ok()
}

fn main() {
    esp_idf_svc::sys::link_patches();

    let peripherals = Peripherals::take().expect("peripherals");
    let pins = peripherals.pins;

    let console_cfg = Config::new().baudrate(Hertz(115_200));
    let console = UartDriver::new(
        peripherals.uart0,
        pins.gpio1,
        pins.gpio3,
        Option::<esp_idf_hal::gpio::Gpio0>::None,
        Option::<esp_idf_hal::gpio::Gpio0>::None,
        &console_cfg,
    )
    .expect("console UART0");

    let cat_cfg = Config::new().baudrate(Hertz(38_400));
    let radio_a = UartDriver::new(
        peripherals.uart2,
        pins.gpio17,
        pins.gpio16,
        Option::<esp_idf_hal::gpio::Gpio0>::None,
        Option::<esp_idf_hal::gpio::Gpio0>::None,
        &cat_cfg,
    )
    .expect("radio A UART2");
    let radio_b = UartDriver::new(
        peripherals.uart1,
        pins.gpio27,
        pins.gpio26,
        Option::<esp_idf_hal::gpio::Gpio0>::None,
        Option::<esp_idf_hal::gpio::Gpio0>::None,
        &cat_cfg,
    )
    .expect("radio B UART1");

    // An unconnected RX pin floats and streams framing garbage; the internal
    // pull-up makes it idle high (no start bits) until a radio is wired in.
    for rx_pin in [16, 26] {
        unsafe {
            esp_idf_sys::gpio_set_pull_mode(rx_pin, esp_idf_sys::gpio_pull_mode_t_GPIO_PULLUP_ONLY);
        }
    }

    let mut radios = [
        RadioPort { name: 'A', uart: radio_a, pending: Vec::new(), responses: Vec::new(), noise: 0, quiet_fa: 0 },
        RadioPort { name: 'B', uart: radio_b, pending: Vec::new(), responses: Vec::new(), noise: 0, quiet_fa: 0 },
    ];
    let mut link = Link::idle();

    write_all(&console, HELP.as_bytes());

    // Boot-time flush. An ESP32 reset (flashing, the RESET button) lets the
    // UART TX pins float for a moment, which can feed the radios a stray
    // byte. The Quansheng parser treats 0xAB as the start of a binary
    // programming frame and swallows CAT until that frame times out, so
    // push a run of harmless terminators through, wait, and discard any
    // replies. Then prove each port with one FA poll.
    for radio in radios.iter_mut() {
        radio.send(&console, b";;;;;;;;;;;;;;;;", false);
    }
    FreeRtos::delay_ms(300);
    for radio in radios.iter_mut() {
        radio.pump(&console);
        radio.flush(&console);
        radio.responses.clear();
        radio.noise = 0;
        radio.pending.clear();
        radio.send(&console, b"FA;", false);
    }
    FreeRtos::delay_ms(300);
    for radio in radios.iter_mut() {
        radio.pump(&console);
        radio.flush(&console);
        let alive = radio.responses.iter().any(|r| parse_fa(r).is_some());
        radio.responses.clear();
        write_all(
            &console,
            format!("boot: radio {} {}\r\n", radio.name, if alive { "answered FA" } else { "silent" }).as_bytes(),
        );
    }

    let mut line: Vec<u8> = Vec::new();
    let mut idle_ticks: u32 = 0;
    loop {
        // Console input: echo, assemble a line, dispatch on CR/LF.
        let mut buf = [0u8; 64];
        if let Ok(n) = console.read(&mut buf, 0) {
            for &byte in &buf[..n] {
                match byte {
                    b'\r' | b'\n' => {
                        write_all(&console, b"\r\n");
                        dispatch(&console, &mut radios, &mut link, &line);
                        line.clear();
                    }
                    0x08 | 0x7f => {
                        if line.pop().is_some() {
                            write_all(&console, b"\x08 \x08");
                        }
                    }
                    _ => {
                        if line.len() < 200 {
                            line.push(byte);
                            write_all(&console, &[byte]);
                        }
                    }
                }
            }
        }

        // Radio output.
        for radio in radios.iter_mut() {
            radio.pump(&console);
        }

        // Transponder link: poll A, retune B when A moved.
        if link.active {
            link.ticks = link.ticks.wrapping_add(1);
            if link.ticks % LINK_POLL_TICKS == 0 {
                radios[0].quiet_fa += 1;
                radios[0].send(&console, b"FA;", false);
            }
            let a_now = radios[0].responses.drain(..).filter_map(|r| parse_fa(&r)).last();
            if let Some(a_hz) = a_now {
                if link.last_a_hz != Some(a_hz) {
                    link.last_a_hz = Some(a_hz);
                    if let Some(b_hz) = link.b_for(a_hz) {
                        if link.last_b_hz != Some(b_hz) {
                            link.last_b_hz = Some(b_hz);
                            let cmd = format!("FA{b_hz:011};");
                            radios[1].send(&console, cmd.as_bytes(), false);
                            write_all(
                                &console,
                                format!("link: A {} -> B {}\r\n", fmt_mhz(a_hz), fmt_mhz(b_hz)).as_bytes(),
                            );
                        }
                    } else {
                        write_all(&console, b"link: B frequency out of range, not tuned\r\n");
                    }
                }
            }
        } else {
            radios[0].responses.clear();
        }
        radios[1].responses.clear();

        // Flush stragglers (no ';' within ~200 ms); summarize noise every ~2 s.
        idle_ticks = idle_ticks.wrapping_add(1);
        if idle_ticks % 40 == 0 {
            for radio in radios.iter_mut() {
                radio.flush(&console);
            }
        }
        if idle_ticks % 400 == 0 {
            for radio in radios.iter_mut() {
                radio.report_noise(&console);
            }
        }

        FreeRtos::delay_ms(5);
    }
}

fn dispatch(console: &UartDriver<'_>, radios: &mut [RadioPort<'_>; 2], link: &mut Link, line: &[u8]) {
    let text = String::from_utf8_lossy(line);
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return;
    }
    if trimmed == "?" || trimmed.eq_ignore_ascii_case("help") {
        write_all(console, HELP.as_bytes());
        return;
    }
    let (target, rest) = match trimmed.split_once(char::is_whitespace) {
        Some((t, r)) => (t, r.trim()),
        None => (trimmed, ""),
    };
    match target.to_ascii_uppercase().as_str() {
        "L" | "LINK" => dispatch_link(console, link, rest),
        _ if rest.is_empty() => {
            write_all(console, b"usage: A <cat> | B <cat> | * <cat> | L ... | ?\r\n");
        }
        "A" => radios[0].send(console, rest.as_bytes(), true),
        "B" => radios[1].send(console, rest.as_bytes(), true),
        "*" => {
            radios[0].send(console, rest.as_bytes(), true);
            radios[1].send(console, rest.as_bytes(), true);
        }
        _ => {
            write_all(console, b"unknown target; use A, B, * or L\r\n");
        }
    }
}

fn dispatch_link(console: &UartDriver<'_>, link: &mut Link, args: &str) {
    let words: Vec<&str> = args.split_whitespace().collect();
    match words.as_slice() {
        [] => write_all(console, link.status().as_bytes()),
        [off] if off.eq_ignore_ascii_case("off") => {
            link.active = false;
            write_all(console, b"link: off\r\n");
        }
        [down, up, rest @ ..] => {
            let inverting = match rest {
                [] => true,
                [mode] if mode.eq_ignore_ascii_case("inv") => true,
                [mode] if mode.eq_ignore_ascii_case("norm") => false,
                _ => {
                    write_all(console, b"usage: L <vhf> <uhf> [inv|norm]\r\n");
                    return;
                }
            };
            match (parse_freq_hz(down), parse_freq_hz(up)) {
                (Some(c1_hz), Some(c2_hz)) => {
                    *link = Link {
                        active: true,
                        center_1_hz: c1_hz,
                        center_2_hz: c2_hz,
                        inverting,
                        ..Link::idle()
                    };
                    write_all(console, link.status().as_bytes());
                }
                _ => write_all(console, b"link: bad frequency; use MHz like 435.850 or Hz like 435850000\r\n"),
            }
        }
        _ => write_all(console, b"usage: L <vhf> <uhf> [inv|norm] | L off | L\r\n"),
    }
}
