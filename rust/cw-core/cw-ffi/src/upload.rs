//! Shared upload-routing helper used by the hunter-log and session APIs.
//!
//! Both `ActivityLogManager.markForUpload` and `LoggingSessionManager.markForUpload`
//! funnel each configured destination through `QSO.markNeedsUpload(to:)`. This is
//! that single rule, faithfully ported: a no-op for non-upload services
//! (`ServiceType.supportsUpload == false`, e.g. LoFi / ClubLog / LoTW); flip an
//! existing presence's `needs_upload` only when the QSO is not already present in
//! that service; otherwise create a fresh needs-upload presence.

use cw_domain::service_type::ServiceType;
use cw_store::{ServicePresence, ServicePresenceFilter, Store};
use uuid::Uuid;

use crate::CwError;

/// Faithful port of `QSO.markNeedsUpload(to:)`. Returns whether a presence row
/// was written (so the caller can decide whether to fire a store notification).
pub(crate) fn mark_needs_upload(
    store: &Store,
    qso_id: &str,
    service: ServiceType,
) -> Result<bool, CwError> {
    if !service.supports_upload() {
        return Ok(false);
    }
    let filter = ServicePresenceFilter {
        qso_id: Some(qso_id.to_string()),
        service_type_raw_value: Some(service.raw_value().to_string()),
        ..Default::default()
    };
    if let Some(mut existing) = store.fetch_service_presences(&filter, 1, 0)?.into_iter().next() {
        if !existing.is_present {
            existing.needs_upload = true;
            store.upsert_service_presence(&existing)?;
            return Ok(true);
        }
        return Ok(false);
    }
    let presence = ServicePresence {
        id: Uuid::new_v4().to_string(),
        service_type_raw_value: service.raw_value().to_string(),
        is_present: false,
        needs_upload: true,
        upload_rejected: false,
        rejected_at_build: None,
        is_submitted: false,
        last_confirmed_at: None,
        park_reference: None,
        cloud_dirty_flag: false,
        qso_id: Some(qso_id.to_string()),
    };
    store.upsert_service_presence(&presence)?;
    Ok(true)
}
