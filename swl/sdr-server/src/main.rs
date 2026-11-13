use std::sync::Arc;

use anyhow::{Context, Result};
use tokio::signal;
use tokio::sync::Mutex;
use tracing::{info, warn};

use sdr_core::api::{self, AppState};
use sdr_core::config::ServerConfig;
use sdr_core::db::Database;
use sdr_core::mux::CaptureMultiplexer;
use sdr_core::recording::RecordingEngine;
use sdr_core::sdr::discovery::SdrRegistry;
use sdr_core::time::TimestampProvider;
use sdr_core::transcription::TranscriptionEngine;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,sdr_core=debug,sdr_server=debug".into()),
        )
        .init();

    // Parse CLI args
    let config_path = std::env::args()
        .nth(1)
        .or_else(|| {
            std::env::args()
                .position(|a| a == "--config")
                .and_then(|i| std::env::args().nth(i + 1))
        })
        .unwrap_or_else(|| "config.toml".into());

    info!(config = %config_path, "Loading configuration");
    let config = ServerConfig::from_file(std::path::Path::new(&config_path))
        .context("Failed to load config")?;

    // Ensure data directories exist
    std::fs::create_dir_all(&config.storage.data_dir).context("Failed to create data directory")?;
    if let Some(parent) = config.storage.db_path.parent() {
        std::fs::create_dir_all(parent).context("Failed to create DB directory")?;
    }

    // Initialize database
    let db_path = config.storage.db_path.to_string_lossy().to_string();
    let db = Database::open(&db_path).context("Failed to open database")?;
    let db = Arc::new(Mutex::new(db));

    // Initialize NTP time provider
    let time_provider = TimestampProvider::new(&config.time.ntp_server);
    match time_provider.sync() {
        Ok(offset) => info!(offset_ms = offset.num_milliseconds(), "Initial NTP sync"),
        Err(e) => warn!(error = %e, "Initial NTP sync failed, using system time"),
    }
    let _time_handle = time_provider.start_sync_loop(config.time.sync_interval_secs);

    // Initialize SDR discovery
    let registry = Arc::new(SdrRegistry::new(config.discovery.clone()));
    registry.scan().await;
    let discovered = registry.list().await;
    info!(count = discovered.len(), "Initial SDR scan complete");

    // Start periodic discovery
    let _discovery_handle =
        Arc::clone(&registry).start_scan_loop(config.discovery.rescan_interval_secs);

    // Initialize capture multiplexer
    let mux = Arc::new(CaptureMultiplexer::new(Arc::clone(&registry), 30));
    let _cleanup_handle = Arc::clone(&mux).start_cleanup_loop();

    // Initialize recording engine
    let recording_engine = Arc::new(RecordingEngine::new(
        Arc::clone(&mux),
        Arc::clone(&db),
        config.storage.data_dir.clone(),
        config.storage.segment_duration_secs as f64,
    ));

    // Initialize transcription engine (with data_dir for upload-based transcription)
    let transcription_engine = Arc::new(TranscriptionEngine::with_data_dir(
        Arc::clone(&db),
        config.storage.data_dir.clone(),
    ));

    // Build API
    let state = Arc::new(AppState::new(
        Arc::clone(&registry),
        Arc::clone(&mux),
        Arc::clone(&recording_engine),
        transcription_engine,
        Arc::clone(&db),
        Some(std::path::PathBuf::from("web")),
        config.storage.data_dir.clone(),
    ));
    let app = api::router(state);

    // Start server
    let addr = format!("{}:{}", config.server.listen_addr, config.server.port);
    let listener = tokio::net::TcpListener::bind(&addr)
        .await
        .context(format!("Failed to bind to {addr}"))?;
    info!(addr = %addr, name = %config.server.name, "Server started");

    // Serve with graceful shutdown
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .context("Server error")?;

    // Graceful shutdown
    info!("Shutting down...");
    recording_engine.stop_all().await;
    info!("All recordings stopped, goodbye!");

    Ok(())
}

async fn shutdown_signal() {
    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
}
