//! Async spot-monitoring API — POTA / RBN / SOTA / WWFF live spot feeds.
//!
//! `SpotsApi` wraps the `cw_net` spot clients (`PotaClient` / `RbnClient` /
//! `SotaClient` / `WwffClient`) and returns the same `Ffi*Spot` records the
//! standalone `decode_*` functions produce, so each platform renders spots
//! identically. Methods are exported with `async_runtime = "tokio"` (like
//! `ClubsApi`); spots are presentation-only, so no store lock is involved.

use cw_net::{HttpClient, PotaClient, RbnClient, SotaClient, WwffClient};

use crate::pota::FfiPotaSpot;
use crate::rbn::FfiRbnSpot;
use crate::sota::FfiSotaSpot;
use crate::wwff::FfiWwffSpot;
use crate::CwError;

/// Recent-spot fetch caps, mirroring the iOS spot-monitor defaults.
const RBN_LIMIT: u32 = 100;
const SOTA_COUNT: u32 = 50;

/// Async spot API. Holds one client per source; POTA / SOTA / WWFF use their own
/// public endpoints, RBN proxies through the activities server.
#[derive(uniffi::Object)]
pub struct SpotsApi {
    pota: PotaClient,
    rbn: RbnClient,
    sota: SotaClient,
    wwff: WwffClient,
}

#[uniffi::export]
impl SpotsApi {
    /// Build a spots API. `activities_base_url` (e.g.
    /// `https://activities.carrierwave.app`) backs the RBN proxy; the other
    /// sources use their own public endpoints.
    #[uniffi::constructor]
    pub fn new(activities_base_url: String) -> Result<Self, CwError> {
        let http = HttpClient::new()?;
        Ok(SpotsApi {
            pota: PotaClient::new(http.clone()),
            rbn: RbnClient::new(http.clone(), activities_base_url),
            sota: SotaClient::new(http.clone()),
            wwff: WwffClient::new(http),
        })
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl SpotsApi {
    /// Recent POTA activator spots.
    pub async fn fetch_pota(&self) -> Result<Vec<FfiPotaSpot>, CwError> {
        Ok(self.pota.fetch_spots().await?.into_iter().map(Into::into).collect())
    }

    /// Recent RBN spots (through the activities-server proxy).
    pub async fn fetch_rbn(&self) -> Result<Vec<FfiRbnSpot>, CwError> {
        Ok(self.rbn.fetch_spots(RBN_LIMIT).await?.into_iter().map(Into::into).collect())
    }

    /// Recent SOTA spots (all associations).
    pub async fn fetch_sota(&self) -> Result<Vec<FfiSotaSpot>, CwError> {
        Ok(self.sota.fetch_spots(SOTA_COUNT, None).await?.into_iter().map(Into::into).collect())
    }

    /// Recent WWFF spots (Spotline HTML scrape).
    pub async fn fetch_wwff(&self) -> Result<Vec<FfiWwffSpot>, CwError> {
        Ok(self.wwff.fetch_spots().await?.into_iter().map(Into::into).collect())
    }
}
