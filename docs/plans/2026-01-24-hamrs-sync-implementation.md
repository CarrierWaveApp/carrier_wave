# HAMRS Sync Implementation Plan

## Overview

Add read-only sync from HAMRS Pro to FullDuplex, importing QSOs logged in HAMRS. This follows existing patterns from QRZ, POTA, and LoFi integrations.

## Design Decisions

- **QSO Model**: Add new fields (`name`, `qth`, `state`, `country`, `power`, `sotaRef`, `theirParkReference`)
- **Park References**: Distinguish between `parkReference` (my activation) and `theirParkReference` (hunter contact)
- **ServicePresence**: Track HAMRS as a service for deduplication and display purposes
- **Read-only**: HAMRS does not support uploads

## Implementation Steps

### Phase 1: Foundation

#### Step 1.1: Add HAMRS to ServiceType and ImportSource
**File**: `FullDuplex/Models/Types.swift`

- Add `case hamrs` to `ServiceType` enum
- Add `displayName` for hamrs: "HAMRS"
- Set `supportsUpload` to `false` for hamrs
- Add `toImportSource` mapping for hamrs
- Add `case hamrs` to `ImportSource` enum

#### Step 1.2: Add Keychain Keys
**File**: `FullDuplex/Utilities/KeychainHelper.swift`

Add to `Keys` enum:
```swift
static let hamrsApiKey = "hamrs.api.key"
```

#### Step 1.3: Extend QSO Model
**File**: `FullDuplex/Models/QSO.swift`

Add optional fields:
- `name: String?` - Contact's name
- `qth: String?` - Contact's QTH/location
- `state: String?` - Contact's state
- `country: String?` - Contact's country
- `power: Int?` - TX power in watts
- `sotaRef: String?` - SOTA summit reference
- `theirParkReference: String?` - Their POTA park (hunter mode)

Update `init()` to accept new parameters.
Update `fieldRichnessScore` to include new fields.

#### Step 1.4: Update FetchedQSO
**File**: `FullDuplex/Services/SyncService.swift`

Add new fields to `FetchedQSO` struct:
- `name: String?`
- `qth: String?`
- `state: String?`
- `country: String?`
- `power: Int?`
- `sotaRef: String?`
- `theirParkReference: String?`

Update all `FetchedQSO` factory methods (`fromQRZ`, `fromPOTA`, `fromLoFi`) to pass `nil` for new fields.
Update `mergeFetchedGroup()` to merge new fields.
Update `createQSO()` to pass new fields.
Update `mergeIntoExisting()` to merge new fields.

---

### Phase 2: HAMRS Client

#### Step 2.1: Create HAMRSModels
**File**: `FullDuplex/Services/HAMRSModels.swift` (new)

Create Codable structs:

```swift
/// Auth response from /api/v1/couchdb_url
struct HAMRSAuthResponse: Codable {
    let subscribed: Bool
    let url: String?  // CouchDB URL with embedded credentials
}

/// HAMRS Logbook document
struct HAMRSLogbook: Codable {
    let _id: String
    let _rev: String?
    let title: String?
    let createdAt: String?
    let updatedAt: String?
    let template: String?
    let myPark: String?
    let myGridsquare: String?
    let `operator`: String?
}

/// HAMRS QSO document
struct HAMRSQSO: Codable {
    let _id: String
    let _rev: String?
    let createdAt: String?
    let call: String?
    let name: String?
    let qth: String?
    let state: String?
    let country: String?
    let gridsquare: String?
    let freq: Double?
    let band: String?
    let mode: String?
    let rstSent: String?
    let rstRcvd: String?
    let qsoDate: String?
    let timeOn: String?
    let qsoDateTime: String?
    let txPwr: Int?
    let potaRef: String?
    let sotaRef: String?
    let notes: String?
    
    var logbookId: String? { ... }
}

/// CouchDB response wrappers
struct CouchDBAllDocsResponse<T: Codable>: Codable { ... }
struct CouchDBRow<T: Codable>: Codable { ... }
```

#### Step 2.2: Create HAMRSError
**File**: `FullDuplex/Services/HAMRSError.swift` (new)

```swift
enum HAMRSError: Error, LocalizedError {
    case notConfigured
    case invalidApiKey
    case subscriptionInactive
    case networkError(Error)
    case invalidResponse(String)
    case decodingError(Error)
    
    var errorDescription: String? { ... }
}
```

#### Step 2.3: Create HAMRSClient
**File**: `FullDuplex/Services/HAMRSClient.swift` (new)

```swift
actor HAMRSClient {
    private let hamrsBaseURL = "https://hamrs.app"
    private let keychain = KeychainHelper.shared
    private var couchDBURL: URL?
    
    // MARK: - Configuration (nonisolated for UI)
    nonisolated var isConfigured: Bool { ... }
    
    // MARK: - Setup
    func configure(apiKey: String) async throws  // Validates then saves
    func clearCredentials()
    
    // MARK: - Internal Auth
    private func authenticate() async throws -> URL  // Gets CouchDB URL
    
    // MARK: - Fetch
    func fetchAllQSOs() async throws -> [(HAMRSQSO, HAMRSLogbook)]
    private func fetchLogbooks(from couchDBURL: URL) async throws -> [HAMRSLogbook]
    private func fetchQSOs(from couchDBURL: URL) async throws -> [HAMRSQSO]
}
```

Key behaviors:
- `configure()` validates API key via auth endpoint before saving
- If `subscribed: false`, throws `HAMRSError.subscriptionInactive`
- `fetchAllQSOs()` joins QSOs with their logbook's activation info
- Returns tuples for mapping

---

### Phase 3: SyncService Integration

#### Step 3.1: Add FetchedQSO.fromHAMRS()
**File**: `FullDuplex/Services/SyncService.swift`

Add static factory method:
```swift
static func fromHAMRS(_ qso: HAMRSQSO, logbook: HAMRSLogbook) -> FetchedQSO?
```

Mapping:
- Parse `qsoDateTime` (ISO 8601) or fall back to `qsoDate` + `timeOn`
- `freq` is already MHz (no conversion)
- `myPark` from logbook → `parkReference`
- `potaRef` from QSO → `theirParkReference`
- `myGridsquare` from logbook → `myGrid`
- `gridsquare` from QSO → `theirGrid`
- `operator` from logbook → `myCallsign`

#### Step 3.2: Add HAMRSClient to SyncService
**File**: `FullDuplex/Services/SyncService.swift`

- Add `private let hamrsClient: HAMRSClient` property
- Initialize in `init()`
- Add HAMRS download task in `downloadFromAllSources()`:
  ```swift
  if hamrsClient.isConfigured {
      group.addTask {
          // Similar pattern to LoFi
      }
  }
  ```

#### Step 3.3: Add syncHAMRS() Method
**File**: `FullDuplex/Services/SyncService.swift`

Add single-service sync method (download only, like LoFi):
```swift
func syncHAMRS() async throws -> Int
```

---

### Phase 4: Settings UI

#### Step 4.1: Create HAMRSSettingsView
**File**: `FullDuplex/Views/Settings/HAMRSSettingsView.swift` (new)

Follow LoFiSettingsView pattern:
- State: `apiKey`, `isConfigured`, `isValidating`, `showingError`, `errorMessage`
- If configured: show "Connected" status with logout button
- If not configured: show API key input with "Connect" button
- Link to hamrs.app for finding API key
- Handle subscription inactive error specially

#### Step 4.2: Add HAMRS to SettingsMainView
**File**: `FullDuplex/Views/Settings/SettingsView.swift`

Add NavigationLink in "Sync Sources" section:
```swift
NavigationLink {
    HAMRSSettingsView()
} label: {
    Label("HAMRS Pro", systemImage: "rectangle.stack")
}
```

---

### Phase 5: Testing

#### Step 5.1: Unit Tests for HAMRSModels
**File**: `FullDuplexTests/HAMRSModelsTests.swift` (new)

- Test `HAMRSQSO.logbookId` extraction
- Test Codable parsing of sample JSON responses
- Test timestamp parsing (ISO 8601 and fallback)

#### Step 5.2: Unit Tests for HAMRSClient
**File**: `FullDuplexTests/HAMRSClientTests.swift` (new)

- Test `isConfigured` states
- Test QSO-logbook joining logic
- Mock network responses for auth and fetch

#### Step 5.3: Integration Tests
**File**: `FullDuplexTests/SyncServiceTests.swift` (update)

- Test `FetchedQSO.fromHAMRS()` mapping
- Test deduplication with HAMRS-sourced QSOs
- Test ServicePresence creation for HAMRS

---

## File Summary

### New Files (6)
1. `FullDuplex/Services/HAMRSModels.swift`
2. `FullDuplex/Services/HAMRSError.swift`
3. `FullDuplex/Services/HAMRSClient.swift`
4. `FullDuplex/Views/Settings/HAMRSSettingsView.swift`
5. `FullDuplexTests/HAMRSModelsTests.swift`
6. `FullDuplexTests/HAMRSClientTests.swift`

### Modified Files (5)
1. `FullDuplex/Models/Types.swift` - Add hamrs cases
2. `FullDuplex/Utilities/KeychainHelper.swift` - Add hamrs key
3. `FullDuplex/Models/QSO.swift` - Add new fields
4. `FullDuplex/Services/SyncService.swift` - Add HAMRS integration
5. `FullDuplex/Views/Settings/SettingsView.swift` - Add HAMRS link

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| SwiftData migration with new QSO fields | New optional fields should auto-migrate; test on device with existing data |
| HAMRS API changes | CouchDB structure is stable; cache CouchDB URL to reduce auth calls |
| Subscription status changes mid-sync | Catch error, show warning, keep existing QSOs |
| Large logbook sync performance | Full sync every time (no incremental); acceptable for typical usage |

---

## Testing Checklist

- [ ] Configure with valid API key → saves, shows "Connected"
- [ ] Configure with invalid API key → shows error, doesn't save
- [ ] Configure with inactive subscription → shows error, doesn't save
- [ ] Sync imports QSOs with all fields populated
- [ ] Activation info (myPark, myGrid) comes from Logbook
- [ ] Hunter park (theirParkReference) populated from QSO.potaRef
- [ ] Duplicate QSOs deduplicated with existing logic
- [ ] HAMRS QSOs create ServicePresence records
- [ ] HAMRS QSOs trigger pending uploads to QRZ/POTA
- [ ] Subscription lapses after config → warning, QSOs retained
- [ ] Clear credentials removes API key, preserves QSOs
- [ ] New QSO fields (name, qth, state, country, power, sotaRef) populated
