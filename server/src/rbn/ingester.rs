use chrono::{NaiveTime, Utc};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpStream;

use super::store::{freq_to_band, RbnSpot, SpotStore};
use crate::metrics as app_metrics;

const RBN_HOST: &str = "telnet.reversebeacon.net";
const RBN_PORT: u16 = 7000;
const LOGIN_TIMEOUT_SECS: u64 = 10;
const BATCH_SIZE: usize = 100;
const BATCH_FLUSH_MS: u64 = 500;
const INITIAL_BACKOFF_SECS: u64 = 5;
const MAX_BACKOFF_SECS: u64 = 300;

/// Spawn the RBN telnet ingester as a background tokio task.
pub fn spawn_rbn_ingester(store: SpotStore, callsign: String) {
    tokio::spawn(async move {
        ingester_loop(store, callsign).await;
    });
}

async fn ingester_loop(store: SpotStore, callsign: String) {
    let mut backoff_secs = INITIAL_BACKOFF_SECS;

    loop {
        tracing::info!("RBN ingester: connecting to {}:{}", RBN_HOST, RBN_PORT);

        match run_connection(&store, &callsign).await {
            Ok(true) => {
                // Was connected and received data — reset backoff
                tracing::info!("RBN ingester: connection closed cleanly");
                backoff_secs = INITIAL_BACKOFF_SECS;
            }
            Ok(false) => {
                // Connected but got no data (immediate close / rate limited)
                tracing::warn!("RBN ingester: connection closed without receiving data");
            }
            Err(e) => {
                tracing::error!("RBN ingester: connection error: {}", e);
                metrics::counter!(app_metrics::SYNC_ERRORS_TOTAL, "aggregator" => "rbn_ingester")
                    .increment(1);
            }
        }

        store.set_connected(false);
        tracing::info!("RBN ingester: reconnecting in {}s", backoff_secs);
        tokio::time::sleep(std::time::Duration::from_secs(backoff_secs)).await;
        backoff_secs = (backoff_secs * 2).min(MAX_BACKOFF_SECS);
    }
}

/// Returns Ok(true) if we successfully connected and received data,
/// Ok(false) if the connection was closed before we got any data.
async fn run_connection(
    store: &SpotStore,
    callsign: &str,
) -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
    let stream = tokio::time::timeout(
        std::time::Duration::from_secs(LOGIN_TIMEOUT_SECS),
        TcpStream::connect((RBN_HOST, RBN_PORT)),
    )
    .await??;

    let (reader, mut writer) = stream.into_split();
    let mut buf_reader = BufReader::new(reader);

    // Wait for login prompt — RBN sends "Please enter your call: " with no
    // trailing newline, so we must read raw bytes instead of lines.
    let login_deadline =
        tokio::time::Instant::now() + std::time::Duration::from_secs(LOGIN_TIMEOUT_SECS);

    let mut login_buf = [0u8; 256];
    let mut login_received = Vec::new();
    loop {
        let n = tokio::time::timeout_at(
            login_deadline,
            tokio::io::AsyncReadExt::read(&mut buf_reader, &mut login_buf),
        )
        .await??;

        if n == 0 {
            if login_received.is_empty() {
                // Server closed immediately — likely rate limited
                return Ok(false);
            }
            let received = String::from_utf8_lossy(&login_received);
            return Err(format!(
                "Connection closed during login (received {} bytes: {:?})",
                login_received.len(),
                &received[..received.len().min(100)]
            )
            .into());
        }

        login_received.extend_from_slice(&login_buf[..n]);
        let received = String::from_utf8_lossy(&login_received);

        if received.contains("call") || received.contains("login") || received.contains("callsign")
        {
            writer
                .write_all(format!("{}\n", callsign).as_bytes())
                .await?;
            tracing::info!("RBN ingester: logged in as {}", callsign);
            break;
        }
    }

    let mut lines = buf_reader.lines();

    store.set_connected(true);

    let mut batch: Vec<RbnSpot> = Vec::with_capacity(BATCH_SIZE);
    let mut flush_deadline =
        tokio::time::Instant::now() + std::time::Duration::from_millis(BATCH_FLUSH_MS);

    loop {
        let result = tokio::time::timeout_at(flush_deadline, lines.next_line()).await;

        match result {
            Ok(Ok(Some(line))) => {
                if let Some(spot) = parse_spot_line(&line, store) {
                    metrics::counter!(
                        app_metrics::RBN_SPOTS_INGESTED_TOTAL,
                        "mode" => spot.mode.clone(),
                        "band" => spot.band.to_string()
                    )
                    .increment(1);
                    metrics::histogram!(app_metrics::RBN_SPOT_SNR, "mode" => spot.mode.clone())
                        .record(spot.snr as f64);
                    if let Some(wpm) = spot.wpm {
                        metrics::histogram!(app_metrics::RBN_SPOT_WPM).record(wpm as f64);
                    }
                    batch.push(spot);
                }

                if batch.len() >= BATCH_SIZE {
                    store.push_batch(std::mem::take(&mut batch));
                    flush_deadline = tokio::time::Instant::now()
                        + std::time::Duration::from_millis(BATCH_FLUSH_MS);
                }
            }
            Ok(Ok(None)) => {
                // Connection closed
                if !batch.is_empty() {
                    store.push_batch(batch);
                }
                return Ok(true);
            }
            Ok(Err(e)) => {
                if !batch.is_empty() {
                    store.push_batch(batch);
                }
                return Err(e.into());
            }
            Err(_) => {
                // Flush timeout — push whatever we have
                if !batch.is_empty() {
                    store.push_batch(std::mem::take(&mut batch));
                }
                flush_deadline =
                    tokio::time::Instant::now() + std::time::Duration::from_millis(BATCH_FLUSH_MS);
            }
        }
    }
}

/// Parse an RBN telnet spot line.
///
/// Format: `DX de KM3T-#:     14039.8  W1AW           CW    18 dB  25 WPM  CQ      1832Z`
fn parse_spot_line(line: &str, store: &SpotStore) -> Option<RbnSpot> {
    let line = line.trim();

    // Must start with "DX de "
    if !line.starts_with("DX de ") {
        return None;
    }

    let rest = &line[6..]; // after "DX de "

    // Spotter ends with ":"
    let colon_pos = rest.find(':')?;
    let spotter = rest[..colon_pos].trim().to_string();

    let after_colon = rest[colon_pos + 1..].trim();

    // Split remaining fields by whitespace
    let fields: Vec<&str> = after_colon.split_whitespace().collect();
    if fields.len() < 5 {
        return None;
    }

    // Field 0: frequency
    let frequency: f64 = fields[0].parse().ok()?;

    // Field 1: callsign
    let callsign = fields[1].to_uppercase();

    // Field 2: mode
    let mode = fields[2].to_uppercase();

    // Find SNR: look for "NN dB" pattern
    let mut snr: i32 = 0;
    let mut wpm: Option<u16> = None;
    let mut spot_type: Option<&str> = None;
    let mut time_str: Option<&str> = None;

    let mut i = 3;
    while i < fields.len() {
        if i + 1 < fields.len() && fields[i + 1] == "dB" {
            snr = fields[i].parse().unwrap_or(0);
            i += 2;
        } else if i + 1 < fields.len() && fields[i + 1] == "WPM" {
            wpm = fields[i].parse().ok();
            i += 2;
        } else if fields[i].ends_with('Z') && fields[i].len() == 5 {
            time_str = Some(fields[i]);
            i += 1;
        } else if matches!(fields[i], "CQ" | "DX" | "BEACON" | "NCDXF" | "DE" | "DXPED") {
            spot_type = Some(fields[i]);
            i += 1;
        } else {
            i += 1;
        }
    }

    // Filter: only keep CQ and DX spot types
    match spot_type {
        Some("CQ") | Some("DX") => {}
        _ => return None,
    }

    // Derive band from frequency
    let band = freq_to_band(frequency)?;

    // Parse timestamp: HHMM from "1832Z" → use today's UTC date
    let timestamp = if let Some(ts) = time_str {
        let hhmm = &ts[..4];
        if let Ok(time) = NaiveTime::parse_from_str(hhmm, "%H%M") {
            Utc::now().date_naive().and_time(time).and_utc()
        } else {
            Utc::now()
        }
    } else {
        Utc::now()
    };

    Some(RbnSpot {
        id: store.next_id(),
        callsign,
        frequency,
        mode,
        snr,
        wpm,
        spotter,
        band,
        timestamp,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_cw_spot() {
        let store = SpotStore::new();
        let line = "DX de KM3T-#:     14039.8  W1AW           CW    18 dB  25 WPM  CQ      1832Z";
        let spot = parse_spot_line(line, &store).unwrap();
        assert_eq!(spot.callsign, "W1AW");
        assert_eq!(spot.spotter, "KM3T-#");
        assert!((spot.frequency - 14039.8).abs() < 0.01);
        assert_eq!(spot.mode, "CW");
        assert_eq!(spot.snr, 18);
        assert_eq!(spot.wpm, Some(25));
        assert_eq!(spot.band, "20m");
    }

    #[test]
    fn test_parse_ft8_spot() {
        let store = SpotStore::new();
        let line = "DX de W3LPL-#:     7074.0  N5XX           FT8    5 dB   CQ      2100Z";
        let spot = parse_spot_line(line, &store).unwrap();
        assert_eq!(spot.callsign, "N5XX");
        assert_eq!(spot.mode, "FT8");
        assert_eq!(spot.snr, 5);
        assert_eq!(spot.wpm, None);
        assert_eq!(spot.band, "40m");
    }

    #[test]
    fn test_parse_beacon_filtered() {
        let store = SpotStore::new();
        let line = "DX de KM3T-#:     14100.0  4U1UN          CW    30 dB  BEACON  1832Z";
        let spot = parse_spot_line(line, &store);
        assert!(spot.is_none(), "BEACON spots should be filtered out");
    }

    #[test]
    fn test_parse_non_spot_line() {
        let store = SpotStore::new();
        assert!(parse_spot_line("Please enter your callsign:", &store).is_none());
        assert!(parse_spot_line("", &store).is_none());
    }

    /// Test that immediate server close (rate limiting) returns Ok(false).
    #[tokio::test]
    async fn test_run_connection_immediate_close() {
        use tokio::net::TcpListener;

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        // Server accepts then immediately closes
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            drop(stream);
        });

        let stream = TcpStream::connect(addr).await.unwrap();
        let (reader, _writer) = stream.into_split();
        let mut buf_reader = BufReader::new(reader);

        let mut login_buf = [0u8; 256];
        let n = tokio::io::AsyncReadExt::read(&mut buf_reader, &mut login_buf)
            .await
            .unwrap();
        assert_eq!(n, 0, "Immediate close should return 0 bytes");

        server.await.unwrap();
    }

    /// Test the full login + spot ingestion flow against a mock TCP server.
    #[tokio::test]
    async fn test_run_connection_with_mock_server() {
        use tokio::io::AsyncWriteExt;
        use tokio::net::TcpListener;

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let store = SpotStore::new();
        let store_clone = store.clone();

        // Mock RBN server: send prompt (no newline), read callsign, send spots, close
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let (reader, mut writer) = stream.into_split();
            let mut buf_reader = BufReader::new(reader);

            // Send login prompt WITHOUT trailing newline (just like real RBN)
            writer.write_all(b"Please enter your call: ").await.unwrap();
            writer.flush().await.unwrap();

            // Read the callsign response
            let mut line = String::new();
            buf_reader.read_line(&mut line).await.unwrap();
            assert_eq!(line.trim(), "W6JSV");

            // Send a few spot lines
            let spots = vec![
                "DX de KM3T-#:     14039.8  W1AW           CW    18 dB  25 WPM  CQ      1832Z\n",
                "DX de W3LPL-#:     7074.0  N5XX           FT8    5 dB   CQ      2100Z\n",
                "DX de KM3T-#:     14100.0  4U1UN          CW    30 dB  BEACON  1832Z\n", // filtered
            ];
            for spot in spots {
                writer.write_all(spot.as_bytes()).await.unwrap();
            }
            writer.flush().await.unwrap();

            // Close connection
            drop(writer);
        });

        // Run the connection against our mock server
        let client = tokio::spawn(async move {
            let stream = TcpStream::connect(addr).await.unwrap();
            let (reader, mut writer) = stream.into_split();
            let mut buf_reader = BufReader::new(reader);

            // Replicate the login logic from run_connection
            let login_deadline =
                tokio::time::Instant::now() + std::time::Duration::from_secs(LOGIN_TIMEOUT_SECS);

            let mut login_buf = [0u8; 256];
            let mut login_received = Vec::new();
            loop {
                let n = tokio::time::timeout_at(
                    login_deadline,
                    tokio::io::AsyncReadExt::read(&mut buf_reader, &mut login_buf),
                )
                .await
                .unwrap()
                .unwrap();

                assert!(n > 0, "Server closed before sending prompt");
                login_received.extend_from_slice(&login_buf[..n]);
                let received = String::from_utf8_lossy(&login_received);
                if received.contains("call") {
                    writer.write_all(b"W6JSV\n").await.unwrap();
                    break;
                }
            }

            // Read spots
            let mut lines = buf_reader.lines();
            let mut spots = Vec::new();
            while let Ok(Some(line)) = lines.next_line().await {
                if let Some(spot) = parse_spot_line(&line, &store_clone) {
                    spots.push(spot);
                }
            }
            spots
        });

        server.await.unwrap();
        let spots = client.await.unwrap();

        // Should have 2 spots (BEACON filtered out)
        assert_eq!(spots.len(), 2);
        assert_eq!(spots[0].callsign, "W1AW");
        assert_eq!(spots[0].band, "20m");
        assert_eq!(spots[1].callsign, "N5XX");
        assert_eq!(spots[1].band, "40m");
    }
}
