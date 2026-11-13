use crate::types::{DemodMode, GainSetting};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

use crate::error::ConfigError;

/// Top-level server configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    pub server: ServerSection,
    #[serde(default)]
    pub discovery: DiscoverySection,
    #[serde(default)]
    pub recording: Vec<RecordingSection>,
    #[serde(default)]
    pub storage: StorageSection,
    #[serde(default)]
    pub time: TimeSection,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerSection {
    pub name: String,
    #[serde(default = "default_listen_addr")]
    pub listen_addr: String,
    #[serde(default = "default_port")]
    pub port: u16,
    /// Maidenhead grid locator.
    #[serde(default)]
    pub location: Option<String>,
}

fn default_listen_addr() -> String {
    "0.0.0.0".to_string()
}

fn default_port() -> u16 {
    8080
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiscoverySection {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_rescan_interval")]
    pub rescan_interval_secs: u64,
    #[serde(default = "default_true")]
    pub mdns_enabled: bool,
    #[serde(default)]
    pub mdns_browse_types: Vec<String>,
    /// Per-device overrides keyed by serial number or device ID.
    #[serde(default)]
    pub overrides: HashMap<String, SdrOverride>,
    /// Manually configured network SDRs.
    #[serde(default)]
    pub network_sdrs: Vec<NetworkSdrConfig>,
    /// Enable auto-discovery from the public KiwiSDR directory.
    #[serde(default)]
    pub kiwisdr_directory: bool,
    /// Country/region codes to filter KiwiSDR directory results.
    /// Examples: ["US"], ["US", "CA"], ["EU"], ["*"]
    #[serde(default)]
    pub kiwisdr_regions: Vec<String>,
}

impl Default for DiscoverySection {
    fn default() -> Self {
        Self {
            enabled: true,
            rescan_interval_secs: default_rescan_interval(),
            mdns_enabled: true,
            mdns_browse_types: vec!["_kiwisdr._tcp".to_string(), "_smartsdr._tcp".to_string()],
            overrides: HashMap::new(),
            network_sdrs: Vec::new(),
            kiwisdr_directory: false,
            kiwisdr_regions: Vec::new(),
        }
    }
}

fn default_true() -> bool {
    true
}

fn default_rescan_interval() -> u64 {
    30
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SdrOverride {
    #[serde(default)]
    pub label: Option<String>,
    #[serde(default)]
    pub antenna: Option<String>,
    #[serde(default)]
    pub gain: Option<GainSetting>,
    #[serde(default)]
    pub sample_rate: Option<u32>,
    #[serde(default)]
    pub enabled: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkSdrConfig {
    pub driver: String,
    pub url: String,
    #[serde(default)]
    pub label: Option<String>,
    #[serde(default)]
    pub gain: Option<GainSetting>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecordingSection {
    /// SDR device ID to use (matches discovered serial/ID).
    pub sdr: String,
    /// Center frequency in Hz.
    pub frequency: u64,
    /// Bandwidth in Hz.
    #[serde(default = "default_bandwidth")]
    pub bandwidth: u32,
    /// Demodulation mode.
    pub mode: DemodMode,
    /// Schedule string: "always" or "HH:MM-HH:MM UTC".
    #[serde(default = "default_schedule")]
    pub schedule: String,
    /// Retention in days (0 = forever).
    #[serde(default)]
    pub retention_days: u32,
}

fn default_bandwidth() -> u32 {
    500
}

fn default_schedule() -> String {
    "always".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StorageSection {
    /// Base directory for recorded audio files.
    #[serde(default = "default_data_dir")]
    pub data_dir: PathBuf,
    /// SQLite database file path.
    #[serde(default = "default_db_path")]
    pub db_path: PathBuf,
    /// Segment duration in seconds.
    #[serde(default = "default_segment_duration")]
    pub segment_duration_secs: u64,
}

impl Default for StorageSection {
    fn default() -> Self {
        Self {
            data_dir: default_data_dir(),
            db_path: default_db_path(),
            segment_duration_secs: default_segment_duration(),
        }
    }
}

fn default_data_dir() -> PathBuf {
    PathBuf::from("data/recordings")
}

fn default_db_path() -> PathBuf {
    PathBuf::from("data/sdr-server.db")
}

fn default_segment_duration() -> u64 {
    300 // 5 minutes
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeSection {
    /// NTP server to use for time synchronization.
    #[serde(default = "default_ntp_server")]
    pub ntp_server: String,
    /// How often to re-sync NTP (seconds).
    #[serde(default = "default_ntp_interval")]
    pub sync_interval_secs: u64,
}

impl Default for TimeSection {
    fn default() -> Self {
        Self {
            ntp_server: default_ntp_server(),
            sync_interval_secs: default_ntp_interval(),
        }
    }
}

fn default_ntp_server() -> String {
    "pool.ntp.org".to_string()
}

fn default_ntp_interval() -> u64 {
    3600 // 1 hour
}

impl ServerConfig {
    /// Load configuration from a TOML file.
    pub fn from_file(path: &Path) -> Result<Self, ConfigError> {
        let contents = std::fs::read_to_string(path)?;
        let config: ServerConfig = toml::from_str(&contents)?;
        config.validate()?;
        Ok(config)
    }

    /// Parse configuration from a TOML string.
    pub fn parse(s: &str) -> Result<Self, ConfigError> {
        let config: ServerConfig = toml::from_str(s)?;
        config.validate()?;
        Ok(config)
    }

    fn validate(&self) -> Result<(), ConfigError> {
        if self.server.name.is_empty() {
            return Err(ConfigError::Invalid("server.name must not be empty".into()));
        }
        if self.server.port == 0 {
            return Err(ConfigError::Invalid("server.port must be > 0".into()));
        }
        for (i, rec) in self.recording.iter().enumerate() {
            if rec.frequency == 0 {
                return Err(ConfigError::Invalid(format!(
                    "recording[{i}].frequency must be > 0"
                )));
            }
            if rec.bandwidth == 0 {
                return Err(ConfigError::Invalid(format!(
                    "recording[{i}].bandwidth must be > 0"
                )));
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_minimal_config() {
        let toml = r#"
[server]
name = "test-server"
"#;
        let config = ServerConfig::parse(toml).unwrap();
        assert_eq!(config.server.name, "test-server");
        assert_eq!(config.server.port, 8080);
        assert!(config.discovery.enabled);
        assert!(config.recording.is_empty());
    }

    #[test]
    fn parse_full_config() {
        let toml = r#"
[server]
name = "k1abc-sdr-server"
location = "FN42ig"
port = 9090

[discovery]
enabled = true
rescan_interval_secs = 60

[discovery.overrides."00000001"]
label = "40m Dipole"
antenna = "dipole-40m"

[[discovery.network_sdrs]]
driver = "kiwisdr"
url = "http://example.com:8073"
label = "Remote Kiwi"

[[recording]]
sdr = "00000001"
frequency = 7030000
bandwidth = 2400
mode = "cw"
schedule = "always"
retention_days = 30

[storage]
data_dir = "/tmp/sdr-data"
db_path = "/tmp/sdr-data/test.db"
segment_duration_secs = 600

[time]
ntp_server = "time.google.com"
sync_interval_secs = 1800
"#;
        let config = ServerConfig::parse(toml).unwrap();
        assert_eq!(config.server.name, "k1abc-sdr-server");
        assert_eq!(config.server.port, 9090);
        assert_eq!(config.discovery.rescan_interval_secs, 60);
        assert_eq!(config.discovery.overrides.len(), 1);
        assert_eq!(config.discovery.network_sdrs.len(), 1);
        assert_eq!(config.recording.len(), 1);
        assert_eq!(config.recording[0].frequency, 7_030_000);
        assert_eq!(config.storage.segment_duration_secs, 600);
        assert_eq!(config.time.ntp_server, "time.google.com");
    }

    #[test]
    fn reject_empty_name() {
        let toml = r#"
[server]
name = ""
"#;
        let err = ServerConfig::parse(toml).unwrap_err();
        assert!(err.to_string().contains("name must not be empty"));
    }

    #[test]
    fn reject_zero_frequency() {
        let toml = r#"
[server]
name = "test"

[[recording]]
sdr = "abc"
frequency = 0
mode = "cw"
"#;
        let err = ServerConfig::parse(toml).unwrap_err();
        assert!(err.to_string().contains("frequency must be > 0"));
    }
}
