//! Carrier Wave spot/API models, parsers, and HTTP transports.
//!
//! Phase 3 of the Rust-core migration. The portable, testable parsing layer
//! for each service lives in its own module (`pota`, `sota`, `wwff`,
//! `pskreporter`, `donki`, `hamqsl`, `lofi`) and is fully covered by unit
//! tests. The async HTTP transport that hits each service lives in
//! [`clients`] on top of a shared [`http::HttpClient`] (`reqwest` + `tokio`).
//!
//! The Swift app keeps owning credentials (keychain), retry/backoff above
//! the per-service rate limits, and any UI integration; this crate is
//! exclusively the wire/parse/cache layer the FFI will swap in for the
//! current Swift `actor`s.

pub mod amsat;
pub mod amt;
pub mod auth;
pub mod boundaries;
pub mod clients;
pub mod clubs;
pub mod cluster;
pub mod contests;
pub mod donki;
pub mod dxheat;
pub mod dxsummit;
pub mod dxwatch;
pub mod enrichment;
pub mod friends;
pub mod hamdb;
pub mod hamqsl;
pub mod http;
pub mod kiwisdr;
pub mod lofi;
pub mod pota;
pub mod pskreporter;
pub mod qrz;
pub mod rbn;
pub mod reference_data;
pub mod satnogs;
pub mod sota;
pub mod unified;
pub mod wsjtx;
pub mod wwff;

pub use amsat::{
    AmsatActivityBucketRow, AmsatActivityResponse, AmsatActivitySatelliteRow, AmsatReportRow,
    AmsatReportSubmission, AmsatReportsResponse, AmsatStatusClient, AmsatStatusResponse,
    AmsatStatusRow, AmsatSubmitClient, AmsatSubmitError, AmsatSubmitReceipt, AMSAT_ATTRIBUTION,
    AMSAT_REPORT_VALUES, AMSAT_STATUS_API_BASE,
};
pub use amt::{
    amt_pkce_challenge, generate_amt_verifier, AmtAccount, AmtActivity, AmtCharacterStats,
    AmtClient, AmtError, AmtModeStats, AmtPollOutcome, AmtProfile, AmtStats, AmtStreak,
    AmtTokens, AmtTotals, AMT_BASE_URL, AMT_CLIENT_ID, AMT_SCOPES,
};
pub use auth::{
    generate_verifier, pkce_challenge, AuthClient, AuthError, PollOutcome, TokenPair,
};
pub use boundaries::{
    AdminBoundariesClient, AdminBoundaryFeature, AdminBoundaryKind, BoundingBox,
    ParkBoundariesClient, ParkBoundariesMeta, ParkBoundaryFull, ParkBoundaryGroup, TrailFeature,
    TrailsClient, TrailsMeta,
};
pub use clients::{
    DonkiClient, DxHeatClient, DxSummitClient, DxWatchClient, HamQslClient, LoFiClient,
    PotaClient, PskReporterClient, RbnClient, SotaClient, WwffClient,
};
pub use clubs::{
    ClubActivityItemWire, ClubActivityPaginationWire, ClubActivityResponseWire, ClubDetailWire,
    ClubMemberWire, ClubMembershipEntryWire, ClubWire, ClubsClient, Conditional,
    MemberOnlineStatusWire, MemberStatusWire, SpotInfoWire,
};
pub use cluster::{ClusterConnection, ClusterError, ClusterEvent};
pub use contests::{ContestEnvelopeWire, ContestSummaryWire, ContestsClient};
pub use donki::{DonkiCme, DonkiEvent, DonkiFlare, DonkiGeostorm, RadioImpactLevel};
pub use dxheat::DxHeatSpot;
pub use dxsummit::DxSummitSpot;
pub use dxwatch::{DxWatchCallInfo, DxWatchResponse, DxWatchSpot};
pub use friends::{
    FeedItemWire, FeedPaginationWire, FeedResponseWire, FriendRequestWire, FriendSuggestionWire,
    FriendWire, FriendsClient, InviteLinkWire, PendingRequestsWire, UserSearchResultWire,
};
pub use enrichment::{
    EnrichmentClient, EnrichmentDataset, EnrichmentEntry, EnrichmentMembership, EnrichmentSource,
};
pub use hamdb::{HamdbClient, HamdbLookup};
pub use hamqsl::{HamQslBandCondition, HamQslSolarData};
pub use http::{HttpClient, HttpError};
pub use kiwisdr::{
    connect_following_redirects, KiwiSdrConnection, KiwiSdrDirectoryClient, KiwiSdrError,
    KiwiSdrEvent, KiwiSdrStatusClient,
};
pub use lofi::{
    LoFiAccountInfo, LoFiAccountsResponse, LoFiOperation, LoFiOperationsResponse, LoFiQso,
    LoFiQsosResponse, LoFiRegistrationRequest, LoFiRegistrationResponse, LoFiSyncFlags,
};
pub use pota::{PotaSpot, PotaSpotPost};
pub use pskreporter::PskReporterSpot;
pub use qrz::{QrzClient, QrzError, QrzLookup};
pub use rbn::{RbnCallsignSpotsResponse, RbnSpot, RbnSpotsResponse};
pub use satnogs::{SatnogsClient, SatnogsSatellite, SatnogsTle, SatnogsTransmitter};
pub use sota::{SotaSpot, SotaSpotPost, SotaSpotPostError};
pub use reference_data::{
    fetch_reference_csv, EquipmentCatalogClient, EquipmentCatalogWire, EquipmentEntryWire,
    FccClient, FccMetadataWire, SotaZoneFeature, SotaZoneInput, SotaZonesClient,
    FCC_DATABASE_URL, FCC_METADATA_URL, POTA_PARKS_CSV_URL, SOTA_SUMMITS_CSV_URL,
    WWFF_DIRECTORY_CSV_URL,
};
pub use wsjtx::{
    decode as decode_wsjtx, Decode as WsjtxDecode, Heartbeat, LoggedAdif, QsoLogged,
    Status as WsjtxStatus, WsjtxError, WsjtxListener, WsjtxMessage, WSJTX_DEFAULT_PORT,
    WSJTX_MAGIC,
};
pub use wwff::{WwffAgendaItem, WwffSpot};
