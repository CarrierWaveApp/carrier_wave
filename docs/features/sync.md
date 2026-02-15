# Sync System

Carrier Wave syncs QSO logs to multiple cloud services.

## Service Sync Directions

| Service | Upload | Download | Notes |
|---------|--------|----------|-------|
| QRZ | ✓ | ✓ | Bidirectional |
| POTA | ✓ | ✓ | Bidirectional |
| HAMRS | ✓ | ✓ | Bidirectional |
| Club Log | ✓ | ✓ | Bidirectional |
| LoFi | | ✓ | Download only |
| LoTW | | ✓ | Download only (upload requires TQSL) |

## Sync Destinations

### QRZ.com

- **Auth**: Username/password → session key
- **Upload**: ADIF via query params, batched (50 QSOs per request)
- **Keychain keys**: `qrz_username`, `qrz_password`, `qrz_session_key`

### Parks on the Air (POTA)

- **Auth**: OAuth via WebView → bearer token
- **Upload**: Multipart ADIF, grouped by park reference
- **Keychain keys**: `pota_token`
- **Special handling**: QSOs with `myParkReference` are grouped and uploaded per-park

### Ham2K LoFi

- **Auth**: Email-based device linking
- **Sync**: Bidirectional - imports operations/QSOs, exports local changes
- **Uses**: `synced_since_millis` for incremental sync
- **Keychain keys**: `lofi_*`

### Club Log

- **Auth**: Email + Application Password + API key
- **Upload**: Batch ADIF via multipart `putlogs.php`, or single QSO via `realtime.php`
- **Download**: Full ADIF log via `getadif.php` (supports date range filtering)
- **Keychain keys**: `clublog.api.key`, `clublog.email`, `clublog.password`, `clublog.callsign`
- **Special handling**:
  - No delta/changelog API — downloads full log (or date range) and diffs locally
  - Duplicate detection is built-in on the server side
  - On HTTP 403: immediately stop all further requests (aggressive IP firewall)
  - Upload is queued server-side, not instant (5–60 seconds processing)

### ARRL LoTW

- **Auth**: Username/password via query params
- **Download**: ADIF via `lotwreport.adi` endpoint
- **Upload**: Not supported (requires TQSL application)
- **Keychain keys**: `lotw_username`, `lotw_password`, `lotw_last_qsl`, `lotw_last_qso_rx`
- **Special handling**: 
  - Provides QSL confirmation status (`lotwConfirmed`, `lotwConfirmedDate`)
  - Fetches QSOs for **all configured callsigns** (current + previous) using `qso_owncall` filter
  - QSOs from all callsigns are included in local stats but never uploaded (download-only service)

## Canonical Sync Flow (MANDATORY)

The full sync (`syncAll()`) MUST follow this exact ordering. Deviations will cause
incorrect upload/presence state and phantom uploads.

### Phase 1: Download from all services (parallel)

Download QSOs from all configured services (QRZ, POTA, LoFi, HAMRS, LoTW, Club Log) in parallel.
Also download POTA upload jobs (`/user/jobs`) — this happens in Phase 2.5c but the data
is fetched from the POTA API.

### Phase 2: Process and deduplicate

Merge downloaded QSOs with local database. New QSOs are created, existing QSOs are
enriched with data from additional sources. ServicePresence records are created for
new QSOs.

### Phase 2.5: Reconcile presence against truth sources

**This is the critical step.** After downloading, we compare local ServicePresence
records against what the services actually report:

- **2.5b: QRZ reconciliation** — Compare QRZ presence against downloaded QRZ QSOs.
  If a QSO is marked `isPresent` for QRZ but QRZ didn't return it, reset to `needsUpload`.
  (Only on full sync — incremental sync doesn't have the complete picture.)

- **2.5c: POTA reconciliation** — Fetch POTA upload jobs, then compare every POTA
  ServicePresence record against the job log:
  - `isPresent=true` with no completed/duplicate job → **reset to `needsUpload=true`**
  - `isSubmitted=true` with completed/duplicate job → **confirm as `isPresent=true`**
  - `isSubmitted=true` with failed job → **reset to `needsUpload=true`**
  - `isSubmitted=true` with pending/processing job submitted <30 min ago → **leave alone** (wait)
  - `isSubmitted=true` with pending/processing job submitted >=30 min ago → **reset to
    `needsUpload=true`** (stale — POTA likely stuck or dropped the job)
  - `isSubmitted=true` with no matching job → **reset to `needsUpload=true`** (silently dropped)

  **Rule: If there is no upload job for an activation, the QSO MUST NOT be marked as
  uploaded.** The POTA job log is the single source of truth for upload status.

  **Job status classification:**
  - `completed` (2), `duplicate` (7) → confirmed (POTA has the QSOs)
  - `failed` (3), `error` (-1) → failed (reset to retry)
  - `pending` (0), `processing` (1), submitted <30 min ago → in-progress (wait)
  - `pending` (0), `processing` (1), submitted >=30 min ago → stale (reset to retry)

- **2.5d–g: Cleanup** — Repair orphaned QSOs, clear metadata mode upload flags,
  clear non-primary callsign upload flags, repair missing DXCC.

### Phase 3: Upload to all destinations (parallel)

Upload QSOs with `needsUpload=true` to QRZ and POTA. Only runs if read-only mode
is disabled.

### Invariants

1. **Download before reconcile**: Phases 1–2 must complete before Phase 2.5.
2. **Reconcile before upload**: Phase 2.5 must complete before Phase 3.
3. **POTA jobs are the truth**: A QSO's POTA upload status is determined solely by
   whether a completed job exists in the POTA job log. Local `isPresent`/`isSubmitted`
   flags are reconciled against this truth source every sync.
4. **No false positives**: If no job exists for an activation, the QSO must be reset
   to `needsUpload=true` so it gets re-uploaded in Phase 3.
5. **Download-sourced QSOs are exempt**: QSOs with `importSource == .pota` (i.e.,
   downloaded from POTA's logbook) are not reconciled because they were never uploaded
   by us — they represent the remote state directly.

## ServicePresence States

| Field | Meaning |
|-------|---------|
| `isPresent` | QSO confirmed present on the service (verified by download or job) |
| `needsUpload` | QSO needs to be uploaded to this service |
| `isSubmitted` | Upload HTTP request succeeded but job completion unconfirmed (POTA only) |
| `uploadRejected` | Upload permanently rejected (e.g., invalid park reference) |
| `lastConfirmedAt` | When presence was last verified |
| `parkReference` | For POTA two-fer: the specific park this record applies to |

## Callsign Filtering (MANDATORY)

**All uploads MUST filter to the user's primary callsign only.** See [Callsign Filtering Guidelines](callsign-filtering.md) for details.

Users may have QSOs logged under previous callsigns (e.g., before a license upgrade or vanity call). These QSOs:
- Are kept locally for records
- MUST NOT be included in upload queues
- MUST NOT have `ServicePresence` records created for upload services

Services authenticate with the user's current callsign. Uploading QSOs from a different callsign will fail or associate data with the wrong account.

## Key Implementation Details

- **Callsign filtering**: Only upload QSOs where `myCallsign` matches user's primary callsign
- **Deduplication**: `QSO.deduplicationKey` uses 2-minute time buckets + band + mode + callsign
- **ADIF preservation**: Original ADIF stored in `rawADIF` for reproducibility
- **Batching**: QRZ uploads batched at 50 QSOs; POTA grouped by park
- **Error handling**: Failed uploads create `POTAUploadAttempt` records for debugging

## Related Plans

- [Sync Model Redesign](../plans/2026-01-21-sync-model-redesign.md)
- [QRZ Token Sync Design](../plans/2026-01-21-qrz-token-sync-design.md)
