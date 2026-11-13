# Full Duplex - iOS Ham Radio Log Sync App

## Overview

Full Duplex is a native iOS app for managing amateur radio logs. It imports QSOs from various sources (Ham2K LoFi, ADIF files, iCloud Drive) and uploads them to logging services (QRZ, POTA.app).

**Primary Use Case:** Log management hub—not a field logger. Users log with other apps (e.g., PoLo) and use Full Duplex to sync to cloud services.

**iOS Target:** 17.0+ (required for SwiftData)

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    iOS App                          │
├─────────────────────────────────────────────────────┤
│  UI Layer (SwiftUI)                                 │
│  ├── DashboardView (home)                           │
│  ├── LogListView                                    │
│  ├── SyncStatusView                                 │
│  └── SettingsView                                   │
├─────────────────────────────────────────────────────┤
│  Services Layer                                     │
│  ├── ADIFParser (parse .adi/.adif files)            │
│  ├── LoFiClient (Ham2K sync API)                    │
│  ├── QRZClient (upload via API token)               │
│  ├── POTAAuthService (WKWebView + fallback)         │
│  ├── POTAClient (upload logs)                       │
│  └── ICloudMonitor (watch folder + notify)          │
├─────────────────────────────────────────────────────┤
│  Data Layer (SwiftData)                             │
│  ├── QSO (individual contact)                       │
│  ├── SyncRecord (per-QSO, per-destination status)   │
│  └── UploadDestination (credentials, last sync)     │
└─────────────────────────────────────────────────────┘
```

**Data Flow:**
1. **Import:** ADIF files or LoFi → ADIFParser → deduplicate → store QSOs in SwiftData
2. **Upload:** User triggers sync → filter QSOs not yet uploaded to destination → upload → mark SyncRecord complete
3. **Monitoring:** ICloudMonitor detects new .adif files → local notification → user opens app to import

---

## Data Model

### QSO (Core Entity)

```swift
@Model
class QSO {
    @Attribute(.unique) var id: UUID
    var callsign: String
    var band: String           // "20m", "40m", etc.
    var mode: String           // "SSB", "CW", "FT8", etc.
    var frequency: Double?     // kHz
    var timestamp: Date
    var rstSent: String?
    var rstReceived: String?
    var myCallsign: String
    var myGrid: String?
    var theirGrid: String?
    var parkReference: String? // "K-1234" for POTA
    var notes: String?
    var importSource: ImportSource  // .lofi, .adifFile, .icloud
    var importedAt: Date
    var rawADIF: String?       // Original ADIF record for re-export

    var syncRecords: [SyncRecord]
}
```

### SyncRecord (Upload Tracking)

```swift
@Model
class SyncRecord {
    var destination: UploadDestination
    var qso: QSO
    var status: SyncStatus     // .pending, .uploaded, .failed
    var uploadedAt: Date?
    var errorMessage: String?
}
```

### UploadDestination (Credentials)

```swift
@Model
class UploadDestination {
    var type: DestinationType  // .qrz, .pota
    var isEnabled: Bool
    var lastSyncAt: Date?
    // Credentials stored in Keychain, not SwiftData
}
```

### Deduplication

On import, hash `(callsign + band + mode + timestamp rounded to 2 min)` and check for existing match before inserting.

---

## POTA.app Authentication

### Primary: WKWebView Flow

```swift
class POTAAuthService {
    func authenticate() async throws -> POTAToken {
        // 1. Present WKWebView in a sheet
        // 2. Load pota.app/#/login
        // 3. User manually enters credentials on Cognito page
        // 4. After redirect back to pota.app, inject JS to extract idToken
        // 5. Dismiss web view, return token
    }
}
```

**Key difference from headless browser approach:** Let the user type their own credentials rather than automating entry. This is more secure (app never sees password), more reliable (no brittle selectors), and better UX.

**Token Extraction:** After detecting URL returns to `pota.app`, inject JavaScript to extract `idToken` from cookies/localStorage/sessionStorage.

**Token Storage:** Store JWT in iOS Keychain with expiry timestamp.

### Fallback: pota-auth-service

If WKWebView extraction fails:
1. Prompt user to enter credentials in-app
2. Call hosted pota-auth-service API
3. Store returned token in Keychain

### Refresh Strategy

Tokens expire hourly. Before each POTA upload, check expiry. If expired or expiring within 5 minutes, trigger re-auth flow.

---

## LoFi Integration

### Ham2K LoFi Client

```swift
class LoFiClient {
    func fetchQSOs(since: Date?) async throws -> [ADIFRecord]
    // - Authenticate with LoFi credentials
    // - Pull QSOs as ADIF data
    // - Return parsed records for import
}
```

**Credential Setup:** User provides their LoFi-linked email, receives confirmation link in PoLo app, then syncs automatically. Store auth token in Keychain.

---

## ADIF Parsing

ADIF format example:
```
<call:5>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 <eor>
```

```swift
struct ADIFParser {
    func parse(data: Data) throws -> [ADIFRecord]
    // - Scan for <field:length> patterns
    // - Extract field values
    // - Map to ADIFRecord struct
    // - Preserve raw ADIF string for re-export
}
```

### Import Sources

- **Files app / Share sheet:** Register for `.adi` and `.adif` UTTypes, handle via `onOpenURL` or share extension
- **iCloud folder:** Monitor designated folder for new files

---

## iCloud Monitoring

### Folder Structure

```
iCloud Drive/
└── Full Duplex/
    └── Import/        # User drops ADIF files here
```

### Monitoring

```swift
class ICloudMonitor {
    private var query: NSMetadataQuery

    func startMonitoring() {
        // NSMetadataQuery watches for files in the iCloud container
        // Predicate: *.adi, *.adif in the Import folder
        // Fires when new files appear or download completes
    }
}
```

### Notification Flow

1. User drops `fieldday.adi` into `Full Duplex/Import/` folder
2. `NSMetadataQuery` detects the new file
3. If app is backgrounded, schedule a local notification: "New log file detected: fieldday.adi - Tap to import"
4. User taps notification → app opens → presents import confirmation
5. After successful import, optionally move file to `Import/Processed/`

**Limitation:** iOS doesn't allow true background monitoring of iCloud. Notifications fire when the app wakes for background refresh or when the user opens the app.

---

## QRZ Upload

### Authentication

```swift
class QRZClient {
    private let baseURL = "https://logbook.qrz.com/api"

    func authenticate(username: String, password: String) async throws -> String {
        // POST: ACTION=LOGIN&USERNAME=xx&PASSWORD=xx
        // Returns: RESULT=OK&KEY=xxxxx
    }
}
```

### Upload

```swift
func uploadQSOs(_ qsos: [QSO]) async throws -> UploadResult {
    // Convert QSOs to ADIF format (use rawADIF if available)
    // POST: ACTION=INSERT&KEY=xxx&ADIF=<adif data>
    // Returns: RESULT=OK&COUNT=5&LOGID=xxxxx
}
```

**Batch Handling:** Chunk large uploads (~50 QSOs per request), update SyncRecords as each batch succeeds.

---

## POTA.app Upload

### API

```
POST https://api.pota.app/activation
Authorization: Bearer <idToken>
Content-Type: multipart/form-data
```

### Upload Flow

```swift
class POTAClient {
    func uploadActivation(
        parkReference: String,    // "K-1234"
        qsos: [QSO],
        token: String
    ) async throws -> UploadResult {
        // 1. Filter QSOs that have this parkReference
        // 2. Convert to ADIF format
        // 3. POST as multipart form with the ADIF file
        // 4. Parse response for success/errors
    }
}
```

**POTA-Specific:**
- Group QSOs by `parkReference` before upload (per-activation)
- POTA requires 10+ QSOs for valid activation; app can warn but allow upload
- POTA server also dedupes; already-uploaded QSOs return success with no new adds

---

## Dashboard UI

### Tab Structure

```
[Dashboard]   [Logs]   [Settings]
```

### Dashboard View

```
┌─────────────────────────────────────────────────┐
│  Full Duplex                           ⟳ Sync   │
├─────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────┐    │
│  │  Summary                                 │    │
│  │  142 QSOs  •  Last sync: 2h ago          │    │
│  └─────────────────────────────────────────┘    │
│                                                  │
│  ┌─────────────┐  ┌─────────────┐              │
│  │ QRZ         │  │ POTA        │              │
│  │ ✓ 142/142   │  │ ⚠ 38/42     │              │
│  │ Synced      │  │ 4 pending   │              │
│  └─────────────┘  └─────────────┘              │
│                                                  │
│  ┌─────────────────────────────────────────┐    │
│  │  Recent Imports                          │    │
│  │  fieldday.adi         12 QSOs   Today    │    │
│  │  pota-k1234.adi        8 QSOs   Yesterday│    │
│  │  LoFi Sync            22 QSOs   Jan 18   │    │
│  └─────────────────────────────────────────┘    │
│                                                  │
│  ┌─────────────────────────────────────────┐    │
│  │  ⚠ 1 new file in iCloud                  │    │
│  │  contest-log.adi  →  [Import]            │    │
│  └─────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

### Logs View

Searchable/filterable list of all QSOs. Tap for detail. Swipe to see sync status per destination.

### Settings View

Configure LoFi, QRZ, POTA credentials. Enable/disable destinations. Set iCloud folder path.

---

## Project Structure

```
FullDuplex/
├── FullDuplexApp.swift           # App entry point
├── Models/
│   ├── QSO.swift
│   ├── SyncRecord.swift
│   └── UploadDestination.swift
├── Services/
│   ├── ADIFParser.swift
│   ├── LoFiClient.swift
│   ├── QRZClient.swift
│   ├── POTAAuthService.swift
│   ├── POTAClient.swift
│   └── ICloudMonitor.swift
├── Views/
│   ├── Dashboard/
│   ├── Logs/
│   └── Settings/
├── Utilities/
│   ├── KeychainHelper.swift
│   └── Notifications.swift
└── Resources/
```

---

## Dependencies

None required—all achievable with Apple frameworks:
- **Networking:** URLSession (async/await)
- **Persistence:** SwiftData
- **Auth UI:** WKWebView
- **Keychain:** Security framework
- **iCloud:** NSMetadataQuery + FileManager

---

## Entitlements Required

- iCloud (Documents container)
- Keychain sharing (if needed across extensions)
- Background modes (background fetch)

---

## Open Questions

1. **LoFi API details:** Need to investigate Ham2K's LoFi sync API endpoints and authentication flow
2. **POTA upload endpoint:** Confirm exact API format for activation uploads
3. **App icon / branding:** Design TBD
