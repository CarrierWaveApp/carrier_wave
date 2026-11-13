use std::sync::Arc;

use sqlx::PgPool;
use tokio::sync::Semaphore;

use crate::aggregators::state_park_sources;
use crate::db::park_boundaries::{self, UnfetchedPark};
use crate::metrics as app_metrics;
use crate::models::park_boundary::{ArcGisFeature, ArcGisResponse};

const PADUS_URL: &str = "https://services.arcgis.com/v01gqwM5QqNysAAi/arcgis/rest/services/Manager_Name_PADUS/FeatureServer/0";

/// Natural England ArcGIS FeatureServer for UK national park boundaries.
const NATURAL_ENGLAND_URL: &str = "https://services.arcgis.com/JJzESW51TqeY9uat/ArcGIS/rest/services/National_Parks_England/FeatureServer/0";

/// WDPA (World Database on Protected Areas) ArcGIS FeatureServer for international parks.
const WDPA_URL: &str =
    "https://services5.arcgis.com/Mj0hjvkNtV7NRhA7/arcgis/rest/services/WDPA_v0/FeatureServer/0";

/// Which data source to use for a given park.
enum DataSource {
    PadUs,
    NaturalEngland,
    Wdpa { iso3: &'static str },
}

/// Configuration for the park boundaries aggregator.
pub struct ParkBoundariesConfig {
    pub batch_size: i64,
    pub cycle_hours: u64,
    pub stale_days: i64,
    pub concurrency: usize,
}

impl Default for ParkBoundariesConfig {
    fn default() -> Self {
        Self {
            batch_size: 20,
            cycle_hours: 24,
            stale_days: 90,
            concurrency: 5,
        }
    }
}

/// Result of attempting to fetch a boundary for one park.
enum FetchResult {
    Cached(String), // match_quality
    NoMatch,
    Error(String),
}

/// Main poll loop — fetches boundaries for unmatched parks, then re-checks stale ones.
pub async fn poll_loop(pool: PgPool, client: reqwest::Client, config: ParkBoundariesConfig) {
    // Wait for POTA stats aggregator to populate pota_parks first
    tracing::info!("Park boundaries: waiting 120s for POTA stats to populate park catalog");
    tokio::time::sleep(std::time::Duration::from_secs(120)).await;

    let semaphore = Arc::new(Semaphore::new(config.concurrency));

    loop {
        let batch_start = std::time::Instant::now();
        let total_cached = park_boundaries::count_boundaries(&pool).await.unwrap_or(0);

        // Phase 1: Fetch boundaries for parks that don't have one yet
        match park_boundaries::get_unfetched_parks(&pool, config.batch_size).await {
            Ok(parks) => {
                if parks.is_empty() {
                    tracing::info!(
                        "Park boundaries: all parks fetched ({} cached)",
                        total_cached
                    );
                } else {
                    tracing::info!(
                        "Park boundaries: fetching {} unfetched parks ({} already cached)",
                        parks.len(),
                        total_cached
                    );

                    let (cached, no_match, errors) =
                        fetch_batch(&pool, &client, &semaphore, parks).await;

                    let new_total = park_boundaries::count_boundaries(&pool).await.unwrap_or(0);
                    tracing::info!(
                        "Park boundaries: batch done — {} cached, {} no match, {} errors ({} total cached)",
                        cached,
                        no_match,
                        errors,
                        new_total
                    );
                }
            }
            Err(e) => {
                tracing::error!("Park boundaries: get_unfetched_parks failed: {}", e);
                metrics::counter!(app_metrics::SYNC_ERRORS_TOTAL, "aggregator" => "park_boundaries")
                    .increment(1);
            }
        }

        // Phase 2: Re-fetch stale boundaries
        match park_boundaries::get_stale_boundaries(&pool, config.stale_days, config.batch_size)
            .await
        {
            Ok(stale) => {
                if !stale.is_empty() {
                    tracing::info!(
                        "Park boundaries: refreshing {} stale boundaries",
                        stale.len()
                    );
                    let unfetched: Vec<UnfetchedPark> = stale
                        .into_iter()
                        .map(|park| UnfetchedPark {
                            reference: park.reference,
                            name: park.name,
                            location_desc: park.location_desc,
                            latitude: park.latitude,
                            longitude: park.longitude,
                        })
                        .collect();

                    fetch_batch(&pool, &client, &semaphore, unfetched).await;
                }
            }
            Err(e) => {
                tracing::error!("Park boundaries: get_stale_boundaries failed: {}", e);
                metrics::counter!(app_metrics::SYNC_ERRORS_TOTAL, "aggregator" => "park_boundaries")
                    .increment(1);
            }
        }

        // Record batch metrics
        let new_total = park_boundaries::count_boundaries(&pool).await.unwrap_or(0);
        metrics::gauge!(app_metrics::GIS_BOUNDARIES_CACHED_TOTAL).set(new_total as f64);
        metrics::histogram!(app_metrics::GIS_BATCH_DURATION_SECONDS, "aggregator" => "park_boundaries")
            .record(batch_start.elapsed().as_secs_f64());
        metrics::gauge!(app_metrics::SYNC_LAST_COMPLETED_TIMESTAMP, "aggregator" => "park_boundaries")
            .set(chrono::Utc::now().timestamp() as f64);

        tracing::info!(
            "Park boundaries: sleeping {}h until next cycle",
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
            let source_label = match data_source_for_park(&park.reference) {
                DataSource::PadUs => "pad_us",
                DataSource::NaturalEngland => "natural_england",
                DataSource::Wdpa { .. } => "wdpa",
            };
            let result = fetch_boundary(&pool, &client, &park).await;

            // Record no-match sentinel so the park doesn't block the queue
            if matches!(result, FetchResult::NoMatch) {
                if let Err(e) = park_boundaries::upsert_no_match(
                    &pool,
                    &park.reference,
                    &park.name,
                    source_label,
                )
                .await
                {
                    tracing::error!(
                        "Park boundaries: {} failed to record no-match: {}",
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
            metrics::counter!(app_metrics::GIS_FETCH_TOTAL, "source" => source_label.to_string(), "result" => result_label)
                .increment(1);
            metrics::histogram!(app_metrics::GIS_FETCH_DURATION_SECONDS, "source" => source_label.to_string())
                .record(start.elapsed().as_secs_f64());
            (park.reference, park.name, park.location_desc, result)
        });
        handles.push(handle);
    }

    let mut cached = 0u32;
    let mut no_match = 0u32;
    let mut errors = 0u32;

    for handle in handles {
        match handle.await {
            Ok((reference, name, _location_desc, FetchResult::Cached(quality))) => {
                tracing::info!(
                    "Park boundaries: {} '{}' -> cached ({})",
                    reference,
                    name,
                    quality
                );
                cached += 1;
            }
            Ok((reference, name, location_desc, FetchResult::NoMatch)) => {
                tracing::info!(
                    "Park boundaries: {} '{}' -> no match (loc={:?})",
                    reference,
                    name,
                    location_desc
                );
                no_match += 1;
            }
            Ok((reference, name, _location_desc, FetchResult::Error(e))) => {
                tracing::warn!("Park boundaries: {} '{}' -> error: {}", reference, name, e);
                errors += 1;
            }
            Err(e) => {
                tracing::error!("Park boundaries: task join error: {}", e);
                errors += 1;
            }
        }
    }

    (cached, no_match, errors)
}

/// Determine which data source to use based on POTA reference prefix.
fn data_source_for_park(reference: &str) -> DataSource {
    if reference.starts_with("GB-") {
        DataSource::NaturalEngland
    } else if reference.starts_with("IT-") {
        DataSource::Wdpa { iso3: "ITA" }
    } else {
        DataSource::PadUs
    }
}

/// Fetch boundary for a single park, routing to the correct data source.
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
    match data_source_for_park(&park.reference) {
        DataSource::PadUs => fetch_boundary_padus(pool, client, park).await,
        DataSource::NaturalEngland => fetch_boundary_uk(pool, client, park).await,
        DataSource::Wdpa { iso3 } => fetch_boundary_wdpa(pool, client, park, iso3).await,
    }
}

// ─── US (PAD-US) ────────────────────────────────────────────────────────────

async fn fetch_boundary_padus(
    pool: &PgPool,
    client: &reqwest::Client,
    park: &UnfetchedPark,
) -> Result<Option<String>, Box<dyn std::error::Error + Send + Sync>> {
    let state_abbrev = park.location_desc.as_deref().and_then(state_code_to_abbrev);

    // Strategy 1: Name + state matching
    if let Some(state) = &state_abbrev {
        match query_padus_by_name(client, &park.name, state, &park.reference).await {
            Ok(Some(feature)) => {
                save_feature(pool, park, &feature, "exact", "pad_us_4").await?;
                return Ok(Some("exact".to_string()));
            }
            Ok(None) => {}
            Err(e) => {
                tracing::warn!(
                    "Park boundaries: {} name query failed: {}",
                    park.reference,
                    e
                );
            }
        }
    } else {
        tracing::info!(
            "Park boundaries: {} has no state mapping for '{:?}', skipping name query",
            park.reference,
            park.location_desc
        );
    }

    // Strategy 2: State-specific data source (name match)
    if let Some(state) = &state_abbrev {
        if let Some(source) = state_park_sources::source_for_state(state) {
            let search_name = normalize_park_name(&park.name);
            match state_park_sources::query_by_name(client, source, &search_name).await {
                Ok(Some(feature)) => {
                    save_feature(pool, park, &feature, "exact", source.source_label).await?;
                    return Ok(Some("exact".to_string()));
                }
                Ok(None) => {}
                Err(e) => {
                    tracing::warn!(
                        "Park boundaries: {} state source {} name query failed: {}",
                        park.reference,
                        source.source_label,
                        e
                    );
                }
            }

            // Strategy 3: State-specific data source (spatial)
            if let (Some(lat), Some(lon)) = (park.latitude, park.longitude) {
                match state_park_sources::query_by_point(client, source, lon, lat).await {
                    Ok(Some(feature)) => {
                        save_feature(pool, park, &feature, "spatial", source.source_label).await?;
                        return Ok(Some("spatial".to_string()));
                    }
                    Ok(None) => {}
                    Err(e) => {
                        tracing::warn!(
                            "Park boundaries: {} state source {} spatial query failed: {}",
                            park.reference,
                            source.source_label,
                            e
                        );
                    }
                }
            }
        }
    }

    // Strategy 4: PAD-US spatial query (point-in-polygon)
    if let (Some(lat), Some(lon)) = (park.latitude, park.longitude) {
        match query_padus_by_point(client, lon, lat, &park.reference).await {
            Ok(Some(feature)) => {
                save_feature(pool, park, &feature, "spatial", "pad_us_4").await?;
                return Ok(Some("spatial".to_string()));
            }
            Ok(None) => {}
            Err(e) => {
                tracing::warn!(
                    "Park boundaries: {} spatial query failed: {}",
                    park.reference,
                    e
                );
            }
        }
    } else {
        tracing::info!(
            "Park boundaries: {} has no lat/lon, skipping spatial query",
            park.reference
        );
    }

    Ok(None)
}

/// Query PAD-US by name and state.
///
/// Tries the full park name first for a precise match. If nothing is returned,
/// falls back to the normalized (suffix-stripped) name with a designation-type
/// filter so that e.g. "Huron" doesn't pull in every golf course and metropark
/// in the state.
async fn query_padus_by_name(
    client: &reqwest::Client,
    full_name: &str,
    state: &str,
    park_ref: &str,
) -> Result<Option<ArcGisFeature>, Box<dyn std::error::Error + Send + Sync>> {
    let out_fields = "Loc_Nm,Unit_Nm,Mang_Name,Des_Tp,GIS_Acres,FeatClass";

    // Strategy A: exact match on full park name
    let escaped_full = full_name.replace('\'', "''");
    let where_full = format!("Loc_Nm = '{}' AND State_Nm = '{}'", escaped_full, state);
    let url_full = format!(
        "{}/query?where={}&outFields={}&f=geojson&outSR=4326",
        PADUS_URL,
        urlencoded(&where_full),
        out_fields,
    );
    let features = fetch_arcgis_features(client, &url_full, "PAD-US exact name").await?;
    if !features.is_empty() {
        return Ok(merge_padus_features(features, park_ref));
    }

    // Strategy B: normalized name + designation filter
    let normalized = normalize_park_name(full_name);
    if normalized == full_name {
        // No suffix was stripped — nothing more to try
        return Ok(None);
    }

    let escaped_norm = normalized.replace('\'', "''");
    let des_filter = designation_filter_for_name(full_name).unwrap_or_default();
    let where_norm = format!(
        "Loc_Nm LIKE '%{}%' AND State_Nm = '{}' {}",
        escaped_norm, state, des_filter,
    );
    let url_norm = format!(
        "{}/query?where={}&outFields={}&f=geojson&outSR=4326",
        PADUS_URL,
        urlencoded(&where_norm),
        out_fields,
    );
    let features = fetch_arcgis_features(client, &url_norm, "PAD-US normalized name").await?;
    // Merge all features into one — parks like Don Edwards SF Bay NWR (US-0189)
    // have many parcels that must be combined into a single geometry.
    Ok(merge_padus_features(features, park_ref))
}

/// Return an additional WHERE clause fragment that constrains results by
/// PAD-US designation type or managing agency, based on the park name suffix.
fn designation_filter_for_name(name: &str) -> Option<&'static str> {
    let lower = name.to_lowercase();
    // Order matters — check longer suffixes first
    let mappings: &[(&str, &str)] = &[
        (
            "national wildlife refuge",
            "AND (Des_Tp IN ('NWR','MPA','WA') OR Mang_Name = 'FWS')",
        ),
        (
            "national park and preserve",
            "AND (Des_Tp IN ('NP','NPRE','WA') OR Mang_Name = 'NPS')",
        ),
        (
            "national park",
            "AND (Des_Tp IN ('NP','NPRE','WA') OR Mang_Name = 'NPS')",
        ),
        (
            "national forest",
            "AND (Des_Tp = 'NF' OR Mang_Name = 'USFS')",
        ),
        (
            "national recreation area",
            "AND (Des_Tp = 'NRA' OR Mang_Name IN ('NPS','USFS','BLM'))",
        ),
        (
            "national monument",
            "AND (Des_Tp IN ('NM','NME') OR Mang_Name IN ('NPS','BLM'))",
        ),
        (
            "national seashore",
            "AND (Des_Tp IN ('NS','NLS') OR Mang_Name = 'NPS')",
        ),
        (
            "national lakeshore",
            "AND (Des_Tp IN ('NL','NLS') OR Mang_Name = 'NPS')",
        ),
        (
            "national historical park",
            "AND (Des_Tp IN ('NHP','NHS') OR Mang_Name = 'NPS')",
        ),
        (
            "national historic site",
            "AND (Des_Tp IN ('NHS','NHP') OR Mang_Name = 'NPS')",
        ),
        ("state park", "AND Des_Tp = 'SP'"),
        ("state forest", "AND Des_Tp = 'SF'"),
        ("state recreation area", "AND Des_Tp IN ('SRMA','SCA')"),
        ("wilderness area", "AND Des_Tp = 'WA'"),
        ("wilderness", "AND Des_Tp IN ('WA','WSA')"),
        ("wildlife management area", "AND Des_Tp IN ('SCA','WA')"),
    ];
    for (suffix, filter) in mappings {
        if lower.ends_with(suffix) {
            return Some(filter);
        }
    }
    None
}

/// Query PAD-US by point intersection.
async fn query_padus_by_point(
    client: &reqwest::Client,
    lon: f64,
    lat: f64,
    park_ref: &str,
) -> Result<Option<ArcGisFeature>, Box<dyn std::error::Error + Send + Sync>> {
    let url = format!(
        "{}/query?geometry={},{}&geometryType=esriGeometryPoint&spatialRel=esriSpatialRelIntersects&outFields=Loc_Nm,Unit_Nm,Mang_Name,Des_Tp,GIS_Acres,FeatClass&f=geojson&outSR=4326",
        PADUS_URL, lon, lat
    );

    let features = fetch_arcgis_features(client, &url, "PAD-US spatial").await?;
    // Merge spatial results too — a point can intersect multiple parcels of the same park
    Ok(merge_padus_features(features, park_ref))
}

// ─── UK (Natural England) ───────────────────────────────────────────────────

async fn fetch_boundary_uk(
    pool: &PgPool,
    client: &reqwest::Client,
    park: &UnfetchedPark,
) -> Result<Option<String>, Box<dyn std::error::Error + Send + Sync>> {
    let search_name = normalize_park_name(&park.name);

    // Strategy 1: Name matching against Natural England dataset
    match query_uk_by_name(client, &search_name, &park.reference).await {
        Ok(Some(feature)) => {
            save_feature(pool, park, &feature, "exact", "natural_england").await?;
            return Ok(Some("exact".to_string()));
        }
        Ok(None) => {}
        Err(e) => {
            tracing::warn!(
                "Park boundaries: {} UK name query failed: {}",
                park.reference,
                e
            );
        }
    }

    // Strategy 2: Spatial query (point-in-polygon)
    if let (Some(lat), Some(lon)) = (park.latitude, park.longitude) {
        match query_uk_by_point(client, lon, lat, &park.reference).await {
            Ok(Some(feature)) => {
                save_feature(pool, park, &feature, "spatial", "natural_england").await?;
                return Ok(Some("spatial".to_string()));
            }
            Ok(None) => {}
            Err(e) => {
                tracing::warn!(
                    "Park boundaries: {} UK spatial query failed: {}",
                    park.reference,
                    e
                );
            }
        }
    }

    Ok(None)
}

/// Query Natural England by park name — merges all returned features.
async fn query_uk_by_name(
    client: &reqwest::Client,
    search_name: &str,
    park_ref: &str,
) -> Result<Option<ArcGisFeature>, Box<dyn std::error::Error + Send + Sync>> {
    let escaped_name = search_name.replace('\'', "''");
    let where_clause = format!("NAME LIKE '%{}%'", escaped_name);

    let url = format!(
        "{}/query?where={}&outFields=NAME,DESIG_DATE,AREA_HA&f=geojson&outSR=4326",
        NATURAL_ENGLAND_URL,
        urlencoded(&where_clause)
    );

    let features = fetch_arcgis_features(client, &url, "Natural England name").await?;
    Ok(merge_arcgis_features(features, park_ref))
}

/// Query Natural England by point intersection — merges all returned features.
async fn query_uk_by_point(
    client: &reqwest::Client,
    lon: f64,
    lat: f64,
    park_ref: &str,
) -> Result<Option<ArcGisFeature>, Box<dyn std::error::Error + Send + Sync>> {
    let url = format!(
        "{}/query?geometry={},{}&geometryType=esriGeometryPoint&spatialRel=esriSpatialRelIntersects&outFields=NAME,DESIG_DATE,AREA_HA&f=geojson&outSR=4326",
        NATURAL_ENGLAND_URL, lon, lat
    );

    let features = fetch_arcgis_features(client, &url, "Natural England spatial").await?;
    Ok(merge_arcgis_features(features, park_ref))
}

// ─── International (WDPA) ───────────────────────────────────────────────────

async fn fetch_boundary_wdpa(
    pool: &PgPool,
    client: &reqwest::Client,
    park: &UnfetchedPark,
    iso3: &str,
) -> Result<Option<String>, Box<dyn std::error::Error + Send + Sync>> {
    let search_name = normalize_park_name(&park.name);
    let source = format!("wdpa_{}", iso3.to_lowercase());

    // Strategy 1: Name + country matching
    match query_wdpa_by_name(client, &search_name, iso3, &park.reference).await {
        Ok(Some(feature)) => {
            save_feature(pool, park, &feature, "exact", &source).await?;
            return Ok(Some("exact".to_string()));
        }
        Ok(None) => {}
        Err(e) => {
            tracing::warn!(
                "Park boundaries: {} WDPA name query failed: {}",
                park.reference,
                e
            );
        }
    }

    // Strategy 2: Spatial query (point-in-polygon) filtered by country
    if let (Some(lat), Some(lon)) = (park.latitude, park.longitude) {
        match query_wdpa_by_point(client, lon, lat, iso3, &park.reference).await {
            Ok(Some(feature)) => {
                save_feature(pool, park, &feature, "spatial", &source).await?;
                return Ok(Some("spatial".to_string()));
            }
            Ok(None) => {}
            Err(e) => {
                tracing::warn!(
                    "Park boundaries: {} WDPA spatial query failed: {}",
                    park.reference,
                    e
                );
            }
        }
    }

    Ok(None)
}

/// Query WDPA by name and ISO3 country code — merges all returned features.
async fn query_wdpa_by_name(
    client: &reqwest::Client,
    search_name: &str,
    iso3: &str,
    park_ref: &str,
) -> Result<Option<ArcGisFeature>, Box<dyn std::error::Error + Send + Sync>> {
    let escaped_name = search_name.replace('\'', "''");
    let where_clause = format!("NAME LIKE '%{}%' AND ISO3 = '{}'", escaped_name, iso3);

    let url = format!(
        "{}/query?where={}&outFields=NAME,DESIG_ENG,DESIG,IUCN_CAT,REP_AREA,ISO3&f=geojson&outSR=4326",
        WDPA_URL,
        urlencoded(&where_clause)
    );

    let features = fetch_arcgis_features(client, &url, "WDPA name").await?;
    Ok(merge_arcgis_features(features, park_ref))
}

/// Query WDPA by point intersection filtered by country — merges all returned features.
async fn query_wdpa_by_point(
    client: &reqwest::Client,
    lon: f64,
    lat: f64,
    iso3: &str,
    park_ref: &str,
) -> Result<Option<ArcGisFeature>, Box<dyn std::error::Error + Send + Sync>> {
    let where_clause = format!("ISO3 = '{}'", iso3);

    let url = format!(
        "{}/query?geometry={},{}&geometryType=esriGeometryPoint&spatialRel=esriSpatialRelIntersects&where={}&outFields=NAME,DESIG_ENG,DESIG,IUCN_CAT,REP_AREA,ISO3&f=geojson&outSR=4326",
        WDPA_URL, lon, lat,
        urlencoded(&where_clause)
    );

    let features = fetch_arcgis_features(client, &url, "WDPA spatial").await?;
    Ok(merge_arcgis_features(features, park_ref))
}

// ─── Shared helpers ─────────────────────────────────────────────────────────

/// Fetch features from an ArcGIS REST endpoint, parsing the standard response format.
async fn fetch_arcgis_features(
    client: &reqwest::Client,
    url: &str,
    label: &str,
) -> Result<Vec<ArcGisFeature>, Box<dyn std::error::Error + Send + Sync>> {
    let resp_text = client
        .get(url)
        .send()
        .await?
        .error_for_status()?
        .text()
        .await?;

    let resp: ArcGisResponse = match serde_json::from_str(&resp_text) {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!(
                "Park boundaries: {} response parse error: {} (first 200 chars: {})",
                label,
                e,
                &resp_text[..resp_text.len().min(200)]
            );
            return Ok(vec![]);
        }
    };

    Ok(resp.features.unwrap_or_default())
}

/// Merge all PAD-US features into a single feature with combined geometry.
///
/// Parks like Don Edwards San Francisco Bay NWR (US-0189) have many separate
/// parcels in PAD-US across multiple FeatClass categories (Designation, Fee,
/// Marine, etc.). We merge ALL geometries into a single GeometryCollection
/// so the full park boundary is preserved, and sum the total acreage.
fn merge_padus_features(features: Vec<ArcGisFeature>, park_ref: &str) -> Option<ArcGisFeature> {
    if features.is_empty() {
        return None;
    }
    if features.len() == 1 {
        return features.into_iter().next();
    }

    // Collect all geometries and sum acreage across all FeatClass categories
    let mut geometries = Vec::new();
    let mut total_acres: f64 = 0.0;
    for feature in &features {
        if let Some(geom) = &feature.geometry {
            geometries.push(geom.clone());
        }
        if let Some(acres) = feature.properties.as_ref().and_then(|a| a.gis_acres) {
            total_acres += acres;
        }
    }

    if geometries.is_empty() {
        return None;
    }

    let merged_geometry = union_geojson_geometries(geometries, park_ref);

    // Take attributes from the first feature, override acreage with total
    let mut result = features.into_iter().next().unwrap();
    result.geometry = Some(merged_geometry);
    if total_acres > 0.0 {
        if let Some(ref mut attrs) = result.properties {
            attrs.gis_acres = Some(total_acres);
        }
    }
    Some(result)
}

/// Merge all ArcGIS features (non-PAD-US) into a single feature with merged geometry.
/// Used for Natural England and WDPA queries where there's no FeatClass grouping.
fn merge_arcgis_features(features: Vec<ArcGisFeature>, park_ref: &str) -> Option<ArcGisFeature> {
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

    let merged_geometry = union_geojson_geometries(geometries, park_ref);
    let mut result = features.into_iter().next().unwrap();
    result.geometry = Some(merged_geometry);
    Some(result)
}

/// Merge multiple GeoJSON geometries into one.
/// Returns the single geometry if only one, or a GeometryCollection if multiple.
pub fn merge_geojson_geometries(geometries: Vec<serde_json::Value>) -> serde_json::Value {
    if geometries.len() == 1 {
        return geometries.into_iter().next().unwrap();
    }
    serde_json::json!({
        "type": "GeometryCollection",
        "geometries": geometries
    })
}

/// Union the polygonal geometries of a single park reference into one merged
/// GeoJSON MultiPolygon.
///
/// A POTA reference often maps to several PAD-US parcels (Designation, Fee,
/// Marine, …) whose polygons overlap. Rendering them as overlapping members of
/// a MultiPolygon draws doubled/tripled outlines on the map. iOS previously
/// dissolved these with a CGPath union (~476 lines) that Android cannot run, so
/// we do the boolean union here at ingest — once — and store the dissolved
/// geometry. Overlapping units collapse into a single polygon; disjoint units
/// remain separate members of the MultiPolygon.
///
/// This runs BEFORE the DB-side `ST_Simplify` (see `upsert_boundary`), so the
/// union is computed on full-resolution geometry.
///
/// Robustness: degenerate or self-intersecting inputs must never fail ingest.
/// If any geometry can't be parsed into a polygon, or the union produces an
/// empty result, we fall back to the unmerged `merge_geojson_geometries`
/// (GeometryCollection) so the boundary is still stored and served.
pub fn union_geojson_geometries(
    geometries: Vec<serde_json::Value>,
    park_ref: &str,
) -> serde_json::Value {
    use geo::orient::{Direction, Orient};
    use geojson::Geometry as GeoJsonGeometry;

    if geometries.len() == 1 {
        return geometries.into_iter().next().unwrap();
    }

    // Parse each GeoJSON geometry and collect its constituent polygons.
    //
    // Upstream ArcGIS/PAD-US exports frequently miswind rings (interior rings
    // wound the same direction as the exterior instead of opposite). If fed
    // to `unary_union` as-is, a miswound hole is silently dropped — the union
    // "succeeds" so neither fallback warning below fires. Normalize every
    // polygon's winding (exterior CCW, interior CW) before union so holes
    // survive regardless of source winding convention.
    let mut polygons: Vec<geo::Polygon<f64>> = Vec::new();
    let mut parse_failed = false;
    for value in &geometries {
        match GeoJsonGeometry::try_from(value.clone())
            .ok()
            .and_then(|g| geo::Geometry::<f64>::try_from(g).ok())
        {
            Some(geo::Geometry::Polygon(p)) => polygons.push(p.orient(Direction::Default)),
            Some(geo::Geometry::MultiPolygon(mp)) => polygons.extend(
                mp.0.into_iter()
                    .map(|p| p.orient(Direction::Default)),
            ),
            _ => {
                // Non-polygonal or unparseable member — can't safely union.
                parse_failed = true;
                break;
            }
        }
    }

    if parse_failed || polygons.is_empty() {
        tracing::warn!(
            "Park boundaries: {} union parse failed, falling back to unmerged geometry",
            park_ref
        );
        return merge_geojson_geometries(geometries);
    }

    // `unary_union` handles overlaps (collapse) and disjoint inputs (kept as
    // separate members) alike, and is much faster than a pairwise fold.
    let unioned: geo::MultiPolygon<f64> = geo::unary_union(&polygons);

    if unioned.0.is_empty() {
        // Union dissolved everything (all-degenerate input) — don't lose the
        // geometry; serve it unmerged.
        tracing::warn!(
            "Park boundaries: {} union produced empty result, falling back to unmerged geometry",
            park_ref
        );
        return merge_geojson_geometries(geometries);
    }

    // Serialize the dissolved MultiPolygon back to a GeoJSON Value.
    let out = GeoJsonGeometry::from(&unioned);
    match serde_json::to_value(&out) {
        Ok(v) => v,
        Err(_) => merge_geojson_geometries(geometries),
    }
}

/// Save an ArcGIS feature as a park boundary.
async fn save_feature(
    pool: &PgPool,
    park: &UnfetchedPark,
    feature: &ArcGisFeature,
    match_quality: &str,
    source: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let geojson = match &feature.geometry {
        Some(g) => serde_json::to_string(g)?,
        None => {
            tracing::warn!(
                "Park boundaries: {} matched but feature has no geometry",
                park.reference
            );
            return Ok(());
        }
    };

    let attrs = feature.properties.as_ref();
    let designation = attrs
        .and_then(|a| a.des_tp.as_deref())
        .or_else(|| attrs.and_then(|a| a.desig_eng.as_deref()))
        .or_else(|| attrs.and_then(|a| a.desig.as_deref()));
    let manager = attrs.and_then(|a| a.mang_name.as_deref());
    let acreage = attrs
        .and_then(|a| a.gis_acres)
        .or_else(|| attrs.and_then(|a| a.area_ha.map(|ha| ha * 2.47105)))
        .or_else(|| attrs.and_then(|a| a.rep_area.map(|km2| km2 * 247.105)));

    park_boundaries::upsert_boundary(
        pool,
        &park.reference,
        &park.name,
        designation,
        manager,
        acreage,
        match_quality,
        &geojson,
        source,
    )
    .await?;

    Ok(())
}

/// URL-encode a string for use in ArcGIS REST API query parameters.
/// The `%` must be encoded first (to `%25`) so that SQL LIKE wildcards
/// don't get misinterpreted as URL percent-encoding by the server.
fn urlencoded(s: &str) -> String {
    s.replace('%', "%25")
        .replace(' ', "%20")
        .replace('\'', "%27")
        .replace('=', "%3D")
        .replace('&', "%26")
}

/// Normalize a POTA park name for search by stripping common suffixes.
fn normalize_park_name(name: &str) -> String {
    let suffixes = [
        " National Park and Preserve",
        " National Park",
        " National Forest",
        " National Wildlife Refuge",
        " National Recreation Area",
        " National Monument",
        " National Seashore",
        " National Lakeshore",
        " National Historical Park",
        " National Historic Site",
        " State Park",
        " State Forest",
        " State Recreation Area",
        " Wilderness Area",
        " Wilderness",
        " Wildlife Management Area",
        " WMA",
        " State Natural Area",
        " State Historic Site",
        " Parco Nazionale",
        " Parco Regionale",
        " Riserva Naturale",
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

/// Extract state abbreviation from POTA location code.
/// Handles single-state codes like "US-ME" -> "ME".
/// Returns None for multi-state codes like "US-DC,US-MD,US-WV".
fn state_code_to_abbrev(code: &str) -> Option<&str> {
    // Skip multi-state codes (contain commas)
    if code.contains(',') {
        return None;
    }
    code.strip_prefix("US-")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::park_boundary::{
        ArcGisAttributes, ArcGisFeature, ArcGisResponse, WfsFeatureCollection,
    };

    // ── data_source_for_park ────────────────────────────────────────────────

    #[test]
    fn test_data_source_routing() {
        assert!(matches!(data_source_for_park("US-0189"), DataSource::PadUs));
        assert!(matches!(data_source_for_park("US-1234"), DataSource::PadUs));
        assert!(matches!(
            data_source_for_park("GB-0001"),
            DataSource::NaturalEngland
        ));
        assert!(matches!(
            data_source_for_park("IT-0001"),
            DataSource::Wdpa { iso3: "ITA" }
        ));
        // PL- parks go through PadUs routing (handled by separate aggregator)
        assert!(matches!(data_source_for_park("PL-0001"), DataSource::PadUs));
    }

    // ── normalize_park_name ─────────────────────────────────────────────────

    #[test]
    fn test_normalize_park_name_us_suffixes() {
        assert_eq!(
            normalize_park_name("Yellowstone National Park"),
            "Yellowstone"
        );
        assert_eq!(
            normalize_park_name("Denali National Park and Preserve"),
            "Denali"
        );
        assert_eq!(
            normalize_park_name("White Mountain National Forest"),
            "White Mountain"
        );
        assert_eq!(
            normalize_park_name("Don Edwards San Francisco Bay National Wildlife Refuge"),
            "Don Edwards San Francisco Bay"
        );
        assert_eq!(
            normalize_park_name("Cape Cod National Seashore"),
            "Cape Cod"
        );
        assert_eq!(
            normalize_park_name("Pictured Rocks National Lakeshore"),
            "Pictured Rocks"
        );
        assert_eq!(normalize_park_name("Baxter State Park"), "Baxter");
        assert_eq!(
            normalize_park_name("Bob Marshall Wilderness Area"),
            "Bob Marshall"
        );
        assert_eq!(
            normalize_park_name("Bob Marshall Wilderness"),
            "Bob Marshall"
        );
        assert_eq!(
            normalize_park_name("Dayton Aviation Heritage National Historical Park"),
            "Dayton Aviation Heritage"
        );
        assert_eq!(
            normalize_park_name("Hubbell Trading Post National Historic Site"),
            "Hubbell Trading Post"
        );
    }

    #[test]
    fn test_normalize_park_name_italian_suffixes() {
        assert_eq!(
            normalize_park_name("Gran Paradiso Parco Nazionale"),
            "Gran Paradiso"
        );
        assert_eq!(
            normalize_park_name("Appennino Lucano Parco Regionale"),
            "Appennino Lucano"
        );
    }

    #[test]
    fn test_normalize_park_name_no_match() {
        assert_eq!(normalize_park_name("Just A Place"), "Just A Place");
        assert_eq!(normalize_park_name(""), "");
    }

    // ── state_code_to_abbrev ────────────────────────────────────────────────

    #[test]
    fn test_state_code_single() {
        assert_eq!(state_code_to_abbrev("US-ME"), Some("ME"));
        assert_eq!(state_code_to_abbrev("US-CA"), Some("CA"));
        assert_eq!(state_code_to_abbrev("US-TX"), Some("TX"));
    }

    #[test]
    fn test_state_code_multi_state() {
        assert_eq!(state_code_to_abbrev("US-DC,US-MD,US-WV"), None);
    }

    #[test]
    fn test_state_code_non_us() {
        assert_eq!(state_code_to_abbrev("GB-ENG"), None);
        assert_eq!(state_code_to_abbrev("IT-LOM"), None);
    }

    // ── designation_filter_for_name ─────────────────────────────────────────

    #[test]
    fn test_designation_filter() {
        assert!(designation_filter_for_name("Yellowstone National Park").is_some());
        assert!(designation_filter_for_name("White Mountain National Forest").is_some());
        assert!(designation_filter_for_name("Baxter State Park").is_some());
        assert!(designation_filter_for_name("Some Random Place").is_none());
    }

    #[test]
    fn test_designation_filter_longer_suffix_first() {
        // "National Park and Preserve" should match before "National Park"
        let filter = designation_filter_for_name("Denali National Park and Preserve").unwrap();
        assert!(filter.contains("NPRE"));
    }

    #[test]
    fn test_designation_filter_historical_park() {
        // NHP parks like US-0732 need an NHP/NHS + NPS filter so spatial fallback
        // doesn't grab the surrounding military polygon (e.g. Wright-Patterson AFB).
        let filter =
            designation_filter_for_name("Dayton Aviation Heritage National Historical Park")
                .unwrap();
        assert!(filter.contains("NHP"));
        assert!(filter.contains("NPS"));

        let filter =
            designation_filter_for_name("Hubbell Trading Post National Historic Site").unwrap();
        assert!(filter.contains("NHS"));
        assert!(filter.contains("NPS"));
    }

    // ── urlencoded ──────────────────────────────────────────────────────────

    #[test]
    fn test_urlencoded() {
        assert_eq!(urlencoded("hello world"), "hello%20world");
        assert_eq!(urlencoded("a=b&c=d"), "a%3Db%26c%3Dd");
        assert_eq!(urlencoded("it's"), "it%27s");
        assert_eq!(urlencoded("100%"), "100%25");
    }

    // ── ArcGIS response parsing ─────────────────────────────────────────────

    #[test]
    fn test_parse_arcgis_padus_response() {
        let json = r#"{
            "features": [{
                "properties": {
                    "Loc_Nm": "Yellowstone",
                    "Unit_Nm": "Yellowstone NP",
                    "Mang_Name": "NPS",
                    "Des_Tp": "NP",
                    "GIS_Acres": 2219791.0,
                    "FeatClass": "Designation"
                },
                "geometry": {
                    "type": "MultiPolygon",
                    "coordinates": [[[[-110.0, 44.0], [-110.5, 44.5], [-110.0, 44.5], [-110.0, 44.0]]]]
                }
            }]
        }"#;

        let resp: ArcGisResponse = serde_json::from_str(json).unwrap();
        let features = resp.features.unwrap();
        assert_eq!(features.len(), 1);

        let attrs = features[0].properties.as_ref().unwrap();
        assert_eq!(attrs.loc_nm.as_deref(), Some("Yellowstone"));
        assert_eq!(attrs.mang_name.as_deref(), Some("NPS"));
        assert_eq!(attrs.des_tp.as_deref(), Some("NP"));
        assert_eq!(attrs.gis_acres, Some(2219791.0));
        assert!(features[0].geometry.is_some());
    }

    #[test]
    fn test_parse_arcgis_natural_england_response() {
        let json = r#"{
            "features": [{
                "properties": {
                    "NAME": "Lake District",
                    "AREA_HA": 236300.0
                },
                "geometry": {
                    "type": "MultiPolygon",
                    "coordinates": [[[[-3.0, 54.4], [-3.1, 54.5], [-3.0, 54.5], [-3.0, 54.4]]]]
                }
            }]
        }"#;

        let resp: ArcGisResponse = serde_json::from_str(json).unwrap();
        let features = resp.features.unwrap();
        let attrs = features[0].properties.as_ref().unwrap();
        assert_eq!(attrs.name.as_deref(), Some("Lake District"));
        assert_eq!(attrs.area_ha, Some(236300.0));
    }

    #[test]
    fn test_parse_arcgis_wdpa_response() {
        let json = r#"{
            "features": [{
                "properties": {
                    "NAME": "Gran Paradiso",
                    "DESIG_ENG": "National Park",
                    "DESIG": "Parco Nazionale",
                    "IUCN_CAT": "II",
                    "REP_AREA": 710.43,
                    "ISO3": "ITA"
                },
                "geometry": {
                    "type": "MultiPolygon",
                    "coordinates": [[[[7.3, 45.5], [7.4, 45.6], [7.3, 45.6], [7.3, 45.5]]]]
                }
            }]
        }"#;

        let resp: ArcGisResponse = serde_json::from_str(json).unwrap();
        let features = resp.features.unwrap();
        let attrs = features[0].properties.as_ref().unwrap();
        assert_eq!(attrs.name.as_deref(), Some("Gran Paradiso"));
        assert_eq!(attrs.desig_eng.as_deref(), Some("National Park"));
        assert_eq!(attrs.iso3.as_deref(), Some("ITA"));
        assert_eq!(attrs.rep_area, Some(710.43));
    }

    #[test]
    fn test_parse_arcgis_empty_features() {
        let json = r#"{"features": []}"#;
        let resp: ArcGisResponse = serde_json::from_str(json).unwrap();
        assert!(resp.features.unwrap().is_empty());
    }

    #[test]
    fn test_parse_arcgis_null_features() {
        let json = r#"{}"#;
        let resp: ArcGisResponse = serde_json::from_str(json).unwrap();
        assert!(resp.features.is_none());
    }

    // ── WFS response parsing (Polish parks) ─────────────────────────────────

    #[test]
    fn test_parse_wfs_feature_collection() {
        let json = r#"{
            "features": [{
                "properties": {
                    "nazwa": "Białowieski Park Narodowy",
                    "pow_ha": 10517.0,
                    "id_iip": "PL.ZIPOP.1393.PN.1"
                },
                "geometry": {
                    "type": "MultiPolygon",
                    "coordinates": [[[[23.7, 52.7], [23.8, 52.8], [23.7, 52.8], [23.7, 52.7]]]]
                }
            }]
        }"#;

        let collection: WfsFeatureCollection = serde_json::from_str(json).unwrap();
        let features = collection.features.unwrap();
        assert_eq!(features.len(), 1);

        let props = features[0].properties.as_ref().unwrap();
        assert_eq!(props.nazwa.as_deref(), Some("Białowieski Park Narodowy"));
        assert_eq!(props.area_ha, Some(10517.0));
        assert!(features[0].geometry.is_some());
    }

    #[test]
    fn test_parse_wfs_alternative_field_names() {
        // Test the "powierzchnia" alias for area_ha
        let json = r#"{
            "features": [{
                "properties": {
                    "nazwa": "Test Park",
                    "powierzchnia": 500.0,
                    "inspireid": "PL.ZIPOP.TEST"
                },
                "geometry": {"type": "Point", "coordinates": [20.0, 50.0]}
            }]
        }"#;

        let collection: WfsFeatureCollection = serde_json::from_str(json).unwrap();
        let features = collection.features.unwrap();
        let props = features[0].properties.as_ref().unwrap();
        assert_eq!(props.area_ha, Some(500.0));
        assert_eq!(props.inspire_id.as_deref(), Some("PL.ZIPOP.TEST"));
    }

    // ── Geometry merging ────────────────────────────────────────────────────

    #[test]
    fn test_merge_single_geometry() {
        let geom = serde_json::json!({
            "type": "Polygon",
            "coordinates": [[[-110.0, 44.0], [-110.5, 44.5], [-110.0, 44.5], [-110.0, 44.0]]]
        });
        let merged = merge_geojson_geometries(vec![geom.clone()]);
        assert_eq!(merged, geom);
    }

    #[test]
    fn test_merge_multiple_geometries() {
        let geom1 = serde_json::json!({"type": "Polygon", "coordinates": [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 0.0]]]});
        let geom2 = serde_json::json!({"type": "Polygon", "coordinates": [[[2.0, 2.0], [3.0, 2.0], [3.0, 3.0], [2.0, 2.0]]]});

        let merged = merge_geojson_geometries(vec![geom1, geom2]);
        assert_eq!(merged["type"], "GeometryCollection");
        assert_eq!(merged["geometries"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn test_merge_padus_features_sums_acreage() {
        let features = vec![
            ArcGisFeature {
                properties: Some(ArcGisAttributes {
                    loc_nm: Some("Test NWR".to_string()),
                    unit_nm: None,
                    mang_name: Some("FWS".to_string()),
                    des_tp: Some("NWR".to_string()),
                    gis_acres: Some(1000.0),
                    feat_class: Some("Designation".to_string()),
                    name: None,
                    area_ha: None,
                    desig_eng: None,
                    desig: None,
                    iucn_cat: None,
                    rep_area: None,
                    iso3: None,
                }),
                geometry: Some(
                    serde_json::json!({"type": "Polygon", "coordinates": [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 0.0]]]}),
                ),
            },
            ArcGisFeature {
                properties: Some(ArcGisAttributes {
                    loc_nm: Some("Test NWR".to_string()),
                    unit_nm: None,
                    mang_name: Some("FWS".to_string()),
                    des_tp: Some("NWR".to_string()),
                    gis_acres: Some(500.0),
                    feat_class: Some("Fee".to_string()),
                    name: None,
                    area_ha: None,
                    desig_eng: None,
                    desig: None,
                    iucn_cat: None,
                    rep_area: None,
                    iso3: None,
                }),
                geometry: Some(
                    serde_json::json!({"type": "Polygon", "coordinates": [[[2.0, 2.0], [3.0, 2.0], [3.0, 3.0], [2.0, 2.0]]]}),
                ),
            },
        ];

        let merged = merge_padus_features(features, "US-TEST").unwrap();
        assert_eq!(merged.properties.as_ref().unwrap().gis_acres, Some(1500.0));
        // Two disjoint parcels union into a MultiPolygon (both members preserved),
        // not the legacy GeometryCollection.
        assert_eq!(
            merged.geometry.as_ref().unwrap()["type"],
            "MultiPolygon"
        );
    }

    #[test]
    fn test_merge_padus_features_empty() {
        assert!(merge_padus_features(vec![], "US-TEST").is_none());
    }

    #[test]
    fn test_merge_padus_features_single() {
        let feature = ArcGisFeature {
            properties: Some(ArcGisAttributes {
                loc_nm: Some("Test".to_string()),
                unit_nm: None,
                mang_name: None,
                des_tp: None,
                gis_acres: Some(100.0),
                feat_class: None,
                name: None,
                area_ha: None,
                desig_eng: None,
                desig: None,
                iucn_cat: None,
                rep_area: None,
                iso3: None,
            }),
            geometry: Some(
                serde_json::json!({"type": "Polygon", "coordinates": [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 0.0]]]}),
            ),
        };
        let merged = merge_padus_features(vec![feature], "US-TEST").unwrap();
        // Single feature returned as-is, not wrapped in GeometryCollection
        assert_eq!(merged.geometry.as_ref().unwrap()["type"], "Polygon");
    }

    // ── Polygon union (multi-unit merge) ────────────────────────────────────

    /// Approximate signed area of a GeoJSON Polygon/MultiPolygon (shoelace, in
    /// squared-degree units). Test-only helper for asserting union behavior.
    fn geojson_area(value: &serde_json::Value) -> f64 {
        fn ring_area(ring: &serde_json::Value) -> f64 {
            let pts = ring.as_array().unwrap();
            let mut sum = 0.0;
            for i in 0..pts.len() {
                let a = pts[i].as_array().unwrap();
                let b = pts[(i + 1) % pts.len()].as_array().unwrap();
                let (ax, ay) = (a[0].as_f64().unwrap(), a[1].as_f64().unwrap());
                let (bx, by) = (b[0].as_f64().unwrap(), b[1].as_f64().unwrap());
                sum += ax * by - bx * ay;
            }
            (sum / 2.0).abs()
        }
        fn polygon_area(coords: &serde_json::Value) -> f64 {
            let rings = coords.as_array().unwrap();
            if rings.is_empty() {
                return 0.0;
            }
            // exterior minus holes
            let mut area = ring_area(&rings[0]);
            for hole in &rings[1..] {
                area -= ring_area(hole);
            }
            area
        }
        match value["type"].as_str() {
            Some("Polygon") => polygon_area(&value["coordinates"]),
            Some("MultiPolygon") => value["coordinates"]
                .as_array()
                .unwrap()
                .iter()
                .map(polygon_area)
                .sum(),
            _ => 0.0,
        }
    }

    /// Count the polygons in a GeoJSON Polygon/MultiPolygon value.
    fn polygon_count(value: &serde_json::Value) -> usize {
        match value["type"].as_str() {
            Some("Polygon") => 1,
            Some("MultiPolygon") => value["coordinates"].as_array().map_or(0, |a| a.len()),
            _ => 0,
        }
    }

    // Two overlapping unit rectangles for one reference must merge into a single
    // polygon whose area is less than the sum of the two parts.
    #[test]
    fn test_union_overlapping_rectangles_single_polygon() {
        // Rect A: (0,0)-(2,2), area 4. Rect B: (1,1)-(3,3), area 4.
        // Overlap (1,1)-(2,2) area 1 -> union area 7.
        let a = serde_json::json!({
            "type": "Polygon",
            "coordinates": [[[0.0, 0.0], [2.0, 0.0], [2.0, 2.0], [0.0, 2.0], [0.0, 0.0]]]
        });
        let b = serde_json::json!({
            "type": "Polygon",
            "coordinates": [[[1.0, 1.0], [3.0, 1.0], [3.0, 3.0], [1.0, 3.0], [1.0, 1.0]]]
        });

        let merged = union_geojson_geometries(vec![a, b], "US-TEST");

        // A single merged polygon (MultiPolygon with exactly one member, or Polygon).
        assert_eq!(
            polygon_count(&merged),
            1,
            "overlapping units must collapse to one polygon, got {}",
            merged
        );

        let area = geojson_area(&merged);
        let sum_of_parts = 4.0 + 4.0;
        assert!(
            area < sum_of_parts,
            "union area {} must be < sum of parts {}",
            area,
            sum_of_parts
        );
        assert!(
            (area - 7.0).abs() < 1e-6,
            "union area {} should be ~7.0",
            area
        );
    }

    // Two disjoint unit polygons for one reference stay separate: a MultiPolygon
    // with both, total area preserved.
    #[test]
    fn test_union_disjoint_polygons_multipolygon() {
        // Rect A: (0,0)-(1,1) area 1. Rect B: (5,5)-(6,6) area 1. No overlap.
        let a = serde_json::json!({
            "type": "Polygon",
            "coordinates": [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0], [0.0, 0.0]]]
        });
        let b = serde_json::json!({
            "type": "Polygon",
            "coordinates": [[[5.0, 5.0], [6.0, 5.0], [6.0, 6.0], [5.0, 6.0], [5.0, 5.0]]]
        });

        let merged = union_geojson_geometries(vec![a, b], "US-TEST");

        assert_eq!(merged["type"], "MultiPolygon");
        assert_eq!(
            polygon_count(&merged),
            2,
            "disjoint units must remain two polygons, got {}",
            merged
        );

        let area = geojson_area(&merged);
        assert!(
            (area - 2.0).abs() < 1e-6,
            "disjoint union area {} should preserve both (~2.0)",
            area
        );
    }

    // A zero-area / collapsed-ring input still parses as a valid `geo::Polygon`
    // and flows through the union normally — this pins that the union survives
    // it without panicking. It does NOT exercise the parse-failure fallback
    // (see `test_union_non_polygonal_member_falls_back` for that).
    #[test]
    fn test_union_zero_area_input_does_not_panic() {
        // A "polygon" whose ring is collapsed to a line (zero area / invalid).
        let degenerate = serde_json::json!({
            "type": "Polygon",
            "coordinates": [[[0.0, 0.0], [1.0, 1.0], [0.0, 0.0]]]
        });
        let good = serde_json::json!({
            "type": "Polygon",
            "coordinates": [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0], [0.0, 0.0]]]
        });

        // Must not panic; must return *something* valid (never drop the geometry).
        let merged = union_geojson_geometries(vec![degenerate, good], "US-TEST");
        assert!(merged.get("type").is_some(), "must produce a geometry");
    }

    // A non-polygonal member (e.g. a LineString) can't be parsed into the
    // polygon union, so ingest must fall back to the unmerged GeometryCollection
    // rather than dropping the geometry.
    #[test]
    fn test_union_non_polygonal_member_falls_back() {
        let polygon = serde_json::json!({
            "type": "Polygon",
            "coordinates": [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0], [0.0, 0.0]]]
        });
        let line = serde_json::json!({
            "type": "LineString",
            "coordinates": [[0.0, 0.0], [1.0, 1.0]]
        });

        let merged = union_geojson_geometries(vec![polygon.clone(), line.clone()], "US-TEST");

        // Falls back to `merge_geojson_geometries`'s unmerged GeometryCollection
        // shape, preserving both original geometries verbatim.
        assert_eq!(merged["type"], "GeometryCollection");
        let geometries = merged["geometries"].as_array().unwrap();
        assert_eq!(geometries.len(), 2);
        assert_eq!(geometries[0], polygon);
        assert_eq!(geometries[1], line);
    }

    // A donut polygon (exterior ring + interior hole) unioned with a disjoint
    // simple polygon must keep the hole intact in the output.
    #[test]
    fn test_union_preserves_interior_ring() {
        // Exterior wound counter-clockwise, interior hole wound clockwise —
        // `unary_union` requires holes to wind opposite their exterior (see
        // `geo::unary_union` docs) or the hole is silently dropped.
        let donut = serde_json::json!({
            "type": "Polygon",
            "coordinates": [
                [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0], [0.0, 0.0]],
                [[3.0, 3.0], [3.0, 7.0], [7.0, 7.0], [7.0, 3.0], [3.0, 3.0]]
            ]
        });
        let disjoint = serde_json::json!({
            "type": "Polygon",
            "coordinates": [[[20.0, 20.0], [21.0, 20.0], [21.0, 21.0], [20.0, 21.0], [20.0, 20.0]]]
        });

        let merged = union_geojson_geometries(vec![donut, disjoint], "US-TEST");

        assert_eq!(merged["type"], "MultiPolygon");
        let polygons = merged["coordinates"].as_array().unwrap();
        assert_eq!(polygons.len(), 2, "donut and disjoint polygon stay separate");

        // Find the donut member (the one with more than one ring) and confirm
        // the hole survived the union.
        let donut_rings = polygons
            .iter()
            .map(|p| p.as_array().unwrap().len())
            .max()
            .unwrap();
        assert!(
            donut_rings > 1,
            "donut polygon must retain its interior ring, got ring counts {:?}",
            polygons.iter().map(|p| p.as_array().unwrap().len()).collect::<Vec<_>>()
        );
    }

    // A donut polygon whose interior ring is miswound — wound the SAME
    // direction as the exterior, as ArcGIS/PAD-US exports frequently ship it —
    // unioned with a disjoint polygon must still preserve the hole. Without
    // normalizing ring winding before union, `unary_union` treats a
    // same-wound "hole" as fill and silently drops it (no warning fires,
    // since the union technically "succeeds").
    #[test]
    fn test_union_miswound_interior_ring_preserved() {
        // Both exterior and interior wound counter-clockwise (miswound —
        // interior should be clockwise per GeoJSON/geo convention).
        let miswound_donut = serde_json::json!({
            "type": "Polygon",
            "coordinates": [
                [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0], [0.0, 0.0]],
                [[3.0, 3.0], [7.0, 3.0], [7.0, 7.0], [3.0, 7.0], [3.0, 3.0]]
            ]
        });
        let disjoint = serde_json::json!({
            "type": "Polygon",
            "coordinates": [[[20.0, 20.0], [21.0, 20.0], [21.0, 21.0], [20.0, 21.0], [20.0, 20.0]]]
        });

        let merged = union_geojson_geometries(vec![miswound_donut, disjoint], "US-TEST");

        assert_eq!(merged["type"], "MultiPolygon");
        let polygons = merged["coordinates"].as_array().unwrap();
        assert_eq!(
            polygons.len(),
            2,
            "miswound donut and disjoint polygon stay separate"
        );

        let ring_counts: Vec<usize> = polygons.iter().map(|p| p.as_array().unwrap().len()).collect();
        assert!(
            ring_counts.iter().any(|&n| n > 1),
            "miswound interior ring must still survive the union (normalize winding before union), got ring counts {:?}",
            ring_counts
        );
    }

    // A plain Polygon unioned with a MultiPolygon (2+ disjoint sub-polygons)
    // must exercise the `Geometry::MultiPolygon` extend path and preserve all
    // input polygons.
    #[test]
    fn test_union_mixed_polygon_and_multipolygon() {
        let solo = serde_json::json!({
            "type": "Polygon",
            "coordinates": [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0], [0.0, 0.0]]]
        });
        let multi = serde_json::json!({
            "type": "MultiPolygon",
            "coordinates": [
                [[[5.0, 5.0], [6.0, 5.0], [6.0, 6.0], [5.0, 6.0], [5.0, 5.0]]],
                [[[10.0, 10.0], [11.0, 10.0], [11.0, 11.0], [10.0, 11.0], [10.0, 10.0]]]
            ]
        });

        let merged = union_geojson_geometries(vec![solo, multi], "US-TEST");

        assert_eq!(merged["type"], "MultiPolygon");
        assert_eq!(
            polygon_count(&merged),
            3,
            "all three disjoint input polygons (1 solo + 2 from the MultiPolygon) must survive, got {}",
            merged
        );

        let area = geojson_area(&merged);
        assert!(
            (area - 3.0).abs() < 1e-6,
            "union area {} should preserve all three unit-square parts (~3.0)",
            area
        );
    }

    #[test]
    fn test_union_single_geometry_passthrough() {
        let geom = serde_json::json!({
            "type": "Polygon",
            "coordinates": [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0], [0.0, 0.0]]]
        });
        let merged = union_geojson_geometries(vec![geom.clone()], "US-TEST");
        // Single input is returned unchanged (no need to round-trip through geo).
        assert_eq!(merged, geom);
    }

    #[test]
    fn test_merge_padus_features_unions_overlapping() {
        // Two overlapping parcels of one park -> single merged polygon, acreage summed.
        let features = vec![
            ArcGisFeature {
                properties: Some(ArcGisAttributes {
                    loc_nm: Some("Overlap Park".to_string()),
                    unit_nm: None,
                    mang_name: Some("NPS".to_string()),
                    des_tp: Some("NP".to_string()),
                    gis_acres: Some(400.0),
                    feat_class: Some("Designation".to_string()),
                    name: None,
                    area_ha: None,
                    desig_eng: None,
                    desig: None,
                    iucn_cat: None,
                    rep_area: None,
                    iso3: None,
                }),
                geometry: Some(serde_json::json!({
                    "type": "Polygon",
                    "coordinates": [[[0.0, 0.0], [2.0, 0.0], [2.0, 2.0], [0.0, 2.0], [0.0, 0.0]]]
                })),
            },
            ArcGisFeature {
                properties: Some(ArcGisAttributes {
                    loc_nm: Some("Overlap Park".to_string()),
                    unit_nm: None,
                    mang_name: Some("NPS".to_string()),
                    des_tp: Some("NP".to_string()),
                    gis_acres: Some(400.0),
                    feat_class: Some("Fee".to_string()),
                    name: None,
                    area_ha: None,
                    desig_eng: None,
                    desig: None,
                    iucn_cat: None,
                    rep_area: None,
                    iso3: None,
                }),
                geometry: Some(serde_json::json!({
                    "type": "Polygon",
                    "coordinates": [[[1.0, 1.0], [3.0, 1.0], [3.0, 3.0], [1.0, 3.0], [1.0, 1.0]]]
                })),
            },
        ];

        let merged = merge_padus_features(features, "US-TEST").unwrap();
        // Acreage still summed across FeatClass parcels.
        assert_eq!(merged.properties.as_ref().unwrap().gis_acres, Some(800.0));
        // Geometry is now a proper union (single polygon), NOT a GeometryCollection.
        let geom = merged.geometry.as_ref().unwrap();
        assert_eq!(geom["type"], "MultiPolygon");
        assert_eq!(polygon_count(geom), 1);
    }

    // ── NPS trail response parsing ──────────────────────────────────────────

    #[test]
    fn test_parse_nps_trail_response() {
        use crate::models::historic_trail::NpsTrailResponse;

        let json = r#"{
            "features": [{
                "attributes": {
                    "Trail_Name": "Lewis and Clark National Historic Trail",
                    "Mang_Agency": "NPS",
                    "Designation": "NHT - Lewis and Clark",
                    "Length_MI": 4900.0,
                    "State": "ID,IL,IA,KS,MO,MT,NE,ND,OR,SD,WA"
                },
                "geometry": {
                    "type": "MultiLineString",
                    "coordinates": [[[-116.0, 46.0], [-115.0, 47.0]]]
                }
            }]
        }"#;

        let resp: NpsTrailResponse = serde_json::from_str(json).unwrap();
        let features = resp.features.unwrap();
        assert_eq!(features.len(), 1);

        let attrs = features[0].properties.as_ref().unwrap();
        assert_eq!(
            attrs.trail_name.as_deref(),
            Some("Lewis and Clark National Historic Trail")
        );
        assert_eq!(attrs.managing_agency.as_deref(), Some("NPS"));
        assert_eq!(attrs.designation.as_deref(), Some("NHT - Lewis and Clark"));
        assert_eq!(attrs.length_miles, Some(4900.0));
        assert!(features[0].geometry.is_some());
    }

    #[test]
    fn test_parse_nps_trail_alternative_field_names() {
        use crate::models::historic_trail::NpsTrailResponse;

        // Test lowercase/alternative field aliases
        let json = r#"{
            "features": [{
                "attributes": {
                    "name": "Oregon Trail",
                    "primarytrailmaintainer": "BLM",
                    "nationaltraildesignation": "NHT - Oregon",
                    "lengthmiles": 2170.0
                },
                "geometry": {
                    "type": "MultiLineString",
                    "coordinates": [[[-100.0, 40.0], [-120.0, 45.0]]]
                }
            }]
        }"#;

        let resp: NpsTrailResponse = serde_json::from_str(json).unwrap();
        let features = resp.features.unwrap();
        let attrs = features[0].properties.as_ref().unwrap();
        assert_eq!(attrs.trail_name.as_deref(), Some("Oregon Trail"));
        assert_eq!(attrs.managing_agency.as_deref(), Some("BLM"));
        assert_eq!(attrs.designation.as_deref(), Some("NHT - Oregon"));
        assert_eq!(attrs.length_miles, Some(2170.0));
    }
}
