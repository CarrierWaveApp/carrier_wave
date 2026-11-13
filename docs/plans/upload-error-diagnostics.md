# Upload Error Diagnostics

## Problem

Users see uploads fail with no clear explanation. Errors are buried in the developer-only SyncDebugView. The sync card shows a single red line like "Upload failed: The operation timed out" with no grouping, no actionable guidance, and no way for us to learn about common failures at scale.

## Design

Three layers:

### Layer 1: Error Classification & Grouping (Client-Side)

**New model: `UploadErrorDiagnostic`** in `CarrierWaveCore` (pure value type, Sendable/Codable).

Classifies every upload error into a category with a user-facing explanation and fix suggestion:

```swift
struct UploadErrorDiagnostic: Sendable, Codable, Equatable {
    let category: ErrorCategory
    let service: ServiceType
    let message: String        // Technical detail
    let guidance: String       // User-facing "check this" text
    let affectedCount: Int     // How many QSOs affected
    let isTransient: Bool      // Will retry help?
    let timestamp: Date

    enum ErrorCategory: String, Sendable, Codable {
        case authentication     // Bad/expired credentials
        case validation         // QSO data issues (missing fields, bad park ref)
        case rateLimited        // Too many requests
        case maintenance        // Service down for maintenance
        case networkTimeout     // Timeout or connectivity
        case networkOffline     // No internet
        case serverError        // 5xx from remote service
        case rejected           // Permanently rejected (bad data)
        case subscriptionRequired // Need paid tier (QRZ XML sub)
    }
}
```

**New: `UploadErrorClassifier`** — maps each service's error types to `UploadErrorDiagnostic`:

```swift
enum UploadErrorClassifier {
    static func classify(
        error: Error,
        service: ServiceType,
        affectedCount: Int
    ) -> UploadErrorDiagnostic
}
```

Maps known error types:
- `QRZError.subscriptionRequired` → `.subscriptionRequired`, guidance: "QRZ requires an XML Logbook Data subscription to upload. Check your QRZ account."
- `QRZError.invalidApiKey` → `.authentication`, guidance: "Your QRZ API key is invalid. Go to Settings → QRZ to update it."
- `POTAError.notAuthenticated` → `.authentication`, guidance: "POTA login expired. Go to Settings → POTA to sign in again."
- `POTAError.maintenanceWindow` → `.maintenance`, guidance: "POTA is in daily maintenance (0000–0400 UTC). Upload will retry automatically."
- `POTAError.invalidParkReference` → `.validation`, guidance: "One or more QSOs have an invalid park reference format."
- `ClubLogError.forbidden` → `.authentication`, guidance: "Club Log rejected your request — this may be an IP firewall issue. Try again later."
- `ClubLogError.uploadRejected` → `.rejected`, guidance: "Club Log permanently rejected these QSOs. Check the data in the debug log."
- `EQSLError.authenticationFailed` → `.authentication`, guidance: "eQSL login failed. Check your credentials in Settings → eQSL."
- `SyncTimeoutError.timeout` → `.networkTimeout`, guidance: "Upload timed out. This usually means a slow connection — will retry on next sync."
- URLError `.notConnectedToInternet` → `.networkOffline`, guidance: "No internet connection. Upload will retry when you're back online."
- URLError `.timedOut` → `.networkTimeout`
- Any other error → `.serverError` with generic guidance

**New: `UploadDiagnosticStore`** — `@MainActor` observable store, persisted to UserDefaults:

```swift
@MainActor
final class UploadDiagnosticStore: ObservableObject {
    @Published private(set) var diagnostics: [UploadErrorDiagnostic] = []
    @Published private(set) var lastUpdated: Date?

    /// Group diagnostics by category for UI display
    var groupedByCategory: [ErrorCategory: [UploadErrorDiagnostic]]

    /// Group diagnostics by service
    var groupedByService: [ServiceType: [UploadErrorDiagnostic]]

    /// Total affected QSOs across all errors
    var totalAffectedQSOs: Int

    /// Whether there are any non-transient errors requiring user action
    var hasActionRequired: Bool

    func record(_ diagnostic: UploadErrorDiagnostic)
    func clearForService(_ service: ServiceType)
    func clearAll()
    func clearResolved()  // Remove transient errors older than 1 hour
}
```

Max 50 diagnostics retained. Cleared on successful upload per-service. Persisted via Codable to UserDefaults key `"uploadDiagnostics"`.

### Layer 2: User-Facing Error Summary UI

**New: `UploadDiagnosticsView`** — accessible from the sync card and settings.

When errors exist after sync, the sync card shows an expandable error summary banner:

```
┌─────────────────────────────────────────┐
│ Services                    Synced 2m ago│
│ ─────────────────────────────────────── │
│ ⚠ 3 upload issues                    ▸  │
│   2 QSOs need attention · 1 will retry  │
│ ─────────────────────────────────────── │
│ ✓ QRZ           312 synced              │
│ ✗ POTA          Upload failed           │
│ ✓ Club Log      89 synced               │
└─────────────────────────────────────────┘
```

Tapping the banner navigates to `UploadDiagnosticsView`:

```
┌─────────────────────────────────────────┐
│ Upload Issues                           │
│                                         │
│ NEEDS ATTENTION                         │
│ ─────────────────────────────────────── │
│ ⚠ Authentication                       │
│   POTA login expired                    │
│   2 QSOs affected                       │
│   → Go to Settings → POTA to sign in   │
│                                         │
│ ⚠ Invalid Data                          │
│   Invalid park reference format         │
│   1 QSO affected                        │
│   → Check park reference in QSO editor  │
│                                         │
│ WILL RETRY AUTOMATICALLY               │
│ ─────────────────────────────────────── │
│ ○ Network Timeout                       │
│   QRZ upload timed out                  │
│   5 QSOs will retry on next sync        │
│                                         │
│              Clear All                  │
└─────────────────────────────────────────┘
```

### Layer 3: Error Telemetry to Activities Server

**New endpoint on activities-server:** `POST /v1/telemetry/upload-errors`

Report aggregated, anonymized error data so we can identify systemic issues (e.g., "POTA is rejecting everyone's uploads today").

**Request body:**
```json
{
  "errors": [
    {
      "service": "pota",
      "category": "authentication",
      "message_hash": "a1b2c3",  // SHA256 of error message (not the message itself)
      "affected_count": 5,
      "is_transient": false,
      "app_version": "1.8.0",
      "os_version": "18.4"
    }
  ]
}
```

Key privacy decisions:
- **No callsigns, QSO data, or raw error messages** sent — only category + hashed message + counts
- Batched: send at most once per sync cycle
- Opt-in: only sent if community features (activities server) are enabled
- Rate limited: max 1 report per 5 minutes

**Client-side:** New method on `ActivitiesClient`:
```swift
func reportUploadErrors(_ errors: [UploadErrorTelemetry]) async throws
```

Called at end of `uploadToAllDestinations()` if errors occurred and user has community features enabled.

## Files to Create/Modify

### New Files
1. `CarrierWave/Services/UploadErrorDiagnostic.swift` — Model + ErrorCategory enum
2. `CarrierWave/Services/UploadErrorClassifier.swift` — Error → Diagnostic mapping
3. `CarrierWave/Services/UploadDiagnosticStore.swift` — Observable store with persistence
4. `CarrierWave/Views/Settings/UploadDiagnosticsView.swift` — Full diagnostics detail view

### Modified Files
5. `CarrierWave/Services/SyncService+Upload.swift` — Record diagnostics after each service upload failure
6. `CarrierWave/Views/Dashboard/SyncProgressCard.swift` — Add error summary banner to SyncCard idle state
7. `CarrierWave/Services/ActivitiesClient.swift` — Add `reportUploadErrors()` method
8. `CarrierWave/Services/ActivitiesError.swift` — Add telemetry error case (if needed)
9. `docs/FILE_INDEX.md` — Register new files

## Implementation Order

1. `UploadErrorDiagnostic` model + `ErrorCategory` enum
2. `UploadErrorClassifier` with mappings for all 6 service error types
3. `UploadDiagnosticStore` with persistence
4. Wire into `SyncService+Upload.swift` — record diagnostics on failure, clear on success
5. `UploadDiagnosticsView` — detail view
6. Error summary banner in `SyncCard`
7. `ActivitiesClient.reportUploadErrors()` — telemetry endpoint
8. Wire telemetry into upload flow
9. Update FILE_INDEX.md

## Scope Notes

- The activities-server Rust endpoint is a separate repo — this plan covers the client contract only. We'll document the expected API shape for server implementation.
- No new SwiftData models — diagnostics are ephemeral (UserDefaults). They don't need to survive database resets.
- Validation errors for missing fields (already detected in `partitionQSOsByValidity`) get diagnostics too, not just service errors.
