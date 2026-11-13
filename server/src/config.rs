// src/config.rs
use std::env;

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct Config {
    pub database_url: String,
    /// sqlx pool size (`DATABASE_MAX_CONNECTIONS`, default 16). Shared by
    /// HTTP handlers, aggregators and background loops.
    pub database_max_connections: u32,
    pub admin_token: String,
    pub port: u16,
    pub base_url: Option<String>,
    pub invite_base_url: String,
    pub invite_expiry_days: i64,
    pub spots_enabled: bool,
    pub pota_aggregator_enabled: bool,
    pub sota_aggregator_enabled: bool,
    pub pota_stats_aggregator_enabled: bool,
    pub pota_stats_concurrency: usize,
    pub pota_stats_batch_size: i64,
    pub pota_stats_cycle_hours: u64,
    pub pota_stats_min_request_interval_ms: u64,
    pub park_boundaries_enabled: bool,
    pub park_boundaries_batch_size: i64,
    pub park_boundaries_cycle_hours: u64,
    pub park_boundaries_stale_days: i64,
    pub park_boundaries_concurrency: usize,
    pub polish_park_boundaries_enabled: bool,
    pub polish_park_boundaries_batch_size: i64,
    pub polish_park_boundaries_cycle_hours: u64,
    pub polish_park_boundaries_stale_days: i64,
    pub polish_park_boundaries_concurrency: usize,
    pub historic_trails_enabled: bool,
    pub historic_trails_batch_size: i64,
    pub historic_trails_cycle_hours: u64,
    pub historic_trails_stale_days: i64,
    pub historic_trails_concurrency: usize,
    pub rbn_proxy_enabled: bool,
    pub rbn_proxy_callsign: String,
    pub snapshot_enabled: bool,
    pub snapshot_dir: String,
    pub snapshot_interval_hours: u64,
    pub snapshot_max_age_hours: u64,
    pub propagation_enabled: bool,
    pub propagation_service_url: String,
    pub propagation_cache_ttl_hours: i64,
    pub propagation_request_timeout_secs: u64,
    pub achievement_evaluator_enabled: bool,
    pub achievement_evaluator_interval_minutes: u64,
    pub achievement_evaluator_recent_days: i32,
    pub callsign_enrichment_aggregator_enabled: bool,
    pub callsign_enrichment_cycle_hours: u64,
    pub club_roster_sync_enabled: bool,
    pub club_roster_sync_cycle_hours: u64,
    pub amsat_status_aggregator_enabled: bool,
    pub amsat_status_cycle_minutes: u64,
    /// AMSAT status API base (`…/api/v1`); unset means status.amsat.org.
    pub amsat_status_api_base: Option<String>,
    pub macros_retention_enabled: bool,
    pub macros_retention_interval_hours: u64,
    pub macros_retention_retain_days: i32,
    // Sync server object storage (S3). All optional: when `s3_bucket` is unset
    // the server falls back to the in-memory blob store (dev/test only).
    pub s3_bucket: Option<String>,
    pub s3_endpoint: Option<String>,
    pub s3_region: Option<String>,
    pub s3_access_key_id: Option<String>,
    pub s3_secret_access_key: Option<String>,
}

impl Config {
    pub fn from_env() -> Result<Self, ConfigError> {
        let database_url =
            env::var("DATABASE_URL").map_err(|_| ConfigError::Missing("DATABASE_URL"))?;

        // Shared sqlx pool size. Must leave room under Postgres'
        // `max_connections` for every other process on the same server
        // (see the pool comment in main.rs).
        let database_max_connections: u32 = env::var("DATABASE_MAX_CONNECTIONS")
            .unwrap_or_else(|_| "16".to_string())
            .parse()
            .ok()
            .filter(|n| *n > 0)
            .unwrap_or(16);

        let admin_token =
            env::var("ADMIN_TOKEN").map_err(|_| ConfigError::Missing("ADMIN_TOKEN"))?;

        let port = env::var("PORT")
            .unwrap_or_else(|_| "8080".to_string())
            .parse()
            .map_err(|_| ConfigError::Invalid("PORT must be a number"))?;

        let base_url = env::var("BASE_URL").ok();

        let invite_base_url = env::var("INVITE_BASE_URL")
            .unwrap_or_else(|_| "https://activities.carrierwave.app".to_string());

        let invite_expiry_days = env::var("INVITE_EXPIRY_DAYS")
            .unwrap_or_else(|_| "7".to_string())
            .parse()
            .map_err(|_| ConfigError::Invalid("INVITE_EXPIRY_DAYS must be a number"))?;

        let spots_enabled = env::var("SPOTS_ENABLED")
            .unwrap_or_else(|_| "true".to_string())
            .parse()
            .unwrap_or(true);

        let pota_aggregator_enabled = env::var("POTA_AGGREGATOR_ENABLED")
            .unwrap_or_else(|_| "false".to_string())
            .parse()
            .unwrap_or(false);

        let sota_aggregator_enabled = env::var("SOTA_AGGREGATOR_ENABLED")
            .unwrap_or_else(|_| "false".to_string())
            .parse()
            .unwrap_or(false);

        let pota_stats_aggregator_enabled = env::var("POTA_STATS_AGGREGATOR_ENABLED")
            .unwrap_or_else(|_| "false".to_string())
            .parse()
            .unwrap_or(false);

        let pota_stats_concurrency: usize = env::var("POTA_STATS_CONCURRENCY")
            .unwrap_or_else(|_| "3".to_string())
            .parse()
            .unwrap_or(3);

        let pota_stats_batch_size: i64 = env::var("POTA_STATS_BATCH_SIZE")
            .unwrap_or_else(|_| "50".to_string())
            .parse()
            .unwrap_or(50);

        let pota_stats_cycle_hours: u64 = env::var("POTA_STATS_CYCLE_HOURS")
            .unwrap_or_else(|_| "24".to_string())
            .parse()
            .unwrap_or(24);

        let pota_stats_min_request_interval_ms: u64 =
            env::var("POTA_STATS_MIN_REQUEST_INTERVAL_MS")
                .unwrap_or_else(|_| "500".to_string())
                .parse()
                .unwrap_or(500);

        let park_boundaries_enabled = env::var("PARK_BOUNDARIES_ENABLED")
            .unwrap_or_else(|_| "false".to_string())
            .parse()
            .unwrap_or(false);

        let park_boundaries_batch_size: i64 = env::var("PARK_BOUNDARIES_BATCH_SIZE")
            .unwrap_or_else(|_| "20".to_string())
            .parse()
            .unwrap_or(20);

        let park_boundaries_cycle_hours: u64 = env::var("PARK_BOUNDARIES_CYCLE_HOURS")
            .unwrap_or_else(|_| "24".to_string())
            .parse()
            .unwrap_or(24);

        let park_boundaries_stale_days: i64 = env::var("PARK_BOUNDARIES_STALE_DAYS")
            .unwrap_or_else(|_| "90".to_string())
            .parse()
            .unwrap_or(90);

        let park_boundaries_concurrency: usize = env::var("PARK_BOUNDARIES_CONCURRENCY")
            .unwrap_or_else(|_| "5".to_string())
            .parse()
            .unwrap_or(5);

        let polish_park_boundaries_enabled = env::var("POLISH_PARK_BOUNDARIES_ENABLED")
            .unwrap_or_else(|_| "false".to_string())
            .parse()
            .unwrap_or(false);

        let historic_trails_enabled = env::var("HISTORIC_TRAILS_ENABLED")
            .unwrap_or_else(|_| "false".to_string())
            .parse()
            .unwrap_or(false);

        let polish_park_boundaries_batch_size: i64 = env::var("POLISH_PARK_BOUNDARIES_BATCH_SIZE")
            .unwrap_or_else(|_| "20".to_string())
            .parse()
            .unwrap_or(20);

        let polish_park_boundaries_cycle_hours: u64 =
            env::var("POLISH_PARK_BOUNDARIES_CYCLE_HOURS")
                .unwrap_or_else(|_| "24".to_string())
                .parse()
                .unwrap_or(24);

        let polish_park_boundaries_stale_days: i64 = env::var("POLISH_PARK_BOUNDARIES_STALE_DAYS")
            .unwrap_or_else(|_| "90".to_string())
            .parse()
            .unwrap_or(90);

        let polish_park_boundaries_concurrency: usize =
            env::var("POLISH_PARK_BOUNDARIES_CONCURRENCY")
                .unwrap_or_else(|_| "3".to_string())
                .parse()
                .unwrap_or(3);

        let historic_trails_batch_size: i64 = env::var("HISTORIC_TRAILS_BATCH_SIZE")
            .unwrap_or_else(|_| "20".to_string())
            .parse()
            .unwrap_or(20);

        let historic_trails_cycle_hours: u64 = env::var("HISTORIC_TRAILS_CYCLE_HOURS")
            .unwrap_or_else(|_| "168".to_string())
            .parse()
            .unwrap_or(168);

        let historic_trails_stale_days: i64 = env::var("HISTORIC_TRAILS_STALE_DAYS")
            .unwrap_or_else(|_| "180".to_string())
            .parse()
            .unwrap_or(180);

        let historic_trails_concurrency: usize = env::var("HISTORIC_TRAILS_CONCURRENCY")
            .unwrap_or_else(|_| "5".to_string())
            .parse()
            .unwrap_or(5);

        let rbn_proxy_enabled = env::var("RBN_PROXY_ENABLED")
            .unwrap_or_else(|_| "false".to_string())
            .parse()
            .unwrap_or(false);

        let rbn_proxy_callsign =
            env::var("RBN_PROXY_CALLSIGN").unwrap_or_else(|_| "W6JSV".to_string());

        let snapshot_enabled = env::var("SNAPSHOT_ENABLED")
            .unwrap_or_else(|_| "true".to_string())
            .parse()
            .unwrap_or(true);

        let snapshot_dir =
            env::var("SNAPSHOT_DIR").unwrap_or_else(|_| "data/snapshots".to_string());

        let snapshot_interval_hours: u64 = env::var("SNAPSHOT_INTERVAL_HOURS")
            .unwrap_or_else(|_| "1".to_string())
            .parse()
            .unwrap_or(1);

        let snapshot_max_age_hours: u64 = env::var("SNAPSHOT_MAX_AGE_HOURS")
            .unwrap_or_else(|_| "24".to_string())
            .parse()
            .unwrap_or(24);

        let propagation_enabled = env::var("PROPAGATION_ENABLED")
            .unwrap_or_else(|_| "false".to_string())
            .parse()
            .unwrap_or(false);

        let propagation_service_url = env::var("PROPAGATION_SERVICE_URL")
            .unwrap_or_else(|_| "http://127.0.0.1:8090".to_string());

        let propagation_cache_ttl_hours: i64 = env::var("PROPAGATION_CACHE_TTL_HOURS")
            .unwrap_or_else(|_| "24".to_string())
            .parse()
            .unwrap_or(24);

        let propagation_request_timeout_secs: u64 = env::var("PROPAGATION_REQUEST_TIMEOUT_SECS")
            .unwrap_or_else(|_| "30".to_string())
            .parse()
            .unwrap_or(30);

        let achievement_evaluator_enabled = env::var("ACHIEVEMENT_EVALUATOR_ENABLED")
            .unwrap_or_else(|_| "true".to_string())
            .parse()
            .unwrap_or(true);

        let achievement_evaluator_interval_minutes: u64 =
            env::var("ACHIEVEMENT_EVALUATOR_INTERVAL_MINUTES")
                .unwrap_or_else(|_| "15".to_string())
                .parse()
                .unwrap_or(15);

        let achievement_evaluator_recent_days: i32 = env::var("ACHIEVEMENT_EVALUATOR_RECENT_DAYS")
            .unwrap_or_else(|_| "1".to_string())
            .parse()
            .unwrap_or(1);

        let callsign_enrichment_aggregator_enabled =
            env::var("CALLSIGN_ENRICHMENT_AGGREGATOR_ENABLED")
                .unwrap_or_else(|_| "true".to_string())
                .parse()
                .unwrap_or(true);

        let callsign_enrichment_cycle_hours: u64 = env::var("CALLSIGN_ENRICHMENT_CYCLE_HOURS")
            .unwrap_or_else(|_| "24".to_string())
            .parse()
            .unwrap_or(24);

        let club_roster_sync_enabled = env::var("CLUB_ROSTER_SYNC_ENABLED")
            .unwrap_or_else(|_| "true".to_string())
            .parse()
            .unwrap_or(true);

        // Notes files (e.g. bkg.club/members.txt) regenerate daily; 6 h keeps
        // rosters same-day fresh at four small fetches per club per day.
        let club_roster_sync_cycle_hours: u64 = env::var("CLUB_ROSTER_SYNC_CYCLE_HOURS")
            .unwrap_or_else(|_| "6".to_string())
            .parse()
            .unwrap_or(6);

        let amsat_status_aggregator_enabled = env::var("AMSAT_STATUS_AGGREGATOR_ENABLED")
            .unwrap_or_else(|_| "true".to_string())
            .parse()
            .unwrap_or(true);

        let amsat_status_cycle_minutes: u64 = env::var("AMSAT_STATUS_CYCLE_MINUTES")
            .unwrap_or_else(|_| "30".to_string())
            .parse()
            .unwrap_or(30);

        let amsat_status_api_base = env::var("AMSAT_STATUS_API_BASE")
            .ok()
            .filter(|base| !base.trim().is_empty());

        let macros_retention_enabled = env::var("MACROS_RETENTION_ENABLED")
            .unwrap_or_else(|_| "true".to_string())
            .parse()
            .unwrap_or(true);

        let macros_retention_interval_hours: u64 = env::var("MACROS_RETENTION_INTERVAL_HOURS")
            .unwrap_or_else(|_| "24".to_string())
            .parse()
            .unwrap_or(24);

        let macros_retention_retain_days: i32 = env::var("MACROS_RETENTION_RETAIN_DAYS")
            .unwrap_or_else(|_| "90".to_string())
            .parse()
            .unwrap_or(90);

        // Sync server object storage. All optional — absence selects the
        // in-memory blob store so the server still boots without S3.
        let s3_bucket = env::var("SYNC_S3_BUCKET").ok();
        let s3_endpoint = env::var("SYNC_S3_ENDPOINT").ok();
        let s3_region = env::var("SYNC_S3_REGION").ok();
        let s3_access_key_id = env::var("SYNC_S3_ACCESS_KEY_ID").ok();
        let s3_secret_access_key = env::var("SYNC_S3_SECRET_ACCESS_KEY").ok();

        Ok(Self {
            database_url,
            database_max_connections,
            admin_token,
            port,
            base_url,
            invite_base_url,
            invite_expiry_days,
            spots_enabled,
            pota_aggregator_enabled,
            sota_aggregator_enabled,
            pota_stats_aggregator_enabled,
            pota_stats_concurrency,
            pota_stats_batch_size,
            pota_stats_cycle_hours,
            pota_stats_min_request_interval_ms,
            park_boundaries_enabled,
            park_boundaries_batch_size,
            park_boundaries_cycle_hours,
            park_boundaries_stale_days,
            park_boundaries_concurrency,
            polish_park_boundaries_enabled,
            polish_park_boundaries_batch_size,
            polish_park_boundaries_cycle_hours,
            polish_park_boundaries_stale_days,
            polish_park_boundaries_concurrency,
            historic_trails_enabled,
            historic_trails_batch_size,
            historic_trails_cycle_hours,
            historic_trails_stale_days,
            historic_trails_concurrency,
            rbn_proxy_enabled,
            rbn_proxy_callsign,
            snapshot_enabled,
            snapshot_dir,
            snapshot_interval_hours,
            snapshot_max_age_hours,
            propagation_enabled,
            propagation_service_url,
            propagation_cache_ttl_hours,
            propagation_request_timeout_secs,
            achievement_evaluator_enabled,
            achievement_evaluator_interval_minutes,
            achievement_evaluator_recent_days,
            callsign_enrichment_aggregator_enabled,
            callsign_enrichment_cycle_hours,
            club_roster_sync_enabled,
            club_roster_sync_cycle_hours,
            amsat_status_aggregator_enabled,
            amsat_status_cycle_minutes,
            amsat_status_api_base,
            macros_retention_enabled,
            macros_retention_interval_hours,
            macros_retention_retain_days,
            s3_bucket,
            s3_endpoint,
            s3_region,
            s3_access_key_id,
            s3_secret_access_key,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("Missing required environment variable: {0}")]
    Missing(&'static str),
    #[error("Invalid configuration: {0}")]
    Invalid(&'static str),
}

/// Output format for the `tracing_subscriber` fmt layer, selected by
/// `LOG_FORMAT`. Production and staging run under systemd with `json` so
/// `journalctl -o cat | jq` and a future Loki/Grafana shipper see one
/// structured object per line (CAR-156, audit T4-2). `pretty` / `compact`
/// are for humans reading a terminal in local dev.
///
/// Read separately from [`Config::from_env`] because the subscriber has to be
/// installed before the rest of the config is validated (a bad `DATABASE_URL`
/// should still be reported through the configured log format).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum LogFormat {
    #[default]
    Json,
    Pretty,
    Compact,
}

impl LogFormat {
    pub const ENV_VAR: &'static str = "LOG_FORMAT";

    /// `LOG_FORMAT=json|pretty|compact` (case-insensitive). Unset → `json`.
    /// Returns the parsed format plus the raw value if it was unrecognised so
    /// the caller can warn once the subscriber is up (the default is still
    /// used — a typo must never leave the server without logs).
    pub fn from_env() -> (Self, Option<String>) {
        match env::var(Self::ENV_VAR) {
            Ok(raw) => match raw.parse::<Self>() {
                Ok(format) => (format, None),
                Err(()) => (Self::default(), Some(raw)),
            },
            Err(_) => (Self::default(), None),
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Json => "json",
            Self::Pretty => "pretty",
            Self::Compact => "compact",
        }
    }
}

impl std::str::FromStr for LogFormat {
    type Err = ();

    fn from_str(s: &str) -> Result<Self, ()> {
        match s.trim().to_ascii_lowercase().as_str() {
            "json" => Ok(Self::Json),
            "pretty" => Ok(Self::Pretty),
            "compact" => Ok(Self::Compact),
            _ => Err(()),
        }
    }
}

#[cfg(test)]
mod log_format_tests {
    use super::LogFormat;

    #[test]
    fn parses_known_formats_case_insensitively() {
        assert_eq!("json".parse::<LogFormat>(), Ok(LogFormat::Json));
        assert_eq!(" Pretty ".parse::<LogFormat>(), Ok(LogFormat::Pretty));
        assert_eq!("COMPACT".parse::<LogFormat>(), Ok(LogFormat::Compact));
        assert_eq!("yaml".parse::<LogFormat>(), Err(()));
    }

    #[test]
    fn default_is_json() {
        assert_eq!(LogFormat::default(), LogFormat::Json);
        assert_eq!(LogFormat::Json.as_str(), "json");
    }
}
