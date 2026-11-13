pub mod achievements;
pub mod amsat_status;
pub mod callsign_enrichment;
pub mod club_rosters;
pub mod historic_trails;
pub mod macros_retention;
pub mod park_boundaries;
pub mod polish_park_boundaries;
pub mod pota;
pub mod pota_stats;
pub mod sota;
pub mod state_park_sources;

use std::time::Duration;

use sqlx::PgPool;

use crate::config::Config;
use crate::metrics as app_metrics;

/// Shared reqwest client for all aggregators. Carries a request + connect
/// timeout so a connected-but-idle upstream (slow-loris, stalled TLS, half-open
/// NAT) can't leave `send()`/`text()` pending forever and permanently wedge a
/// poll loop (CAR-326 / CAR-329 / CAR-331). Previously each builder set only a
/// user-agent and reqwest applies no default timeout.
fn aggregator_client() -> reqwest::Client {
    reqwest::Client::builder()
        .user_agent(format!(
            "{}/{}",
            env!("CARGO_PKG_NAME"),
            env!("CARGO_PKG_VERSION")
        ))
        .timeout(Duration::from_secs(60))
        .connect_timeout(Duration::from_secs(10))
        .build()
        .expect("failed to build HTTP client")
}

/// Spawn all aggregator background tasks and the TTL cleanup task.
pub fn spawn_aggregators(pool: PgPool, config: &Config) {
    // TTL cleanup always runs
    let cleanup_pool = pool.clone();
    tokio::spawn(async move {
        ttl_cleanup_loop(cleanup_pool).await;
    });

    // Shared HTTP client for all aggregators
    let client = aggregator_client();

    if config.pota_aggregator_enabled {
        let pota_pool = pool.clone();
        let pota_client = client.clone();
        tokio::spawn(async move {
            pota::poll_loop(pota_pool, pota_client).await;
        });
        tracing::info!("POTA aggregator started");
    }

    if config.sota_aggregator_enabled {
        let sota_pool = pool.clone();
        let sota_client = client.clone();
        tokio::spawn(async move {
            sota::poll_loop(sota_pool, sota_client).await;
        });
        tracing::info!("SOTA aggregator started");
    }
}

/// Spawn the historic trails aggregator.
pub fn spawn_historic_trails_aggregator(pool: PgPool, config: &Config) {
    let client = aggregator_client();
    let trails_config = historic_trails::HistoricTrailsConfig {
        batch_size: config.historic_trails_batch_size,
        cycle_hours: config.historic_trails_cycle_hours,
        stale_days: config.historic_trails_stale_days,
        concurrency: config.historic_trails_concurrency,
    };
    tokio::spawn(async move {
        historic_trails::poll_loop(pool, client, trails_config).await;
    });
    tracing::info!("Historic trails aggregator started");
}

/// Spawn the park boundaries aggregator (requires POTA stats for park catalog).
pub fn spawn_park_boundaries_aggregator(pool: PgPool, config: &Config) {
    let client = aggregator_client();
    let boundaries_config = park_boundaries::ParkBoundariesConfig {
        batch_size: config.park_boundaries_batch_size,
        cycle_hours: config.park_boundaries_cycle_hours,
        stale_days: config.park_boundaries_stale_days,
        concurrency: config.park_boundaries_concurrency,
    };
    tokio::spawn(async move {
        park_boundaries::poll_loop(pool, client, boundaries_config).await;
    });
    tracing::info!("Park boundaries aggregator started");
}

/// Spawn the Polish park boundaries aggregator (requires POTA stats for park catalog).
pub fn spawn_polish_park_boundaries_aggregator(pool: PgPool, config: &Config) {
    let client = aggregator_client();
    let boundaries_config = polish_park_boundaries::PolishParkBoundariesConfig {
        batch_size: config.polish_park_boundaries_batch_size,
        cycle_hours: config.polish_park_boundaries_cycle_hours,
        stale_days: config.polish_park_boundaries_stale_days,
        concurrency: config.polish_park_boundaries_concurrency,
    };
    tokio::spawn(async move {
        polish_park_boundaries::poll_loop(pool, client, boundaries_config).await;
    });
    tracing::info!("Polish park boundaries aggregator started");
}

/// Spawn the achievement batch evaluator.
pub fn spawn_achievement_evaluator(pool: PgPool, config: &Config) {
    let sweep_config = achievements::AchievementSweepConfig {
        interval_minutes: config.achievement_evaluator_interval_minutes,
        recent_days: config.achievement_evaluator_recent_days,
    };
    tokio::spawn(async move {
        achievements::poll_loop(pool, sweep_config).await;
    });
    tracing::info!(
        interval_minutes = config.achievement_evaluator_interval_minutes,
        recent_days = config.achievement_evaluator_recent_days,
        "Achievement evaluator started"
    );
}

/// Spawn the AMSAT community satellite status aggregator.
pub fn spawn_amsat_status_aggregator(pool: PgPool, config: &Config) {
    let client = aggregator_client();
    let cfg = amsat_status::AmsatStatusConfig {
        cycle_minutes: config.amsat_status_cycle_minutes,
        api_base: config.amsat_status_api_base.clone(),
    };
    tokio::spawn(async move {
        amsat_status::poll_loop(pool, client, cfg).await;
    });
    tracing::info!(
        cycle_minutes = config.amsat_status_cycle_minutes,
        "AMSAT status aggregator started"
    );
}

/// Spawn the callsign enrichment aggregator (CWops, future SKCC, etc.).
pub fn spawn_callsign_enrichment_aggregator(pool: PgPool, config: &Config) {
    let client = aggregator_client();
    let cfg = callsign_enrichment::CallsignEnrichmentConfig {
        cycle_hours: config.callsign_enrichment_cycle_hours,
    };
    tokio::spawn(async move {
        callsign_enrichment::poll_loop(pool, client, cfg).await;
    });
    tracing::info!(
        cycle_hours = config.callsign_enrichment_cycle_hours,
        "Callsign enrichment aggregator started"
    );
}

/// Spawn the club roster aggregator: reconciles every club that has a
/// notes URL against that file (add new members, drop departed ones).
pub fn spawn_club_rosters_aggregator(pool: PgPool, config: &Config) {
    let client = aggregator_client();
    let cfg = club_rosters::ClubRostersConfig {
        cycle_hours: config.club_roster_sync_cycle_hours,
    };
    tokio::spawn(async move {
        club_rosters::poll_loop(pool, client, cfg).await;
    });
    tracing::info!(
        cycle_hours = config.club_roster_sync_cycle_hours,
        "Club roster aggregator started"
    );
}

/// Spawn the macros telemetry retention job (CAR-271 T9). Daily by default.
pub fn spawn_macros_retention(pool: PgPool, config: &Config) {
    let cfg = macros_retention::MacrosRetentionConfig {
        interval_hours: config.macros_retention_interval_hours,
        retain_days: config.macros_retention_retain_days,
    };
    tokio::spawn(async move {
        macros_retention::poll_loop(pool, cfg).await;
    });
    tracing::info!(
        interval_hours = config.macros_retention_interval_hours,
        retain_days = config.macros_retention_retain_days,
        "Macros retention job started"
    );
}

/// Spawn the POTA stats aggregator (independent of the spots system).
pub fn spawn_pota_stats_aggregator(pool: PgPool, config: &Config) {
    let client = aggregator_client();
    let stats_config = pota_stats::PotaStatsConfig {
        concurrency: config.pota_stats_concurrency,
        batch_size: config.pota_stats_batch_size,
        cycle_hours: config.pota_stats_cycle_hours,
        min_request_interval_ms: config.pota_stats_min_request_interval_ms,
    };
    tokio::spawn(async move {
        pota_stats::poll_loop(pool, client, stats_config).await;
    });
    tracing::info!("POTA stats aggregator started");
}

/// Delete expired spots every 2 minutes.
async fn ttl_cleanup_loop(pool: PgPool) {
    let mut interval = tokio::time::interval(std::time::Duration::from_secs(120));

    loop {
        interval.tick().await;
        match crate::db::delete_expired_spots(&pool).await {
            Ok(count) => {
                if count > 0 {
                    tracing::debug!("TTL cleanup: deleted {} expired spots", count);
                }
            }
            Err(e) => {
                tracing::error!("TTL cleanup error: {}", e);
                metrics::counter!(app_metrics::SYNC_ERRORS_TOTAL, "aggregator" => "ttl_cleanup")
                    .increment(1);
            }
        }
    }
}
