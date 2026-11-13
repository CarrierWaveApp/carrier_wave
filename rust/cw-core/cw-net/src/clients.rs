//! Service clients. Each one wraps `HttpClient` with the per-endpoint
//! URL building, rate-limit, and cache behavior the Swift `actor`s had.
//!
//! The cw-net design intentionally splits "models + parsers" (in
//! [`crate::sota`] / [`crate::wwff`] / …) from the HTTP transport here.
//! Tests live next to their model module; this file is the live-network
//! glue, which is exercised once `cw-ffi` calls into it from the app.

use std::sync::Arc;
use std::time::{Duration, Instant};

use chrono::{DateTime, Utc};
use tokio::sync::Mutex;
use url::form_urlencoded;

use crate::donki::{format_query_date, DonkiCme, DonkiEvent, DonkiFlare, DonkiGeostorm};
use crate::dxheat::DxHeatSpot;
use crate::dxsummit::DxSummitSpot;
use crate::dxwatch::DxWatchResponse;
use crate::hamqsl::{self, HamQslSolarData};
use crate::http::{HttpClient, HttpError};
use crate::lofi::{
    LoFiAccountsResponse, LoFiLinkDeviceRequest, LoFiOperationsResponse, LoFiQsosResponse,
    LoFiRegistrationRequest, LoFiRegistrationResponse,
};
use crate::pota::{PotaSpot, PotaSpotPost};
use crate::pskreporter::{self, PskReporterSpot};
use crate::rbn::RbnSpot;
use crate::sota::{SotaSpot, SotaSpotPost};
use crate::wwff::{self, WwffAgendaItem, WwffSpot};

// ---- RBN ------------------------------------------------------------------

/// Reverse Beacon Network spot client. RBN exposes no public API of its own;
/// spots come through the activities-server proxy at `{base}/v1/rbn/spots`, the
/// same endpoint the iOS `RBNClient` uses. The proxy needs no auth. Responses
/// are decoded by [`RbnSpot::parse_response`] (callsign-echo / total-count /
/// bare-array shapes).
#[derive(Debug, Clone)]
pub struct RbnClient {
    http: HttpClient,
    /// Activities-server base, e.g. `https://activities.carrierwave.app`.
    base_url: String,
}

impl RbnClient {
    pub fn new(http: HttpClient, activities_base_url: impl Into<String>) -> Self {
        Self {
            http,
            base_url: activities_base_url.into(),
        }
    }

    /// Fetch the most recent RBN spots (newest first), capped at `limit`.
    pub async fn fetch_spots(&self, limit: u32) -> Result<Vec<RbnSpot>, HttpError> {
        let query = QueryBuilder::new().pair("limit", &limit.to_string()).build();
        let url = format!(
            "{}/v1/rbn/spots?{}",
            self.base_url.trim_end_matches('/'),
            query
        );
        let json = self.http.get_text(&url, "application/json").await?;
        RbnSpot::parse_response(&json)
            .ok_or_else(|| HttpError::Parse("unrecognized RBN response shape".into()))
    }

    /// Fetch spots for a specific callsign within the last `hours` hours.
    /// Mirrors the iOS `RBNClient.spots(for:hours:limit:)` query
    /// (`call` + ISO-8601 `since` + `limit`).
    pub async fn fetch_spots_for_callsign(
        &self,
        callsign: &str,
        hours: u32,
        limit: u32,
    ) -> Result<Vec<RbnSpot>, HttpError> {
        let since = Utc::now() - chrono::Duration::hours(i64::from(hours));
        let query = QueryBuilder::new()
            .pair("call", &callsign.to_uppercase())
            .pair("since", &since.format("%Y-%m-%dT%H:%M:%SZ").to_string())
            .pair("limit", &limit.to_string())
            .build();
        let url = format!(
            "{}/v1/rbn/spots?{}",
            self.base_url.trim_end_matches('/'),
            query
        );
        let json = self.http.get_text(&url, "application/json").await?;
        RbnSpot::parse_response(&json)
            .ok_or_else(|| HttpError::Parse("unrecognized RBN response shape".into()))
    }
}

// ---- POTA -----------------------------------------------------------------

/// POTA spot client.
#[derive(Debug, Clone)]
pub struct PotaClient {
    http: HttpClient,
    base_url: String,
}

impl PotaClient {
    pub const DEFAULT_BASE_URL: &'static str = "https://api.pota.app";

    pub fn new(http: HttpClient) -> Self {
        Self {
            http,
            base_url: Self::DEFAULT_BASE_URL.to_string(),
        }
    }

    pub fn with_base_url(mut self, base: impl Into<String>) -> Self {
        self.base_url = base.into();
        self
    }

    /// Fetch the recent POTA spots feed.
    pub async fn fetch_spots(&self) -> Result<Vec<PotaSpot>, HttpError> {
        let url = format!("{}/spot/activator", self.base_url);
        self.http.get_json(&url).await
    }

    /// Post a respot (or self-spot) to the POTA spot endpoint. Mirrors iOS
    /// `POTAClient.postRespot`; the endpoint accepts unauthenticated posts.
    pub async fn post_spot(&self, body: &PotaSpotPost) -> Result<(), HttpError> {
        let url = format!("{}/spot", self.base_url);
        self.http.post_json_unit(&url, body).await
    }
}

// ---- SOTA -----------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct SotaClient {
    http: HttpClient,
    base_url: String,
}

impl SotaClient {
    pub const DEFAULT_BASE_URL: &'static str = "https://api2.sota.org.uk/api";

    pub fn new(http: HttpClient) -> Self {
        Self {
            http,
            base_url: Self::DEFAULT_BASE_URL.to_string(),
        }
    }

    pub fn with_base_url(mut self, base: impl Into<String>) -> Self {
        self.base_url = base.into();
        self
    }

    /// Fetch the most recent SOTA spots. `association` filters by ASSOC code
    /// (e.g. "W4C"); pass `None` for all associations.
    pub async fn fetch_spots(
        &self,
        count: u32,
        association: Option<&str>,
    ) -> Result<Vec<SotaSpot>, HttpError> {
        let filter = association.unwrap_or("all");
        let url = format!("{}/spots/{}/{}", self.base_url, count, filter);
        // Decode element-wise: the API injects a deprecation-notice entry with
        // null fields, and one malformed spot must not fail the whole feed.
        let values: Vec<serde_json::Value> = self.http.get_json(&url).await?;
        Ok(SotaSpot::from_values(values))
    }

    /// Post a self-spot (or respot) to SOTAwatch.
    pub async fn post_spot(&self, body: &SotaSpotPost) -> Result<(), HttpError> {
        let url = format!("{}/spots", self.base_url);
        self.http.post_json_unit(&url, body).await
    }
}

// ---- WWFF -----------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct WwffClient {
    http: HttpClient,
    base_url: String,
}

impl WwffClient {
    pub const DEFAULT_BASE_URL: &'static str = "https://spots.wwff.co";

    pub fn new(http: HttpClient) -> Self {
        Self {
            http,
            base_url: Self::DEFAULT_BASE_URL.to_string(),
        }
    }

    pub fn with_base_url(mut self, base: impl Into<String>) -> Self {
        self.base_url = base.into();
        self
    }

    /// Fetch the recent spot table (HTML scrape).
    pub async fn fetch_spots(&self) -> Result<Vec<WwffSpot>, HttpError> {
        let html = self
            .http
            .get_text(&format!("{}/spots", self.base_url), "text/html")
            .await?;
        Ok(wwff::parse_spots_html(&html))
    }

    /// Fetch the agenda (scheduled activations) HTML scrape.
    pub async fn fetch_agenda(&self) -> Result<Vec<WwffAgendaItem>, HttpError> {
        let html = self
            .http
            .get_text(&format!("{}/agenda", self.base_url), "text/html")
            .await?;
        Ok(wwff::parse_agenda_html(&html))
    }
}

// ---- DX Summit ------------------------------------------------------------

/// DX Summit REST client (dxsummit.fi). Port of the transport half of
/// Sweep's `DXSummitClient.swift`.
#[derive(Debug, Clone)]
pub struct DxSummitClient {
    http: HttpClient,
    base_url: String,
}

impl DxSummitClient {
    pub const DEFAULT_BASE_URL: &'static str = "http://www.dxsummit.fi/api/v1/spots";

    pub fn new(http: HttpClient) -> Self {
        Self {
            http,
            base_url: Self::DEFAULT_BASE_URL.to_string(),
        }
    }

    pub fn with_base_url(mut self, base: impl Into<String>) -> Self {
        self.base_url = base.into();
        self
    }

    /// Fetch recent spots, capped at `limit` (Sweep default 50).
    pub async fn fetch_spots(&self, limit: u32) -> Result<Vec<DxSummitSpot>, HttpError> {
        let query = QueryBuilder::new().pair("limit", &limit.to_string()).build();
        let json = self
            .http
            .get_text(&format!("{}?{}", self.base_url, query), "application/json")
            .await?;
        DxSummitSpot::parse_response(&json)
            .ok_or_else(|| HttpError::Parse("unrecognized DX Summit response".into()))
    }
}

// ---- DXHeat ----------------------------------------------------------------

/// DXHeat spot client (dxheat.com). Port of the transport half of Sweep's
/// `DXHeatClient.swift`.
#[derive(Debug, Clone)]
pub struct DxHeatClient {
    http: HttpClient,
    base_url: String,
}

impl DxHeatClient {
    pub const DEFAULT_BASE_URL: &'static str = "https://dxheat.com/source/spots/";

    pub fn new(http: HttpClient) -> Self {
        Self {
            http,
            base_url: Self::DEFAULT_BASE_URL.to_string(),
        }
    }

    pub fn with_base_url(mut self, base: impl Into<String>) -> Self {
        self.base_url = base.into();
        self
    }

    /// Fetch recent spots, capped at `limit` (Sweep default 50).
    pub async fn fetch_spots(&self, limit: u32) -> Result<Vec<DxHeatSpot>, HttpError> {
        let query = QueryBuilder::new().pair("limit", &limit.to_string()).build();
        let json = self
            .http
            .get_text(&format!("{}?{}", self.base_url, query), "application/json")
            .await?;
        DxHeatSpot::parse_response(&json)
            .ok_or_else(|| HttpError::Parse("unrecognized DXHeat response".into()))
    }
}

// ---- DXWatch ---------------------------------------------------------------

/// DXWatch compact-JSON client (dxwatch.com). Incremental polling: the
/// first call fetches an initial batch (`d=1`), subsequent calls fetch only
/// spots newer than the highest id seen — port of Sweep's
/// `DXWatchClient.swift` including its `lastSpotId` actor state.
#[derive(Debug, Clone)]
pub struct DxWatchClient {
    http: HttpClient,
    base_url: String,
    last_spot_id: Arc<Mutex<i64>>,
}

impl DxWatchClient {
    pub const DEFAULT_BASE_URL: &'static str = "https://dxwatch.com/dxsd1/s.php";

    pub fn new(http: HttpClient) -> Self {
        Self {
            http,
            base_url: Self::DEFAULT_BASE_URL.to_string(),
            last_spot_id: Arc::new(Mutex::new(0)),
        }
    }

    pub fn with_base_url(mut self, base: impl Into<String>) -> Self {
        self.base_url = base.into();
        self
    }

    /// Fetch spots newer than the last seen id, capped at `rows` (Sweep
    /// default 50). Advances the incremental cursor on success.
    pub async fn fetch_spots(&self, rows: u32) -> Result<DxWatchResponse, HttpError> {
        let mut last_id = self.last_spot_id.lock().await;
        let mut builder = QueryBuilder::new()
            .pair("s", &last_id.to_string())
            .pair("r", &rows.to_string());
        if *last_id == 0 {
            builder = builder.pair("d", "1");
        }
        let url = format!("{}?{}", self.base_url, builder.build());
        let json = self.http.get_text(&url, "application/json").await?;
        let response = DxWatchResponse::parse_response(&json)
            .ok_or_else(|| HttpError::Parse("unrecognized DXWatch response".into()))?;

        if let Some(max_id) =
            response.spots.iter().filter_map(|spot| spot.id.parse::<i64>().ok()).max()
        {
            *last_id = max_id;
        }
        Ok(response)
    }
}

// ---- PSK Reporter ---------------------------------------------------------

/// PSK Reporter client. Enforces the 5-minute per-instance request floor the
/// Swift actor enforces.
#[derive(Debug, Clone)]
pub struct PskReporterClient {
    http: HttpClient,
    base_url: String,
    app_contact: String,
    rate_limit: Arc<Mutex<RateLimiter>>,
}

impl PskReporterClient {
    pub const DEFAULT_BASE_URL: &'static str = "https://retrieve.pskreporter.info/query";
    pub const MIN_REQUEST_INTERVAL: Duration = Duration::from_secs(300);

    pub fn new(http: HttpClient, app_contact: impl Into<String>) -> Self {
        Self {
            http,
            base_url: Self::DEFAULT_BASE_URL.to_string(),
            app_contact: app_contact.into(),
            rate_limit: Arc::new(Mutex::new(RateLimiter::new(Self::MIN_REQUEST_INTERVAL))),
        }
    }

    pub fn with_base_url(mut self, base: impl Into<String>) -> Self {
        self.base_url = base.into();
        self
    }

    /// Reception reports for a given sender callsign.
    pub async fn fetch_sender_spots(
        &self,
        callsign: &str,
        seconds: i64,
    ) -> Result<Vec<PskReporterSpot>, HttpError> {
        let query = QueryBuilder::new()
            .pair("rronly", "1")
            .pair("noactive", "1")
            .pair("appcontact", &self.app_contact)
            .pair("senderCallsign", &callsign.to_uppercase())
            .pair("flowStartSeconds", &seconds.to_string())
            .build();
        self.fetch(&query).await
    }

    /// Reception reports filtered by mode + frequency window.
    pub async fn fetch_spots(
        &self,
        mode: &str,
        min_freq_hz: i64,
        max_freq_hz: i64,
        seconds: i64,
        limit: u32,
    ) -> Result<Vec<PskReporterSpot>, HttpError> {
        let query = QueryBuilder::new()
            .pair("rronly", "1")
            .pair("noactive", "1")
            .pair("appcontact", &self.app_contact)
            .pair("mode", mode)
            .pair("frange", &format!("{}-{}", min_freq_hz, max_freq_hz))
            .pair("flowStartSeconds", &seconds.to_string())
            .pair("rptlimit", &limit.to_string())
            .build();
        self.fetch(&query).await
    }

    async fn fetch(&self, query: &str) -> Result<Vec<PskReporterSpot>, HttpError> {
        {
            let mut limiter = self.rate_limit.lock().await;
            if !limiter.allow() {
                return Err(HttpError::RateLimited);
            }
        }
        let url = format!("{}?{}", self.base_url, query);
        let xml = self.http.get_text(&url, "application/xml").await?;
        pskreporter::parse(&xml).map_err(|e| HttpError::Parse(e.to_string()))
    }
}

// ---- DONKI ----------------------------------------------------------------

/// DONKI client. Caches the unified `active_events` list for 30 minutes to
/// match the Swift actor.
#[derive(Debug, Clone)]
pub struct DonkiClient {
    http: HttpClient,
    base_url: String,
    cache: Arc<Mutex<TtlCache<Vec<DonkiEvent>>>>,
}

impl DonkiClient {
    pub const DEFAULT_BASE_URL: &'static str = "https://kauai.ccmc.gsfc.nasa.gov/DONKI/WS/get/";
    pub const CACHE_INTERVAL: Duration = Duration::from_secs(1_800);

    pub fn new(http: HttpClient) -> Self {
        Self {
            http,
            base_url: Self::DEFAULT_BASE_URL.to_string(),
            cache: Arc::new(Mutex::new(TtlCache::new(Self::CACHE_INTERVAL))),
        }
    }

    pub fn with_base_url(mut self, base: impl Into<String>) -> Self {
        self.base_url = base.into();
        self
    }

    pub async fn fetch_geostorms(
        &self,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> Result<Vec<DonkiGeostorm>, HttpError> {
        self.fetch_endpoint("GST", start, end).await
    }

    pub async fn fetch_flares(
        &self,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> Result<Vec<DonkiFlare>, HttpError> {
        self.fetch_endpoint("FLR", start, end).await
    }

    pub async fn fetch_cmes(
        &self,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> Result<Vec<DonkiCme>, HttpError> {
        self.fetch_endpoint("CME", start, end).await
    }

    /// Fetch geomagnetic storms, flares, and CMEs from the lookback window,
    /// drop expired events, and sort newest first. Cached for 30 minutes.
    /// Individual endpoint failures are swallowed (matches Swift).
    pub async fn fetch_active_events(&self, lookback_days: i64) -> Vec<DonkiEvent> {
        let now = Utc::now();
        {
            let cache = self.cache.lock().await;
            if let Some(events) = cache.get(now) {
                return events.clone();
            }
        }

        let start = now - chrono::Duration::days(lookback_days);
        let mut events: Vec<DonkiEvent> = Vec::new();

        if let Ok(storms) = self.fetch_geostorms(start, now).await {
            events.extend(storms.into_iter().map(DonkiEvent::Geostorm));
        }
        if let Ok(flares) = self.fetch_flares(start, now).await {
            events.extend(flares.into_iter().map(DonkiEvent::Flare));
        }
        if let Ok(cmes) = self.fetch_cmes(start, now).await {
            events.extend(cmes.into_iter().map(DonkiEvent::Cme));
        }

        events.retain(|e| e.is_active(now));
        events.sort_by(|a, b| {
            b.start_date()
                .unwrap_or(chrono::DateTime::<Utc>::MIN_UTC)
                .cmp(&a.start_date().unwrap_or(chrono::DateTime::<Utc>::MIN_UTC))
        });

        let mut cache = self.cache.lock().await;
        cache.set(events.clone(), now);
        events
    }

    async fn fetch_endpoint<T: serde::de::DeserializeOwned>(
        &self,
        endpoint: &str,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> Result<Vec<T>, HttpError> {
        let url = format!(
            "{}{}?startDate={}&endDate={}",
            self.base_url,
            endpoint,
            format_query_date(start),
            format_query_date(end)
        );
        self.http.get_json(&url).await
    }
}

// ---- HamQSL ---------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct HamQslClient {
    http: HttpClient,
    url: String,
    cache: Arc<Mutex<TtlCache<HamQslSolarData>>>,
}

impl HamQslClient {
    pub const DEFAULT_URL: &'static str = "https://www.hamqsl.com/solarxml.php";
    pub const CACHE_INTERVAL: Duration = Duration::from_secs(900);

    pub fn new(http: HttpClient) -> Self {
        Self {
            http,
            url: Self::DEFAULT_URL.to_string(),
            cache: Arc::new(Mutex::new(TtlCache::new(Self::CACHE_INTERVAL))),
        }
    }

    pub fn with_url(mut self, url: impl Into<String>) -> Self {
        self.url = url.into();
        self
    }

    pub async fn fetch_solar_data(&self) -> Result<HamQslSolarData, HttpError> {
        let now = Utc::now();
        {
            let cache = self.cache.lock().await;
            if let Some(cached) = cache.get(now) {
                return Ok(cached.clone());
            }
        }
        let xml = self.http.get_text(&self.url, "application/xml").await?;
        let data = hamqsl::parse(&xml, now).map_err(|e| HttpError::Parse(e.to_string()))?;
        let mut cache = self.cache.lock().await;
        cache.set(data.clone(), now);
        Ok(data)
    }
}

// ---- LoFi -----------------------------------------------------------------

/// LoFi transport surface. Credentials live in the Swift keychain — the
/// caller supplies the bearer token explicitly. This matches the Phase 5 plan
/// for OAuth2; for today the token is whatever LoFi handed back at
/// registration.
#[derive(Debug, Clone)]
pub struct LoFiClient {
    http: HttpClient,
    base_url: String,
}

impl LoFiClient {
    pub const DEFAULT_BASE_URL: &'static str = "https://lofi.ham2k.net";

    pub fn new(http: HttpClient) -> Self {
        Self {
            http,
            base_url: Self::DEFAULT_BASE_URL.to_string(),
        }
    }

    pub fn with_base_url(mut self, base: impl Into<String>) -> Self {
        self.base_url = base.into();
        self
    }

    pub async fn register(
        &self,
        request: &LoFiRegistrationRequest,
    ) -> Result<LoFiRegistrationResponse, HttpError> {
        let url = format!("{}/v1/client", self.base_url);
        self.http.post_json(&url, request, None).await
    }

    pub async fn link_device(
        &self,
        bearer: &str,
        email: &str,
    ) -> Result<(), HttpError> {
        let url = format!("{}/v1/client/link", self.base_url);
        let body = LoFiLinkDeviceRequest {
            email: email.to_string(),
        };
        // Empty-response endpoint; reuse `post_json` with `serde_json::Value`.
        let _value: serde_json::Value = self.http.post_json(&url, &body, Some(bearer)).await?;
        Ok(())
    }

    pub async fn fetch_accounts(&self, bearer: &str) -> Result<LoFiAccountsResponse, HttpError> {
        let url = format!("{}/v1/accounts", self.base_url);
        self.get_with_bearer(&url, bearer).await
    }

    pub async fn fetch_operations(
        &self,
        bearer: &str,
        since_millis: Option<i64>,
        limit: Option<u32>,
    ) -> Result<LoFiOperationsResponse, HttpError> {
        let mut query = QueryBuilder::new();
        if let Some(since) = since_millis {
            query = query.pair("synced_since_millis", &since.to_string());
        }
        if let Some(limit) = limit {
            query = query.pair("limit", &limit.to_string());
        }
        let url = format!("{}/v1/operations?{}", self.base_url, query.build());
        self.get_with_bearer(&url, bearer).await
    }

    pub async fn fetch_qsos(
        &self,
        bearer: &str,
        operation_uuid: &str,
        since_millis: Option<i64>,
        limit: Option<u32>,
    ) -> Result<LoFiQsosResponse, HttpError> {
        let mut query = QueryBuilder::new();
        if let Some(since) = since_millis {
            query = query.pair("synced_since_millis", &since.to_string());
        }
        if let Some(limit) = limit {
            query = query.pair("limit", &limit.to_string());
        }
        let url = format!(
            "{}/v1/operations/{}/qsos?{}",
            self.base_url,
            operation_uuid,
            query.build()
        );
        self.get_with_bearer(&url, bearer).await
    }

    async fn get_with_bearer<T: serde::de::DeserializeOwned>(
        &self,
        url: &str,
        bearer: &str,
    ) -> Result<T, HttpError> {
        let request = self.http.inner().get(url).bearer_auth(bearer);
        let bytes = self.http.send_bytes(request).await?;
        Ok(serde_json::from_slice(&bytes)?)
    }
}

// ---- Rate limiter / cache primitives --------------------------------------

#[derive(Debug)]
pub(crate) struct RateLimiter {
    min_interval: Duration,
    last_request: Option<Instant>,
}

impl RateLimiter {
    pub fn new(min_interval: Duration) -> Self {
        Self {
            min_interval,
            last_request: None,
        }
    }

    /// Returns `true` if a new request is allowed; if so, records `now` as
    /// the last-request time.
    pub fn allow(&mut self) -> bool {
        let now = Instant::now();
        if let Some(last) = self.last_request {
            if now.duration_since(last) < self.min_interval {
                return false;
            }
        }
        self.last_request = Some(now);
        true
    }
}

#[derive(Debug)]
pub(crate) struct TtlCache<T: Clone> {
    ttl: chrono::Duration,
    stored: Option<(DateTime<Utc>, T)>,
}

impl<T: Clone> TtlCache<T> {
    pub fn new(ttl: Duration) -> Self {
        Self {
            ttl: chrono::Duration::from_std(ttl).unwrap_or(chrono::Duration::zero()),
            stored: None,
        }
    }

    pub fn get(&self, now: DateTime<Utc>) -> Option<&T> {
        let (stamp, value) = self.stored.as_ref()?;
        if now.signed_duration_since(*stamp) < self.ttl {
            Some(value)
        } else {
            None
        }
    }

    pub fn set(&mut self, value: T, now: DateTime<Utc>) {
        self.stored = Some((now, value));
    }
}

// ---- Query-string helper --------------------------------------------------

struct QueryBuilder {
    pairs: Vec<(String, String)>,
}

impl QueryBuilder {
    fn new() -> Self {
        Self { pairs: Vec::new() }
    }

    fn pair(mut self, key: &str, value: &str) -> Self {
        self.pairs.push((key.to_string(), value.to_string()));
        self
    }

    fn build(self) -> String {
        let mut serializer = form_urlencoded::Serializer::new(String::new());
        for (k, v) in &self.pairs {
            serializer.append_pair(k, v);
        }
        serializer.finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread::sleep;

    #[test]
    fn query_builder_percent_encodes_values() {
        let q = QueryBuilder::new()
            .pair("appcontact", "carrierwave-app@example.com")
            .pair("frange", "14000000-14100000")
            .build();
        assert!(q.contains("carrierwave-app%40example.com"));
        assert!(q.contains("frange=14000000-14100000"));
    }

    #[test]
    fn rate_limiter_blocks_inside_window_and_releases_after() {
        let mut limiter = RateLimiter::new(Duration::from_millis(50));
        assert!(limiter.allow());
        assert!(!limiter.allow()); // immediately again — blocked
        sleep(Duration::from_millis(60));
        assert!(limiter.allow());
    }

    #[test]
    fn ttl_cache_serves_and_expires() {
        let mut cache: TtlCache<i32> = TtlCache::new(Duration::from_secs(60));
        let t0 = Utc.with_ymd_and_hms(2026, 6, 13, 12, 0, 0).unwrap();
        cache.set(42, t0);
        assert_eq!(cache.get(t0), Some(&42));
        let t_inside = t0 + chrono::Duration::seconds(30);
        assert_eq!(cache.get(t_inside), Some(&42));
        let t_outside = t0 + chrono::Duration::seconds(61);
        assert_eq!(cache.get(t_outside), None);
    }

    // bring TimeZone in scope only inside tests
    use chrono::TimeZone;

    // Live-endpoint smoke tests — run explicitly with
    // `cargo test -p cw-net -- --ignored dx_live`.
    #[tokio::test]
    #[ignore = "hits the live dxsummit.fi API"]
    async fn dx_live_dxsummit_fetches() {
        let client = DxSummitClient::new(HttpClient::new().unwrap());
        let spots = client.fetch_spots(5).await.unwrap();
        assert!(!spots.is_empty());
        assert!(spots[0].timestamp_epoch_seconds().is_some());
    }

    #[tokio::test]
    #[ignore = "hits the live dxheat.com API"]
    async fn dx_live_dxheat_fetches() {
        let client = DxHeatClient::new(HttpClient::new().unwrap());
        let spots = client.fetch_spots(5).await.unwrap();
        assert!(!spots.is_empty());
        assert!(spots[0].frequency_khz().is_some());
    }

    #[tokio::test]
    #[ignore = "hits the live dxwatch.com API"]
    async fn dx_live_dxwatch_fetches_incrementally() {
        let http = HttpClient::new().unwrap();
        let body = http
            .get_text("https://dxwatch.com/dxsd1/s.php?s=0&r=5&d=1", "application/json")
            .await
            .unwrap();
        eprintln!("RAW BODY HEAD: {:?}", &body[..body.len().min(400)]);
        let client = DxWatchClient::new(http);
        let first = client.fetch_spots(5).await.unwrap();
        assert!(!first.spots.is_empty());
        // Second call uses the advanced cursor; may legitimately be empty.
        let _ = client.fetch_spots(5).await.unwrap();
    }
}
