//! Browser-side logbook filtering, reusing the shared `.cwquery` language.
//!
//! The viewer decrypts QSOs client-side (no SQLite), so it can't run the store's
//! SQL compiler. Instead it parses a query with `cw_domain::query` and evaluates
//! it in memory with `cw_domain::query::matches` — the same AST the app uses,
//! parity-tested against the SQL compiler (see cw-store's `query_eval_parity`).
//!
//! [`LogbookIndex`] parses the decrypted QSOs once, then [`LogbookIndex::filter`]
//! runs a query and returns the matching row indices, so re-filtering as the user
//! types is cheap.

use cw_domain::query::{matches, parse, QueryRow};
use serde::Deserialize;
use wasm_bindgen::prelude::*;

/// The subset of `SyncQso` fields the query language addresses, deserialized from
/// the decrypted-QSO JSON (camelCase, matching the sync wire shape). `park` maps
/// to `parkReference`; `timestamp` is the `qso_date`; `frequency` is kHz.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct WebQso {
    #[serde(default)]
    callsign: Option<String>,
    #[serde(default)]
    band: Option<String>,
    #[serde(default)]
    mode: Option<String>,
    #[serde(default)]
    my_callsign: Option<String>,
    #[serde(default)]
    park_reference: Option<String>,
    #[serde(default)]
    sota_ref: Option<String>,
    #[serde(default)]
    their_grid: Option<String>,
    #[serde(default)]
    state: Option<String>,
    #[serde(default)]
    country: Option<String>,
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    qth: Option<String>,
    #[serde(default)]
    notes: Option<String>,
    #[serde(default)]
    my_grid: Option<String>,
    #[serde(default)]
    frequency: Option<f64>,
    #[serde(default)]
    dxcc: Option<f64>,
    #[serde(default)]
    power: Option<f64>,
    #[serde(default)]
    timestamp: i64,
    #[serde(default)]
    qrz_confirmed: bool,
    #[serde(default)]
    lotw_confirmed: bool,
    #[serde(default)]
    import_source: String,
}

impl QueryRow for WebQso {
    fn callsign(&self) -> Option<&str> {
        self.callsign.as_deref()
    }
    fn band(&self) -> Option<&str> {
        self.band.as_deref()
    }
    fn mode(&self) -> Option<&str> {
        self.mode.as_deref()
    }
    fn my_callsign(&self) -> Option<&str> {
        self.my_callsign.as_deref()
    }
    fn park(&self) -> Option<&str> {
        self.park_reference.as_deref()
    }
    fn sota_ref(&self) -> Option<&str> {
        self.sota_ref.as_deref()
    }
    fn their_grid(&self) -> Option<&str> {
        self.their_grid.as_deref()
    }
    fn state(&self) -> Option<&str> {
        self.state.as_deref()
    }
    fn country(&self) -> Option<&str> {
        self.country.as_deref()
    }
    fn name(&self) -> Option<&str> {
        self.name.as_deref()
    }
    fn qth(&self) -> Option<&str> {
        self.qth.as_deref()
    }
    fn notes(&self) -> Option<&str> {
        self.notes.as_deref()
    }
    fn my_grid(&self) -> Option<&str> {
        self.my_grid.as_deref()
    }
    fn frequency_khz(&self) -> Option<f64> {
        self.frequency
    }
    fn dxcc(&self) -> Option<f64> {
        self.dxcc
    }
    fn power(&self) -> Option<f64> {
        self.power
    }
    fn qso_date(&self) -> i64 {
        self.timestamp
    }
    fn qrz_confirmed(&self) -> bool {
        self.qrz_confirmed
    }
    fn lotw_confirmed(&self) -> bool {
        self.lotw_confirmed
    }
    fn import_source(&self) -> &str {
        &self.import_source
    }
    // service_presence_supported() defaults to false: the viewer doesn't decrypt
    // ServicePresence, so `synced:`/`pending:` match nothing (documented).
}

/// A parsed set of decrypted QSOs, ready to filter by `.cwquery` repeatedly.
#[wasm_bindgen]
pub struct LogbookIndex {
    rows: Vec<WebQso>,
}

#[wasm_bindgen]
impl LogbookIndex {
    /// Parse the decrypted QSOs (a JSON array in load order). Row indices returned
    /// by [`filter`](Self::filter) refer to this order.
    #[wasm_bindgen(constructor)]
    pub fn new(qsos_json: &str) -> Result<LogbookIndex, JsError> {
        let rows: Vec<WebQso> = serde_json::from_str(qsos_json)
            .map_err(|e| JsError::new(&format!("invalid QSO json: {e}")))?;
        Ok(LogbookIndex { rows })
    }

    /// Number of indexed rows.
    #[wasm_bindgen(getter)]
    pub fn len(&self) -> usize {
        self.rows.len()
    }

    #[wasm_bindgen(getter)]
    pub fn is_empty(&self) -> bool {
        self.rows.is_empty()
    }

    /// Indices of the rows matching `query` (in index order). An empty/whitespace
    /// query matches everything. A syntax error returns a `JsError` carrying the
    /// parser's message so the UI can show it inline.
    pub fn filter(&self, query: &str) -> Result<Vec<u32>, JsError> {
        let parsed = parse(query).map_err(|e| JsError::new(&e.to_string()))?;
        Ok(self
            .rows
            .iter()
            .enumerate()
            .filter(|(_, row)| matches(&parsed, *row))
            .map(|(i, _)| i as u32)
            .collect())
    }

    /// Validate a query without running it. Returns the parser error message, or
    /// `null` when the query is valid — for live syntax feedback while typing.
    pub fn validate(&self, query: &str) -> Option<String> {
        parse(query).err().map(|e| e.to_string())
    }
}
