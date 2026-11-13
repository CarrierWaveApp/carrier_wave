//! WSJT-X UDP "Network Protocol" decoder.
//!
//! WSJT-X (and compatible apps: JTDX, MSHV, WSJT-Z) broadcast their state and
//! logged QSOs over UDP using Qt's `QDataStream` framing (big-endian). Loggers
//! subscribe to that stream and persist the QSOs. This module decodes the wire
//! format into typed messages; the QSO-bearing ones — [`QsoLogged`] (type 5)
//! and [`LoggedAdif`] (type 12) — are the reason CAR-277 exists.
//!
//! Fully decoded message types:
//!
//! | Type | Message      | Variant                       |
//! |------|--------------|-------------------------------|
//! | 0    | Heartbeat    | [`WsjtxMessage::Heartbeat`]   |
//! | 1    | Status       | [`WsjtxMessage::Status`]      |
//! | 2    | Decode       | [`WsjtxMessage::Decode`]      |
//! | 5    | QSO Logged   | [`WsjtxMessage::QsoLogged`]   |
//! | 6    | Close        | [`WsjtxMessage::Close`]       |
//! | 12   | Logged ADIF  | [`WsjtxMessage::LoggedAdif`]  |
//!
//! Everything else surfaces as [`WsjtxMessage::Other`] with its payload
//! skipped.
//!
//! Greenfield (no Swift counterpart). The wire layout matches the reference
//! implementations (`pywsjtx`, the WSJT-X `NetworkMessage.hpp`): every datagram
//! is `magic:u32, schema:u32, type:u32, id:utf8` followed by per-type fields.
//! Strings are a `i32` byte-length (`-1` == null) then UTF-8. Bools are one
//! byte. Times are Qt `QTime` (`ms_since_midnight:u32`) or `QDateTime`:
//! `julian_day:i64, ms_since_midnight:u32, timespec:u8 (+i32 offset when
//! timespec==2)`. Floats are IEEE-754 `f64`.
//!
//! WSJT-X has appended fields to Status and Decode over the years without
//! bumping the schema number, so those messages are decoded best-effort: once
//! the datagram ends, every remaining (later-version) field is `None` rather
//! than an error. A field that is present but cut short is still
//! [`WsjtxError::UnexpectedEof`].

use chrono::{DateTime, Duration, NaiveDate, NaiveTime, TimeZone, Utc};

/// Magic number prefixing every WSJT-X datagram.
pub const WSJTX_MAGIC: u32 = 0xadbc_cbda;

/// Default UDP port WSJT-X transmits to.
pub const WSJTX_DEFAULT_PORT: u16 = 2237;

/// Errors decoding a WSJT-X datagram.
#[derive(Debug, thiserror::Error)]
pub enum WsjtxError {
    /// Buffer ended before a field could be read.
    #[error("unexpected end of datagram")]
    UnexpectedEof,
    /// Leading magic number did not match [`WSJTX_MAGIC`].
    #[error("bad magic number: {0:#010x}")]
    BadMagic(u32),
    /// A length-prefixed string was not valid UTF-8.
    #[error("invalid utf-8 in string field")]
    InvalidUtf8,
    /// A `QDateTime` carried a julian day outside the representable range.
    #[error("julian day {0} out of range")]
    BadJulianDay(i64),
    /// A `QTime` carried more milliseconds than a day holds.
    #[error("time of day {0} ms out of range")]
    BadTime(u32),
    /// Socket error (listener only).
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
}

/// A decoded WSJT-X message. The messages relevant to logging and to
/// mirroring WSJT-X's live state are given full field structs; everything
/// else is surfaced as [`WsjtxMessage::Other`] carrying its numeric type so
/// callers can still observe it.
#[derive(Debug, Clone, PartialEq)]
pub enum WsjtxMessage {
    /// Type 0 — sent ~once per second; the handshake/keepalive.
    Heartbeat(Heartbeat),
    /// Type 1 — rig/decoder state, sent whenever something changes.
    Status(Box<Status>),
    /// Type 2 — one decoded transmission from the band-activity window.
    Decode(Decode),
    /// Type 5 — a structured logged QSO.
    QsoLogged(Box<QsoLogged>),
    /// Type 12 — the logged QSO as a full ADIF record.
    LoggedAdif(LoggedAdif),
    /// Type 6 — the client is shutting down.
    Close {
        /// Client id (e.g. `"WSJT-X"`).
        id: String,
    },
    /// Any other message type, payload skipped.
    Other {
        /// Numeric message type from the datagram.
        kind: u32,
        /// Client id.
        id: String,
    },
}

/// Type 0 Heartbeat.
#[derive(Debug, Clone, PartialEq)]
pub struct Heartbeat {
    pub id: String,
    pub max_schema_number: u32,
    pub version: String,
    pub revision: String,
}

/// Type 1 Status — WSJT-X's current rig and decoder state, in wire order.
///
/// Fields through `decoding` have been in the message since the protocol
/// shipped (WSJT-X 1.6). Everything after was appended by later releases
/// (`rx_df`…`dx_grid` 1.7, `tx_watchdog`…`fast_mode` 1.8,
/// `special_operation_mode` 2.0, `frequency_tolerance`…`configuration_name`
/// 2.1, `tx_message` 2.3) and is `None` when the sender's datagram ends
/// before it.
#[derive(Debug, Clone, PartialEq)]
pub struct Status {
    pub id: String,
    pub dial_frequency_hz: u64,
    pub mode: String,
    pub dx_call: String,
    pub report: String,
    pub tx_mode: String,
    pub tx_enabled: bool,
    pub transmitting: bool,
    pub decoding: bool,
    pub rx_df: Option<u32>,
    pub tx_df: Option<u32>,
    pub de_call: Option<String>,
    pub de_grid: Option<String>,
    pub dx_grid: Option<String>,
    pub tx_watchdog: Option<bool>,
    pub sub_mode: Option<String>,
    pub fast_mode: Option<bool>,
    /// WSJT-X special-operation enum: 0 none, 1 NA VHF, 2 EU VHF, 3 field
    /// day, 4 RTTY RU, 5 WW digi, 6 Fox, 7 Hound, 8 ARRL digi.
    pub special_operation_mode: Option<u8>,
    pub frequency_tolerance: Option<u32>,
    pub tr_period: Option<u32>,
    pub configuration_name: Option<String>,
    pub tx_message: Option<String>,
}

/// Type 2 Decode — a single decoded transmission, in wire order.
///
/// Fields through `message` have been in the message since WSJT-X 1.6;
/// `low_confidence` and `off_air` were appended later (1.8 / 2.0) and are
/// `None` when the sender's datagram ends before them.
#[derive(Debug, Clone, PartialEq)]
pub struct Decode {
    pub id: String,
    /// `true` for a fresh decode, `false` when WSJT-X is replaying its
    /// band-activity window (after a Replay request).
    pub new: bool,
    /// UTC time of day of the decoded period; `None` if WSJT-X sent a null
    /// `QTime`.
    pub time: Option<NaiveTime>,
    pub snr: i32,
    /// Time offset from the period start, in seconds.
    pub delta_time: f64,
    /// Audio frequency offset from the dial frequency, in Hz.
    pub delta_frequency: u32,
    /// WSJT-X's one-character mode tag (e.g. `"~"` for FT8, `"+"` for FT4).
    pub mode: String,
    pub message: String,
    pub low_confidence: Option<bool>,
    pub off_air: Option<bool>,
}

// Type 5 QSOLogged + type 12 LoggedADIF are plain data shared with the store
// mapping (`cw-store::wsjtx_import`, CAR-280); they are defined in `cw-domain`
// so neither crate has to depend on the other, and re-exported here unchanged.
pub use cw_domain::wsjtx::{LoggedAdif, QsoLogged};

/// Decode a single WSJT-X datagram.
pub fn decode(buf: &[u8]) -> Result<WsjtxMessage, WsjtxError> {
    let mut r = Reader::new(buf);
    let magic = r.read_u32()?;
    if magic != WSJTX_MAGIC {
        return Err(WsjtxError::BadMagic(magic));
    }
    let _schema = r.read_u32()?;
    let kind = r.read_u32()?;
    let id = r.read_string()?;

    let message = match kind {
        0 => WsjtxMessage::Heartbeat(Heartbeat {
            id,
            max_schema_number: r.read_u32()?,
            version: r.read_string()?,
            revision: r.read_string()?,
        }),
        1 => WsjtxMessage::Status(Box::new(Status {
            id,
            dial_frequency_hz: r.read_u64()?,
            mode: r.read_string()?,
            dx_call: r.read_string()?,
            report: r.read_string()?,
            tx_mode: r.read_string()?,
            tx_enabled: r.read_bool()?,
            transmitting: r.read_bool()?,
            decoding: r.read_bool()?,
            rx_df: r.read_trailing(Reader::read_u32)?,
            tx_df: r.read_trailing(Reader::read_u32)?,
            de_call: r.read_trailing(Reader::read_string)?,
            de_grid: r.read_trailing(Reader::read_string)?,
            dx_grid: r.read_trailing(Reader::read_string)?,
            tx_watchdog: r.read_trailing(Reader::read_bool)?,
            sub_mode: r.read_trailing(Reader::read_string)?,
            fast_mode: r.read_trailing(Reader::read_bool)?,
            special_operation_mode: r.read_trailing(Reader::read_u8)?,
            frequency_tolerance: r.read_trailing(Reader::read_u32)?,
            tr_period: r.read_trailing(Reader::read_u32)?,
            configuration_name: r.read_trailing(Reader::read_string)?,
            tx_message: r.read_trailing(Reader::read_string)?,
        })),
        2 => WsjtxMessage::Decode(Decode {
            id,
            new: r.read_bool()?,
            time: r.read_qtime()?,
            snr: r.read_i32()?,
            delta_time: r.read_f64()?,
            delta_frequency: r.read_u32()?,
            mode: r.read_string()?,
            message: r.read_string()?,
            low_confidence: r.read_trailing(Reader::read_bool)?,
            off_air: r.read_trailing(Reader::read_bool)?,
        }),
        5 => WsjtxMessage::QsoLogged(Box::new(QsoLogged {
            id,
            date_time_off: r.read_datetime()?,
            dx_call: r.read_string()?,
            dx_grid: r.read_string()?,
            tx_frequency_hz: r.read_u64()?,
            mode: r.read_string()?,
            report_sent: r.read_string()?,
            report_received: r.read_string()?,
            tx_power: r.read_string()?,
            comments: r.read_string()?,
            name: r.read_string()?,
            date_time_on: r.read_datetime()?,
            operator_call: r.read_string()?,
            my_call: r.read_string()?,
            my_grid: r.read_string()?,
            exchange_sent: r.read_string()?,
            exchange_received: r.read_string()?,
            adif_propagation_mode: r.read_string()?,
        })),
        6 => WsjtxMessage::Close { id },
        12 => WsjtxMessage::LoggedAdif(LoggedAdif {
            id,
            adif: r.read_string()?,
        }),
        other => WsjtxMessage::Other { kind: other, id },
    };
    Ok(message)
}

/// A bound UDP socket that receives and decodes WSJT-X datagrams.
///
/// WSJT-X transmits to a single host:port (default `127.0.0.1:2237`), or to a
/// multicast group. Bind to the address WSJT-X is configured to send to, then
/// poll [`recv`](WsjtxListener::recv) in a loop.
pub struct WsjtxListener {
    socket: tokio::net::UdpSocket,
}

impl WsjtxListener {
    /// Bind a listener to `addr`. Use `("0.0.0.0", WSJTX_DEFAULT_PORT)` for the
    /// common single-instance case, or `127.0.0.1:0` to let the OS pick a port.
    pub async fn bind<A: tokio::net::ToSocketAddrs>(addr: A) -> Result<Self, WsjtxError> {
        let socket = tokio::net::UdpSocket::bind(addr).await?;
        Ok(Self { socket })
    }

    /// The local address the listener is bound to.
    pub fn local_addr(&self) -> Result<std::net::SocketAddr, WsjtxError> {
        Ok(self.socket.local_addr()?)
    }

    /// Await the next datagram and decode it, returning the message and the
    /// sender's address. A datagram that fails to decode surfaces as `Err`;
    /// callers typically log and keep polling.
    pub async fn recv(&self) -> Result<(WsjtxMessage, std::net::SocketAddr), WsjtxError> {
        // UDP datagrams are bounded; 64 KiB covers the largest WSJT-X message.
        let mut buf = [0u8; 65_536];
        let (len, from) = self.socket.recv_from(&mut buf).await?;
        let message = decode(&buf[..len])?;
        Ok((message, from))
    }
}

/// Big-endian `QDataStream` reader over a borrowed datagram.
struct Reader<'a> {
    buf: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn new(buf: &'a [u8]) -> Self {
        Self { buf, pos: 0 }
    }

    fn take(&mut self, n: usize) -> Result<&'a [u8], WsjtxError> {
        let end = self.pos.checked_add(n).ok_or(WsjtxError::UnexpectedEof)?;
        let slice = self.buf.get(self.pos..end).ok_or(WsjtxError::UnexpectedEof)?;
        self.pos = end;
        Ok(slice)
    }

    /// `true` once every byte of the datagram has been consumed.
    fn at_end(&self) -> bool {
        self.pos >= self.buf.len()
    }

    /// Read a field appended by a later WSJT-X version: `None` if the
    /// datagram has already ended (the sender predates the field), otherwise
    /// the field itself. A field that is present but cut short still errors.
    fn read_trailing<T>(
        &mut self,
        read: impl FnOnce(&mut Self) -> Result<T, WsjtxError>,
    ) -> Result<Option<T>, WsjtxError> {
        if self.at_end() {
            Ok(None)
        } else {
            read(self).map(Some)
        }
    }

    fn read_u8(&mut self) -> Result<u8, WsjtxError> {
        Ok(self.take(1)?[0])
    }

    /// QDataStream `bool`: a single byte, non-zero == true.
    fn read_bool(&mut self) -> Result<bool, WsjtxError> {
        Ok(self.read_u8()? != 0)
    }

    fn read_u32(&mut self) -> Result<u32, WsjtxError> {
        let b = self.take(4)?;
        Ok(u32::from_be_bytes([b[0], b[1], b[2], b[3]]))
    }

    fn read_i32(&mut self) -> Result<i32, WsjtxError> {
        Ok(self.read_u32()? as i32)
    }

    fn read_u64(&mut self) -> Result<u64, WsjtxError> {
        let b = self.take(8)?;
        Ok(u64::from_be_bytes([b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7]]))
    }

    fn read_i64(&mut self) -> Result<i64, WsjtxError> {
        Ok(self.read_u64()? as i64)
    }

    /// QDataStream `double`: big-endian IEEE-754 binary64.
    fn read_f64(&mut self) -> Result<f64, WsjtxError> {
        Ok(f64::from_bits(self.read_u64()?))
    }

    /// QDataStream string: `i32` byte length (`-1` == null → empty), UTF-8 body.
    fn read_string(&mut self) -> Result<String, WsjtxError> {
        let len = self.read_i32()?;
        if len < 0 {
            return Ok(String::new());
        }
        let bytes = self.take(len as usize)?;
        std::str::from_utf8(bytes)
            .map(str::to_owned)
            .map_err(|_| WsjtxError::InvalidUtf8)
    }

    /// Qt `QTime`: ms since midnight (`u32`). `u32::MAX` is Qt's null time.
    fn read_qtime(&mut self) -> Result<Option<NaiveTime>, WsjtxError> {
        let ms = self.read_u32()?;
        if ms == u32::MAX {
            return Ok(None);
        }
        NaiveTime::from_num_seconds_from_midnight_opt(ms / 1000, (ms % 1000) * 1_000_000)
            .map(Some)
            .ok_or(WsjtxError::BadTime(ms))
    }

    /// Qt `QDateTime`: julian day (`i64`), ms since midnight (`u32`), timespec
    /// (`u8`; `2` adds an `i32` UTC-offset in seconds). Julian day `0` is null.
    fn read_datetime(&mut self) -> Result<Option<DateTime<Utc>>, WsjtxError> {
        let julian_day = self.read_i64()?;
        let ms = self.read_u32()?;
        let timespec = self.read_u8()?;
        let offset_secs = if timespec == 2 { self.read_i32()? } else { 0 };
        if timespec == 3 {
            // Qt::TimeZone: a serialized zone id we don't model — skip it.
            let _ = self.read_string()?;
        }
        if julian_day == 0 {
            return Ok(None);
        }
        let date = jdn_to_naive_date(julian_day).ok_or(WsjtxError::BadJulianDay(julian_day))?;
        let total_secs = ms / 1000;
        let milli = ms % 1000;
        let naive = date
            .and_hms_milli_opt(total_secs / 3600, (total_secs % 3600) / 60, total_secs % 60, milli)
            .ok_or(WsjtxError::BadJulianDay(julian_day))?;
        // timespec 1 = UTC, 0 = local (assume UTC), 2 = offset-from-UTC.
        let dt = Utc.from_utc_datetime(&naive) - Duration::seconds(offset_secs as i64);
        Ok(Some(dt))
    }
}

/// Convert an integer Julian Day Number to a Gregorian date
/// (Fliegel–Van Flandern). JDN 2440588 == 1970-01-01.
fn jdn_to_naive_date(jdn: i64) -> Option<NaiveDate> {
    let a = jdn + 32044;
    let b = (4 * a + 3) / 146097;
    let c = a - (146097 * b) / 4;
    let d = (4 * c + 3) / 1461;
    let e = c - (1461 * d) / 4;
    let m = (5 * e + 2) / 153;
    let day = e - (153 * m + 2) / 5 + 1;
    let month = m + 3 - 12 * (m / 10);
    let year = 100 * b + d - 4800 + m / 10;
    NaiveDate::from_ymd_opt(year as i32, month as u32, day as u32)
}

#[cfg(test)]
mod tests {
    use super::*;

    // ---- encoder helpers (independent of the decoder) --------------------

    fn put_u32(b: &mut Vec<u8>, v: u32) {
        b.extend_from_slice(&v.to_be_bytes());
    }
    fn put_u64(b: &mut Vec<u8>, v: u64) {
        b.extend_from_slice(&v.to_be_bytes());
    }
    fn put_f64(b: &mut Vec<u8>, v: f64) {
        b.extend_from_slice(&v.to_be_bytes());
    }
    fn put_bool(b: &mut Vec<u8>, v: bool) {
        b.push(u8::from(v));
    }
    fn put_string(b: &mut Vec<u8>, s: Option<&str>) {
        match s {
            None => put_u32(b, 0xffff_ffff),
            Some(s) => {
                put_u32(b, s.len() as u32);
                b.extend_from_slice(s.as_bytes());
            }
        }
    }
    fn put_datetime(b: &mut Vec<u8>, julian_day: i64, ms: u32, timespec: u8) {
        b.extend_from_slice(&julian_day.to_be_bytes());
        put_u32(b, ms);
        b.push(timespec);
    }
    fn header(kind: u32, id: &str) -> Vec<u8> {
        let mut b = Vec::new();
        put_u32(&mut b, WSJTX_MAGIC);
        put_u32(&mut b, 3); // schema
        put_u32(&mut b, kind);
        put_string(&mut b, Some(id));
        b
    }

    // ---- anchors ---------------------------------------------------------

    #[test]
    fn jdn_anchors_match_known_dates() {
        assert_eq!(jdn_to_naive_date(2440588), NaiveDate::from_ymd_opt(1970, 1, 1));
        assert_eq!(jdn_to_naive_date(2451545), NaiveDate::from_ymd_opt(2000, 1, 1));
    }

    #[test]
    fn decodes_heartbeat_from_literal_bytes() {
        // Independent reference bytes (not built by our encoder helpers).
        let bytes: &[u8] = &[
            0xad, 0xbc, 0xcb, 0xda, // magic
            0x00, 0x00, 0x00, 0x03, // schema
            0x00, 0x00, 0x00, 0x00, // type 0 = Heartbeat
            0x00, 0x00, 0x00, 0x06, b'W', b'S', b'J', b'T', b'-', b'X', // id
            0x00, 0x00, 0x00, 0x03, // max schema number
            0x00, 0x00, 0x00, 0x05, b'2', b'.', b'6', b'.', b'1', // version
            0x00, 0x00, 0x00, 0x07, b'a', b'1', b'b', b'2', b'c', b'3', b'd', // revision
        ];
        let msg = decode(bytes).unwrap();
        assert_eq!(
            msg,
            WsjtxMessage::Heartbeat(Heartbeat {
                id: "WSJT-X".into(),
                max_schema_number: 3,
                version: "2.6.1".into(),
                revision: "a1b2c3d".into(),
            })
        );
    }

    #[test]
    fn rejects_bad_magic() {
        let bytes = [0x00, 0x00, 0x00, 0x00, 0, 0, 0, 3, 0, 0, 0, 0];
        assert!(matches!(decode(&bytes), Err(WsjtxError::BadMagic(0))));
    }

    #[test]
    fn decodes_qso_logged_with_utc_times() {
        let mut b = header(5, "WSJT-X");
        put_datetime(&mut b, 2440588, 0, 1); // off: 1970-01-01T00:00:00Z (UTC)
        put_string(&mut b, Some("K2ABC"));
        put_string(&mut b, Some("FN31"));
        put_u64(&mut b, 14_074_000);
        put_string(&mut b, Some("FT8"));
        put_string(&mut b, Some("-10"));
        put_string(&mut b, Some("+05"));
        put_string(&mut b, Some("50"));
        put_string(&mut b, Some("nice qso"));
        put_string(&mut b, Some("Bob"));
        put_datetime(&mut b, 2440588, 60_000, 1); // on: 00:01:00Z
        put_string(&mut b, Some("W6JY"));
        put_string(&mut b, Some("W6JY"));
        put_string(&mut b, Some("CM87"));
        put_string(&mut b, Some(""));
        put_string(&mut b, Some(""));
        put_string(&mut b, Some(""));

        let msg = decode(&b).unwrap();
        let WsjtxMessage::QsoLogged(qso) = msg else {
            panic!("expected QsoLogged, got {msg:?}");
        };
        assert_eq!(qso.dx_call, "K2ABC");
        assert_eq!(qso.dx_grid, "FN31");
        assert_eq!(qso.tx_frequency_hz, 14_074_000);
        assert_eq!(qso.mode, "FT8");
        assert_eq!(qso.report_sent, "-10");
        assert_eq!(qso.report_received, "+05");
        assert_eq!(qso.my_call, "W6JY");
        assert_eq!(qso.my_grid, "CM87");
        assert_eq!(qso.name, "Bob");
        assert_eq!(
            qso.date_time_off,
            Some(Utc.with_ymd_and_hms(1970, 1, 1, 0, 0, 0).unwrap())
        );
        assert_eq!(
            qso.date_time_on,
            Some(Utc.with_ymd_and_hms(1970, 1, 1, 0, 1, 0).unwrap())
        );
    }

    #[test]
    fn applies_utc_offset_timespec() {
        // 2440588 / 0ms / timespec 2 with +3600s offset → 1969-12-31T23:00:00Z.
        let mut b = header(5, "X");
        b.extend_from_slice(&2440588i64.to_be_bytes());
        put_u32(&mut b, 0);
        b.push(2); // OffsetFromUTC
        put_u32(&mut b, 3600); // +1h offset
        for _ in 0..2 {
            put_string(&mut b, Some(""));
        }
        put_u64(&mut b, 0);
        for _ in 0..6 {
            put_string(&mut b, Some(""));
        }
        put_datetime(&mut b, 0, 0, 1); // null date_time_on
        for _ in 0..6 {
            put_string(&mut b, Some(""));
        }
        let WsjtxMessage::QsoLogged(qso) = decode(&b).unwrap() else {
            panic!("expected QsoLogged");
        };
        assert_eq!(
            qso.date_time_off,
            Some(Utc.with_ymd_and_hms(1969, 12, 31, 23, 0, 0).unwrap())
        );
        assert_eq!(qso.date_time_on, None);
    }

    #[test]
    fn null_string_becomes_empty() {
        let mut b = header(12, "WSJT-X");
        put_string(&mut b, None);
        let WsjtxMessage::LoggedAdif(adif) = decode(&b).unwrap() else {
            panic!("expected LoggedAdif");
        };
        assert_eq!(adif.adif, "");
    }

    #[test]
    fn decodes_logged_adif() {
        let record = "<call:5>K2ABC <mode:3>FT8 <eor>";
        let mut b = header(12, "WSJT-X");
        put_string(&mut b, Some(record));
        assert_eq!(
            decode(&b).unwrap(),
            WsjtxMessage::LoggedAdif(LoggedAdif {
                id: "WSJT-X".into(),
                adif: record.into(),
            })
        );
    }

    #[test]
    fn decodes_close() {
        let b = header(6, "WSJT-X");
        assert_eq!(
            decode(&b).unwrap(),
            WsjtxMessage::Close { id: "WSJT-X".into() }
        );
    }

    // ---- Status (type 1) -------------------------------------------------

    /// The nine fields every WSJT-X since 1.6 has sent (through `Decoding`).
    fn status_base(b: &mut Vec<u8>) {
        put_u64(b, 14_074_000); // dial frequency
        put_string(b, Some("FT8")); // mode
        put_string(b, Some("JA1ABC")); // dx call
        put_string(b, Some("-15")); // report
        put_string(b, Some("FT8")); // tx mode
        put_bool(b, true); // tx enabled
        put_bool(b, false); // transmitting
        put_bool(b, true); // decoding
    }

    #[test]
    fn decodes_full_status() {
        let mut b = header(1, "WSJT-X");
        status_base(&mut b);
        put_u32(&mut b, 1500); // rx df
        put_u32(&mut b, 1200); // tx df
        put_string(&mut b, Some("W6JY")); // de call
        put_string(&mut b, Some("CM87")); // de grid
        put_string(&mut b, Some("PM95")); // dx grid
        put_bool(&mut b, false); // tx watchdog
        put_string(&mut b, None); // sub-mode (null for FT8)
        put_bool(&mut b, false); // fast mode
        b.push(7); // special operation mode: Hound
        put_u32(&mut b, 20); // frequency tolerance
        put_u32(&mut b, 15); // T/R period
        put_string(&mut b, Some("Default")); // configuration name
        put_string(&mut b, Some("JA1ABC W6JY CM87")); // tx message

        let msg = decode(&b).unwrap();
        let WsjtxMessage::Status(status) = msg else {
            panic!("expected Status, got {msg:?}");
        };
        assert_eq!(
            *status,
            Status {
                id: "WSJT-X".into(),
                dial_frequency_hz: 14_074_000,
                mode: "FT8".into(),
                dx_call: "JA1ABC".into(),
                report: "-15".into(),
                tx_mode: "FT8".into(),
                tx_enabled: true,
                transmitting: false,
                decoding: true,
                rx_df: Some(1500),
                tx_df: Some(1200),
                de_call: Some("W6JY".into()),
                de_grid: Some("CM87".into()),
                dx_grid: Some("PM95".into()),
                tx_watchdog: Some(false),
                sub_mode: Some(String::new()),
                fast_mode: Some(false),
                special_operation_mode: Some(7),
                frequency_tolerance: Some(20),
                tr_period: Some(15),
                configuration_name: Some("Default".into()),
                tx_message: Some("JA1ABC W6JY CM87".into()),
            }
        );
    }

    #[test]
    fn status_from_original_schema_leaves_appended_fields_none() {
        // A WSJT-X 1.6-era Status ends after `Decoding`.
        let mut b = header(1, "WSJT-X");
        status_base(&mut b);

        let WsjtxMessage::Status(status) = decode(&b).unwrap() else {
            panic!("expected Status");
        };
        assert_eq!(status.dial_frequency_hz, 14_074_000);
        assert_eq!(status.dx_call, "JA1ABC");
        assert!(status.tx_enabled);
        assert!(!status.transmitting);
        assert!(status.decoding);
        assert_eq!(status.rx_df, None);
        assert_eq!(status.tx_df, None);
        assert_eq!(status.de_call, None);
        assert_eq!(status.de_grid, None);
        assert_eq!(status.dx_grid, None);
        assert_eq!(status.tx_watchdog, None);
        assert_eq!(status.sub_mode, None);
        assert_eq!(status.fast_mode, None);
        assert_eq!(status.special_operation_mode, None);
        assert_eq!(status.frequency_tolerance, None);
        assert_eq!(status.tr_period, None);
        assert_eq!(status.configuration_name, None);
        assert_eq!(status.tx_message, None);
    }

    #[test]
    fn status_stops_cleanly_at_any_appended_field_boundary() {
        // WSJT-X 1.7 appended Rx DF … DX grid; a sender of that vintage must
        // decode those and leave everything after `None`.
        let mut b = header(1, "WSJT-X");
        status_base(&mut b);
        put_u32(&mut b, 1500);
        put_u32(&mut b, 1200);
        put_string(&mut b, Some("W6JY"));
        put_string(&mut b, Some("CM87"));
        put_string(&mut b, Some("PM95"));

        let WsjtxMessage::Status(status) = decode(&b).unwrap() else {
            panic!("expected Status");
        };
        assert_eq!(status.rx_df, Some(1500));
        assert_eq!(status.dx_grid, Some("PM95".into()));
        assert_eq!(status.tx_watchdog, None);
        assert_eq!(status.tx_message, None);
    }

    #[test]
    fn status_with_partial_appended_field_errors() {
        // Two bytes of a four-byte Rx DF is corruption, not an older sender.
        let mut b = header(1, "WSJT-X");
        status_base(&mut b);
        b.extend_from_slice(&[0x00, 0x05]);
        assert!(matches!(decode(&b), Err(WsjtxError::UnexpectedEof)));
    }

    #[test]
    fn status_base_fields_are_required() {
        // Truncation inside the original field set is still an error.
        let mut b = header(1, "WSJT-X");
        put_u64(&mut b, 14_074_000);
        put_string(&mut b, Some("FT8"));
        assert!(matches!(decode(&b), Err(WsjtxError::UnexpectedEof)));
    }

    // ---- Decode (type 2) -------------------------------------------------

    #[test]
    fn decodes_decode_from_literal_bytes() {
        // Independent reference bytes (not built by our encoder helpers):
        // 12:34:56 UTC, -12 dB, dt 0.3 s, 1523 Hz, FT8 ("~"), a CQ.
        let bytes: &[u8] = &[
            0xad, 0xbc, 0xcb, 0xda, // magic
            0x00, 0x00, 0x00, 0x02, // schema
            0x00, 0x00, 0x00, 0x02, // type 2 = Decode
            0x00, 0x00, 0x00, 0x06, b'W', b'S', b'J', b'T', b'-', b'X', // id
            0x01, // new
            0x02, 0xb3, 0x29, 0x80, // time: 45_296_000 ms = 12:34:56.000
            0xff, 0xff, 0xff, 0xf4, // snr: -12
            0x3f, 0xd3, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, // delta time: 0.3
            0x00, 0x00, 0x05, 0xf3, // delta frequency: 1523
            0x00, 0x00, 0x00, 0x01, b'~', // mode
            0x00, 0x00, 0x00, 0x11, // message (17 bytes)
            b'C', b'Q', b' ', b'D', b'X', b' ', b'J', b'A', b'1', b'A', b'B', b'C', b' ',
            b'P', b'M', b'9', b'5',
            0x00, // low confidence
            0x00, // off air
        ];
        assert_eq!(
            decode(bytes).unwrap(),
            WsjtxMessage::Decode(Decode {
                id: "WSJT-X".into(),
                new: true,
                time: NaiveTime::from_hms_opt(12, 34, 56),
                snr: -12,
                delta_time: 0.3,
                delta_frequency: 1523,
                mode: "~".into(),
                message: "CQ DX JA1ABC PM95".into(),
                low_confidence: Some(false),
                off_air: Some(false),
            })
        );
    }

    #[test]
    fn decodes_decode_with_flags_set_and_fractional_time() {
        let mut b = header(2, "JTDX");
        put_bool(&mut b, false); // replayed, not new
        put_u32(&mut b, 23 * 3_600_000 + 59 * 60_000 + 45_500); // 23:59:45.500
        put_u32(&mut b, 0x0000_0003); // snr +3
        put_f64(&mut b, -0.7);
        put_u32(&mut b, 350);
        put_string(&mut b, Some("+")); // FT4
        put_string(&mut b, Some("W6JY JA1ABC R-08"));
        put_bool(&mut b, true);
        put_bool(&mut b, true);

        let WsjtxMessage::Decode(d) = decode(&b).unwrap() else {
            panic!("expected Decode");
        };
        assert_eq!(d.id, "JTDX");
        assert!(!d.new);
        assert_eq!(d.time, NaiveTime::from_hms_milli_opt(23, 59, 45, 500));
        assert_eq!(d.snr, 3);
        assert_eq!(d.delta_time, -0.7);
        assert_eq!(d.delta_frequency, 350);
        assert_eq!(d.mode, "+");
        assert_eq!(d.message, "W6JY JA1ABC R-08");
        assert_eq!(d.low_confidence, Some(true));
        assert_eq!(d.off_air, Some(true));
    }

    #[test]
    fn decode_from_original_schema_leaves_flags_none() {
        // WSJT-X 1.6/1.7 Decode ends after `Message`; a null QTime is `None`.
        let mut b = header(2, "WSJT-X");
        put_bool(&mut b, true);
        put_u32(&mut b, u32::MAX); // null QTime
        put_u32(&mut b, 0);
        put_f64(&mut b, 0.0);
        put_u32(&mut b, 1000);
        put_string(&mut b, Some("~"));
        put_string(&mut b, Some("CQ W6JY CM87"));

        let WsjtxMessage::Decode(d) = decode(&b).unwrap() else {
            panic!("expected Decode");
        };
        assert_eq!(d.time, None);
        assert_eq!(d.message, "CQ W6JY CM87");
        assert_eq!(d.low_confidence, None);
        assert_eq!(d.off_air, None);
    }

    #[test]
    fn decode_rejects_out_of_range_qtime() {
        let mut b = header(2, "WSJT-X");
        put_bool(&mut b, true);
        put_u32(&mut b, 86_400_000); // one ms past the end of the day
        assert!(matches!(decode(&b), Err(WsjtxError::BadTime(86_400_000))));
    }

    #[test]
    fn unknown_type_becomes_other() {
        let b = header(3, "WSJT-X"); // Clear — not decoded
        assert_eq!(
            decode(&b).unwrap(),
            WsjtxMessage::Other { kind: 3, id: "WSJT-X".into() }
        );
    }

    #[test]
    fn truncated_datagram_errors() {
        let bytes = [0xad, 0xbc, 0xcb]; // shorter than the magic
        assert!(matches!(decode(&bytes), Err(WsjtxError::UnexpectedEof)));
    }

    #[tokio::test]
    async fn listener_receives_and_decodes_datagram() {
        let listener = WsjtxListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let client = tokio::net::UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let datagram = header(6, "WSJT-X"); // Close
        client.send_to(&datagram, addr).await.unwrap();

        let (msg, from) = listener.recv().await.unwrap();
        assert_eq!(msg, WsjtxMessage::Close { id: "WSJT-X".into() });
        assert_eq!(from, client.local_addr().unwrap());
    }
}
