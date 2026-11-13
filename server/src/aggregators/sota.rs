use chrono::{Duration, NaiveDateTime};
use serde::Deserialize;
use sqlx::PgPool;

use crate::db::upsert_aggregated_spot;
use crate::metrics as app_metrics;
use crate::models::spot::{AggregatedSpot, SpotSource};

const SOTA_SPOTS_URL: &str = "https://api2.sota.org.uk/api/spots/-1";

/// Upstream JSON shape from the SOTA spots endpoint.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SotaSpot {
    id: i64,
    /// The spotter's callsign (NOT the activator).
    callsign: String,
    activator_callsign: String,
    /// Frequency in **MHz** (must multiply by 1000 for kHz).
    frequency: String,
    mode: String,
    association_code: String,
    summit_code: String,
    #[serde(default)]
    summit_details: Option<String>,
    /// UTC timestamp without Z suffix.
    time_stamp: String,
    #[serde(default)]
    comments: Option<String>,
}

/// Poll SOTA spots every 90 seconds.
pub async fn poll_loop(pool: PgPool, client: reqwest::Client) {
    let mut interval = tokio::time::interval(std::time::Duration::from_secs(90));

    loop {
        interval.tick().await;
        if let Err(e) = fetch_and_upsert(&pool, &client).await {
            tracing::error!("SOTA aggregator error: {}", e);
            metrics::counter!(app_metrics::SYNC_ERRORS_TOTAL, "aggregator" => "sota_spots")
                .increment(1);
        }
    }
}

async fn fetch_and_upsert(
    pool: &PgPool,
    client: &reqwest::Client,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let spots: Vec<SotaSpot> = client
        .get(SOTA_SPOTS_URL)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;

    tracing::debug!("SOTA: fetched {} spots", spots.len());

    let mut upserted = 0u32;
    for spot in &spots {
        match map_spot(spot) {
            Ok(agg) => match upsert_aggregated_spot(pool, &agg).await {
                Ok(_) => upserted += 1,
                Err(e) => {
                    tracing::warn!("SOTA upsert error for {}: {}", spot.activator_callsign, e);
                }
            },
            Err(e) => {
                if spot.frequency.is_empty() {
                    tracing::debug!("SOTA spot id={}: empty frequency, skipping", spot.id);
                } else {
                    tracing::warn!("SOTA parse error id={}: {}", spot.id, e);
                }
            }
        }
    }

    tracing::debug!("SOTA: upserted {}/{} spots", upserted, spots.len());
    Ok(())
}

fn map_spot(spot: &SotaSpot) -> Result<AggregatedSpot, Box<dyn std::error::Error + Send + Sync>> {
    // Frequency is in MHz — convert to kHz
    let frequency_khz: f64 = spot.frequency.parse::<f64>()? * 1000.0;

    // timeStamp is UTC but has no Z suffix
    let spotted_at = NaiveDateTime::parse_from_str(&spot.time_stamp, "%Y-%m-%dT%H:%M:%S")
        .map(|naive| naive.and_utc())?;

    let expires_at = spotted_at + Duration::minutes(30);

    let reference = format!("{}/{}", spot.association_code, spot.summit_code);

    Ok(AggregatedSpot {
        callsign: spot.activator_callsign.clone(),
        program_slug: Some("sota".to_string()),
        source: SpotSource::Sota,
        external_id: spot.id.to_string(),
        frequency_khz,
        mode: spot.mode.clone(),
        reference: Some(reference),
        reference_name: spot.summit_details.clone(),
        spotter: Some(spot.callsign.clone()),
        spotter_grid: None,
        location_desc: None,
        country_code: None,
        state_abbr: None,
        comments: spot.comments.clone(),
        snr: None,
        wpm: None,
        spotted_at,
        expires_at,
    })
}
