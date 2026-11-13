# Investigation: QSO Data Loss — Available Debug Surfaces

## Symptom
User reports complete loss of active QSOs from the SwiftData store. Backups
and the QSO Safety Ledger are intact (ledger was working; backups exist),
so the QSOs were logged at some point — they're just gone from `default.store`.

## Goal of this doc
Catalogue every diagnostic the iOS app already produces, where each one lives
on disk, and which questions it can/can't answer. This is the menu of evidence
to ask the user for.

## The single thing to ask for first

**Settings → Send Diagnostics, with "Include database snapshot" toggled ON.**

Source: `swift/ios/CarrierWave/Views/Settings/SendDiagnosticsView.swift`,
collector at `swift/ios/CarrierWave/Services/DiagnosticsCollector+Collectors.swift`.

The bundle is a single zip and pulls together every artifact below in one
shot. The DB snapshot is the only way to inspect *what's actually in the
store right now* (vs. what the user thinks should be there). The toggle is
opt-in because it's large; for a data-loss case it is mandatory.

If the user can't / won't share the DB, the rest of the bundle still narrows
the cause significantly.

## Artifact-by-artifact: what each tells us

| Artifact in bundle | On-device path | Answers |
|---|---|---|
| `database.sqlite` (toggle) | `Library/Application Support/default.store` | What QSOs/sessions/presences exist *now*. Diff against the ledger to enumerate exactly which UUIDs vanished. |
| `recent-qsos.json` | (live fetch, top 50, notes redacted) | Newest 50 surviving QSOs — confirms the cliff (`is everything before date X gone?`) without the full DB. |
| `backup-manifest.json` | `Library/Backups/backups.json` | Every snapshot with timestamp, trigger (`launch`/`preSync`/`preImport`/`manual`/`preRestore`), QSO count, size, location (local/iCloud), app version. **The QSO count series is the smoking gun** — find the snapshot pair where count drops, and the `trigger` on the *later* one names the operation that preceded the loss. |
| `sync-debug-log.json` | `Library/Application Support/sync-debug-log.json` | Per-service (QRZ, POTA, LoFi, LoTW, HAMRS) info/warn/error/action log incl. raw upload payloads. Tells us if a sync wrote unexpected state or got an "actionRequired" deletion response. |
| `cloud-sync-events.json` | `Library/CloudSync/sync_events.json` (FIFO 500) | iCloud `CKSyncEngine` event log — includes `.conflict` entries from `CloudSyncEngine+ConflictResolution.swift` whenever a CKRecord conflict was resolved. **This is where multi-device-overwrite data loss shows up.** |
| `ledger-tail.adi` | `Documents/QSOLedger/{YYYY-MM,YYYY-MM-1}.adi` (last 2 months) | What the safety net captured at log-time. Ground truth for "QSOs the user actually made", independent of the DB. The full ledger lives on the device; the bundle only ships the most recent two months — for an older horizon ask separately. |
| `storage-info.json` | computed | DB file size, ledger sizes, available disk, physical memory. A DB that's smaller than expected without a corresponding backup-manifest count drop suggests on-device file truncation rather than logical deletion. |
| `startup-profile.json` | `Caches/startup-profile.json` | Launch milestone trace. Useful only if the loss correlates with a startup hang / crash. |
| `perf-summary.json` | computed | Device model, OS version, thermal state, low-power-mode flag. |
| `os-log.txt` | `OSLogStore` last hour, ≤2,000 lines | Only if user reproduces / opens the app and immediately exports. Past sessions are gone unless captured before they aged out. |

## Source-of-truth files (read before filing fix)

- `swift/ios/CarrierWave/Services/DiagnosticsCollector+Collectors.swift` —
  the canonical list of what gets collected and from where.
- `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Utilities/QSOLedger.swift` —
  monthly ADIF + QSON in `Documents/QSOLedger/`. Append-only, never touched
  by sync or backup pruning. Files: `YYYY-MM.adi` + `YYYY-MM.qsonl`.
- `swift/ios/CarrierWave/Services/BackupService.swift` —
  `BackupEntry { id, timestamp, trigger, qsoCount, sizeBytes, appVersion,
  location, filename }`. Manifest is `Library/Backups/backups.json`.
- `swift/packages/CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncEventLog.swift` —
  500-event FIFO. **Caveat: `isExcludedFromBackup = true`, so a device
  restore from an iCloud/iTunes backup will not contain prior sync events.**
- `swift/packages/CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncEngine+ConflictResolution.swift` —
  every CKRecord save conflict appends a `.conflict` event. Resolver
  decisions per entity type are dispatched from here.
- `swift/ios/CarrierWave/Services/SyncDebugLog.swift` — `actionRequired`
  level is the one to grep for; it's used when a service flagged
  user-visible deletion-style state.

## Triage path with the bundle in hand

1. Open `backup-manifest.json` → sort by `timestamp` → find the entry
   where `qsoCount` first drops. Note its `trigger` and `appVersion`.
   - `trigger == .preRestore` → user (or auto) restored an older backup.
   - `trigger == .preImport` → an import wiped/replaced existing rows;
     check `sync-debug-log.json` around that timestamp.
   - `trigger == .preSync` → check `cloud-sync-events.json` for
     `.conflict` events around that timestamp; iCloud overwrite from a
     stale device is the likely path.
   - `trigger == .launch` → loss happened *between* sessions —
     migration/store-corruption suspect; pull `startup-profile.json`
     and look for a SwiftData migration milestone.
2. Cross-reference UUIDs: extract `<APP_UUID>` (or callsign+timestamp
   tuple) from `ledger-tail.adi`, fetch the same set from `database.sqlite`,
   and the diff is the exact lost-QSO list.
3. If `cloud-sync-events.json` is empty or missing iCloud is either off
   or the events were wiped by a device restore — confirm with the user.

## Gaps to fix in a follow-up (not this PR)

- Ledger-tail in the bundle is only the last 2 months. For a user reporting
  loss of "active QSOs" (open question: how far back?) we may need the full
  ledger directory. Add an "Include full ledger" toggle to `SendDiagnosticsView`.
- `BackupEntry` records the trigger but not *what initiated the trigger*
  (which sync source, which import file). For `.preImport` and `.preSync`
  triggers we should attach a small free-form `context: String?`.
- `CloudSyncEvent` `.conflict` detail is `"Conflict resolved: \(entityType)"`
  — it doesn't record which side won or how many fields differed. For
  data-loss forensics we want winner identity + lost-field count.
- Sync events file is excluded from device backup. That's correct for
  privacy/size, but means after a device-restore-driven loss we lose the
  evidence trail. Consider a small archive-on-rotation that *is* included.

## Asks to send the user

1. Settings → Send Diagnostics → describe what happened → toggle
   **Include database snapshot** ON → Collect & Share → AirDrop / email
   the zip.
2. Approximate date/time the QSOs were last seen, and approximate date/time
   they were noticed missing.
3. Whether they restored the device, switched iCloud accounts, or used
   "Restore from backup" inside the app within that window.
4. Other devices (iPad, second iPhone, Mac) running Carrier Wave with the
   same iCloud account — capture the same diagnostics from each.
