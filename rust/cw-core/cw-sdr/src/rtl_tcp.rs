//! rtl_tcp protocol client — works with `rtl_tcp` (RTL-SDR) and compatible
//! servers such as `rsp_tcp` (SDRplay).
//!
//! Wire format: on connect the server sends a 12-byte header (`"RTL0"`, tuner
//! type u32 BE, gain count u32 BE), then streams interleaved unsigned 8-bit
//! I/Q. Commands are 5 bytes: an opcode followed by a big-endian u32 argument.

use std::io::{ErrorKind, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

use num_complex::Complex32;

use crate::error::SdrError;
use crate::source::{IqSource, SourceConfig};

pub const CMD_SET_FREQUENCY: u8 = 0x01;
pub const CMD_SET_SAMPLE_RATE: u8 = 0x02;
pub const CMD_SET_GAIN_MODE: u8 = 0x03;
pub const CMD_SET_GAIN: u8 = 0x04;
pub const CMD_SET_AGC_MODE: u8 = 0x08;
pub const CMD_SET_DIRECT_SAMPLING: u8 = 0x09;

const READ_TIMEOUT: Duration = Duration::from_millis(500);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
/// Bytes per read (8192 complex samples).
const READ_CHUNK: usize = 16_384;

/// Encode one 5-byte rtl_tcp command.
pub fn encode_command(opcode: u8, arg: u32) -> [u8; 5] {
    let be = arg.to_be_bytes();
    [opcode, be[0], be[1], be[2], be[3]]
}

/// Convert interleaved u8 I/Q to complex floats in [-1, 1].
pub fn convert_u8_iq(bytes: &[u8], out: &mut Vec<Complex32>) {
    out.extend(bytes.chunks_exact(2).map(|pair| {
        Complex32::new((f32::from(pair[0]) - 127.5) / 127.5, (f32::from(pair[1]) - 127.5) / 127.5)
    }));
}

pub struct RtlTcpSource {
    stream: TcpStream,
    sample_rate: f64,
    buf: Vec<u8>,
    /// Bytes carried over from the previous read (an unpaired I byte).
    pending: usize,
}

impl RtlTcpSource {
    pub fn connect(host: &str, port: u16, config: &SourceConfig) -> Result<Self, SdrError> {
        let addr = (host, port)
            .to_socket_addrs()?
            .next()
            .ok_or_else(|| SdrError::Config(format!("cannot resolve {host}:{port}")))?;
        let mut stream = TcpStream::connect_timeout(&addr, CONNECT_TIMEOUT)?;
        stream.set_nodelay(true)?;
        stream.set_read_timeout(Some(CONNECT_TIMEOUT))?;

        let mut header = [0u8; 12];
        stream.read_exact(&mut header)?;
        if &header[..4] != b"RTL0" {
            return Err(SdrError::Device("not an rtl_tcp server (bad header magic)".into()));
        }
        stream.set_read_timeout(Some(READ_TIMEOUT))?;

        let mut source = RtlTcpSource { stream, sample_rate: f64::from(config.sample_rate), buf: vec![0; READ_CHUNK], pending: 0 };
        source.send(CMD_SET_SAMPLE_RATE, config.sample_rate)?;
        source.send(CMD_SET_DIRECT_SAMPLING, u32::from(config.direct_sampling))?;
        match config.gain_db {
            Some(gain) => {
                source.send(CMD_SET_GAIN_MODE, 1)?;
                source.send(CMD_SET_AGC_MODE, 0)?;
                source.send(CMD_SET_GAIN, (gain * 10.0).round().max(0.0) as u32)?;
            }
            None => {
                source.send(CMD_SET_GAIN_MODE, 0)?;
                source.send(CMD_SET_AGC_MODE, 1)?;
            }
        }
        source.set_center_hz(config.center_hz)?;
        Ok(source)
    }

    fn send(&mut self, opcode: u8, arg: u32) -> Result<(), SdrError> {
        self.stream.write_all(&encode_command(opcode, arg))?;
        Ok(())
    }
}

impl IqSource for RtlTcpSource {
    fn read_block(&mut self) -> Result<Option<Vec<Complex32>>, SdrError> {
        let pending = self.pending;
        let read = match self.stream.read(&mut self.buf[pending..]) {
            Ok(0) => return Ok(None),
            Ok(n) => n,
            Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {
                return Ok(Some(Vec::new()));
            }
            Err(e) => return Err(e.into()),
        };
        let total = pending + read;
        let paired = total - total % 2;
        let mut samples = Vec::with_capacity(paired / 2);
        convert_u8_iq(&self.buf[..paired], &mut samples);
        self.buf.copy_within(paired..total, 0);
        self.pending = total - paired;
        Ok(Some(samples))
    }

    fn set_center_hz(&mut self, hz: f64) -> Result<(), SdrError> {
        if !(0.0..=f64::from(u32::MAX)).contains(&hz) {
            return Err(SdrError::Config(format!("frequency {hz} Hz out of rtl_tcp range")));
        }
        self.send(CMD_SET_FREQUENCY, hz.round() as u32)
    }

    fn sample_rate(&self) -> f64 {
        self.sample_rate
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;
    use std::thread;

    #[test]
    fn encodes_big_endian_commands() {
        assert_eq!(encode_command(CMD_SET_FREQUENCY, 8_235_000), [0x01, 0x00, 0x7D, 0xA7, 0xF8]);
    }

    #[test]
    fn converts_u8_iq_to_unit_range() {
        let mut out = Vec::new();
        convert_u8_iq(&[0, 255, 128, 127], &mut out);
        assert_eq!(out.len(), 2);
        assert!((out[0].re + 1.0).abs() < 1e-6 && (out[0].im - 1.0).abs() < 1e-6);
        assert!(out[1].re.abs() < 0.01 && out[1].im.abs() < 0.01);
    }

    #[test]
    fn handshakes_configures_and_streams() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = thread::spawn(move || {
            let (mut sock, _) = listener.accept().unwrap();
            let mut header = b"RTL0".to_vec();
            header.extend_from_slice(&5u32.to_be_bytes());
            header.extend_from_slice(&29u32.to_be_bytes());
            sock.write_all(&header).unwrap();
            // sample rate, direct sampling, gain mode, agc, gain, frequency
            let mut cmds = [0u8; 30];
            sock.read_exact(&mut cmds).unwrap();
            // Three bytes: one full sample and a dangling I byte.
            sock.write_all(&[255, 0, 128]).unwrap();
            sock.write_all(&[128]).unwrap();
            cmds
        });

        let config = SourceConfig { sample_rate: 2_048_000, center_hz: 8_235_000.0, gain_db: Some(20.0), direct_sampling: 2 };
        let mut source = RtlTcpSource::connect("127.0.0.1", port, &config).unwrap();
        let mut samples = Vec::new();
        while samples.len() < 2 {
            samples.extend(source.read_block().unwrap().unwrap());
        }
        let cmds = server.join().unwrap();
        let expected: Vec<[u8; 5]> = vec![
            encode_command(CMD_SET_SAMPLE_RATE, 2_048_000),
            encode_command(CMD_SET_DIRECT_SAMPLING, 2),
            encode_command(CMD_SET_GAIN_MODE, 1),
            encode_command(CMD_SET_AGC_MODE, 0),
            encode_command(CMD_SET_GAIN, 200),
            encode_command(CMD_SET_FREQUENCY, 8_235_000),
        ];
        assert_eq!(cmds.to_vec(), expected.concat());
        assert!((samples[0].re - 1.0).abs() < 1e-6);
        assert!(samples[1].re.abs() < 0.01);
    }

    #[test]
    fn rejects_non_rtl_server() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = thread::spawn(move || {
            let (mut sock, _) = listener.accept().unwrap();
            sock.write_all(b"HTTP/1.1 200").unwrap();
        });
        let config = SourceConfig { sample_rate: 1_000_000, center_hz: 7e6, gain_db: None, direct_sampling: 0 };
        assert!(matches!(RtlTcpSource::connect("127.0.0.1", port, &config), Err(SdrError::Device(_))));
        server.join().unwrap();
    }
}
