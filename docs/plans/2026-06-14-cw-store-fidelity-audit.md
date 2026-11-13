# cw-store ↔ SwiftData Field-Fidelity Audit

**Date:** 2026-06-14
**Why:** The SwiftData→cw-store seed importer must lose nothing. Before building
it, confirm every persisted `@Model` field has a home in the Rust schema.
**Method:** Diff each SwiftData `@Model`'s persisted stored properties against the
`cw-store` Rust struct + DDL, field by field.

## Verdict

**11 of 12 entities are already faithful mirrors.** The gap is **QSO** alone (a
reduced sketch). This is a single-entity expansion, not a 12-entity rewrite.

> Correction: an earlier draft flagged LoggingSession as missing
> `totaT3CandidatesData`/`totaT3SnapshotAt`. That was a false positive from a
> field-extraction regex that skipped names containing a digit (`tota_t3_*`).
> LoggingSession already carries both — it is complete.

| Entity | Status | Action |
|---|---|---|
| QSO | ❌ ~33 fields missing + ambiguities | **Expand (major)** |
| LoggingSession | ✅ faithful (all ~73 fields incl. tota_t3_*) | none |
| ServicePresence | ✅ faithful (qso relation → `qso_id`) | none |
| SessionSpot | ✅ faithful | none |
| ActivationMetadata | ✅ faithful | none |
| ActivityLog | ✅ faithful | none |
| EquipmentItem | ✅ faithful | none |
| RadioMacro | ✅ faithful | none |
| WebSDRRecording | ✅ faithful | none |
| WebSDRFavorite | ✅ faithful | none |
| UploadDestination | ✅ faithful | none |
| CloudSyncMetadata | ✅ faithful | none |

## LoggingSession — no action (already complete)

Rust `LoggingSession` mirrors all ~73 `@Model` fields, including
`tota_t3_candidates_data` and `tota_t3_snapshot_at`. Type note (not a gap):
`winterActivationOverride: Bool?` is stored as `winter_activation_override:
Option<i64>` — representable (null / 0 / 1); the importer maps `false→0`,
`true→1`, `nil→NULL`.

## QSO — the real expansion

Rust `Qso` has **15** fields; the `@Model` persists **~48**. Current Rust fields:
`id, callsign, band, mode, freq_khz, qso_date, grid, rst_sent, rst_rcvd,
my_callsign, park, notes, created_at, updated_at, dirty`.

### Ambiguities to resolve (decisions for the expansion)

1. **`grid` is ambiguous** — the `@Model` has both `myGrid` and `theirGrid`; the
   Rust struct has one `grid`. **Decision:** replace `grid` with **`my_grid`** and
   **`their_grid`** (lossless). Nothing in production consumes the store yet, so
   this is a safe restructure (schema v3).
2. **Timestamps** — the `@Model` uses `importedAt: Date` (non-opt) and
   `modifiedAt: Date?`, not `createdAt`/`updatedAt`. **Decision:** map
   `created_at ← importedAt`, add **`modified_at: Option<i64>` ← modifiedAt**; keep
   `updated_at` as store-managed bookkeeping (set on each upsert).
3. **`park`** maps to `parkReference` (my activation). Add **`their_park` ←
   theirParkReference** so the hunter side isn't lost.
4. **Unit caveat (importer, not schema):** Rust field is `freq_khz`; the `@Model`
   `frequency` unit must be confirmed at projection time (kHz vs MHz) so the
   value isn't silently rescaled.

### Fields to ADD to Rust `Qso` (mapped from `@Model`)

```
their_grid: Option<String>          ← theirGrid           (with my_grid replacing `grid`)
their_park: Option<String>          ← theirParkReference
notes_user_authored: bool           ← notesUserAuthored
spot_comments_data: Option<Vec<u8>> ← spotCommentsData    (JSON blob, stored verbatim)
callsign_change_note: Option<String>← callsignChangeNote
original_callsign: Option<String>   ← originalCallsign
import_source_raw_value: String     ← importSourceRawValue (col `importSource`)
imported_at: i64                    ← importedAt  (see timestamp decision)
modified_at: Option<i64>            ← modifiedAt
raw_adif: Option<String>            ← rawADIF
name: Option<String>                ← name
qth: Option<String>                 ← qth
state: Option<String>               ← state
country: Option<String>             ← country
power: Option<i64>                  ← power
my_rig: Option<String>              ← myRig
station_profile_name: Option<String>← stationProfileName
sota_ref: Option<String>            ← sotaRef
wwff_ref: Option<String>            ← wwffRef
aoa_code: Option<String>            ← aoaCode
qrz_log_id: Option<String>          ← qrzLogId
qrz_confirmed: bool                 ← qrzConfirmed
lotw_confirmed_date: Option<i64>    ← lotwConfirmedDate
lotw_confirmed: bool                ← lotwConfirmed
dxcc: Option<i64>                   ← dxcc
their_license_class: Option<String> ← theirLicenseClass
contest_name: Option<String>        ← contestName
contest_serial_sent: Option<i64>    ← contestSerialSent
contest_serial_received: Option<i64>← contestSerialReceived
contest_exchange_sent: Option<String>    ← contestExchangeSent
contest_exchange_received: Option<String>← contestExchangeReceived
is_hidden: bool                     ← isHidden
is_activity_log_qso: bool           ← isActivityLogQSO
station_callsign: Option<String>    ← stationCallsign
logging_session_id: Option<String>  ← loggingSessionId
```

`servicePresence` is a relationship, not a column — already covered by
`ServicePresence.qso_id`. `dirty` stays as the sync-journal flag (distinct from
`cloud_dirty_flag` elsewhere; QSO uses `cloudDirtyFlag` → keep mapping `dirty ←
cloudDirtyFlag`, or add `cloud_dirty_flag` for exactness — **decision:** keep the
existing `dirty` column and map it from `cloudDirtyFlag` to avoid a redundant
column).

## Plan (this work)

1. **Expand Rust `Qso`** (`cw-store/src/qso.rs`): add the fields above, split
   `grid`→`my_grid`/`their_grid`, add `imported_at`/`modified_at`/`their_park`.
   Bump schema to **v3** in `migrations.rs` (new columns; `qso` is recreated or
   `ALTER TABLE ADD COLUMN` per field since it's additive — except the `grid`
   split, which on a fresh store is just the new column set).
2. **Expand `FfiQso`** (`cw-ffi/src/lib.rs`) + both `From` impls to carry the new
   fields.
3. **Add the 2 LoggingSession fields** (`cw-store` + `cw-ffi`).
4. Update round-trip tests to set/assert the new fields; `cargo test --workspace`
   + clippy.
5. Regenerate bindings (`build-xcframework.sh`).
6. **Then** the importer (unblocked, lossless).

## Notes

- The store has no real users yet, so the `grid` split + schema v3 need no data
  migration — fresh stores get the new shape.
- Keep the faithful-port convention: the Rust struct names mirror the `@Model`
  property names (snake_case), so the importer projection is a 1:1 copy.
