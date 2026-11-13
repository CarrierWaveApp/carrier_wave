use std::sync::Arc;

use sqlx::PgPool;
use tokio::sync::Semaphore;

use crate::db::historic_trails::{self, UnfetchedTrail};
use crate::metrics as app_metrics;
use crate::models::historic_trail::{NpsTrailFeature, NpsTrailResponse};

use super::park_boundaries::merge_geojson_geometries;

/// National Trails layer on the USGS National Map (MapServer layer 11).
/// The old FeatureServer at services.arcgis.com was retired; this is the
/// current authoritative source for National Historic/Scenic Trail geometries.
const NPS_TRAILS_URL: &str =
    "https://carto.nationalmap.gov/arcgis/rest/services/transportation/MapServer/11";

/// NTIR (NPS National Trails Intermountain Region) ArcGIS organization.
/// Hosts per-trail Feature Services for trails not always in the USGS dataset.
const NTIR_BASE_URL: &str = "https://services1.arcgis.com/fBc8EJBxQRMcHlei/arcgis/rest/services";

/// Configuration for the historic trails aggregator.
pub struct HistoricTrailsConfig {
    pub batch_size: i64,
    pub cycle_hours: u64,
    pub stale_days: i64,
    pub concurrency: usize,
}

impl Default for HistoricTrailsConfig {
    fn default() -> Self {
        Self {
            batch_size: 20,
            cycle_hours: 168, // weekly — only 19 trails
            stale_days: 180,
            concurrency: 5,
        }
    }
}

enum FetchResult {
    Cached(String),
    NoMatch,
    Error(String),
}

/// Main poll loop — fetches geometries for unmatched trails, then re-checks stale ones.
pub async fn poll_loop(pool: PgPool, client: reqwest::Client, config: HistoricTrailsConfig) {
    // Wait for migrations and initial setup
    tracing::info!("Historic trails: waiting 60s before first cycle");
    tokio::time::sleep(std::time::Duration::from_secs(60)).await;

    let semaphore = Arc::new(Semaphore::new(config.concurrency));

    loop {
        let batch_start = std::time::Instant::now();
        let total_cached = historic_trails::count_trails(&pool).await.unwrap_or(0);

        // Reset consecutive error counters so previously-failing trails
        // get retried each cycle (they may have been fixed upstream)
        match historic_trails::reset_trail_consecutive_errors(&pool).await {
            Ok(n) if n > 0 => {
                tracing::info!("Historic trails: reset error counters for {} trails", n);
            }
            Err(e) => {
                tracing::error!(
                    "Historic trails: reset_trail_consecutive_errors failed: {}",
                    e
                );
            }
            _ => {}
        }

        // Phase 1: Fetch geometries for trails that don't have one yet
        match historic_trails::get_unfetched_trails(&pool, config.batch_size).await {
            Ok(trails) => {
                if trails.is_empty() {
                    tracing::info!(
                        "Historic trails: all trails fetched ({} cached)",
                        total_cached
                    );
                } else {
                    tracing::info!(
                        "Historic trails: fetching {} unfetched trails ({} already cached)",
                        trails.len(),
                        total_cached
                    );

                    let (cached, no_match, errors) =
                        fetch_batch(&pool, &client, &semaphore, trails).await;

                    let new_total = historic_trails::count_trails(&pool).await.unwrap_or(0);
                    tracing::info!(
                        "Historic trails: batch done — {} cached, {} no match, {} errors ({} total cached)",
                        cached, no_match, errors, new_total
                    );
                }
            }
            Err(e) => {
                tracing::error!("Historic trails: get_unfetched_trails failed: {}", e);
                metrics::counter!(app_metrics::SYNC_ERRORS_TOTAL, "aggregator" => "historic_trails")
                    .increment(1);
            }
        }

        // Phase 2: Re-fetch stale trail geometries
        match historic_trails::get_stale_trails(&pool, config.stale_days, config.batch_size).await {
            Ok(stale) => {
                if !stale.is_empty() {
                    tracing::info!("Historic trails: refreshing {} stale trails", stale.len());
                    let unfetched: Vec<UnfetchedTrail> = stale
                        .into_iter()
                        .map(|trail| UnfetchedTrail {
                            reference: trail.reference,
                            name: trail.name,
                            location_desc: trail.location_desc,
                            managing_agency: trail.managing_agency,
                            ntir_service: trail.ntir_service,
                        })
                        .collect();

                    fetch_batch(&pool, &client, &semaphore, unfetched).await;
                }
            }
            Err(e) => {
                tracing::error!("Historic trails: get_stale_trails failed: {}", e);
                metrics::counter!(app_metrics::SYNC_ERRORS_TOTAL, "aggregator" => "historic_trails")
                    .increment(1);
            }
        }

        // Record batch metrics
        let new_total = historic_trails::count_trails(&pool).await.unwrap_or(0);
        metrics::gauge!(app_metrics::GIS_TRAILS_CACHED_TOTAL).set(new_total as f64);
        metrics::histogram!(app_metrics::GIS_BATCH_DURATION_SECONDS, "aggregator" => "historic_trails")
            .record(batch_start.elapsed().as_secs_f64());
        metrics::gauge!(app_metrics::SYNC_LAST_COMPLETED_TIMESTAMP, "aggregator" => "historic_trails")
            .set(chrono::Utc::now().timestamp() as f64);

        tracing::info!(
            "Historic trails: sleeping {}h until next cycle",
            config.cycle_hours
        );
        tokio::time::sleep(std::time::Duration::from_secs(config.cycle_hours * 3600)).await;
    }
}

/// Fetch a batch of trails concurrently using the semaphore for rate limiting.
async fn fetch_batch(
    pool: &PgPool,
    client: &reqwest::Client,
    semaphore: &Arc<Semaphore>,
    trails: Vec<UnfetchedTrail>,
) -> (u32, u32, u32) {
    let mut handles = Vec::with_capacity(trails.len());

    for trail in trails {
        let pool = pool.clone();
        let client = client.clone();
        let semaphore = semaphore.clone();

        let handle = tokio::spawn(async move {
            let _permit = semaphore.acquire().await.unwrap();
            let start = std::time::Instant::now();
            let result = fetch_trail(&pool, &client, &trail).await;
            let result_label = match &result {
                FetchResult::Cached(_) => "cached",
                FetchResult::NoMatch => "no_match",
                FetchResult::Error(_) => "error",
            };
            metrics::counter!(app_metrics::GIS_FETCH_TOTAL, "source" => "nps_trails", "result" => result_label)
                .increment(1);
            metrics::histogram!(app_metrics::GIS_FETCH_DURATION_SECONDS, "source" => "nps_trails")
                .record(start.elapsed().as_secs_f64());
            (trail.reference, trail.name, result)
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
                    "Historic trails: {} '{}' -> cached ({})",
                    reference,
                    name,
                    quality
                );
                cached += 1;
            }
            Ok((reference, name, FetchResult::NoMatch)) => {
                tracing::info!("Historic trails: {} '{}' -> no match", reference, name);
                if let Err(e) = historic_trails::increment_trail_errors(pool, &reference).await {
                    tracing::error!(
                        "Historic trails: failed to increment errors for {}: {}",
                        reference,
                        e
                    );
                }
                no_match += 1;
            }
            Ok((reference, name, FetchResult::Error(e))) => {
                tracing::warn!("Historic trails: {} '{}' -> error: {}", reference, name, e);
                if let Err(e2) = historic_trails::increment_trail_errors(pool, &reference).await {
                    tracing::error!(
                        "Historic trails: failed to increment errors for {}: {}",
                        reference,
                        e2
                    );
                }
                errors += 1;
            }
            Err(e) => {
                tracing::error!("Historic trails: task join error: {}", e);
                errors += 1;
            }
        }
    }

    (cached, no_match, errors)
}

async fn fetch_trail(
    pool: &PgPool,
    client: &reqwest::Client,
    trail: &UnfetchedTrail,
) -> FetchResult {
    match fetch_trail_inner(pool, client, trail).await {
        Ok(Some(quality)) => FetchResult::Cached(quality),
        Ok(None) => FetchResult::NoMatch,
        Err(e) => FetchResult::Error(e.to_string()),
    }
}

async fn fetch_trail_inner(
    pool: &PgPool,
    client: &reqwest::Client,
    trail: &UnfetchedTrail,
) -> Result<Option<String>, Box<dyn std::error::Error + Send + Sync>> {
    // Strategy: query NPS National Trails by name
    let search_name = normalize_trail_name(&trail.name);

    match query_by_name(client, NPS_TRAILS_URL, &search_name).await {
        Ok(Some(feature)) => {
            save_feature(pool, trail, &feature, "exact").await?;
            return Ok(Some("exact".to_string()));
        }
        Ok(None) => {}
        Err(e) => {
            tracing::warn!(
                "Historic trails: {} name query failed: {}",
                trail.reference,
                e
            );
        }
    }

    // Fallback: broader search with shorter name
    let short_name = search_name
        .split_whitespace()
        .take(3)
        .collect::<Vec<_>>()
        .join(" ");
    if short_name != search_name && !short_name.is_empty() {
        match query_by_name(client, NPS_TRAILS_URL, &short_name).await {
            Ok(Some(feature)) => {
                save_feature(pool, trail, &feature, "fuzzy").await?;
                return Ok(Some("fuzzy".to_string()));
            }
            Ok(None) => {}
            Err(e) => {
                tracing::warn!(
                    "Historic trails: {} short-name query failed: {}",
                    trail.reference,
                    e
                );
            }
        }
    }

    // Fallback: NTIR per-trail Feature Service (if configured)
    if let Some(ntir_service) = &trail.ntir_service {
        match query_ntir_service(client, ntir_service).await {
            Ok(Some(feature)) => {
                save_feature(pool, trail, &feature, "ntir").await?;
                return Ok(Some("ntir".to_string()));
            }
            Ok(None) => {
                tracing::info!(
                    "Historic trails: {} NTIR service '{}' returned no features",
                    trail.reference,
                    ntir_service
                );
            }
            Err(e) => {
                tracing::warn!(
                    "Historic trails: {} NTIR query failed: {}",
                    trail.reference,
                    e
                );
            }
        }
    }

    Ok(None)
}

/// Query National Trails MapServer by trail name — merges all line segments.
///
/// Queries the `nationaltraildesignation` field (e.g. "NHT - Lewis and Clark")
/// which groups all segments of a given national trail. Falls back to the
/// `name` field if no designation match is found.
async fn query_by_name(
    client: &reqwest::Client,
    service_url: &str,
    search_name: &str,
) -> Result<Option<NpsTrailFeature>, Box<dyn std::error::Error + Send + Sync>> {
    let escaped_name = search_name.replace('\'', "''");

    // Strategy 1: match via nationaltraildesignation (e.g. "NHT - Lewis and Clark")
    // Use UPPER() for case-insensitive matching (ArcGIS LIKE is case-sensitive)
    let where_clause = format!(
        "UPPER(nationaltraildesignation) LIKE UPPER('%{}%')",
        escaped_name
    );

    let url = format!(
        "{}/query?where={}&outFields=name,nationaltraildesignation,primarytrailmaintainer,lengthmiles&f=geojson&outSR=4326&resultRecordCount=5000",
        service_url,
        urlencoded(&where_clause)
    );

    let features = fetch_trail_response(client, &url).await?;
    if !features.is_empty() {
        return Ok(merge_trail_features(features));
    }

    // Strategy 2: match via segment name field
    let where_clause = format!("UPPER(name) LIKE UPPER('%{}%')", escaped_name);

    let url = format!(
        "{}/query?where={}&outFields=name,nationaltraildesignation,primarytrailmaintainer,lengthmiles&f=geojson&outSR=4326&resultRecordCount=5000",
        service_url,
        urlencoded(&where_clause)
    );

    let features = fetch_trail_response(client, &url).await?;
    Ok(merge_trail_features(features))
}

/// Query an NTIR per-trail Feature Service — fetches all features and merges them.
async fn query_ntir_service(
    client: &reqwest::Client,
    service_name: &str,
) -> Result<Option<NpsTrailFeature>, Box<dyn std::error::Error + Send + Sync>> {
    let url = format!(
        "{}/{}/FeatureServer/0/query?where=1%3D1&outFields=*&f=geojson&outSR=4326&resultRecordCount=5000",
        NTIR_BASE_URL, service_name
    );

    let features = fetch_trail_response(client, &url).await?;
    Ok(merge_trail_features(features))
}

/// Fetch and parse trail features from an ArcGIS query URL.
async fn fetch_trail_response(
    client: &reqwest::Client,
    url: &str,
) -> Result<Vec<NpsTrailFeature>, Box<dyn std::error::Error + Send + Sync>> {
    let resp_text = client
        .get(url)
        .send()
        .await?
        .error_for_status()?
        .text()
        .await?;

    let resp: NpsTrailResponse = match serde_json::from_str(&resp_text) {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!(
                "Historic trails: response parse error: {} (first 200 chars: {})",
                e,
                &resp_text[..resp_text.len().min(200)]
            );
            return Ok(vec![]);
        }
    };

    Ok(resp.features.unwrap_or_default())
}

/// Merge all trail features into a single feature with merged geometry.
/// A trail can have multiple line segments returned as separate features.
fn merge_trail_features(features: Vec<NpsTrailFeature>) -> Option<NpsTrailFeature> {
    if features.is_empty() {
        return None;
    }
    if features.len() == 1 {
        return features.into_iter().next();
    }

    let geometries: Vec<serde_json::Value> =
        features.iter().filter_map(|f| f.geometry.clone()).collect();

    if geometries.is_empty() {
        return None;
    }

    let merged = merge_geojson_geometries(geometries);
    let mut result = features.into_iter().next().unwrap();
    result.geometry = Some(merged);
    Some(result)
}

/// Save a trail feature to the database.
async fn save_feature(
    pool: &PgPool,
    trail: &UnfetchedTrail,
    feature: &NpsTrailFeature,
    match_quality: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let geojson = match &feature.geometry {
        Some(g) => serde_json::to_string(g)?,
        None => {
            tracing::warn!(
                "Historic trails: {} matched but feature has no geometry",
                trail.reference
            );
            return Ok(());
        }
    };

    let attrs = feature.properties.as_ref();
    let designation = attrs.and_then(|a| a.designation.as_deref());
    let managing_agency = attrs.and_then(|a| a.managing_agency.as_deref());
    let length_miles = attrs.and_then(|a| a.length_miles);
    let state = attrs.and_then(|a| a.state.as_deref());

    historic_trails::upsert_trail(
        pool,
        &trail.reference,
        &trail.name,
        designation,
        managing_agency,
        length_miles,
        state,
        match_quality,
        &geojson,
        "nps_trails",
    )
    .await?;

    Ok(())
}

/// URL-encode a string for use in ArcGIS REST API query parameters.
/// The `%` must be encoded first (to `%25`) so that SQL LIKE wildcards
/// (`%`) don't get misinterpreted as URL percent-encoding by the server.
fn urlencoded(s: &str) -> String {
    s.replace('%', "%25")
        .replace(' ', "%20")
        .replace('\'', "%27")
        .replace('=', "%3D")
        .replace('&', "%26")
}

/// Normalize a trail name for search by stripping the "National Historic Trail" suffix.
fn normalize_trail_name(name: &str) -> String {
    let suffixes = [
        " National Historic Trail",
        " National Scenic Trail",
        " National Recreation Trail",
        " National Heritage Area Trail",
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
