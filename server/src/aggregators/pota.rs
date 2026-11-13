use chrono::{Duration, NaiveDateTime, Utc};
use serde::Deserialize;
use sqlx::PgPool;

use crate::db::upsert_aggregated_spot;
use crate::metrics as app_metrics;
use crate::models::spot::{AggregatedSpot, SpotSource};

const POTA_SPOTS_URL: &str = "https://api.pota.app/spot/activator";

/// Upstream JSON shape from the POTA activator spots endpoint.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PotaSpot {
    spot_id: i64,
    activator: String,
    frequency: String,
    mode: String,
    reference: String,
    #[serde(default)]
    park_name: Option<String>,
    /// Park name as served by the rebuilt POTA API (October 2026), which
    /// leaves `parkName` null and fills `name` instead.
    #[serde(default)]
    name: Option<String>,
    spot_time: String,
    #[serde(default)]
    spotter: Option<String>,
    #[serde(default)]
    comments: Option<String>,
    #[serde(default)]
    location_desc: Option<String>,
    /// Seconds until the spot expires. Absent or 0 → use 30 min default.
    #[serde(default)]
    expire: Option<i64>,
}

/// Poll POTA activator spots every 60 seconds.
pub async fn poll_loop(pool: PgPool, client: reqwest::Client) {
    let mut interval = tokio::time::interval(std::time::Duration::from_secs(60));

    loop {
        interval.tick().await;
        if let Err(e) = fetch_and_upsert(&pool, &client).await {
            tracing::error!("POTA aggregator error: {}", e);
            metrics::counter!(app_metrics::SYNC_ERRORS_TOTAL, "aggregator" => "pota_spots")
                .increment(1);
        }
    }
}

async fn fetch_and_upsert(
    pool: &PgPool,
    client: &reqwest::Client,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let spots: Vec<PotaSpot> = client
        .get(POTA_SPOTS_URL)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;

    tracing::debug!("POTA: fetched {} spots", spots.len());

    let mut upserted = 0u32;
    for spot in &spots {
        match map_spot(spot) {
            Ok(agg) => match upsert_aggregated_spot(pool, &agg).await {
                Ok(_) => upserted += 1,
                Err(e) => tracing::warn!("POTA upsert error for {}: {}", spot.activator, e),
            },
            Err(e) => {
                tracing::warn!("POTA parse error spotId={}: {}", spot.spot_id, e);
            }
        }
    }

    tracing::debug!("POTA: upserted {}/{} spots", upserted, spots.len());
    Ok(())
}

fn map_spot(spot: &PotaSpot) -> Result<AggregatedSpot, Box<dyn std::error::Error + Send + Sync>> {
    let frequency_khz: f64 = spot.frequency.parse()?;

    // spotTime is UTC but has no Z suffix
    let spotted_at = NaiveDateTime::parse_from_str(&spot.spot_time, "%Y-%m-%dT%H:%M:%S")
        .map(|naive| naive.and_utc())?;

    // expire = seconds remaining; fallback 30 min.
    // CAR-330: `expire` is unvalidated upstream input. A huge value panics chrono
    // (Duration::seconds / DateTime addition both `expect`) and kills the spot
    // aggregator task permanently; a merely-large value writes a spot that never
    // expires and never gets TTL-reaped. Clamp to a sane window and add safely.
    let default_ttl = Duration::minutes(30);
    let ttl = match spot.expire {
        Some(secs) if secs > 0 => Duration::try_seconds(secs.min(24 * 3600)).unwrap_or(default_ttl),
        _ => default_ttl,
    };
    let expires_at = Utc::now()
        .checked_add_signed(ttl)
        .unwrap_or_else(|| Utc::now() + default_ttl);

    // Split locationDesc (e.g. "US-WY") into country / state
    let (country_code, state_abbr) = spot
        .location_desc
        .as_deref()
        .map(|desc| {
            let mut parts = desc.splitn(2, '-');
            let country = parts.next().map(str::to_string);
            let state = parts.next().map(str::to_string);
            (country, state)
        })
        .unwrap_or((None, None));

    Ok(AggregatedSpot {
        callsign: spot.activator.clone(),
        program_slug: Some("pota".to_string()),
        source: SpotSource::Pota,
        external_id: spot.spot_id.to_string(),
        frequency_khz,
        mode: spot.mode.clone(),
        reference: Some(spot.reference.clone()),
        reference_name: spot.park_name.clone().or_else(|| spot.name.clone()),
        spotter: spot.spotter.clone(),
        spotter_grid: None,
        location_desc: spot.location_desc.clone(),
        country_code,
        state_abbr,
        comments: spot.comments.clone(),
        snr: None,
        wpm: None,
        spotted_at,
        expires_at,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn park_name_falls_back_to_name_field() {
        let json = r#"{"spotId": 59348762, "activator": "EA2CYT", "frequency": "14056",
            "mode": "CW", "reference": "ES-1329", "parkName": null,
            "spotTime": "2026-10-23T18:01:20", "spotter": "EA2CYT", "comments": "QRT",
            "source": "Ham2K Portable Logger", "name": "Zadorra ibaia", "locationDesc": "ES-PV",
            "expire": 1740}"#;
        let spot: PotaSpot = serde_json::from_str(json).unwrap();
        let agg = map_spot(&spot).unwrap();
        assert_eq!(agg.reference_name.as_deref(), Some("Zadorra ibaia"));
        assert_eq!(agg.reference.as_deref(), Some("ES-1329"));
        assert_eq!(agg.country_code.as_deref(), Some("ES"));
    }

    #[test]
    fn explicit_park_name_wins_over_name() {
        let json = r#"{"spotId": 1, "activator": "W1AW", "frequency": "7040", "mode": "CW",
            "reference": "US-0001", "parkName": "Acadia", "name": "Other",
            "spotTime": "2026-10-23T18:01:20"}"#;
        let spot: PotaSpot = serde_json::from_str(json).unwrap();
        assert_eq!(map_spot(&spot).unwrap().reference_name.as_deref(), Some("Acadia"));
    }
}
