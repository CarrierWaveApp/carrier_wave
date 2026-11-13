//! Telnet DX cluster transport. Port of Sweep's `TelnetClusterClient.swift`
//! (NWConnection TCP client): connect, auto-login with the callsign, frame
//! bytes into lines, surface every line plus any parsed DX spot.
//!
//! Reconnect/backoff and the periodic `SH/WWV` + `SH/FILTER` query cycle are
//! deliberately NOT here — they belong to the engine layer (`cw-ffi`), the
//! same split as `ClusterManager` vs `TelnetClusterClient` in Swift and
//! `SdrApi` monitors vs `kiwisdr::connect`.

use std::time::{SystemTime, UNIX_EPOCH};

use cw_domain::spots::cluster_parser::{self, DxClusterSpot};
use thiserror::Error;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::mpsc;

#[derive(Debug, Error)]
pub enum ClusterError {
    #[error("connect failed: {0}")]
    Connect(String),
    #[error("not connected")]
    NotConnected,
}

/// Events emitted by an active cluster connection.
#[derive(Debug, Clone, PartialEq)]
pub enum ClusterEvent {
    /// One received line (line endings stripped, empty lines skipped).
    Line(String),
    /// A line that parsed as a DX spot (also delivered as `Line`).
    Spot(DxClusterSpot),
    /// The socket closed (server disconnect or error). No further events.
    Disconnected { reason: String },
}

enum Command {
    Send(String),
    Close,
}

/// Handle to an active cluster connection. Dropping it (or calling
/// [`ClusterConnection::disconnect`]) tears the connection down.
pub struct ClusterConnection {
    command_tx: mpsc::UnboundedSender<Command>,
}

impl ClusterConnection {
    /// Send a raw command; `\r\n` is appended (Swift `send`).
    pub fn send(&self, command: &str) -> Result<(), ClusterError> {
        self.command_tx
            .send(Command::Send(command.to_string()))
            .map_err(|_| ClusterError::NotConnected)
    }

    /// Close the connection. The event channel receives a final
    /// `Disconnected` when the socket actually closes.
    pub fn disconnect(&self) {
        let _ = self.command_tx.send(Command::Close);
    }
}

impl Drop for ClusterConnection {
    fn drop(&mut self) {
        let _ = self.command_tx.send(Command::Close);
    }
}

/// Connect to a cluster node and auto-login by sending `callsign` once the
/// socket is up (Swift `handleStateUpdate(.ready)`).
pub async fn connect(
    host: &str,
    port: u16,
    callsign: &str,
) -> Result<(ClusterConnection, mpsc::UnboundedReceiver<ClusterEvent>), ClusterError> {
    let stream = TcpStream::connect((host, port))
        .await
        .map_err(|err| ClusterError::Connect(err.to_string()))?;

    let (command_tx, mut command_rx) = mpsc::unbounded_channel::<Command>();
    let (event_tx, event_rx) = mpsc::unbounded_channel::<ClusterEvent>();

    let login = callsign.to_string();
    tokio::spawn(async move {
        let (mut reader, mut writer) = stream.into_split();

        // Auto-login with the callsign.
        if writer.write_all(format!("{login}\r\n").as_bytes()).await.is_err() {
            let _ = event_tx.send(ClusterEvent::Disconnected {
                reason: "login write failed".to_string(),
            });
            return;
        }

        let mut line_buffer = String::new();
        let mut read_buf = [0u8; 4096];
        loop {
            tokio::select! {
                command = command_rx.recv() => match command {
                    Some(Command::Send(text)) => {
                        if writer.write_all(format!("{text}\r\n").as_bytes()).await.is_err() {
                            let _ = event_tx.send(ClusterEvent::Disconnected {
                                reason: "write failed".to_string(),
                            });
                            return;
                        }
                    }
                    Some(Command::Close) | None => {
                        let _ = event_tx.send(ClusterEvent::Disconnected {
                            reason: "closed".to_string(),
                        });
                        return;
                    }
                },
                read = reader.read(&mut read_buf) => match read {
                    Ok(0) => {
                        let _ = event_tx.send(ClusterEvent::Disconnected {
                            reason: "server closed connection".to_string(),
                        });
                        return;
                    }
                    Ok(n) => {
                        line_buffer.push_str(&String::from_utf8_lossy(&read_buf[..n]));
                        drain_lines(&mut line_buffer, &event_tx);
                    }
                    Err(err) => {
                        let _ = event_tx.send(ClusterEvent::Disconnected {
                            reason: err.to_string(),
                        });
                        return;
                    }
                },
            }
        }
    });

    Ok((ClusterConnection { command_tx }, event_rx))
}

/// Split accumulated text into lines and emit events. Swift parity: prefer
/// the first `\r\n`, else the first `\r`, else the first `\n`; skip empty
/// lines; parse each line as a potential DX spot.
fn drain_lines(buffer: &mut String, event_tx: &mpsc::UnboundedSender<ClusterEvent>) {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    while let Some((start, width)) = next_line_break(buffer) {
        let line: String = buffer[..start].to_string();
        buffer.replace_range(..start + width, "");
        if line.is_empty() {
            continue;
        }
        let _ = event_tx.send(ClusterEvent::Line(line.clone()));
        if let Some(spot) = cluster_parser::parse_line(&line, now) {
            let _ = event_tx.send(ClusterEvent::Spot(spot));
        }
    }
}

fn next_line_break(buffer: &str) -> Option<(usize, usize)> {
    if let Some(idx) = buffer.find("\r\n") {
        return Some((idx, 2));
    }
    if let Some(idx) = buffer.find('\r') {
        return Some((idx, 1));
    }
    buffer.find('\n').map(|idx| (idx, 1))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn collect(events: &mut mpsc::UnboundedReceiver<ClusterEvent>) -> Vec<ClusterEvent> {
        let mut out = Vec::new();
        while let Ok(event) = events.try_recv() {
            out.push(event);
        }
        out
    }

    #[test]
    fn drain_lines_frames_and_parses_spots() {
        let (tx, mut rx) = mpsc::unbounded_channel();
        let mut buffer = String::new();

        // Partial line — nothing emitted yet.
        buffer.push_str("DX de W3LPL:      14076.0  JA1ABC");
        drain_lines(&mut buffer, &tx);
        assert!(collect(&mut rx).is_empty());

        // Completing the line emits Line + Spot.
        buffer.push_str("     FT8               1423Z\r\n");
        drain_lines(&mut buffer, &tx);
        let events = collect(&mut rx);
        assert_eq!(events.len(), 2);
        assert!(matches!(&events[0], ClusterEvent::Line(line) if line.contains("JA1ABC")));
        assert!(matches!(&events[1], ClusterEvent::Spot(spot) if spot.callsign == "JA1ABC"));
        assert!(buffer.is_empty());
    }

    #[test]
    fn drain_lines_skips_empties_and_non_spots() {
        let (tx, mut rx) = mpsc::unbounded_channel();
        let mut buffer = "login: please enter your call\r\n\r\nWWV de W0MU\n".to_string();
        drain_lines(&mut buffer, &tx);
        let events = collect(&mut rx);
        // Two non-empty lines, neither parses as a spot.
        assert_eq!(events.len(), 2);
        assert!(matches!(&events[0], ClusterEvent::Line(_)));
        assert!(matches!(&events[1], ClusterEvent::Line(_)));
    }

    #[tokio::test]
    async fn connects_logs_in_and_streams_lines() {
        use tokio::io::AsyncWriteExt as _;

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let server = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            // Expect the auto-login line.
            let mut buf = [0u8; 64];
            let n = socket.read(&mut buf).await.unwrap();
            assert_eq!(&buf[..n], b"W6JY\r\n");
            // Send a greeting and a spot, then wait for a command.
            socket
                .write_all(b"Hello W6JY\r\nDX de K3LR:       7005.5  W1AW       CW 28 WPM         0930Z\r\n")
                .await
                .unwrap();
            let n = socket.read(&mut buf).await.unwrap();
            assert_eq!(&buf[..n], b"SH/WWV\r\n");
            // Close from the server side.
        });

        let (conn, mut events) = connect(&addr.ip().to_string(), addr.port(), "W6JY")
            .await
            .unwrap();

        assert_eq!(
            events.recv().await,
            Some(ClusterEvent::Line("Hello W6JY".to_string()))
        );
        assert!(matches!(events.recv().await, Some(ClusterEvent::Line(_))));
        let spot_event = events.recv().await.unwrap();
        let ClusterEvent::Spot(spot) = spot_event else {
            panic!("expected spot event, got {spot_event:?}");
        };
        assert_eq!(spot.callsign, "W1AW");
        assert_eq!(spot.spotter, "K3LR");

        conn.send("SH/WWV").unwrap();
        server.await.unwrap();

        conn.disconnect();
        // Drain until Disconnected.
        loop {
            match events.recv().await {
                Some(ClusterEvent::Disconnected { .. }) | None => break,
                Some(_) => {}
            }
        }
    }
}
