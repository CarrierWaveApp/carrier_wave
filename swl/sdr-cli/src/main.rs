use std::collections::{HashMap, HashSet};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use chrono::Utc;
use clap::{Parser, Subcommand};
use reqwest::blocking::Client;
use serde::Deserialize;
use serde_json::Value;

#[derive(Parser)]
#[command(name = "sdr-cli", about = "CLI client for the SDR recording server")]
struct Cli {
    /// Server base URL
    #[arg(
        short,
        long,
        env = "SDR_SERVER_URL",
        default_value = "http://localhost:8080"
    )]
    server: String,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Check server health
    Health,
    /// SDR device management
    #[command(subcommand)]
    Sdrs(SdrsCommand),
    /// Capture session management
    #[command(subcommand)]
    Captures(CapturesCommand),
    /// Recording management
    #[command(subcommand)]
    Recordings(RecordingsCommand),
    /// Multi-SDR recording with combine and transcription
    Record {
        /// Center frequency in Hz
        #[arg(long)]
        frequency: u64,
        /// Demodulation mode (default: from POTA spot, or "cw")
        #[arg(long, value_parser = ["cw", "usb", "lsb", "am"])]
        mode: Option<String>,
        /// Location (default: from POTA spot, or required if no spot found)
        #[arg(long)]
        location: Option<String>,
        /// Bandwidth in Hz
        #[arg(long, default_value = "500")]
        bandwidth: u32,
        /// Recording duration in seconds
        #[arg(long, default_value = "60")]
        duration: u64,
        /// Total SDRs to use (split across 3 distance rings)
        #[arg(long, default_value = "45")]
        count: usize,
        /// Output directory (default: ~/tmp/recording-YYYYMMDD-HHMMSS)
        #[arg(short, long)]
        output_dir: Option<PathBuf>,
    },
    /// Monitor POTA spots and auto-record CW activations
    Monitor {
        /// Override location (default: use park location from spot)
        #[arg(long)]
        location: Option<String>,
        /// Recording duration per spot in seconds
        #[arg(long, default_value = "120")]
        duration: u64,
        /// Number of SDRs per spot
        #[arg(long, default_value = "15")]
        sdrs_per_spot: usize,
        /// Bandwidth in Hz
        #[arg(long, default_value = "500")]
        bandwidth: u32,
        /// Seconds between POTA API polls
        #[arg(long, default_value = "60")]
        poll_interval: u64,
        /// Output directory (default: ~/tmp/monitor-YYYYMMDD-HHMMSS)
        #[arg(short, long)]
        output_dir: Option<PathBuf>,
        /// Only record spots matching this mode (or "all")
        #[arg(long, default_value = "cw")]
        mode_filter: String,
        /// Band filter, e.g. "20m"
        #[arg(long)]
        band: Option<String>,
    },
}

#[derive(Subcommand)]
enum SdrsCommand {
    /// List all SDR devices
    List,
    /// Get details for a specific SDR
    Get { id: String },
    /// Trigger device scan
    Scan,
    /// Search for nearby available SDRs
    Search {
        /// Location as grid square (EM55) or lat,lon (35.4,-89.6)
        #[arg(long)]
        location: String,
        /// Number of results
        #[arg(long, default_value = "10")]
        count: usize,
        /// Only return SDRs with available slots
        #[arg(long)]
        available_only: bool,
        /// Output full JSON instead of one ID per line
        #[arg(short, long)]
        json: bool,
    },
}

#[derive(Subcommand)]
enum CapturesCommand {
    /// List active capture sessions
    List,
    /// Get details for a specific capture
    Get { id: String },
}

#[derive(Subcommand)]
enum RecordingsCommand {
    /// List all recordings
    List,
    /// Get details for a specific recording (with segments)
    Get { id: String },
    /// Show recording metadata (alias for get)
    Metadata { id: String },
    /// Create a new recording
    Create {
        /// Center frequency in Hz
        #[arg(long)]
        frequency: u64,
        /// Demodulation mode
        #[arg(long, value_parser = ["cw", "usb", "lsb", "am"])]
        mode: String,
        /// Bandwidth in Hz
        #[arg(long, default_value = "500")]
        bandwidth: u32,
        /// Specific SDR device ID
        #[arg(long)]
        sdr: Option<String>,
        /// Output sample rate in Hz
        #[arg(long, default_value = "12000")]
        sample_rate: u32,
        /// Retention period in days
        #[arg(long, default_value = "30")]
        retention: u32,
        /// Reference time for multi-SDR alignment (ISO 8601, e.g. 2025-01-15T12:00:00.000Z)
        #[arg(long)]
        reference_time: Option<String>,
    },
    /// Stop a recording (keeps data)
    Stop { id: String },
    /// Delete a recording
    Delete { id: String },
    /// Combine multiple recordings by averaging (noise reduction)
    Combine {
        /// Recording IDs to combine (minimum 2)
        #[arg(required = true, num_args = 2..)]
        ids: Vec<String>,
        /// Retention period in days
        #[arg(long, default_value = "30")]
        retention: u32,
        /// Skip quality filter (include all recordings even if noisy/dead)
        #[arg(long)]
        no_filter: bool,
    },
    /// Transcribe a CW recording (must be stopped, CW mode)
    Transcribe {
        /// Recording ID to transcribe
        id: String,
    },
    /// Download segment audio
    Audio {
        /// Recording ID
        id: String,
        /// Segment number
        segment: i64,
        /// Output file path (writes to stdout if omitted)
        #[arg(short, long)]
        output: Option<String>,
        /// Write a metadata sidecar JSON alongside the WAV file (requires -o)
        #[arg(short, long)]
        metadata: bool,
    },
}

// ---------------------------------------------------------------------------
// POTA spot types
// ---------------------------------------------------------------------------

/// Deserialize a JSON null or missing value as T::default().
fn null_as_default<'de, D, T>(deserializer: D) -> Result<T, D::Error>
where
    D: serde::Deserializer<'de>,
    T: Default + Deserialize<'de>,
{
    Option::<T>::deserialize(deserializer).map(|v| v.unwrap_or_default())
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
struct PotaSpot {
    #[serde(rename = "spotId")]
    spot_id: u64,
    #[serde(default, deserialize_with = "null_as_default")]
    activator: String,
    #[serde(default, deserialize_with = "null_as_default")]
    frequency: String,
    #[serde(default, deserialize_with = "null_as_default")]
    mode: String,
    #[serde(default, deserialize_with = "null_as_default")]
    reference: String,
    #[serde(rename = "parkName", default, deserialize_with = "null_as_default")]
    park_name: String,
    #[serde(rename = "spotTime", default, deserialize_with = "null_as_default")]
    spot_time: String,
    #[serde(default)]
    spotter: Option<String>,
    #[serde(default)]
    comments: Option<String>,
    #[serde(default)]
    source: Option<String>,
    #[serde(rename = "locationDesc", default, deserialize_with = "null_as_default")]
    location_desc: String,
    #[serde(default)]
    grid4: Option<String>,
    #[serde(default)]
    grid6: Option<String>,
    #[serde(default)]
    latitude: Option<f64>,
    #[serde(default)]
    longitude: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct SpotKey {
    activator: String,
    reference: String,
    frequency_khz: u32,
}

impl SpotKey {
    fn from_spot(spot: &PotaSpot) -> Option<Self> {
        let freq_khz: f64 = spot.frequency.parse().ok()?;
        Some(SpotKey {
            activator: spot.activator.clone(),
            reference: spot.reference.clone(),
            frequency_khz: freq_khz.round() as u32,
        })
    }
}

impl PotaSpot {
    /// Return a location string suitable for parse_location().
    /// Prefers lat,lon from the spot; falls back to grid6/grid4.
    fn location_string(&self) -> Option<String> {
        if let (Some(lat), Some(lon)) = (self.latitude, self.longitude) {
            return Some(format!("{lat},{lon}"));
        }
        if let Some(g) = self.grid6.as_ref().or(self.grid4.as_ref()) {
            if !g.is_empty() {
                return Some(g.clone());
            }
        }
        None
    }
}

// ---------------------------------------------------------------------------
// Location parsing
// ---------------------------------------------------------------------------

/// Parse a location string as lat,lon or Maidenhead grid square.
fn parse_location(loc: &str) -> Result<(f64, f64), String> {
    let loc = loc.trim();

    // Try lat,lon
    if let Some((lat_s, lon_s)) = loc.split_once(',') {
        let lat: f64 = lat_s
            .trim()
            .parse()
            .map_err(|_| format!("Invalid lat: {lat_s}"))?;
        let lon: f64 = lon_s
            .trim()
            .parse()
            .map_err(|_| format!("Invalid lon: {lon_s}"))?;
        return Ok((lat, lon));
    }

    // Try Maidenhead grid square
    grid_to_latlon(loc)
}

/// Convert a Maidenhead grid square to (lat, lon) center.
fn grid_to_latlon(grid: &str) -> Result<(f64, f64), String> {
    let grid = grid.trim().to_uppercase();
    let chars: Vec<char> = grid.chars().collect();
    if chars.len() < 2 {
        return Err(format!("Invalid grid: {grid}"));
    }

    let mut lon = (chars[0] as i32 - 'A' as i32) as f64 * 20.0 - 180.0;
    let mut lat = (chars[1] as i32 - 'A' as i32) as f64 * 10.0 - 90.0;

    if chars.len() >= 4 {
        let d2 = chars[2]
            .to_digit(10)
            .ok_or_else(|| format!("Invalid grid digit: {}", chars[2]))?;
        let d3 = chars[3]
            .to_digit(10)
            .ok_or_else(|| format!("Invalid grid digit: {}", chars[3]))?;
        lon += d2 as f64 * 2.0;
        lat += d3 as f64;
    }

    if chars.len() >= 6 {
        lon += (chars[4] as i32 - 'A' as i32) as f64 * (2.0 / 24.0);
        lat += (chars[5] as i32 - 'A' as i32) as f64 * (1.0 / 24.0);
        // Center of subsquare
        lon += 1.0 / 24.0;
        lat += 0.5 / 24.0;
    } else if chars.len() >= 4 {
        // Center of square
        lon += 1.0;
        lat += 0.5;
    } else {
        // Center of field
        lon += 10.0;
        lat += 5.0;
    }

    Ok((lat, lon))
}

// ---------------------------------------------------------------------------
// Utility: frequency <-> band
// ---------------------------------------------------------------------------

fn frequency_to_band(freq_khz: f64) -> Option<&'static str> {
    match freq_khz as u32 {
        1800..=2000 => Some("160m"),
        3500..=4000 => Some("80m"),
        7000..=7300 => Some("40m"),
        10100..=10150 => Some("30m"),
        14000..=14350 => Some("20m"),
        18068..=18168 => Some("17m"),
        21000..=21450 => Some("15m"),
        24890..=24990 => Some("12m"),
        28000..=29700 => Some("10m"),
        _ => None,
    }
}

// ---------------------------------------------------------------------------
// Utility: default output dir
// ---------------------------------------------------------------------------

fn default_output_dir(prefix: &str) -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    let stamp = Utc::now().format("%Y%m%d-%H%M%S");
    PathBuf::from(home)
        .join("tmp")
        .join(format!("{prefix}-{stamp}"))
}

// ---------------------------------------------------------------------------
// HTTP helpers (existing + new value-returning variants)
// ---------------------------------------------------------------------------

fn get_json(client: &Client, url: &str) -> Result<(), String> {
    let resp = client.get(url).send().map_err(|e| e.to_string())?;
    handle_json_response(resp)
}

fn get_json_value(client: &Client, url: &str) -> Result<Value, String> {
    let resp = client.get(url).send().map_err(|e| e.to_string())?;
    let status = resp.status();
    let body = resp.text().unwrap_or_default();
    if !status.is_success() {
        return Err(format!("HTTP {status}: {body}"));
    }
    serde_json::from_str(&body).map_err(|e| format!("invalid JSON response: {e}\n{body}"))
}

fn post_empty(client: &Client, url: &str) -> Result<(), String> {
    let resp = client.post(url).send().map_err(|e| e.to_string())?;
    handle_json_response(resp)
}

fn post_json(client: &Client, url: &str, body: &Value) -> Result<(), String> {
    let resp = client
        .post(url)
        .json(body)
        .send()
        .map_err(|e| e.to_string())?;
    handle_json_response(resp)
}

fn post_json_return_value(client: &Client, url: &str, body: &Value) -> Result<Value, String> {
    let resp = client
        .post(url)
        .json(body)
        .send()
        .map_err(|e| e.to_string())?;
    let status = resp.status();
    let text = resp.text().unwrap_or_default();
    if !status.is_success() {
        return Err(format!("HTTP {status}: {text}"));
    }
    serde_json::from_str(&text).map_err(|e| format!("invalid JSON: {e}\n{text}"))
}

fn delete(client: &Client, url: &str) -> Result<(), String> {
    let resp = client.delete(url).send().map_err(|e| e.to_string())?;
    let status = resp.status();
    if status.is_success() {
        if status == reqwest::StatusCode::NO_CONTENT {
            println!("Deleted.");
            return Ok(());
        }
        handle_json_response(resp)
    } else {
        let body = resp.text().unwrap_or_default();
        Err(format!("HTTP {status}: {body}"))
    }
}

fn handle_json_response(resp: reqwest::blocking::Response) -> Result<(), String> {
    let status = resp.status();
    let body = resp.text().unwrap_or_default();

    if !status.is_success() {
        return Err(format!("HTTP {status}: {body}"));
    }

    let value: Value =
        serde_json::from_str(&body).map_err(|e| format!("invalid JSON response: {e}\n{body}"))?;
    let pretty =
        serde_json::to_string_pretty(&value).map_err(|e| format!("formatting error: {e}"))?;
    println!("{pretty}");
    Ok(())
}

fn download_audio(client: &Client, url: &str, output: Option<&str>) -> Result<(), String> {
    let resp = client.get(url).send().map_err(|e| e.to_string())?;
    let status = resp.status();

    if !status.is_success() {
        let body = resp.text().unwrap_or_default();
        return Err(format!("HTTP {status}: {body}"));
    }

    let bytes = resp.bytes().map_err(|e| e.to_string())?;

    match output {
        Some(path) => {
            std::fs::write(path, &bytes).map_err(|e| format!("failed to write {path}: {e}"))?;
            eprintln!("Wrote {} bytes to {path}", bytes.len());
        }
        None => {
            let stdout = io::stdout();
            let mut handle = stdout.lock();
            handle.write_all(&bytes).map_err(|e| e.to_string())?;
        }
    }

    Ok(())
}

fn write_sidecar(
    client: &Client,
    recording_url: &str,
    segment_number: i64,
    wav_path: &str,
) -> Result<(), String> {
    let resp = client
        .get(recording_url)
        .send()
        .map_err(|e| e.to_string())?;
    let status = resp.status();
    let body = resp.text().unwrap_or_default();

    if !status.is_success() {
        return Err(format!(
            "failed to fetch recording metadata: HTTP {status}: {body}"
        ));
    }

    let data: Value =
        serde_json::from_str(&body).map_err(|e| format!("invalid recording JSON: {e}"))?;

    let segment = data["segments"]
        .as_array()
        .and_then(|segs| {
            segs.iter()
                .find(|s| s["segment_number"].as_i64() == Some(segment_number))
        })
        .ok_or_else(|| format!("segment {segment_number} not found in recording metadata"))?;

    let sidecar = serde_json::json!({
        "recording_id": data["id"],
        "sdr_id": data["sdr_id"],
        "frequency": data["frequency"],
        "bandwidth": data["bandwidth"],
        "mode": data["mode"],
        "recording_started_at": data["started_at"],
        "segment_number": segment["segment_number"],
        "sample_rate": segment["sample_rate"],
        "duration_secs": segment["duration_secs"],
        "started_at": segment["started_at"],
        "ended_at": segment["ended_at"],
    });

    let json_path = PathBuf::from(wav_path).with_extension("json");
    let pretty =
        serde_json::to_string_pretty(&sidecar).map_err(|e| format!("JSON format error: {e}"))?;
    std::fs::write(&json_path, pretty)
        .map_err(|e| format!("failed to write {}: {e}", json_path.display()))?;
    eprintln!("Wrote sidecar to {}", json_path.display());

    Ok(())
}

// ---------------------------------------------------------------------------
// SDR search (existing, refactored for reuse)
// ---------------------------------------------------------------------------

fn search_sdrs(
    client: &Client,
    base: &str,
    location: &str,
    count: usize,
    available_only: bool,
    json_output: bool,
) -> Result<(), String> {
    let (lat, lon) = parse_location(location)?;
    let url = format!(
        "{base}/api/v1/sdrs/search?lat={lat}&lon={lon}&count={count}&available_only={available_only}"
    );
    let resp = client.get(&url).send().map_err(|e| e.to_string())?;
    let status = resp.status();
    let body = resp.text().unwrap_or_default();

    if !status.is_success() {
        return Err(format!("HTTP {status}: {body}"));
    }

    if json_output {
        let value: Value = serde_json::from_str(&body)
            .map_err(|e| format!("invalid JSON response: {e}\n{body}"))?;
        let pretty =
            serde_json::to_string_pretty(&value).map_err(|e| format!("formatting error: {e}"))?;
        println!("{pretty}");
    } else {
        let data: Value = serde_json::from_str(&body)
            .map_err(|e| format!("invalid JSON response: {e}\n{body}"))?;
        if let Some(results) = data["results"].as_array() {
            for r in results {
                if let Some(id) = r["sdr"]["id"].as_str() {
                    println!("{id}");
                }
            }
        }
    }

    Ok(())
}

fn combine_recordings(client: &Client, base: &str, body: &Value) -> Result<(), String> {
    let resp = client
        .post(format!("{base}/api/v1/recordings/combine"))
        .json(body)
        .send()
        .map_err(|e| e.to_string())?;
    let status = resp.status();
    let text = resp.text().unwrap_or_default();

    if !status.is_success() {
        return Err(format!("HTTP {status}: {text}"));
    }

    let value: Value =
        serde_json::from_str(&text).map_err(|e| format!("invalid JSON: {e}\n{text}"))?;

    // Print excluded recordings as warnings to stderr
    if let Some(excluded) = value["excluded"].as_array() {
        for ex in excluded {
            let id = ex["id"].as_str().unwrap_or("?");
            let reason = ex["reason"].as_str().unwrap_or("unknown");
            eprintln!("warning: excluded {id}: {reason}");
        }
    }

    // Print the full JSON to stdout
    let pretty =
        serde_json::to_string_pretty(&value).map_err(|e| format!("formatting error: {e}"))?;
    println!("{pretty}");
    Ok(())
}

// ---------------------------------------------------------------------------
// Recording workflow (record command)
// ---------------------------------------------------------------------------

/// Search for SDRs and split into 3 distance rings (close/medium/far).
#[allow(clippy::type_complexity)]
fn search_sdrs_by_rings(
    client: &Client,
    base: &str,
    location: &str,
    total_count: usize,
) -> Result<(Vec<String>, Vec<String>, Vec<String>), String> {
    let pool_size = total_count * 6;
    let (lat, lon) = parse_location(location)?;
    let url = format!(
        "{base}/api/v1/sdrs/search?lat={lat}&lon={lon}&count={pool_size}&available_only=true"
    );

    let data = get_json_value(client, &url)?;
    let mut sdr_ids: Vec<String> = Vec::new();

    if let Some(results) = data["results"].as_array() {
        for r in results {
            if let Some(id) = r["sdr"]["id"].as_str() {
                sdr_ids.push(id.to_string());
            }
        }
    }

    if sdr_ids.is_empty() {
        return Err("No available SDRs found".to_string());
    }

    let total = sdr_ids.len();
    let third = total.div_ceil(3);

    let close = sdr_ids[..third.min(total)].to_vec();
    let medium = sdr_ids[third.min(total)..(third * 2).min(total)].to_vec();
    let far = sdr_ids[(third * 2).min(total)..].to_vec();

    eprintln!(
        "Pool: {total} SDRs -> close {}, medium {}, far {}",
        close.len(),
        medium.len(),
        far.len()
    );

    Ok((close, medium, far))
}

/// Start recordings on SDRs from a ring, stopping at `target` successes.
/// Returns (recording_ids, sdr_ids) for successfully started recordings.
#[allow(clippy::too_many_arguments)]
fn start_ring_recordings(
    client: &Client,
    base: &str,
    ring_name: &str,
    sdrs: &[String],
    target: usize,
    frequency: u64,
    mode: &str,
    bandwidth: u32,
    reference_time: &str,
) -> (Vec<String>, Vec<String>) {
    let mut recording_ids = Vec::new();
    let mut sdr_ids = Vec::new();

    for sdr in sdrs {
        if recording_ids.len() >= target {
            break;
        }

        let body = serde_json::json!({
            "frequency": frequency,
            "mode": mode,
            "bandwidth": bandwidth,
            "sdr_id": sdr,
            "output_sample_rate": 12000,
            "retention_days": 30,
            "reference_time": reference_time,
        });

        match post_json_return_value(client, &format!("{base}/api/v1/recordings"), &body) {
            Ok(resp) => {
                if let Some(id) = resp["id"].as_str() {
                    eprintln!("  [{ring_name}] Started {sdr} -> {id}");
                    recording_ids.push(id.to_string());
                    sdr_ids.push(sdr.clone());
                }
            }
            Err(_) => {
                eprintln!("  [{ring_name}] FAILED {sdr} (trying next)");
            }
        }
    }

    eprintln!("  {ring_name}: {}/{target}", recording_ids.len());
    (recording_ids, sdr_ids)
}

/// Stop all recordings by ID.
fn stop_all_recordings(client: &Client, base: &str, ids: &[String]) {
    for id in ids {
        let url = format!("{base}/api/v1/recordings/{id}/stop");
        match client.post(&url).send() {
            Ok(resp) if resp.status().is_success() => {
                eprintln!("Stopped {id}");
            }
            Ok(resp) => {
                eprintln!("Failed to stop {id}: HTTP {}", resp.status());
            }
            Err(e) => {
                eprintln!("Failed to stop {id}: {e}");
            }
        }
    }
}

/// Download all segments for a list of recordings.
fn download_all_segments(
    client: &Client,
    base: &str,
    recording_ids: &[String],
    sdr_ids: &[String],
    output_dir: &Path,
) -> Result<(), String> {
    for (i, id) in recording_ids.iter().enumerate() {
        let sdr = sdr_ids.get(i).map(|s| s.as_str()).unwrap_or("unknown");
        let safe_sdr: String = sdr
            .chars()
            .map(|c| {
                if c.is_alphanumeric() || c == '.' || c == '-' || c == '_' {
                    c
                } else {
                    '_'
                }
            })
            .collect();

        let data = get_json_value(client, &format!("{base}/api/v1/recordings/{id}"))?;
        let seg_count = data["segments"].as_array().map(|a| a.len()).unwrap_or(0);

        if seg_count == 0 {
            eprintln!("  (no segments for {sdr})");
            continue;
        }

        for seg in 0..seg_count {
            let outfile = output_dir.join(format!("{safe_sdr}_seg{seg}.wav"));
            let audio_url = format!("{base}/api/v1/recordings/{id}/segments/{seg}/audio");
            let out_str = outfile.to_string_lossy().to_string();
            download_audio(client, &audio_url, Some(&out_str))?;

            let recording_url = format!("{base}/api/v1/recordings/{id}");
            write_sidecar(client, &recording_url, seg as i64, &out_str)?;
        }
    }
    Ok(())
}

/// Combine recordings and download the result. Returns (combined_id, included, total).
fn combine_and_download(
    client: &Client,
    base: &str,
    ids: &[String],
    output_dir: &Path,
) -> Result<(String, u64, u64), String> {
    let body = serde_json::json!({
        "source_recording_ids": ids,
        "retention_days": 30,
        "skip_quality_filter": false,
    });

    let value = post_json_return_value(client, &format!("{base}/api/v1/recordings/combine"), &body)
        .map_err(|e| format!("Combine failed: {e}"))?;

    // Print excluded warnings
    if let Some(excluded) = value["excluded"].as_array() {
        for ex in excluded {
            let id = ex["id"].as_str().unwrap_or("?");
            let reason = ex["reason"].as_str().unwrap_or("unknown");
            eprintln!("  excluded {id}: {reason}");
        }
    }

    let combined_id = value["id"]
        .as_str()
        .ok_or("No id in combine response")?
        .to_string();
    let included = value["included_count"].as_u64().unwrap_or(0);
    let total = value["source_count"].as_u64().unwrap_or(0);

    eprintln!("Combined recording: {combined_id} ({included}/{total} sources used)");

    // Download combined segments
    let data = get_json_value(client, &format!("{base}/api/v1/recordings/{combined_id}"))?;
    let seg_count = data["segments"].as_array().map(|a| a.len()).unwrap_or(0);

    for seg in 0..seg_count {
        let outfile = output_dir.join(format!("combined_seg{seg}.wav"));
        let audio_url = format!("{base}/api/v1/recordings/{combined_id}/segments/{seg}/audio");
        let out_str = outfile.to_string_lossy().to_string();
        download_audio(client, &audio_url, Some(&out_str))?;

        let recording_url = format!("{base}/api/v1/recordings/{combined_id}");
        write_sidecar(client, &recording_url, seg as i64, &out_str)?;
    }

    Ok((combined_id, included, total))
}

/// Transcribe a recording and save text. Returns (text, wpm, char_count) if successful.
fn transcribe_recording(
    client: &Client,
    base: &str,
    id: &str,
    output_dir: &Path,
) -> Result<Option<(String, String, i64)>, String> {
    let body = serde_json::json!({ "recording_id": id });

    let value =
        match post_json_return_value(client, &format!("{base}/api/v1/transcriptions"), &body) {
            Ok(v) => v,
            Err(e) => {
                eprintln!("Transcription failed: {e}");
                return Ok(None);
            }
        };

    let text = value["text"].as_str().unwrap_or("").to_string();
    if text.is_empty() {
        eprintln!("  (no text decoded)");
        return Ok(None);
    }

    let wpm = match value["wpm_estimate"].as_f64() {
        Some(w) => format!("{w:.0}"),
        None => "?".to_string(),
    };
    let chars = value["char_count"].as_i64().unwrap_or(0);

    eprintln!("  WPM: {wpm}  chars: {chars}");
    eprintln!("  Text: {text}");

    // Save transcription to file
    let tx_path = output_dir.join("transcription.txt");
    std::fs::write(&tx_path, &text)
        .map_err(|e| format!("failed to write {}: {e}", tx_path.display()))?;
    eprintln!("  Saved to {}", tx_path.display());

    Ok(Some((text, wpm, chars)))
}

/// Resolve mode and location for a record command.
/// If not explicitly provided, looks up the frequency in active POTA spots.
fn resolve_record_params(
    client: &Client,
    frequency: u64,
    mode: Option<&str>,
    location: Option<&str>,
) -> Result<(String, String), String> {
    // If both are provided, just use them
    if let (Some(m), Some(l)) = (mode, location) {
        return Ok((m.to_string(), l.to_string()));
    }

    let freq_khz = frequency as f64 / 1e3;

    // Try POTA spot lookup for missing values
    eprintln!("Looking up {freq_khz:.1} kHz in active POTA spots...");
    match find_spot_by_frequency(client, frequency) {
        Ok(Some(spot)) => {
            let grid_display = spot
                .grid6
                .as_deref()
                .or(spot.grid4.as_deref())
                .unwrap_or("?");
            eprintln!(
                "Found: {} at {} ({}) - {} on {} [{}]",
                spot.activator,
                spot.reference,
                spot.location_desc,
                spot.mode,
                spot.frequency,
                grid_display
            );

            let resolved_mode = mode
                .map(|m| m.to_string())
                .unwrap_or_else(|| spot.mode.to_lowercase());
            let resolved_location = location
                .map(|l| l.to_string())
                .or_else(|| spot.location_string());

            match resolved_location {
                Some(loc) => Ok((resolved_mode, loc)),
                None => {
                    Err("POTA spot found but has no location data. Provide --location.".to_string())
                }
            }
        }
        Ok(None) => {
            eprintln!("No POTA spot found at {freq_khz:.1} kHz.");
            let resolved_mode = mode.unwrap_or("cw").to_string();
            match location {
                Some(l) => Ok((resolved_mode, l.to_string())),
                None => Err(
                    "No POTA spot found and no --location provided. Provide --location."
                        .to_string(),
                ),
            }
        }
        Err(e) => {
            eprintln!("POTA lookup failed: {e}");
            let resolved_mode = mode.unwrap_or("cw").to_string();
            match location {
                Some(l) => Ok((resolved_mode, l.to_string())),
                None => Err(format!(
                    "POTA lookup failed ({e}) and no --location provided. Provide --location."
                )),
            }
        }
    }
}

/// Full recording workflow: search SDRs, record, stop, download, combine, transcribe.
#[allow(clippy::too_many_arguments)]
fn execute_recording_workflow(
    client: &Client,
    base: &str,
    frequency: u64,
    mode: &str,
    location: &str,
    bandwidth: u32,
    duration: u64,
    sdr_count: usize,
    output_dir: &Path,
) -> Result<(), String> {
    std::fs::create_dir_all(output_dir)
        .map_err(|e| format!("failed to create {}: {e}", output_dir.display()))?;

    let reference_time = Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string();
    let per_ring = sdr_count.div_ceil(3);

    let freq_mhz = frequency as f64 / 1e6;
    let mode_up = mode.to_uppercase();
    eprintln!();
    eprintln!(
        "Recording up to {sdr_count} SDRs at {freq_mhz:.3} MHz {mode_up} bw={bandwidth}Hz for {duration}s"
    );
    eprintln!("Output: {}", output_dir.display());
    eprintln!();

    // Search SDRs
    let (close, medium, far) = search_sdrs_by_rings(client, base, location, sdr_count)?;
    eprintln!("  Targets: close {per_ring}, medium {per_ring}, far {per_ring} = {sdr_count} total");
    eprintln!();

    // Start recordings across 3 rings
    let (mut all_rec_ids, mut all_sdr_ids) = (Vec::new(), Vec::new());

    let (rec, sdr) = start_ring_recordings(
        client,
        base,
        "close",
        &close,
        per_ring,
        frequency,
        mode,
        bandwidth,
        &reference_time,
    );
    all_rec_ids.extend(rec);
    all_sdr_ids.extend(sdr);

    let (rec, sdr) = start_ring_recordings(
        client,
        base,
        "medium",
        &medium,
        per_ring,
        frequency,
        mode,
        bandwidth,
        &reference_time,
    );
    all_rec_ids.extend(rec);
    all_sdr_ids.extend(sdr);

    let (rec, sdr) = start_ring_recordings(
        client,
        base,
        "far",
        &far,
        per_ring,
        frequency,
        mode,
        bandwidth,
        &reference_time,
    );
    all_rec_ids.extend(rec);
    all_sdr_ids.extend(sdr);

    eprintln!();
    eprintln!(
        "{}/{sdr_count} SDRs started across 3 rings",
        all_rec_ids.len()
    );

    if all_rec_ids.is_empty() {
        return Err("No recordings started, exiting.".to_string());
    }

    // Wait for duration
    eprintln!();
    eprintln!("Listening for {duration}s...");
    thread::sleep(Duration::from_secs(duration));

    // Stop all recordings
    stop_all_recordings(client, base, &all_rec_ids);

    // Download segments
    eprintln!();
    eprintln!("Downloading segments...");
    download_all_segments(client, base, &all_rec_ids, &all_sdr_ids, output_dir)?;

    // Combine
    if all_rec_ids.len() >= 2 {
        eprintln!();
        eprintln!("Combining {} recordings...", all_rec_ids.len());
        match combine_and_download(client, base, &all_rec_ids, output_dir) {
            Ok((combined_id, _included, _total)) => {
                // Transcribe if CW
                if mode == "cw" {
                    eprintln!();
                    eprintln!("Transcribing combined recording...");
                    transcribe_recording(client, base, &combined_id, output_dir)?;
                }
            }
            Err(e) => {
                eprintln!("Combine failed: {e}");
            }
        }
    } else {
        eprintln!("Only {} recording(s), skipping combine", all_rec_ids.len());
    }

    eprintln!();
    eprintln!("Done. Files in {}", output_dir.display());

    Ok(())
}

// ---------------------------------------------------------------------------
// POTA monitor
// ---------------------------------------------------------------------------

fn fetch_pota_spots(client: &Client) -> Result<Vec<PotaSpot>, String> {
    let resp = client
        .get("https://api.pota.app/spot/activator")
        .send()
        .map_err(|e| format!("POTA API request failed: {e}"))?;

    let status = resp.status();
    let body = resp.text().unwrap_or_default();

    if !status.is_success() {
        return Err(format!("POTA API HTTP {status}: {body}"));
    }

    serde_json::from_str(&body).map_err(|e| format!("POTA JSON parse error: {e}"))
}

/// Find the POTA spot closest to the given frequency (Hz). Matches within 1 kHz.
fn find_spot_by_frequency(client: &Client, frequency_hz: u64) -> Result<Option<PotaSpot>, String> {
    let spots = fetch_pota_spots(client)?;
    let target_khz = frequency_hz as f64 / 1000.0;

    let mut best: Option<(f64, PotaSpot)> = None;
    for spot in spots {
        if let Ok(spot_khz) = spot.frequency.parse::<f64>() {
            let diff = (spot_khz - target_khz).abs();
            if diff <= 1.0 && best.as_ref().is_none_or(|(d, _)| diff < *d) {
                best = Some((diff, spot));
            }
        }
    }

    Ok(best.map(|(_, spot)| spot))
}

fn filter_spots(spots: Vec<PotaSpot>, mode_filter: &str, band: Option<&str>) -> Vec<PotaSpot> {
    spots
        .into_iter()
        .filter(|s| {
            if mode_filter.eq_ignore_ascii_case("all") {
                true
            } else {
                s.mode.eq_ignore_ascii_case(mode_filter)
            }
        })
        .filter(|s| {
            if let Some(band) = band {
                if let Ok(freq_khz) = s.frequency.parse::<f64>() {
                    frequency_to_band(freq_khz)
                        .map(|b| b.eq_ignore_ascii_case(band))
                        .unwrap_or(false)
                } else {
                    false
                }
            } else {
                true
            }
        })
        .collect()
}

#[allow(clippy::too_many_arguments)]
fn run_monitor(
    client: &Client,
    base: &str,
    location_override: Option<&str>,
    duration: u64,
    sdrs_per_spot: usize,
    bandwidth: u32,
    poll_interval: u64,
    output_base: &Path,
    mode_filter: &str,
    band: Option<&str>,
) -> Result<(), String> {
    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();
    ctrlc::set_handler(move || {
        eprintln!();
        eprintln!("Ctrl+C received, finishing active recordings...");
        r.store(false, Ordering::SeqCst);
    })
    .map_err(|e| format!("Failed to set Ctrl+C handler: {e}"))?;

    let mut seen_spots: HashSet<SpotKey> = HashSet::new();
    let mut active_threads: HashMap<SpotKey, thread::JoinHandle<()>> = HashMap::new();

    eprintln!(
        "Monitoring POTA spots (mode={mode_filter}, band={})...",
        band.unwrap_or("all")
    );
    if let Some(loc) = location_override {
        eprintln!("  Location override: {loc}");
    } else {
        eprintln!("  Location: from park coordinates");
    }
    eprintln!("  Duration per spot: {duration}s, SDRs per spot: {sdrs_per_spot}");
    eprintln!("  Poll interval: {poll_interval}s");
    eprintln!("  Output: {}", output_base.display());
    eprintln!("  Press Ctrl+C to stop");
    eprintln!();

    std::fs::create_dir_all(output_base)
        .map_err(|e| format!("failed to create {}: {e}", output_base.display()))?;

    while running.load(Ordering::SeqCst) {
        // Clean up finished threads
        active_threads.retain(|_key, handle| !handle.is_finished());

        // Fetch and filter spots
        let spots = match fetch_pota_spots(client) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("POTA fetch error: {e}");
                thread::sleep(Duration::from_secs(poll_interval));
                continue;
            }
        };

        let filtered = filter_spots(spots, mode_filter, band);
        let mut new_count = 0;

        for spot in &filtered {
            let key = match SpotKey::from_spot(spot) {
                Some(k) => k,
                None => continue,
            };

            if seen_spots.contains(&key) {
                continue;
            }

            seen_spots.insert(key.clone());
            new_count += 1;

            let freq_khz: f64 = match spot.frequency.parse() {
                Ok(f) => f,
                Err(_) => continue,
            };
            let frequency_hz = (freq_khz * 1000.0) as u64;
            let band_str = frequency_to_band(freq_khz).unwrap_or("?");

            // Resolve location: override > spot lat/lon > spot grid
            let spot_location = if let Some(loc) = location_override {
                loc.to_string()
            } else if let Some(loc) = spot.location_string() {
                loc
            } else {
                eprintln!(
                    "[SKIP] {} at {} - no location data",
                    spot.activator, spot.reference
                );
                continue;
            };

            eprintln!(
                "[NEW] {} at {} ({}) on {} ({band_str}) - {} [{}]",
                spot.activator,
                spot.reference,
                spot.location_desc,
                spot.frequency,
                spot.mode,
                spot.grid6
                    .as_deref()
                    .or(spot.grid4.as_deref())
                    .unwrap_or(&spot_location)
            );

            // Build per-spot output dir
            let safe_ref: String = spot
                .reference
                .chars()
                .map(|c| {
                    if c.is_alphanumeric() || c == '-' {
                        c
                    } else {
                        '_'
                    }
                })
                .collect();
            let safe_call: String = spot
                .activator
                .chars()
                .map(|c| {
                    if c.is_alphanumeric() || c == '-' || c == '/' {
                        c
                    } else {
                        '_'
                    }
                })
                .collect();
            let stamp = Utc::now().format("%H%M%S");
            let spot_dir = output_base.join(format!("{stamp}_{safe_call}_{safe_ref}_{band_str}"));

            let base_owned = base.to_string();
            let location_owned = spot_location;
            let mode = spot.mode.to_lowercase();
            let running_flag = running.clone();

            let handle = thread::spawn(move || {
                if !running_flag.load(Ordering::SeqCst) {
                    return;
                }
                let thread_client = Client::new();
                if let Err(e) = execute_recording_workflow(
                    &thread_client,
                    &base_owned,
                    frequency_hz,
                    &mode,
                    &location_owned,
                    bandwidth,
                    duration,
                    sdrs_per_spot,
                    &spot_dir,
                ) {
                    eprintln!("Recording workflow error for {safe_ref}: {e}");
                }
            });

            active_threads.insert(key, handle);
        }

        if new_count > 0 {
            eprintln!(
                "{new_count} new spot(s), {} active recording(s), {} total seen",
                active_threads.len(),
                seen_spots.len()
            );
        }

        // Sleep in small increments so Ctrl+C is responsive
        let sleep_end = std::time::Instant::now() + Duration::from_secs(poll_interval);
        while std::time::Instant::now() < sleep_end && running.load(Ordering::SeqCst) {
            thread::sleep(Duration::from_millis(500));
        }
    }

    // Wait for active recordings to finish
    let remaining = active_threads.len();
    if remaining > 0 {
        eprintln!("Waiting for {remaining} active recording(s) to finish...");
    }
    for (_key, handle) in active_threads {
        let _ = handle.join();
    }

    eprintln!("Monitor stopped. Files in {}", output_base.display());
    Ok(())
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

fn main() {
    let cli = Cli::parse();
    let base = cli.server.trim_end_matches('/');
    let client = Client::new();

    let result = match cli.command {
        Command::Health => get_json(&client, &format!("{base}/api/v1/health")),
        Command::Sdrs(cmd) => match cmd {
            SdrsCommand::List => get_json(&client, &format!("{base}/api/v1/sdrs")),
            SdrsCommand::Get { id } => get_json(&client, &format!("{base}/api/v1/sdrs/{id}")),
            SdrsCommand::Scan => post_empty(&client, &format!("{base}/api/v1/sdrs/scan")),
            SdrsCommand::Search {
                location,
                count,
                available_only,
                json,
            } => search_sdrs(&client, base, &location, count, available_only, json),
        },
        Command::Captures(cmd) => match cmd {
            CapturesCommand::List => get_json(&client, &format!("{base}/api/v1/captures")),
            CapturesCommand::Get { id } => {
                get_json(&client, &format!("{base}/api/v1/captures/{id}"))
            }
        },
        Command::Recordings(cmd) => match cmd {
            RecordingsCommand::List => get_json(&client, &format!("{base}/api/v1/recordings")),
            RecordingsCommand::Get { id } | RecordingsCommand::Metadata { id } => {
                get_json(&client, &format!("{base}/api/v1/recordings/{id}"))
            }
            RecordingsCommand::Create {
                frequency,
                mode,
                bandwidth,
                sdr,
                sample_rate,
                retention,
                reference_time,
            } => {
                let mut body = serde_json::json!({
                    "frequency": frequency,
                    "mode": mode,
                    "bandwidth": bandwidth,
                    "sdr_id": sdr,
                    "output_sample_rate": sample_rate,
                    "retention_days": retention,
                });
                if let Some(rt) = reference_time {
                    body["reference_time"] = serde_json::Value::String(rt);
                }
                post_json(&client, &format!("{base}/api/v1/recordings"), &body)
            }
            RecordingsCommand::Stop { id } => (|| {
                let url = format!("{base}/api/v1/recordings/{id}/stop");
                let resp = client.post(&url).send().map_err(|e| e.to_string())?;
                let status = resp.status();
                if status == reqwest::StatusCode::NO_CONTENT {
                    println!("Stopped.");
                    return Ok(());
                }
                if !status.is_success() {
                    let body = resp.text().unwrap_or_default();
                    return Err(format!("HTTP {status}: {body}"));
                }
                handle_json_response(resp)
            })(),
            RecordingsCommand::Delete { id } => {
                delete(&client, &format!("{base}/api/v1/recordings/{id}"))
            }
            RecordingsCommand::Combine {
                ids,
                retention,
                no_filter,
            } => {
                let body = serde_json::json!({
                    "source_recording_ids": ids,
                    "retention_days": retention,
                    "skip_quality_filter": no_filter,
                });
                combine_recordings(&client, base, &body)
            }
            RecordingsCommand::Transcribe { id } => {
                let body = serde_json::json!({ "recording_id": id });
                post_json(&client, &format!("{base}/api/v1/transcriptions"), &body)
            }
            RecordingsCommand::Audio {
                id,
                segment,
                output,
                metadata,
            } => (|| {
                let audio_url = format!("{base}/api/v1/recordings/{id}/segments/{segment}/audio");
                download_audio(&client, &audio_url, output.as_deref())?;

                if metadata {
                    let wav_path = output.as_deref().ok_or_else(|| {
                        "--metadata requires --output/-o to determine sidecar path".to_string()
                    })?;
                    let recording_url = format!("{base}/api/v1/recordings/{id}");
                    write_sidecar(&client, &recording_url, segment, wav_path)?;
                }

                Ok(())
            })(),
        },
        Command::Record {
            frequency,
            mode,
            location,
            bandwidth,
            duration,
            count,
            output_dir,
        } => (|| {
            // If location or mode not provided, try POTA spot lookup
            let (resolved_mode, resolved_location) =
                resolve_record_params(&client, frequency, mode.as_deref(), location.as_deref())?;

            let dir = output_dir.unwrap_or_else(|| default_output_dir("recording"));
            execute_recording_workflow(
                &client,
                base,
                frequency,
                &resolved_mode,
                &resolved_location,
                bandwidth,
                duration,
                count,
                &dir,
            )
        })(),
        Command::Monitor {
            location,
            duration,
            sdrs_per_spot,
            bandwidth,
            poll_interval,
            output_dir,
            mode_filter,
            band,
        } => {
            let dir = output_dir.unwrap_or_else(|| default_output_dir("monitor"));
            run_monitor(
                &client,
                base,
                location.as_deref(),
                duration,
                sdrs_per_spot,
                bandwidth,
                poll_interval,
                &dir,
                &mode_filter,
                band.as_deref(),
            )
        }
    };

    if let Err(e) = result {
        eprintln!("Error: {e}");
        process::exit(1);
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_frequency_to_band_known() {
        assert_eq!(frequency_to_band(14058.5), Some("20m"));
        assert_eq!(frequency_to_band(7030.0), Some("40m"));
        assert_eq!(frequency_to_band(21060.0), Some("15m"));
        assert_eq!(frequency_to_band(10115.0), Some("30m"));
        assert_eq!(frequency_to_band(3550.0), Some("80m"));
        assert_eq!(frequency_to_band(1850.0), Some("160m"));
        assert_eq!(frequency_to_band(18100.0), Some("17m"));
        assert_eq!(frequency_to_band(24920.0), Some("12m"));
        assert_eq!(frequency_to_band(28050.0), Some("10m"));
    }

    #[test]
    fn test_frequency_to_band_out_of_range() {
        assert_eq!(frequency_to_band(5000.0), None);
        assert_eq!(frequency_to_band(50000.0), None);
        assert_eq!(frequency_to_band(0.0), None);
    }

    #[test]
    fn test_spot_key_from_spot() {
        let spot = PotaSpot {
            spot_id: 1,
            activator: "W1AW".to_string(),
            frequency: "14062.5".to_string(),
            mode: "CW".to_string(),
            reference: "K-1234".to_string(),
            park_name: "Test Park".to_string(),
            spot_time: "2025-01-15T12:00:00Z".to_string(),
            spotter: None,
            comments: None,
            source: None,
            location_desc: "US-NH".to_string(),
            grid4: Some("FN43".to_string()),
            grid6: Some("FN43gi".to_string()),
            latitude: Some(43.2),
            longitude: Some(-71.5),
        };

        let key = SpotKey::from_spot(&spot).unwrap();
        assert_eq!(key.activator, "W1AW");
        assert_eq!(key.reference, "K-1234");
        assert_eq!(key.frequency_khz, 14063); // 14062.5 rounded
    }

    #[test]
    fn test_spot_key_dedup() {
        let mut seen = HashSet::new();

        let key1 = SpotKey {
            activator: "W1AW".to_string(),
            reference: "K-1234".to_string(),
            frequency_khz: 14063,
        };
        let key2 = SpotKey {
            activator: "W1AW".to_string(),
            reference: "K-1234".to_string(),
            frequency_khz: 14063,
        };
        let key3 = SpotKey {
            activator: "W1AW".to_string(),
            reference: "K-5678".to_string(),
            frequency_khz: 14063,
        };

        assert!(seen.insert(key1));
        assert!(!seen.insert(key2)); // duplicate
        assert!(seen.insert(key3)); // different reference
    }

    #[test]
    fn test_filter_spots_by_mode() {
        let spots = vec![
            make_test_spot("CW", "14060"),
            make_test_spot("SSB", "14250"),
            make_test_spot("cw", "7030"),
        ];

        let filtered = filter_spots(spots, "cw", None);
        assert_eq!(filtered.len(), 2);
    }

    #[test]
    fn test_filter_spots_all_modes() {
        let spots = vec![
            make_test_spot("CW", "14060"),
            make_test_spot("SSB", "14250"),
        ];

        let filtered = filter_spots(spots, "all", None);
        assert_eq!(filtered.len(), 2);
    }

    #[test]
    fn test_filter_spots_by_band() {
        let spots = vec![
            make_test_spot("CW", "14060"),
            make_test_spot("CW", "7030"),
            make_test_spot("CW", "21060"),
        ];

        let filtered = filter_spots(spots, "cw", Some("20m"));
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].frequency, "14060");
    }

    #[test]
    fn test_grid_to_latlon() {
        let (lat, lon) = grid_to_latlon("EM55").unwrap();
        // EM55 center: lat ~35.5, lon ~-89.0
        assert!((lat - 35.5).abs() < 1.0);
        assert!((lon - (-89.0)).abs() < 1.0);
    }

    #[test]
    fn test_spot_location_prefers_latlon() {
        let mut spot = make_test_spot("CW", "14060");
        spot.latitude = Some(44.31);
        spot.longitude = Some(-68.20);
        spot.grid6 = Some("FN54vh".to_string());

        let loc = spot.location_string().unwrap();
        assert_eq!(loc, "44.31,-68.2");
    }

    #[test]
    fn test_spot_location_falls_back_to_grid() {
        let mut spot = make_test_spot("CW", "14060");
        spot.grid6 = Some("FN54vh".to_string());

        let loc = spot.location_string().unwrap();
        assert_eq!(loc, "FN54vh");
    }

    #[test]
    fn test_spot_location_none_when_no_data() {
        let spot = make_test_spot("CW", "14060");
        assert!(spot.location_string().is_none());
    }

    fn make_test_spot(mode: &str, freq: &str) -> PotaSpot {
        PotaSpot {
            spot_id: 1,
            activator: "TEST".to_string(),
            frequency: freq.to_string(),
            mode: mode.to_string(),
            reference: "K-0001".to_string(),
            park_name: "Test".to_string(),
            spot_time: "".to_string(),
            spotter: None,
            comments: None,
            source: None,
            location_desc: "US-XX".to_string(),
            grid4: None,
            grid6: None,
            latitude: None,
            longitude: None,
        }
    }
}
