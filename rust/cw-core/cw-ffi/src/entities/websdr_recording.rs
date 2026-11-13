//! FFI surface for `WebSDRRecording` (mirrors `cw-store`'s `WebSDRRecording`).

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};
use cw_store::{WebSDRRecording, WebSDRRecordingFilter};

// ---------- DTO ----------

#[derive(uniffi::Record)]
pub struct FfiWebSDRRecording {
    pub id: String,
    pub logging_session_id: String,
    pub kiwisdr_host: String,
    pub kiwisdr_name: String,
    pub started_at: i64,
    pub ended_at: Option<i64>,
    pub frequency_k_hz: f64,
    pub mode: String,
    pub relative_file_path: String,
    pub file_size_bytes: i64,
    pub duration_seconds: f64,
    pub is_complete: bool,
    pub spot_callsign: Option<String>,
    pub spot_park_ref: Option<String>,
    pub spot_park_name: Option<String>,
    pub spot_summit_code: Option<String>,
    pub spot_band: Option<String>,
    pub is_tune_in_recording: bool,
    pub clip_bookmarks_data: Option<Vec<u8>>,
    pub parameter_changes_data: Option<Vec<u8>>,
}

// ---------- Conversions ----------

impl From<WebSDRRecording> for FfiWebSDRRecording {
    fn from(x: WebSDRRecording) -> Self {
        FfiWebSDRRecording {
            id: x.id,
            logging_session_id: x.logging_session_id,
            kiwisdr_host: x.kiwisdr_host,
            kiwisdr_name: x.kiwisdr_name,
            started_at: x.started_at,
            ended_at: x.ended_at,
            frequency_k_hz: x.frequency_k_hz,
            mode: x.mode,
            relative_file_path: x.relative_file_path,
            file_size_bytes: x.file_size_bytes,
            duration_seconds: x.duration_seconds,
            is_complete: x.is_complete,
            spot_callsign: x.spot_callsign,
            spot_park_ref: x.spot_park_ref,
            spot_park_name: x.spot_park_name,
            spot_summit_code: x.spot_summit_code,
            spot_band: x.spot_band,
            is_tune_in_recording: x.is_tune_in_recording,
            clip_bookmarks_data: x.clip_bookmarks_data,
            parameter_changes_data: x.parameter_changes_data,
        }
    }
}

impl From<FfiWebSDRRecording> for WebSDRRecording {
    fn from(x: FfiWebSDRRecording) -> Self {
        WebSDRRecording {
            id: x.id,
            logging_session_id: x.logging_session_id,
            kiwisdr_host: x.kiwisdr_host,
            kiwisdr_name: x.kiwisdr_name,
            started_at: x.started_at,
            ended_at: x.ended_at,
            frequency_k_hz: x.frequency_k_hz,
            mode: x.mode,
            relative_file_path: x.relative_file_path,
            file_size_bytes: x.file_size_bytes,
            duration_seconds: x.duration_seconds,
            is_complete: x.is_complete,
            spot_callsign: x.spot_callsign,
            spot_park_ref: x.spot_park_ref,
            spot_park_name: x.spot_park_name,
            spot_summit_code: x.spot_summit_code,
            spot_band: x.spot_band,
            is_tune_in_recording: x.is_tune_in_recording,
            clip_bookmarks_data: x.clip_bookmarks_data,
            parameter_changes_data: x.parameter_changes_data,
        }
    }
}

// ---------- Filter DTO ----------

#[derive(uniffi::Record, Default)]
pub struct FfiWebSDRRecordingFilter {
    pub logging_session_id: Option<String>,
    pub is_complete: Option<bool>,
    pub is_tune_in_recording: Option<bool>,
}

impl From<FfiWebSDRRecordingFilter> for WebSDRRecordingFilter {
    fn from(f: FfiWebSDRRecordingFilter) -> Self {
        WebSDRRecordingFilter {
            logging_session_id: f.logging_session_id,
            is_complete: f.is_complete,
            is_tune_in_recording: f.is_tune_in_recording,
        }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    pub fn upsert_websdr_recording(&self, item: FfiWebSDRRecording) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.upsert_websdr_recording(&item.into())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::WebSdrRecording, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    /// Upsert a batch of WebSDR recordings in a single transaction — one commit for the
    /// whole batch (see `FieldStore::upsert_qsos`). Used by the SwiftData seed
    /// importer. Atomic per batch; notifies observers once.
    pub fn upsert_websdr_recordings(&self, items: Vec<FfiWebSDRRecording>) -> Result<(), CwError> {
        if items.is_empty() {
            return Ok(());
        }
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.in_transaction(|| {
                for item in items {
                    store.upsert_websdr_recording(&item.into())?;
                }
                Ok(())
            })?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::WebSdrRecording, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    pub fn websdr_recording_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.websdr_recording_count()?)
    }

    pub fn fetch_websdr_recordings(
        &self,
        filter: FfiWebSDRRecordingFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiWebSDRRecording>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_websdr_recordings(&filter.into(), limit, offset)?;
        Ok(rows.into_iter().map(FfiWebSDRRecording::from).collect())
    }

    pub fn fetch_websdr_recording(
        &self,
        id: String,
    ) -> Result<Option<FfiWebSDRRecording>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.fetch_websdr_recording(&id)?.map(FfiWebSDRRecording::from))
    }

    pub fn delete_websdr_recording(&self, id: String) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_websdr_recording(&id)?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::WebSdrRecording, kind: FfiChangeKind::Delete });
        Ok(())
    }
}
