# Sync System

Carrier Wave syncs QSO logs to multiple cloud services.

## Service Sync Directions

| Service | Upload | Download | Notes |
|---------|--------|----------|-------|
| QRZ | ✓ | ✓ | Bidirectional |
| POTA | ✓ | ✓ | Bidirectional |
| HAMRS | ✓ | ✓ | Bidirectional |
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

### ARRL LoTW

- **Auth**: Username/password via query params
- **Download**: ADIF via `lotwreport.adi` endpoint
- **Upload**: Not supported (requires TQSL application)
- **Keychain keys**: `lotw_username`, `lotw_password`, `lotw_last_qsl`, `lotw_last_qso_rx`
- **Special handling**: 
  - Provides QSL confirmation status (`lotwConfirmed`, `lotwConfirmedDate`)
  - Fetches QSOs for **all configured callsigns** (current + previous) using `qso_owncall` filter
  - QSOs from all callsigns are included in local stats but never uploaded (download-only service)

## Data Flow

```
ADIF Import → ADIFParser → ImportService → QSO + SyncRecord (pending)
                                              ↓
                                         SyncService
                                              ↓
                      ┌───────────────┬───────────────┬───────────────┬───────────────┐
                      ↓               ↓               ↓               ↓               ↓
                  QRZClient      POTAClient      LoFiClient      HAMRSClient     LoTWClient
                      ↓               ↓               ↓               ↓               ↓
                 SyncRecord status updated        (download only, no SyncRecord)
```

## SyncRecord States

| Status | Meaning |
|--------|---------|
| `pending` | Awaiting upload |
| `uploaded` | Successfully synced |
| `failed` | Upload failed (will retry) |

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
