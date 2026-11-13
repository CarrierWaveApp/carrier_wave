use std::sync::Arc;

use sqlx::PgPool;
use tokio::sync::Semaphore;

use crate::db::park_boundaries::{self, UnfetchedPark};
use crate::metrics as app_metrics;
use crate::models::park_boundary::{WfsFeature, WfsFeatureCollection};

use super::park_boundaries::merge_geojson_geometries;

/// GDOŚ WFS endpoint for Polish protected areas.
const GDOS_WFS_URL: &str = "https://sdi.gdos.gov.pl/wfs";

/// WFS layer names for different Polish protected area types.
const WFS_LAYERS: &[&str] = &[
    "ParkiNarodowe",
    "ParkiKrajobrazowe",
    "Rezerwaty",
    "ObszaryChronionegoKrajobrazu",
    "ObszarySpecjalnejOchrony",
    "SpecjalneObszaryOchrony",
];

/// Configuration for the Polish park boundaries aggregator.
pub struct PolishParkBoundariesConfig {
    pub batch_size: i64,
    pub cycle_hours: u64,
    pub stale_days: i64,
    pub concurrency: usize,
}

impl Default for PolishParkBoundariesConfig {
    fn default() -> Self {
        Self {
            batch_size: 20,
            cycle_hours: 24,
            stale_days: 90,
            concurrency: 3,
        }
    }
}

enum FetchResult {
    Cached(String),
    NoMatch,
    Error(String),
}

/// Main poll loop — fetches boundaries for unmatched Polish parks, then re-checks stale ones.
pub async fn poll_loop(pool: PgPool, client: reqwest::Client, config: PolishParkBoundariesConfig) {
    // Wait for POTA stats aggregator to populate park catalog
    tracing::info!("Polish park boundaries: waiting 180s for POTA stats to populate park catalog");
    tokio::time::sleep(std::time::Duration::from_secs(180)).await;

    let semaphore = Arc::new(Semaphore::new(config.concurrency));

    loop {
        let batch_start = std::time::Instant::now();
        let total_cached = park_boundaries::count_boundaries(&pool).await.unwrap_or(0);

        // Phase 1: Fetch boundaries for Polish parks that don't have one yet
        match park_boundaries::get_unfetched_polish_parks(&pool, config.batch_size).await {
            Ok(parks) => {
                if parks.is_empty() {
                    tracing::info!(
                        "Polish park boundaries: all SP- parks fetched ({} total cached)",
                        total_cached
                    );
                } else {
                    tracing::info!(
                        "Polish park boundaries: fetching {} unfetched parks ({} total cached)",
                        parks.len(),
                        total_cached
                    );

                    let (cached, no_match, errors) =
                        fetch_batch(&pool, &client, &semaphore, parks).await;

                    let new_total = park_boundaries::count_boundaries(&pool).await.unwrap_or(0);
                    tracing::info!(
                        "Polish park boundaries: batch done — {} cached, {} no match, {} errors ({} total cached)",
                        cached,
                        no_match,
                        errors,
                        new_total
                    );
                }
            }
            Err(e) => {
                tracing::error!(
                    "Polish park boundaries: get_unfetched_polish_parks failed: {}",
                    e
                );
                metrics::counter!(app_metrics::SYNC_ERRORS_TOTAL, "aggregator" => "polish_park_boundaries")
                    .increment(1);
            }
        }

        // Phase 2: Re-fetch stale Polish boundaries
        match park_boundaries::get_stale_boundaries(&pool, config.stale_days, config.batch_size)
            .await
        {
            Ok(stale) => {
                // Only process SP- parks from the stale list
                let polish_stale: Vec<UnfetchedPark> = stale
                    .into_iter()
                    .filter(|s| s.reference.starts_with("PL-"))
                    .map(|park| UnfetchedPark {
                        reference: park.reference,
                        name: park.name,
                        location_desc: park.location_desc,
                        latitude: park.latitude,
                        longitude: park.longitude,
                    })
                    .collect();
                if !polish_stale.is_empty() {
                    tracing::info!(
                        "Polish park boundaries: refreshing {} stale boundaries",
                        polish_stale.len()
                    );
                    fetch_batch(&pool, &client, &semaphore, polish_stale).await;
                }
            }
            Err(e) => {
                tracing::error!("Polish park boundaries: get_stale_boundaries failed: {}", e);
                metrics::counter!(app_metrics::SYNC_ERRORS_TOTAL, "aggregator" => "polish_park_boundaries")
                    .increment(1);
            }
        }

        // Record batch metrics
        metrics::histogram!(app_metrics::GIS_BATCH_DURATION_SECONDS, "aggregator" => "polish_park_boundaries")
            .record(batch_start.elapsed().as_secs_f64());
        metrics::gauge!(app_metrics::SYNC_LAST_COMPLETED_TIMESTAMP, "aggregator" => "polish_park_boundaries")
            .set(chrono::Utc::now().timestamp() as f64);

        tracing::info!(
            "Polish park boundaries: sleeping {}h until next cycle",
            config.cycle_hours
        );
        tokio::time::sleep(std::time::Duration::from_secs(config.cycle_hours * 3600)).await;
    }
}

/// Fetch a batch of parks concurrently using the semaphore for rate limiting.
async fn fetch_batch(
    pool: &PgPool,
    client: &reqwest::Client,
    semaphore: &Arc<Semaphore>,
    parks: Vec<UnfetchedPark>,
) -> (u32, u32, u32) {
    let mut handles = Vec::with_capacity(parks.len());

    for park in parks {
        let pool = pool.clone();
        let client = client.clone();
        let semaphore = semaphore.clone();

        let handle = tokio::spawn(async move {
            let _permit = semaphore.acquire().await.unwrap();
            let start = std::time::Instant::now();
            let result = fetch_boundary(&pool, &client, &park).await;

            // Record no-match sentinel so the park doesn't block the queue
            if matches!(result, FetchResult::NoMatch) {
                if let Err(e) =
                    park_boundaries::upsert_no_match(&pool, &park.reference, &park.name, "gdos_wfs")
                        .await
                {
                    tracing::error!(
                        "Polish park boundaries: {} failed to record no-match: {}",
                        park.reference,
                        e
                    );
                }
            }

            let result_label = match &result {
                FetchResult::Cached(_) => "cached",
                FetchResult::NoMatch => "no_match",
                FetchResult::Error(_) => "error",
            };
            metrics::counter!(app_metrics::GIS_FETCH_TOTAL, "source" => "gdos_wfs", "result" => result_label)
                .increment(1);
            metrics::histogram!(app_metrics::GIS_FETCH_DURATION_SECONDS, "source" => "gdos_wfs")
                .record(start.elapsed().as_secs_f64());
            (park.reference, park.name, result)
        });
        handles.push(handle);
    }

    let mut cached = 0u32;
    let mut no_match = 0u32;
    let mut errors = 0u32;

    for handle in handles {
        match handle.await {
            Ok((reference, name, FetchResult::Cached(quality))) => {
                tracing::info!(
                    "Polish park boundaries: {} '{}' -> cached ({})",
                    reference,
                    name,
                    quality
                );
                cached += 1;
            }
            Ok((reference, name, FetchResult::NoMatch)) => {
                tracing::info!(
                    "Polish park boundaries: {} '{}' -> no match",
                    reference,
                    name,
                );
                no_match += 1;
            }
            Ok((reference, name, FetchResult::Error(e))) => {
                tracing::warn!(
                    "Polish park boundaries: {} '{}' -> error: {}",
                    reference,
                    name,
                    e
                );
                errors += 1;
            }
            Err(e) => {
                tracing::error!("Polish park boundaries: task join error: {}", e);
                errors += 1;
            }
        }
    }

    (cached, no_match, errors)
}

/// Fetch boundary for a single Polish park from GDOŚ WFS.
async fn fetch_boundary(
    pool: &PgPool,
    client: &reqwest::Client,
    park: &UnfetchedPark,
) -> FetchResult {
    match fetch_boundary_inner(pool, client, park).await {
        Ok(Some(quality)) => FetchResult::Cached(quality),
        Ok(None) => FetchResult::NoMatch,
        Err(e) => FetchResult::Error(e.to_string()),
    }
}

async fn fetch_boundary_inner(
    pool: &PgPool,
    client: &reqwest::Client,
    park: &UnfetchedPark,
) -> Result<Option<String>, Box<dyn std::error::Error + Send + Sync>> {
    let search_name = normalize_polish_park_name(&park.name);

    // Strategy 1: Search by name across all WFS layers
    for layer in WFS_LAYERS {
        match query_wfs_by_name(client, layer, &search_name).await {
            Ok(Some(feature)) => {
                save_wfs_feature(pool, park, &feature, "exact", layer).await?;
                return Ok(Some("exact".to_string()));
            }
            Ok(None) => {}
            Err(e) => {
                tracing::warn!(
                    "Polish park boundaries: {} WFS name query on {} failed: {}",
                    park.reference,
                    layer,
                    e
                );
            }
        }
    }

    // Strategy 2: Spatial query (point-in-polygon) across all layers
    if let (Some(lat), Some(lon)) = (park.latitude, park.longitude) {
        for layer in WFS_LAYERS {
            match query_wfs_by_point(client, layer, lon, lat).await {
                Ok(Some(feature)) => {
                    save_wfs_feature(pool, park, &feature, "spatial", layer).await?;
                    return Ok(Some("spatial".to_string()));
                }
                Ok(None) => {}
                Err(e) => {
                    tracing::warn!(
                        "Polish park boundaries: {} WFS spatial query on {} failed: {}",
                        park.reference,
                        layer,
                        e
                    );
                }
            }
        }
    } else {
        tracing::info!(
            "Polish park boundaries: {} has no lat/lon, skipping spatial query",
            park.reference
        );
    }

    Ok(None)
}

/// Query GDOŚ WFS by name using a CQL filter — merges all features with geometry.
async fn query_wfs_by_name(
    client: &reqwest::Client,
    layer: &str,
    search_name: &str,
) -> Result<Option<WfsFeature>, Box<dyn std::error::Error + Send + Sync>> {
    let escaped_name = search_name.replace('\'', "''");
    let cql_filter = format!("nazwa LIKE '%{}%'", escaped_name);

    let url = format!(
        "{}?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature\
         &TYPENAMES=GDOS:{}\
         &CQL_FILTER={}\
         &outputFormat=application/json\
         &srsName=EPSG:4326\
         &COUNT=5",
        GDOS_WFS_URL,
        layer,
        urlencoded(&cql_filter)
    );

    let features = fetch_wfs_features(client, &url, layer).await?;
    Ok(merge_wfs_features(features))
}

/// Query GDOŚ WFS by point intersection using a BBOX filter — merges all features with geometry.
async fn query_wfs_by_point(
    client: &reqwest::Client,
    layer: &str,
    lon: f64,
    lat: f64,
) -> Result<Option<WfsFeature>, Box<dyn std::error::Error + Send + Sync>> {
    // Use a small bounding box around the point (~100m)
    let delta = 0.001;
    let bbox = format!(
        "{},{},{},{},EPSG:4326",
        lat - delta,
        lon - delta,
        lat + delta,
        lon + delta
    );

    let url = format!(
        "{}?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature\
         &TYPENAMES=GDOS:{}\
         &BBOX={}\
         &outputFormat=application/json\
         &srsName=EPSG:4326\
         &COUNT=5",
        GDOS_WFS_URL, layer, bbox
    );

    let features = fetch_wfs_features(client, &url, layer).await?;
    Ok(merge_wfs_features(features))
}

/// Fetch and parse WFS features from a URL.
async fn fetch_wfs_features(
    client: &reqwest::Client,
    url: &str,
    layer: &str,
) -> Result<Vec<WfsFeature>, Box<dyn std::error::Error + Send + Sync>> {
    let resp = client.get(url).send().await?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        return Err(format!(
            "WFS returned {} (first 200: {})",
            status,
            &body[..body.len().min(200)]
        )
        .into());
    }

    let resp_text = resp.text().await?;
    let collection: WfsFeatureCollection = match serde_json::from_str(&resp_text) {
        Ok(c) => c,
        Err(e) => {
            tracing::warn!(
                "Polish park boundaries: WFS response parse error on {}: {} (first 200: {})",
                layer,
                e,
                &resp_text[..resp_text.len().min(200)]
            );
            return Ok(vec![]);
        }
    };

    Ok(collection.features.unwrap_or_default())
}

/// Merge all WFS features with geometry into a single feature.
fn merge_wfs_features(features: Vec<WfsFeature>) -> Option<WfsFeature> {
    let with_geom: Vec<WfsFeature> = features
        .into_iter()
        .filter(|f| f.geometry.is_some())
        .collect();

    if with_geom.is_empty() {
        return None;
    }
    if with_geom.len() == 1 {
        return with_geom.into_iter().next();
    }

    let geometries: Vec<serde_json::Value> = with_geom
        .iter()
        .filter_map(|f| f.geometry.clone())
        .collect();

    let merged = merge_geojson_geometries(geometries);
    let mut result = with_geom.into_iter().next().unwrap();
    result.geometry = Some(merged);
    Some(result)
}

/// Save a WFS feature as a park boundary.
async fn save_wfs_feature(
    pool: &PgPool,
    park: &UnfetchedPark,
    feature: &WfsFeature,
    match_quality: &str,
    layer: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let geojson = match &feature.geometry {
        Some(g) => serde_json::to_string(g)?,
        None => {
            tracing::warn!(
                "Polish park boundaries: {} matched but feature has no geometry",
                park.reference
            );
            return Ok(());
        }
    };

    let props = feature.properties.as_ref();
    let area_ha = props.and_then(|p| p.area_ha);
    // Convert hectares to acres for consistency with US data (1 ha = 2.47105 acres)
    let acreage = area_ha.map(|ha| ha * 2.47105);

    let source = format!("gdos_wfs_{}", layer);

    park_boundaries::upsert_boundary(
        pool,
        &park.reference,
        &park.name,
        Some(layer), // Use the WFS layer name as designation
        Some("GDOŚ"),
        acreage,
        match_quality,
        &geojson,
        &source,
    )
    .await?;

    Ok(())
}

/// URL-encode a string for use in WFS query parameters.
/// The `%` must be encoded first (to `%25`) so that SQL LIKE wildcards
/// don't get misinterpreted as URL percent-encoding by the server.
fn urlencoded(s: &str) -> String {
    s.replace('%', "%25")
        .replace(' ', "%20")
        .replace('\'', "%27")
        .replace('=', "%3D")
        .replace('&', "%26")
}

/// Normalize a Polish POTA park name for WFS search by stripping common suffixes.
fn normalize_polish_park_name(name: &str) -> String {
    let suffixes = [
        " - Park Narodowy",
        " Park Narodowy",
        " - Park Krajobrazowy",
        " Park Krajobrazowy",
        " - Rezerwat Przyrody",
        " Rezerwat Przyrody",
        " - Obszar Chronionego Krajobrazu",
        " Obszar Chronionego Krajobrazu",
        " - Zespół Przyrodniczo-Krajobrazowy",
        " Zespół Przyrodniczo-Krajobrazowy",
        " - Użytek Ekologiczny",
        " Użytek Ekologiczny",
        " - Pomnik Przyrody",
        " Pomnik Przyrody",
        " - Stanowisko Dokumentacyjne",
        " Stanowisko Dokumentacyjne",
        " National Park",
        " Landscape Park",
        " Nature Reserve",
    ];

    let mut result = name.to_string();
    for suffix in &suffixes {
        if let Some(stripped) = result.strip_suffix(suffix) {
            result = stripped.to_string();
            break;
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_polish_park_name() {
        assert_eq!(
            normalize_polish_park_name("Białowieski Park Narodowy"),
            "Białowieski"
        );
        assert_eq!(
            normalize_polish_park_name("Dolina Baryczy - Park Krajobrazowy"),
            "Dolina Baryczy"
        );
        assert_eq!(
            normalize_polish_park_name("Some Reserve - Rezerwat Przyrody"),
            "Some Reserve"
        );
        // Name without a recognized suffix stays unchanged
        assert_eq!(normalize_polish_park_name("Kampinoski"), "Kampinoski");
    }
}
