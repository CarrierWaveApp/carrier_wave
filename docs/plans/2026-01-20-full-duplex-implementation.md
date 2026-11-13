# Full Duplex Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an iOS app that imports ham radio logs from LoFi/ADIF/iCloud and uploads to QRZ and POTA.app.

**Architecture:** SwiftUI + SwiftData app with service layer for API clients. WKWebView for POTA authentication. NSMetadataQuery for iCloud monitoring.

**Tech Stack:** Swift, SwiftUI, SwiftData, WebKit, Security framework (Keychain)

---

## Phase 1: Project Foundation

### Task 1: Create Xcode Project

**Step 1: Create the iOS app project**

Run from `/Users/jsvana/projects/FullDuplex`:
```bash
# Remove existing placeholder files if any, keep docs
mkdir -p /tmp/fullduplex-docs-backup
cp -r docs /tmp/fullduplex-docs-backup/

# We'll create the Xcode project manually since xcodebuild can't create new projects
# The user needs to: File > New > Project > iOS App
# Product Name: FullDuplex
# Organization Identifier: com.jsvana (or their preferred)
# Interface: SwiftUI
# Storage: SwiftData
# Include Tests: Yes
```

Note: Xcode project creation must be done via Xcode GUI. After creation, restore docs:
```bash
cp -r /tmp/fullduplex-docs-backup/docs .
```

**Step 2: Verify project structure exists**

After Xcode project creation, verify:
```
FullDuplex/
├── FullDuplex/
│   ├── FullDuplexApp.swift
│   ├── ContentView.swift
│   ├── Item.swift (SwiftData template - will replace)
│   └── Assets.xcassets/
├── FullDuplexTests/
├── FullDuplexUITests/
├── docs/
│   └── plans/
└── FullDuplex.xcodeproj/
```

**Step 3: Commit initial project**

```bash
# Add .gitignore for Xcode
cat > .gitignore << 'EOF'
# Xcode
*.xcodeproj/project.xcworkspace/
*.xcodeproj/xcuserdata/
*.xcworkspace/xcuserdata/
DerivedData/
*.hmap
*.ipa
*.dSYM.zip
*.dSYM

# Swift Package Manager
.build/
.swiftpm/

# CocoaPods (if used later)
Pods/

# Misc
.DS_Store
*.swp
*~
EOF

git add .
git commit -m "feat: initial Xcode project setup

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Create Directory Structure

**Files:**
- Create: `FullDuplex/Models/` directory
- Create: `FullDuplex/Services/` directory
- Create: `FullDuplex/Views/` directory
- Create: `FullDuplex/Utilities/` directory

**Step 1: Create directory structure**

In Xcode, create groups (which creates folders):
- Right-click FullDuplex folder > New Group > "Models"
- Right-click FullDuplex folder > New Group > "Services"
- Right-click FullDuplex folder > New Group > "Views"
- Right-click FullDuplex folder > New Group > "Utilities"

Or via terminal:
```bash
cd FullDuplex/FullDuplex
mkdir -p Models Services Views/Dashboard Views/Logs Views/Settings Utilities
```

**Step 2: Commit structure**

```bash
git add .
git commit -m "chore: add directory structure for models, services, views

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Phase 2: Data Models

### Task 3: Create Core Enums and Types

**Files:**
- Create: `FullDuplex/Models/Types.swift`
- Test: Manual compile check

**Step 1: Create Types.swift**

```swift
import Foundation

enum ImportSource: String, Codable {
    case lofi
    case adifFile
    case icloud
}

enum SyncStatus: String, Codable {
    case pending
    case uploaded
    case failed
}

enum DestinationType: String, Codable, CaseIterable {
    case qrz
    case pota

    var displayName: String {
        switch self {
        case .qrz: return "QRZ"
        case .pota: return "POTA"
        }
    }
}
```

**Step 2: Build to verify compilation**

Run: Cmd+B in Xcode
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add FullDuplex/Models/Types.swift
git commit -m "feat: add core enums for import source, sync status, destination type

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 4: Create QSO Model

**Files:**
- Create: `FullDuplex/Models/QSO.swift`
- Delete: `FullDuplex/Item.swift` (SwiftData template)

**Step 1: Delete template Item.swift**

Remove the auto-generated `Item.swift` file from Xcode.

**Step 2: Create QSO.swift**

```swift
import Foundation
import SwiftData

@Model
final class QSO {
    var id: UUID
    var callsign: String
    var band: String
    var mode: String
    var frequency: Double?
    var timestamp: Date
    var rstSent: String?
    var rstReceived: String?
    var myCallsign: String
    var myGrid: String?
    var theirGrid: String?
    var parkReference: String?
    var notes: String?
    var importSource: ImportSource
    var importedAt: Date
    var rawADIF: String?

    @Relationship(deleteRule: .cascade, inverse: \SyncRecord.qso)
    var syncRecords: [SyncRecord] = []

    init(
        id: UUID = UUID(),
        callsign: String,
        band: String,
        mode: String,
        frequency: Double? = nil,
        timestamp: Date,
        rstSent: String? = nil,
        rstReceived: String? = nil,
        myCallsign: String,
        myGrid: String? = nil,
        theirGrid: String? = nil,
        parkReference: String? = nil,
        notes: String? = nil,
        importSource: ImportSource,
        importedAt: Date = Date(),
        rawADIF: String? = nil
    ) {
        self.id = id
        self.callsign = callsign
        self.band = band
        self.mode = mode
        self.frequency = frequency
        self.timestamp = timestamp
        self.rstSent = rstSent
        self.rstReceived = rstReceived
        self.myCallsign = myCallsign
        self.myGrid = myGrid
        self.theirGrid = theirGrid
        self.parkReference = parkReference
        self.notes = notes
        self.importSource = importSource
        self.importedAt = importedAt
        self.rawADIF = rawADIF
    }

    /// Deduplication key: callsign + band + mode + timestamp (rounded to 2 min)
    var deduplicationKey: String {
        let roundedTimestamp = timestamp.timeIntervalSince1970
        let rounded = Int(roundedTimestamp / 120) * 120 // 2 minute buckets
        return "\(callsign.uppercased())|\(band.uppercased())|\(mode.uppercased())|\(rounded)"
    }
}
```

**Step 3: Build to verify**

Run: Cmd+B in Xcode
Expected: Build will fail (SyncRecord not defined yet - expected)

**Step 4: Commit partial progress**

```bash
git add FullDuplex/Models/QSO.swift
git rm FullDuplex/Item.swift 2>/dev/null || true
git commit -m "feat: add QSO SwiftData model with deduplication key

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 5: Create SyncRecord Model

**Files:**
- Create: `FullDuplex/Models/SyncRecord.swift`

**Step 1: Create SyncRecord.swift**

```swift
import Foundation
import SwiftData

@Model
final class SyncRecord {
    var id: UUID
    var destinationType: DestinationType
    var status: SyncStatus
    var uploadedAt: Date?
    var errorMessage: String?

    var qso: QSO?

    init(
        id: UUID = UUID(),
        destinationType: DestinationType,
        status: SyncStatus = .pending,
        uploadedAt: Date? = nil,
        errorMessage: String? = nil,
        qso: QSO? = nil
    ) {
        self.id = id
        self.destinationType = destinationType
        self.status = status
        self.uploadedAt = uploadedAt
        self.errorMessage = errorMessage
        self.qso = qso
    }
}
```

**Step 2: Build to verify**

Run: Cmd+B in Xcode
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add FullDuplex/Models/SyncRecord.swift
git commit -m "feat: add SyncRecord model for tracking per-destination upload status

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 6: Create UploadDestination Model

**Files:**
- Create: `FullDuplex/Models/UploadDestination.swift`

**Step 1: Create UploadDestination.swift**

```swift
import Foundation
import SwiftData

@Model
final class UploadDestination {
    var id: UUID
    var type: DestinationType
    var isEnabled: Bool
    var lastSyncAt: Date?

    init(
        id: UUID = UUID(),
        type: DestinationType,
        isEnabled: Bool = false,
        lastSyncAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.isEnabled = isEnabled
        self.lastSyncAt = lastSyncAt
    }
}

// Note: Credentials (API keys, tokens) stored in Keychain, not SwiftData
```

**Step 2: Build to verify**

Run: Cmd+B in Xcode
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add FullDuplex/Models/UploadDestination.swift
git commit -m "feat: add UploadDestination model for service configuration

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 7: Update App Entry Point with SwiftData Schema

**Files:**
- Modify: `FullDuplex/FullDuplexApp.swift`

**Step 1: Update FullDuplexApp.swift**

```swift
import SwiftUI
import SwiftData

@main
struct FullDuplexApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            QSO.self,
            SyncRecord.self,
            UploadDestination.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
```

**Step 2: Build to verify**

Run: Cmd+B in Xcode
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add FullDuplex/FullDuplexApp.swift
git commit -m "feat: configure SwiftData schema with QSO, SyncRecord, UploadDestination

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Phase 3: Utilities

### Task 8: Create Keychain Helper

**Files:**
- Create: `FullDuplex/Utilities/KeychainHelper.swift`

**Step 1: Create KeychainHelper.swift**

```swift
import Foundation
import Security

enum KeychainError: Error {
    case duplicateItem
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidData
}

struct KeychainHelper {
    static let shared = KeychainHelper()

    private let service = "com.fullduplex.credentials"

    private init() {}

    func save(_ data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func save(_ string: String, for key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try save(data, for: key)
    }

    func read(for key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        return data
    }

    func readString(for key: String) throws -> String {
        let data = try read(for: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }

    func delete(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

// Keychain keys for each service
extension KeychainHelper {
    enum Keys {
        static let qrzSessionKey = "qrz.session.key"
        static let qrzUsername = "qrz.username"
        static let potaIdToken = "pota.id.token"
        static let potaTokenExpiry = "pota.token.expiry"
        static let lofiAuthToken = "lofi.auth.token"
    }
}
```

**Step 2: Build to verify**

Run: Cmd+B in Xcode
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add FullDuplex/Utilities/KeychainHelper.swift
git commit -m "feat: add KeychainHelper for secure credential storage

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Phase 4: ADIF Parser Service

### Task 9: Create ADIF Record Struct

**Files:**
- Create: `FullDuplex/Services/ADIFParser.swift`
- Test: `FullDuplexTests/ADIFParserTests.swift`

**Step 1: Write failing test**

Create `FullDuplexTests/ADIFParserTests.swift`:

```swift
import XCTest
@testable import FullDuplex

final class ADIFParserTests: XCTestCase {

    func testParseSimpleRecord() throws {
        let adif = "<call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 <eor>"

        let parser = ADIFParser()
        let records = try parser.parse(adif)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].callsign, "W1AW")
        XCTAssertEqual(records[0].band, "20m")
        XCTAssertEqual(records[0].mode, "CW")
    }
}
```

**Step 2: Run test to verify it fails**

Run: Cmd+U in Xcode or `xcodebuild test -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 15'`
Expected: FAIL - ADIFParser not defined

**Step 3: Create ADIFParser.swift with minimal implementation**

```swift
import Foundation

struct ADIFRecord {
    var callsign: String
    var band: String
    var mode: String
    var frequency: Double?
    var qsoDate: String?       // YYYYMMDD
    var timeOn: String?        // HHMM or HHMMSS
    var rstSent: String?
    var rstReceived: String?
    var myCallsign: String?
    var myGridsquare: String?
    var gridsquare: String?    // Their grid
    var sigInfo: String?       // Park reference for POTA
    var comment: String?
    var rawADIF: String

    var timestamp: Date? {
        guard let dateStr = qsoDate else { return nil }
        let timeStr = timeOn ?? "0000"

        let formatter = DateFormatter()
        formatter.dateFormat = timeStr.count == 6 ? "yyyyMMddHHmmss" : "yyyyMMddHHmm"
        formatter.timeZone = TimeZone(identifier: "UTC")

        return formatter.date(from: dateStr + timeStr)
    }
}

struct ADIFParser {

    func parse(_ content: String) throws -> [ADIFRecord] {
        var records: [ADIFRecord] = []

        // Find header end if present
        let workingContent: String
        if let headerEnd = content.range(of: "<eoh>", options: .caseInsensitive) {
            workingContent = String(content[headerEnd.upperBound...])
        } else {
            workingContent = content
        }

        // Split by <eor> (end of record)
        let rawRecords = workingContent.components(separatedBy: RegexPattern.eor)

        for rawRecord in rawRecords {
            let trimmed = rawRecord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let fields = parseFields(from: trimmed)
            guard let callsign = fields["call"],
                  let band = fields["band"],
                  let mode = fields["mode"] else {
                continue // Skip records missing required fields
            }

            let record = ADIFRecord(
                callsign: callsign.uppercased(),
                band: band.lowercased(),
                mode: mode.uppercased(),
                frequency: fields["freq"].flatMap { Double($0) },
                qsoDate: fields["qso_date"],
                timeOn: fields["time_on"],
                rstSent: fields["rst_sent"],
                rstReceived: fields["rst_rcvd"],
                myCallsign: fields["station_callsign"] ?? fields["operator"],
                myGridsquare: fields["my_gridsquare"],
                gridsquare: fields["gridsquare"],
                sigInfo: fields["sig_info"] ?? fields["pota_ref"],
                comment: fields["comment"] ?? fields["notes"],
                rawADIF: "<" + trimmed + "<eor>"
            )

            records.append(record)
        }

        return records
    }

    private func parseFields(from record: String) -> [String: String] {
        var fields: [String: String] = [:]

        // Pattern: <fieldname:length>value or <fieldname:length:type>value
        let pattern = #"<(\w+):(\d+)(?::\w)?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return fields
        }

        let nsString = record as NSString
        let matches = regex.matches(in: record, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }

            let fieldName = nsString.substring(with: match.range(at: 1)).lowercased()
            let lengthStr = nsString.substring(with: match.range(at: 2))
            guard let length = Int(lengthStr) else { continue }

            let valueStart = match.range.location + match.range.length
            guard valueStart + length <= nsString.length else { continue }

            let value = nsString.substring(with: NSRange(location: valueStart, length: length))
            fields[fieldName] = value.trimmingCharacters(in: .whitespaces)
        }

        return fields
    }
}

private enum RegexPattern {
    static let eor = try! NSRegularExpression(pattern: "<eor>", options: .caseInsensitive)
        .pattern
        .replacingOccurrences(of: "\\", with: "")
}

extension String {
    func components(separatedBy regex: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: regex, options: .caseInsensitive) else {
            return [self]
        }
        let nsString = self as NSString
        let results = re.matches(in: self, range: NSRange(location: 0, length: nsString.length))

        var parts: [String] = []
        var lastEnd = 0

        for result in results {
            let range = NSRange(location: lastEnd, length: result.range.location - lastEnd)
            parts.append(nsString.substring(with: range))
            lastEnd = result.range.location + result.range.length
        }

        // Add remaining
        if lastEnd < nsString.length {
            parts.append(nsString.substring(from: lastEnd))
        }

        return parts
    }
}
```

**Step 4: Run test to verify it passes**

Run: Cmd+U in Xcode
Expected: PASS

**Step 5: Commit**

```bash
git add FullDuplex/Services/ADIFParser.swift FullDuplexTests/ADIFParserTests.swift
git commit -m "feat: add ADIF parser with basic field extraction

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 10: Add More ADIF Parser Tests

**Files:**
- Modify: `FullDuplexTests/ADIFParserTests.swift`

**Step 1: Add additional tests**

```swift
// Add to ADIFParserTests.swift

func testParseMultipleRecords() throws {
    let adif = """
    <call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 <eor>
    <call:5>K3LR <band:3>40m <mode:3>SSB <qso_date:8>20240115 <time_on:4>1445 <eor>
    """

    let parser = ADIFParser()
    let records = try parser.parse(adif)

    XCTAssertEqual(records.count, 2)
    XCTAssertEqual(records[0].callsign, "W1AW")
    XCTAssertEqual(records[1].callsign, "K3LR")
    XCTAssertEqual(records[1].mode, "SSB")
}

func testParseWithHeader() throws {
    let adif = """
    Generated by Test App
    <adif_ver:5>3.1.4
    <programid:8>TestApp
    <eoh>
    <call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 <eor>
    """

    let parser = ADIFParser()
    let records = try parser.parse(adif)

    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records[0].callsign, "W1AW")
}

func testParseTimestamp() throws {
    let adif = "<call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 <eor>"

    let parser = ADIFParser()
    let records = try parser.parse(adif)

    XCTAssertNotNil(records[0].timestamp)

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "UTC")

    XCTAssertEqual(formatter.string(from: records[0].timestamp!), "2024-01-15 14:30")
}

func testParsePOTAFields() throws {
    let adif = "<call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 <sig_info:6>K-1234 <my_gridsquare:6>FN31pr <eor>"

    let parser = ADIFParser()
    let records = try parser.parse(adif)

    XCTAssertEqual(records[0].sigInfo, "K-1234")
    XCTAssertEqual(records[0].myGridsquare, "FN31pr")
}

func testSkipsInvalidRecords() throws {
    let adif = """
    <call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <eor>
    <band:3>40m <mode:3>SSB <eor>
    <call:5>K3LR <band:3>40m <mode:3>SSB <eor>
    """

    let parser = ADIFParser()
    let records = try parser.parse(adif)

    // Second record missing callsign, should be skipped
    XCTAssertEqual(records.count, 2)
    XCTAssertEqual(records[0].callsign, "W1AW")
    XCTAssertEqual(records[1].callsign, "K3LR")
}
```

**Step 2: Run tests**

Run: Cmd+U
Expected: All PASS

**Step 3: Commit**

```bash
git add FullDuplexTests/ADIFParserTests.swift
git commit -m "test: add comprehensive ADIF parser tests

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Phase 5: QRZ Client

### Task 11: Create QRZ Client

**Files:**
- Create: `FullDuplex/Services/QRZClient.swift`
- Test: `FullDuplexTests/QRZClientTests.swift`

**Step 1: Write failing test**

Create `FullDuplexTests/QRZClientTests.swift`:

```swift
import XCTest
@testable import FullDuplex

final class QRZClientTests: XCTestCase {

    func testParseLoginResponse() throws {
        let response = "RESULT=OK&KEY=abc123&COUNT=1"

        let result = QRZClient.parseResponse(response)

        XCTAssertEqual(result["RESULT"], "OK")
        XCTAssertEqual(result["KEY"], "abc123")
    }

    func testParseErrorResponse() throws {
        let response = "RESULT=FAIL&REASON=Invalid credentials"

        let result = QRZClient.parseResponse(response)

        XCTAssertEqual(result["RESULT"], "FAIL")
        XCTAssertEqual(result["REASON"], "Invalid credentials")
    }
}
```

**Step 2: Run test to verify it fails**

Run: Cmd+U
Expected: FAIL - QRZClient not defined

**Step 3: Create QRZClient.swift**

```swift
import Foundation

enum QRZError: Error, LocalizedError {
    case invalidCredentials
    case sessionExpired
    case uploadFailed(String)
    case networkError(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid QRZ username or password"
        case .sessionExpired:
            return "QRZ session expired, please re-authenticate"
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from QRZ"
        }
    }
}

actor QRZClient {
    private let baseURL = "https://logbook.qrz.com/api"
    private let keychain = KeychainHelper.shared

    static func parseResponse(_ response: String) -> [String: String] {
        var result: [String: String] = [:]
        let pairs = response.components(separatedBy: "&")

        for pair in pairs {
            let parts = pair.components(separatedBy: "=")
            if parts.count == 2 {
                result[parts[0]] = parts[1]
            } else if parts.count > 2 {
                // Handle values containing "="
                result[parts[0]] = parts.dropFirst().joined(separator: "=")
            }
        }

        return result
    }

    func authenticate(username: String, password: String) async throws -> String {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "ACTION", value: "LOGIN"),
            URLQueryItem(name: "USERNAME", value: username),
            URLQueryItem(name: "PASSWORD", value: password)
        ]

        guard let url = components.url else {
            throw QRZError.invalidResponse
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw QRZError.invalidResponse
        }

        let parsed = Self.parseResponse(responseString)

        guard parsed["RESULT"] == "OK", let key = parsed["KEY"] else {
            throw QRZError.invalidCredentials
        }

        // Store credentials
        try keychain.save(key, for: KeychainHelper.Keys.qrzSessionKey)
        try keychain.save(username, for: KeychainHelper.Keys.qrzUsername)

        return key
    }

    func getSessionKey() throws -> String {
        try keychain.readString(for: KeychainHelper.Keys.qrzSessionKey)
    }

    func uploadQSOs(_ qsos: [QSO]) async throws -> (uploaded: Int, duplicates: Int) {
        let sessionKey = try getSessionKey()

        // Convert QSOs to ADIF
        let adifContent = qsos.map { qso in
            qso.rawADIF ?? generateADIF(for: qso)
        }.joined(separator: "\n")

        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "ACTION", value: "INSERT"),
            URLQueryItem(name: "KEY", value: sessionKey),
            URLQueryItem(name: "ADIF", value: adifContent)
        ]

        guard let url = components.url else {
            throw QRZError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw QRZError.invalidResponse
        }

        let parsed = Self.parseResponse(responseString)

        if parsed["RESULT"] == "AUTH" {
            throw QRZError.sessionExpired
        }

        guard parsed["RESULT"] == "OK" else {
            throw QRZError.uploadFailed(parsed["REASON"] ?? "Unknown error")
        }

        let count = Int(parsed["COUNT"] ?? "0") ?? 0
        let dupes = Int(parsed["DUPES"] ?? "0") ?? 0

        return (uploaded: count, duplicates: dupes)
    }

    private func generateADIF(for qso: QSO) -> String {
        var fields: [String] = []

        func addField(_ name: String, _ value: String?) {
            guard let value = value, !value.isEmpty else { return }
            fields.append("<\(name):\(value.count)>\(value)")
        }

        addField("call", qso.callsign)
        addField("band", qso.band)
        addField("mode", qso.mode)

        if let freq = qso.frequency {
            addField("freq", String(format: "%.4f", freq / 1000)) // kHz to MHz
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        addField("qso_date", dateFormatter.string(from: qso.timestamp))

        dateFormatter.dateFormat = "HHmm"
        addField("time_on", dateFormatter.string(from: qso.timestamp))

        addField("rst_sent", qso.rstSent)
        addField("rst_rcvd", qso.rstReceived)
        addField("station_callsign", qso.myCallsign)
        addField("my_gridsquare", qso.myGrid)
        addField("gridsquare", qso.theirGrid)
        addField("sig_info", qso.parkReference)
        addField("comment", qso.notes)

        return fields.joined(separator: " ") + " <eor>"
    }

    func logout() {
        try? keychain.delete(for: KeychainHelper.Keys.qrzSessionKey)
    }
}
```

**Step 4: Run tests**

Run: Cmd+U
Expected: PASS

**Step 5: Commit**

```bash
git add FullDuplex/Services/QRZClient.swift FullDuplexTests/QRZClientTests.swift
git commit -m "feat: add QRZ client for authentication and log upload

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Phase 6: POTA Authentication

### Task 12: Create POTA Auth Service

**Files:**
- Create: `FullDuplex/Services/POTAAuthService.swift`

**Step 1: Create POTAAuthService.swift**

```swift
import Foundation
import WebKit
import SwiftUI

enum POTAAuthError: Error, LocalizedError {
    case tokenExtractionFailed
    case authenticationCancelled
    case networkError(Error)
    case tokenExpired

    var errorDescription: String? {
        switch self {
        case .tokenExtractionFailed:
            return "Failed to extract authentication token from POTA"
        case .authenticationCancelled:
            return "Authentication was cancelled"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .tokenExpired:
            return "POTA token has expired, please re-authenticate"
        }
    }
}

struct POTAToken: Codable {
    let idToken: String
    let expiresAt: Date
    let callsign: String?

    var isExpired: Bool {
        Date() >= expiresAt
    }

    func isExpiringSoon(buffer: TimeInterval = 300) -> Bool {
        Date().addingTimeInterval(buffer) >= expiresAt
    }
}

@MainActor
class POTAAuthService: NSObject, ObservableObject {
    @Published var isAuthenticating = false
    @Published var currentToken: POTAToken?

    private let keychain = KeychainHelper.shared
    private var webView: WKWebView?
    private var authContinuation: CheckedContinuation<POTAToken, Error>?

    private let potaAppURL = "https://pota.app"

    // JavaScript to extract token from cookies/localStorage
    private let extractTokenJS = """
    (function() {
        // Check cookies first
        const cookies = document.cookie.split(';');
        for (const cookie of cookies) {
            const trimmed = cookie.trim();
            if (trimmed.includes('idToken=')) {
                const eqIdx = trimmed.indexOf('=');
                if (eqIdx > 0) {
                    const val = trimmed.substring(eqIdx + 1);
                    if (val && val.startsWith('eyJ')) {
                        return val;
                    }
                }
            }
        }

        // Try localStorage
        for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i);
            if (key && key.includes('idToken')) {
                const val = localStorage.getItem(key);
                if (val && val.startsWith('eyJ')) {
                    return val;
                }
            }
        }

        // Check sessionStorage
        for (let i = 0; i < sessionStorage.length; i++) {
            const key = sessionStorage.key(i);
            if (key && key.includes('idToken')) {
                const val = sessionStorage.getItem(key);
                if (val && val.startsWith('eyJ')) {
                    return val;
                }
            }
        }

        // Try Amplify auth data
        for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i);
            if (key && (key.includes('amplify') || key.includes('Cognito') || key.includes('auth'))) {
                try {
                    const val = localStorage.getItem(key);
                    const parsed = JSON.parse(val);
                    if (parsed && parsed.idToken) {
                        return parsed.idToken;
                    }
                    if (parsed && parsed.signInUserSession && parsed.signInUserSession.idToken) {
                        return parsed.signInUserSession.idToken.jwtToken;
                    }
                } catch (e) {}
            }
        }

        return null;
    })()
    """

    override init() {
        super.init()
        loadStoredToken()
    }

    func loadStoredToken() {
        do {
            let tokenData = try keychain.read(for: KeychainHelper.Keys.potaIdToken)
            let token = try JSONDecoder().decode(POTAToken.self, from: tokenData)
            if !token.isExpired {
                currentToken = token
            }
        } catch {
            // No stored token or expired
            currentToken = nil
        }
    }

    func authenticate() async throws -> POTAToken {
        // Check if we have a valid token
        if let token = currentToken, !token.isExpiringSoon() {
            return token
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        return try await withCheckedThrowingContinuation { continuation in
            self.authContinuation = continuation
            self.setupWebView()
        }
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent() // Don't persist between sessions

        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self

        guard let url = URL(string: "\(potaAppURL)/#/login") else {
            authContinuation?.resume(throwing: POTAAuthError.tokenExtractionFailed)
            return
        }

        webView?.load(URLRequest(url: url))
    }

    func getWebView() -> WKWebView? {
        return webView
    }

    func cancelAuthentication() {
        authContinuation?.resume(throwing: POTAAuthError.authenticationCancelled)
        authContinuation = nil
        webView = nil
    }

    private func extractToken() async throws -> POTAToken {
        guard let webView = webView else {
            throw POTAAuthError.tokenExtractionFailed
        }

        // Try multiple times with delay
        for _ in 0..<5 {
            if let token = try await webView.evaluateJavaScript(extractTokenJS) as? String,
               !token.isEmpty {
                let potaToken = try decodeToken(token)
                try saveToken(potaToken)
                currentToken = potaToken
                return potaToken
            }
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }

        throw POTAAuthError.tokenExtractionFailed
    }

    private func decodeToken(_ jwt: String) throws -> POTAToken {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count >= 2 else {
            throw POTAAuthError.tokenExtractionFailed
        }

        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw POTAAuthError.tokenExtractionFailed
        }

        let exp = claims["exp"] as? TimeInterval ?? (Date().timeIntervalSince1970 + 3600)
        let callsign = claims["pota:callsign"] as? String

        return POTAToken(
            idToken: jwt,
            expiresAt: Date(timeIntervalSince1970: exp),
            callsign: callsign
        )
    }

    private func saveToken(_ token: POTAToken) throws {
        let data = try JSONEncoder().encode(token)
        try keychain.save(data, for: KeychainHelper.Keys.potaIdToken)
    }

    func logout() {
        try? keychain.delete(for: KeychainHelper.Keys.potaIdToken)
        currentToken = nil
        webView = nil
    }

    func ensureValidToken() async throws -> String {
        if let token = currentToken, !token.isExpiringSoon() {
            return token.idToken
        }

        let newToken = try await authenticate()
        return newToken.idToken
    }
}

extension POTAAuthService: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard let url = webView.url?.absoluteString else { return }

            // Check if we've returned to POTA after Cognito auth
            if url.contains("pota.app") && !url.contains("cognito") && !url.contains("login") {
                do {
                    let token = try await extractToken()
                    authContinuation?.resume(returning: token)
                    authContinuation = nil
                    self.webView = nil
                } catch {
                    // Keep waiting, user might not be fully logged in yet
                }
            }
        }
    }
}
```

**Step 2: Build to verify**

Run: Cmd+B
Expected: Build Succeeded

**Step 3: Commit**

```swift
git add FullDuplex/Services/POTAAuthService.swift
git commit -m "feat: add POTA auth service with WKWebView Cognito flow

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 13: Create POTA Auth Web View

**Files:**
- Create: `FullDuplex/Views/Settings/POTAAuthWebView.swift`

**Step 1: Create POTAAuthWebView.swift**

```swift
import SwiftUI
import WebKit

struct POTAAuthWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No updates needed
    }
}

struct POTALoginSheet: View {
    @ObservedObject var authService: POTAAuthService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let webView = authService.getWebView() {
                    POTAAuthWebView(webView: webView)
                } else {
                    ProgressView("Loading...")
                }
            }
            .navigationTitle("POTA Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        authService.cancelAuthentication()
                        dismiss()
                    }
                }
            }
        }
    }
}
```

**Step 2: Build to verify**

Run: Cmd+B
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add FullDuplex/Views/Settings/POTAAuthWebView.swift
git commit -m "feat: add POTA login web view sheet

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Phase 7: POTA Upload Client

### Task 14: Create POTA Client

**Files:**
- Create: `FullDuplex/Services/POTAClient.swift`

**Step 1: Create POTAClient.swift**

```swift
import Foundation

enum POTAError: Error, LocalizedError {
    case notAuthenticated
    case uploadFailed(String)
    case invalidParkReference
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with POTA"
        case .uploadFailed(let reason):
            return "POTA upload failed: \(reason)"
        case .invalidParkReference:
            return "Invalid park reference format"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

struct POTAUploadResult {
    let success: Bool
    let qsosAccepted: Int
    let message: String?
}

actor POTAClient {
    private let baseURL = "https://api.pota.app"
    private let authService: POTAAuthService

    init(authService: POTAAuthService) {
        self.authService = authService
    }

    func uploadActivation(parkReference: String, qsos: [QSO]) async throws -> POTAUploadResult {
        // Validate park reference format (e.g., "K-1234", "VE-1234")
        let parkPattern = #"^[A-Z]{1,2}-\d{4,5}$"#
        guard parkReference.range(of: parkPattern, options: .regularExpression) != nil else {
            throw POTAError.invalidParkReference
        }

        // Get valid token
        let token = try await MainActor.run {
            try await authService.ensureValidToken()
        }

        // Filter QSOs for this park
        let parkQSOs = qsos.filter { $0.parkReference == parkReference }
        guard !parkQSOs.isEmpty else {
            return POTAUploadResult(success: true, qsosAccepted: 0, message: "No QSOs for this park")
        }

        // Generate ADIF content
        let adifContent = generateADIF(for: parkQSOs, parkReference: parkReference)

        // Create multipart form data
        let boundary = UUID().uuidString
        var body = Data()

        // Add ADIF file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"activation.adi\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(adifContent.data(using: .utf8)!)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        // Create request
        guard let url = URL(string: "\(baseURL)/activation") else {
            throw POTAError.uploadFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw POTAError.uploadFailed("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200...299:
            // Parse success response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let count = json["qsosAccepted"] as? Int ?? parkQSOs.count
                let message = json["message"] as? String
                return POTAUploadResult(success: true, qsosAccepted: count, message: message)
            }
            return POTAUploadResult(success: true, qsosAccepted: parkQSOs.count, message: nil)

        case 401:
            throw POTAError.notAuthenticated

        case 400...499:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Client error"
            throw POTAError.uploadFailed(errorMessage)

        default:
            throw POTAError.uploadFailed("Server error: \(httpResponse.statusCode)")
        }
    }

    private func generateADIF(for qsos: [QSO], parkReference: String) -> String {
        var lines: [String] = []

        // Header
        lines.append("ADIF Export for POTA")
        lines.append("<adif_ver:5>3.1.4")
        lines.append("<programid:10>FullDuplex")
        lines.append("<eoh>")
        lines.append("")

        // Records
        for qso in qsos {
            var fields: [String] = []

            func addField(_ name: String, _ value: String?) {
                guard let value = value, !value.isEmpty else { return }
                fields.append("<\(name):\(value.count)>\(value)")
            }

            addField("call", qso.callsign)
            addField("band", qso.band)
            addField("mode", qso.mode)

            if let freq = qso.frequency {
                addField("freq", String(format: "%.4f", freq / 1000))
            }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd"
            dateFormatter.timeZone = TimeZone(identifier: "UTC")
            addField("qso_date", dateFormatter.string(from: qso.timestamp))

            dateFormatter.dateFormat = "HHmm"
            addField("time_on", dateFormatter.string(from: qso.timestamp))

            addField("rst_sent", qso.rstSent)
            addField("rst_rcvd", qso.rstReceived)
            addField("station_callsign", qso.myCallsign)
            addField("my_gridsquare", qso.myGrid)
            addField("gridsquare", qso.theirGrid)
            addField("my_sig", "POTA")
            addField("my_sig_info", parkReference)
            addField("comment", qso.notes)

            lines.append(fields.joined(separator: " ") + " <eor>")
        }

        return lines.joined(separator: "\n")
    }

    /// Get all unique park references from QSOs
    static func groupQSOsByPark(_ qsos: [QSO]) -> [String: [QSO]] {
        Dictionary(grouping: qsos.filter { $0.parkReference != nil }) { $0.parkReference! }
    }
}
```

**Step 2: Build to verify**

Run: Cmd+B
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add FullDuplex/Services/POTAClient.swift
git commit -m "feat: add POTA client for activation uploads

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Phase 8: iCloud Monitoring

### Task 15: Create iCloud Monitor

**Files:**
- Create: `FullDuplex/Services/ICloudMonitor.swift`

**Step 1: Create ICloudMonitor.swift**

```swift
import Foundation
import UserNotifications

@MainActor
class ICloudMonitor: ObservableObject {
    @Published var pendingFiles: [URL] = []
    @Published var isMonitoring = false

    private var metadataQuery: NSMetadataQuery?
    private let fileManager = FileManager.default

    var iCloudContainerURL: URL? {
        fileManager.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            .appendingPathComponent("Import")
    }

    init() {
        setupNotifications()
    }

    private func setupNotifications() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()

            if settings.authorizationStatus == .notDetermined {
                try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
        }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        guard iCloudContainerURL != nil else {
            print("iCloud not available")
            return
        }

        metadataQuery = NSMetadataQuery()
        metadataQuery?.predicate = NSPredicate(format: "%K LIKE[c] '*.adi' OR %K LIKE[c] '*.adif'",
                                                NSMetadataItemFSNameKey, NSMetadataItemFSNameKey)
        metadataQuery?.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate),
            name: .NSMetadataQueryDidUpdate,
            object: metadataQuery
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidFinishGathering),
            name: .NSMetadataQueryDidFinishGathering,
            object: metadataQuery
        )

        metadataQuery?.start()
        isMonitoring = true
    }

    func stopMonitoring() {
        metadataQuery?.stop()
        metadataQuery = nil
        isMonitoring = false
    }

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        processQueryResults()
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        processQueryResults()
    }

    private func processQueryResults() {
        guard let query = metadataQuery else { return }

        query.disableUpdates()
        defer { query.enableUpdates() }

        var newFiles: [URL] = []

        for item in query.results {
            guard let metadataItem = item as? NSMetadataItem,
                  let url = metadataItem.value(forAttribute: NSMetadataItemURLKey) as? URL else {
                continue
            }

            // Check if file is downloaded
            let downloadStatus = metadataItem.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String

            if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                // File is downloaded and ready
                if !pendingFiles.contains(url) {
                    newFiles.append(url)
                }
            } else if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded {
                // Trigger download
                try? fileManager.startDownloadingUbiquitousItem(at: url)
            }
        }

        if !newFiles.isEmpty {
            pendingFiles.append(contentsOf: newFiles)
            scheduleNotification(for: newFiles)
        }
    }

    private func scheduleNotification(for files: [URL]) {
        let content = UNMutableNotificationContent()

        if files.count == 1 {
            content.title = "New Log File"
            content.body = "Tap to import: \(files[0].lastPathComponent)"
        } else {
            content.title = "New Log Files"
            content.body = "\(files.count) ADIF files ready to import"
        }

        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
    }

    func markFileAsProcessed(_ url: URL) {
        pendingFiles.removeAll { $0 == url }

        // Optionally move to Processed folder
        guard let containerURL = iCloudContainerURL else { return }
        let processedURL = containerURL
            .deletingLastPathComponent()
            .appendingPathComponent("Processed")

        try? fileManager.createDirectory(at: processedURL, withIntermediateDirectories: true)

        let destination = processedURL.appendingPathComponent(url.lastPathComponent)
        try? fileManager.moveItem(at: url, to: destination)
    }

    func createImportFolderIfNeeded() {
        guard let url = iCloudContainerURL else { return }
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
```

**Step 2: Build to verify**

Run: Cmd+B
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add FullDuplex/Services/ICloudMonitor.swift
git commit -m "feat: add iCloud monitor for watching ADIF files

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Phase 9: Basic UI Views

### Task 16: Create Dashboard View

**Files:**
- Create: `FullDuplex/Views/Dashboard/DashboardView.swift`
- Modify: `FullDuplex/ContentView.swift`

**Step 1: Create DashboardView.swift**

```swift
import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var qsos: [QSO]
    @Query(filter: #Predicate<SyncRecord> { $0.status == .pending })
    private var pendingSyncs: [SyncRecord]

    @ObservedObject var iCloudMonitor: ICloudMonitor

    @State private var isSyncing = false
    @State private var lastSyncDate: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Summary Card
                    summaryCard

                    // Destination Status Cards
                    HStack(spacing: 12) {
                        destinationCard(for: .qrz)
                        destinationCard(for: .pota)
                    }

                    // Recent Imports
                    recentImportsCard

                    // iCloud Pending Files
                    if !iCloudMonitor.pendingFiles.isEmpty {
                        pendingFilesCard
                    }
                }
                .padding()
            }
            .navigationTitle("Full Duplex")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await performSync() }
                    } label: {
                        if isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isSyncing)
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.headline)

            HStack {
                Label("\(qsos.count) QSOs", systemImage: "antenna.radiowaves.left.and.right")
                Spacer()
                if let lastSync = lastSyncDate {
                    Text("Last sync: \(lastSync, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func destinationCard(for type: DestinationType) -> some View {
        let totalForDest = qsos.count
        let pending = pendingSyncs.filter { $0.destinationType == type }.count
        let synced = totalForDest - pending

        return VStack(alignment: .leading, spacing: 8) {
            Text(type.displayName)
                .font(.headline)

            if pending > 0 {
                Label("\(synced)/\(totalForDest)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("\(pending) pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("\(synced)/\(totalForDest)", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Text("Synced")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var recentImportsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Imports")
                .font(.headline)

            let recentQSOs = Array(qsos.sorted { $0.importedAt > $1.importedAt }.prefix(5))

            if recentQSOs.isEmpty {
                Text("No logs imported yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentQSOs) { qso in
                    HStack {
                        Text(qso.callsign)
                            .fontWeight(.medium)
                        Spacer()
                        Text(qso.band)
                            .foregroundStyle(.secondary)
                        Text(qso.importedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var pendingFilesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(iCloudMonitor.pendingFiles.count) new file(s) in iCloud",
                  systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.orange)

            ForEach(iCloudMonitor.pendingFiles, id: \.self) { url in
                HStack {
                    Text(url.lastPathComponent)
                    Spacer()
                    Button("Import") {
                        // TODO: Trigger import
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func performSync() async {
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        // TODO: Implement actual sync logic
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
}
```

**Step 2: Update ContentView.swift**

```swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var iCloudMonitor = ICloudMonitor()

    var body: some View {
        TabView {
            DashboardView(iCloudMonitor: iCloudMonitor)
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                }

            LogsView()
                .tabItem {
                    Label("Logs", systemImage: "list.bullet")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .onAppear {
            iCloudMonitor.startMonitoring()
        }
    }
}

// Placeholder views
struct LogsView: View {
    var body: some View {
        NavigationStack {
            Text("Logs")
                .navigationTitle("Logs")
        }
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Text("Settings")
                .navigationTitle("Settings")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [QSO.self, SyncRecord.self, UploadDestination.self], inMemory: true)
}
```

**Step 3: Build to verify**

Run: Cmd+B
Expected: Build Succeeded

**Step 4: Commit**

```bash
git add FullDuplex/Views/Dashboard/DashboardView.swift FullDuplex/ContentView.swift
git commit -m "feat: add dashboard view with sync status and recent imports

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 17: Create Logs List View

**Files:**
- Create: `FullDuplex/Views/Logs/LogsListView.swift`
- Modify: `FullDuplex/ContentView.swift`

**Step 1: Create LogsListView.swift**

```swift
import SwiftUI
import SwiftData

struct LogsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \QSO.timestamp, order: .reverse) private var qsos: [QSO]

    @State private var searchText = ""
    @State private var selectedBand: String?
    @State private var selectedMode: String?

    private var filteredQSOs: [QSO] {
        qsos.filter { qso in
            let matchesSearch = searchText.isEmpty ||
                qso.callsign.localizedCaseInsensitiveContains(searchText) ||
                (qso.parkReference?.localizedCaseInsensitiveContains(searchText) ?? false)

            let matchesBand = selectedBand == nil || qso.band == selectedBand
            let matchesMode = selectedMode == nil || qso.mode == selectedMode

            return matchesSearch && matchesBand && matchesMode
        }
    }

    private var availableBands: [String] {
        Array(Set(qsos.map(\.band))).sorted()
    }

    private var availableModes: [String] {
        Array(Set(qsos.map(\.mode))).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredQSOs) { qso in
                    QSORow(qso: qso)
                }
                .onDelete(perform: deleteQSOs)
            }
            .searchable(text: $searchText, prompt: "Search callsigns or parks")
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Menu("Band") {
                            Button("All") { selectedBand = nil }
                            ForEach(availableBands, id: \.self) { band in
                                Button(band) { selectedBand = band }
                            }
                        }

                        Menu("Mode") {
                            Button("All") { selectedMode = nil }
                            ForEach(availableModes, id: \.self) { mode in
                                Button(mode) { selectedMode = mode }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .overlay {
                if qsos.isEmpty {
                    ContentUnavailableView(
                        "No Logs",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Import ADIF files or sync from LoFi to see your QSOs")
                    )
                }
            }
        }
    }

    private func deleteQSOs(at offsets: IndexSet) {
        for index in offsets {
            let qso = filteredQSOs[index]
            modelContext.delete(qso)
        }
    }
}

struct QSORow: View {
    let qso: QSO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(qso.callsign)
                    .font(.headline)

                Spacer()

                Text(qso.timestamp, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label(qso.band, systemImage: "waveform")
                Label(qso.mode, systemImage: "dot.radiowaves.left.and.right")

                if let park = qso.parkReference {
                    Label(park, systemImage: "tree")
                        .foregroundStyle(.green)
                }

                Spacer()

                Text(qso.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Sync status indicators
            HStack(spacing: 8) {
                ForEach(qso.syncRecords) { record in
                    SyncStatusBadge(record: record)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SyncStatusBadge: View {
    let record: SyncRecord

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
            Text(record.destinationType.displayName)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(backgroundColor.opacity(0.2))
        .foregroundStyle(backgroundColor)
        .clipShape(Capsule())
    }

    private var iconName: String {
        switch record.status {
        case .pending: return "clock"
        case .uploaded: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var backgroundColor: Color {
        switch record.status {
        case .pending: return .orange
        case .uploaded: return .green
        case .failed: return .red
        }
    }
}

#Preview {
    LogsListView()
        .modelContainer(for: [QSO.self, SyncRecord.self], inMemory: true)
}
```

**Step 2: Update ContentView to use LogsListView**

Replace the placeholder `LogsView` in ContentView.swift:

```swift
// In ContentView.swift, update the TabView:
LogsListView()
    .tabItem {
        Label("Logs", systemImage: "list.bullet")
    }
```

**Step 3: Build and run**

Run: Cmd+R
Expected: App launches with Dashboard and Logs tabs

**Step 4: Commit**

```bash
git add FullDuplex/Views/Logs/LogsListView.swift FullDuplex/ContentView.swift
git commit -m "feat: add logs list view with filtering and sync status

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 18: Create Settings View

**Files:**
- Create: `FullDuplex/Views/Settings/SettingsView.swift`
- Modify: `FullDuplex/ContentView.swift`

**Step 1: Create SettingsView.swift**

```swift
import SwiftUI
import SwiftData

struct SettingsMainView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var potaAuth = POTAAuthService()

    @State private var qrzUsername = ""
    @State private var qrzPassword = ""
    @State private var qrzIsAuthenticated = false
    @State private var showingQRZLogin = false
    @State private var showingPOTALogin = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            List {
                // QRZ Section
                Section {
                    if qrzIsAuthenticated {
                        HStack {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Button("Logout") {
                                logoutQRZ()
                            }
                            .foregroundStyle(.red)
                        }
                    } else {
                        Button("Login to QRZ") {
                            showingQRZLogin = true
                        }
                    }
                } header: {
                    Text("QRZ Logbook")
                } footer: {
                    Text("Upload your logs to QRZ.com logbook")
                }

                // POTA Section
                Section {
                    if let token = potaAuth.currentToken, !token.isExpired {
                        HStack {
                            VStack(alignment: .leading) {
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                if let callsign = token.callsign {
                                    Text(callsign)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Logout") {
                                potaAuth.logout()
                            }
                            .foregroundStyle(.red)
                        }

                        Text("Token expires: \(token.expiresAt, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Login to POTA") {
                            showingPOTALogin = true
                            Task {
                                do {
                                    _ = try await potaAuth.authenticate()
                                    showingPOTALogin = false
                                } catch {
                                    showingPOTALogin = false
                                    errorMessage = error.localizedDescription
                                    showingError = true
                                }
                            }
                        }
                    }
                } header: {
                    Text("POTA")
                } footer: {
                    Text("Upload activation logs to Parks on the Air")
                }

                // iCloud Section
                Section {
                    NavigationLink {
                        ICloudSettingsView()
                    } label: {
                        Label("iCloud Folder", systemImage: "icloud")
                    }
                } header: {
                    Text("Import Sources")
                }

                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingQRZLogin) {
                QRZLoginSheet(
                    username: $qrzUsername,
                    password: $qrzPassword,
                    isAuthenticated: $qrzIsAuthenticated,
                    errorMessage: $errorMessage,
                    showingError: $showingError
                )
            }
            .sheet(isPresented: $showingPOTALogin) {
                POTALoginSheet(authService: potaAuth)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                checkQRZAuth()
            }
        }
    }

    private func checkQRZAuth() {
        do {
            _ = try KeychainHelper.shared.readString(for: KeychainHelper.Keys.qrzSessionKey)
            qrzIsAuthenticated = true
        } catch {
            qrzIsAuthenticated = false
        }
    }

    private func logoutQRZ() {
        try? KeychainHelper.shared.delete(for: KeychainHelper.Keys.qrzSessionKey)
        try? KeychainHelper.shared.delete(for: KeychainHelper.Keys.qrzUsername)
        qrzIsAuthenticated = false
    }
}

struct QRZLoginSheet: View {
    @Binding var username: String
    @Binding var password: String
    @Binding var isAuthenticated: Bool
    @Binding var errorMessage: String
    @Binding var showingError: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var isLoggingIn = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                Section {
                    Button {
                        Task { await login() }
                    } label: {
                        if isLoggingIn {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Login")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || isLoggingIn)
                }
            }
            .navigationTitle("QRZ Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func login() async {
        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            let client = QRZClient()
            _ = try await client.authenticate(username: username, password: password)
            isAuthenticated = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

struct ICloudSettingsView: View {
    @StateObject private var monitor = ICloudMonitor()

    var body: some View {
        List {
            Section {
                if let url = monitor.iCloudContainerURL {
                    VStack(alignment: .leading) {
                        Text("Import Folder")
                            .font(.headline)
                        Text(url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Create Folder") {
                        monitor.createImportFolderIfNeeded()
                    }
                } else {
                    Text("iCloud is not available")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Place ADIF files in this folder to import them")
            }

            Section {
                Toggle("Monitor for new files", isOn: .constant(monitor.isMonitoring))
                    .disabled(true) // Read-only for now
            }
        }
        .navigationTitle("iCloud")
    }
}

#Preview {
    SettingsMainView()
        .modelContainer(for: [QSO.self], inMemory: true)
}
```

**Step 2: Update ContentView to use SettingsMainView**

```swift
// In ContentView.swift, update the TabView:
SettingsMainView()
    .tabItem {
        Label("Settings", systemImage: "gear")
    }
```

**Step 3: Build and run**

Run: Cmd+R
Expected: Settings tab shows QRZ and POTA login options

**Step 4: Commit**

```bash
git add FullDuplex/Views/Settings/SettingsView.swift FullDuplex/ContentView.swift
git commit -m "feat: add settings view with QRZ and POTA authentication

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Phase 10: Import & Sync Logic

### Task 19: Create Import Service

**Files:**
- Create: `FullDuplex/Services/ImportService.swift`

**Step 1: Create ImportService.swift**

```swift
import Foundation
import SwiftData

@MainActor
class ImportService: ObservableObject {
    private let modelContext: ModelContext
    private let parser = ADIFParser()

    @Published var isImporting = false
    @Published var lastImportResult: ImportResult?

    struct ImportResult {
        let totalRecords: Int
        let imported: Int
        let duplicates: Int
        let errors: Int
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func importADIF(from url: URL, source: ImportSource, myCallsign: String) async throws -> ImportResult {
        isImporting = true
        defer { isImporting = false }

        // Read file
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidFile
        }

        // Parse ADIF
        let records = try parser.parse(content)

        var imported = 0
        var duplicates = 0
        var errors = 0

        // Get existing dedup keys
        let existingKeys = try fetchExistingDeduplicationKeys()

        for record in records {
            do {
                let qso = try createQSO(from: record, source: source, myCallsign: myCallsign)

                if existingKeys.contains(qso.deduplicationKey) {
                    duplicates += 1
                    continue
                }

                modelContext.insert(qso)

                // Create pending sync records for enabled destinations
                for destType in DestinationType.allCases {
                    let syncRecord = SyncRecord(destinationType: destType, qso: qso)
                    modelContext.insert(syncRecord)
                    qso.syncRecords.append(syncRecord)
                }

                imported += 1
            } catch {
                errors += 1
            }
        }

        try modelContext.save()

        let result = ImportResult(
            totalRecords: records.count,
            imported: imported,
            duplicates: duplicates,
            errors: errors
        )

        lastImportResult = result
        return result
    }

    func importADIF(content: String, source: ImportSource, myCallsign: String) async throws -> ImportResult {
        isImporting = true
        defer { isImporting = false }

        let records = try parser.parse(content)

        var imported = 0
        var duplicates = 0
        var errors = 0

        let existingKeys = try fetchExistingDeduplicationKeys()

        for record in records {
            do {
                let qso = try createQSO(from: record, source: source, myCallsign: myCallsign)

                if existingKeys.contains(qso.deduplicationKey) {
                    duplicates += 1
                    continue
                }

                modelContext.insert(qso)

                for destType in DestinationType.allCases {
                    let syncRecord = SyncRecord(destinationType: destType, qso: qso)
                    modelContext.insert(syncRecord)
                    qso.syncRecords.append(syncRecord)
                }

                imported += 1
            } catch {
                errors += 1
            }
        }

        try modelContext.save()

        let result = ImportResult(
            totalRecords: records.count,
            imported: imported,
            duplicates: duplicates,
            errors: errors
        )

        lastImportResult = result
        return result
    }

    private func fetchExistingDeduplicationKeys() throws -> Set<String> {
        let descriptor = FetchDescriptor<QSO>()
        let qsos = try modelContext.fetch(descriptor)
        return Set(qsos.map(\.deduplicationKey))
    }

    private func createQSO(from record: ADIFRecord, source: ImportSource, myCallsign: String) throws -> QSO {
        guard let timestamp = record.timestamp else {
            throw ImportError.missingTimestamp
        }

        return QSO(
            callsign: record.callsign,
            band: record.band,
            mode: record.mode,
            frequency: record.frequency,
            timestamp: timestamp,
            rstSent: record.rstSent,
            rstReceived: record.rstReceived,
            myCallsign: record.myCallsign ?? myCallsign,
            myGrid: record.myGridsquare,
            theirGrid: record.gridsquare,
            parkReference: record.sigInfo,
            notes: record.comment,
            importSource: source,
            rawADIF: record.rawADIF
        )
    }
}

enum ImportError: Error, LocalizedError {
    case invalidFile
    case missingTimestamp
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "Could not read the ADIF file"
        case .missingTimestamp:
            return "QSO record missing date/time"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}
```

**Step 2: Build to verify**

Run: Cmd+B
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add FullDuplex/Services/ImportService.swift
git commit -m "feat: add import service with deduplication

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 20: Create Sync Service

**Files:**
- Create: `FullDuplex/Services/SyncService.swift`

**Step 1: Create SyncService.swift**

```swift
import Foundation
import SwiftData

@MainActor
class SyncService: ObservableObject {
    private let modelContext: ModelContext
    private let qrzClient: QRZClient
    private let potaClient: POTAClient

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncProgress: SyncProgress?

    struct SyncProgress {
        var destination: DestinationType
        var current: Int
        var total: Int
    }

    struct SyncResult {
        var qrzUploaded: Int
        var qrzDuplicates: Int
        var qrzErrors: [String]
        var potaUploaded: Int
        var potaErrors: [String]
    }

    init(modelContext: ModelContext, potaAuthService: POTAAuthService) {
        self.modelContext = modelContext
        self.qrzClient = QRZClient()
        self.potaClient = POTAClient(authService: potaAuthService)
    }

    func syncAll() async throws -> SyncResult {
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        var result = SyncResult(
            qrzUploaded: 0,
            qrzDuplicates: 0,
            qrzErrors: [],
            potaUploaded: 0,
            potaErrors: []
        )

        // Sync to QRZ
        do {
            let qrzResult = try await syncToQRZ()
            result.qrzUploaded = qrzResult.uploaded
            result.qrzDuplicates = qrzResult.duplicates
        } catch {
            result.qrzErrors.append(error.localizedDescription)
        }

        // Sync to POTA
        do {
            let potaResult = try await syncToPOTA()
            result.potaUploaded = potaResult
        } catch {
            result.potaErrors.append(error.localizedDescription)
        }

        return result
    }

    func syncToQRZ() async throws -> (uploaded: Int, duplicates: Int) {
        syncProgress = SyncProgress(destination: .qrz, current: 0, total: 0)

        // Fetch pending QSOs for QRZ
        let pendingRecords = try fetchPendingSyncRecords(for: .qrz)
        guard !pendingRecords.isEmpty else {
            return (uploaded: 0, duplicates: 0)
        }

        let qsos = pendingRecords.compactMap(\.qso)
        syncProgress?.total = qsos.count

        // Upload in batches of 50
        let batchSize = 50
        var totalUploaded = 0
        var totalDuplicates = 0

        for batch in stride(from: 0, to: qsos.count, by: batchSize) {
            let end = min(batch + batchSize, qsos.count)
            let batchQSOs = Array(qsos[batch..<end])

            let result = try await qrzClient.uploadQSOs(batchQSOs)
            totalUploaded += result.uploaded
            totalDuplicates += result.duplicates

            // Mark as uploaded
            for qso in batchQSOs {
                if let record = qso.syncRecords.first(where: { $0.destinationType == .qrz }) {
                    record.status = .uploaded
                    record.uploadedAt = Date()
                }
            }

            try modelContext.save()
            syncProgress?.current = end
        }

        return (uploaded: totalUploaded, duplicates: totalDuplicates)
    }

    func syncToPOTA() async throws -> Int {
        syncProgress = SyncProgress(destination: .pota, current: 0, total: 0)

        // Fetch pending QSOs for POTA
        let pendingRecords = try fetchPendingSyncRecords(for: .pota)
        let qsos = pendingRecords.compactMap(\.qso)

        // Group by park reference
        let byPark = POTAClient.groupQSOsByPark(qsos)
        syncProgress?.total = byPark.count

        var totalUploaded = 0
        var currentPark = 0

        for (parkRef, parkQSOs) in byPark {
            let result = try await potaClient.uploadActivation(
                parkReference: parkRef,
                qsos: parkQSOs
            )

            if result.success {
                totalUploaded += result.qsosAccepted

                // Mark as uploaded
                for qso in parkQSOs {
                    if let record = qso.syncRecords.first(where: { $0.destinationType == .pota }) {
                        record.status = .uploaded
                        record.uploadedAt = Date()
                    }
                }
            }

            currentPark += 1
            syncProgress?.current = currentPark
            try modelContext.save()
        }

        return totalUploaded
    }

    private func fetchPendingSyncRecords(for destination: DestinationType) throws -> [SyncRecord] {
        let predicate = #Predicate<SyncRecord> { record in
            record.destinationType == destination && record.status == .pending
        }
        let descriptor = FetchDescriptor<SyncRecord>(predicate: predicate)
        return try modelContext.fetch(descriptor)
    }
}
```

**Step 2: Build to verify**

Run: Cmd+B
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add FullDuplex/Services/SyncService.swift
git commit -m "feat: add sync service for QRZ and POTA uploads

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Phase 11: Wire Everything Together

### Task 21: Update Dashboard with Real Sync

**Files:**
- Modify: `FullDuplex/Views/Dashboard/DashboardView.swift`

**Step 1: Update DashboardView with sync service**

Update the DashboardView to use the actual SyncService:

```swift
// Add to DashboardView:
@StateObject private var syncService: SyncService

// In init or onAppear, initialize syncService with modelContext

// Update performSync():
private func performSync() async {
    do {
        let result = try await syncService.syncAll()
        // Handle result - show alert or update UI
    } catch {
        // Show error
    }
}
```

(Full implementation details in the file)

**Step 2: Build and test**

Run: Cmd+R
Expected: Sync button triggers actual sync

**Step 3: Commit**

```bash
git add FullDuplex/Views/Dashboard/DashboardView.swift
git commit -m "feat: wire dashboard sync to actual sync service

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 22: Add File Import Handler

**Files:**
- Modify: `FullDuplex/FullDuplexApp.swift`

**Step 1: Add ADIF file handling**

```swift
// Update FullDuplexApp to handle file opens:
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct FullDuplexApp: App {
    // ... existing code ...

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleADIFFile(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func handleADIFFile(_ url: URL) {
        // Post notification or use environment to trigger import
        NotificationCenter.default.post(
            name: .didReceiveADIFFile,
            object: url
        )
    }
}

extension Notification.Name {
    static let didReceiveADIFFile = Notification.Name("didReceiveADIFFile")
}

// Register UTType for ADIF in Info.plist:
// - UTImportedTypeDeclarations for .adi and .adif
```

**Step 2: Add Info.plist entries for ADIF files**

Add to Info.plist (via Xcode):
- Document Types: ADIF Log File
- Exported/Imported Type Identifiers for .adi, .adif

**Step 3: Commit**

```bash
git add FullDuplex/FullDuplexApp.swift
git commit -m "feat: add ADIF file import handler

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 23: Add iCloud Entitlements

**Files:**
- Modify: `FullDuplex/FullDuplex.entitlements`

**Step 1: Enable iCloud in Xcode**

In Xcode:
1. Select the FullDuplex target
2. Go to Signing & Capabilities
3. Click "+ Capability"
4. Add "iCloud"
5. Check "iCloud Documents"
6. Add container: iCloud.com.yourteam.FullDuplex

**Step 2: Enable Background Modes**

1. Add "Background Modes" capability
2. Check "Background fetch"

**Step 3: Commit**

```bash
git add FullDuplex/FullDuplex.entitlements FullDuplex.xcodeproj/project.pbxproj
git commit -m "feat: add iCloud and background mode entitlements

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Phase 12: Testing & Polish

### Task 24: Add Integration Tests

**Files:**
- Create: `FullDuplexTests/ImportServiceTests.swift`

**Step 1: Create integration tests**

```swift
import XCTest
import SwiftData
@testable import FullDuplex

final class ImportServiceTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var importService: ImportService!

    @MainActor
    override func setUp() async throws {
        let schema = Schema([QSO.self, SyncRecord.self, UploadDestination.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = modelContainer.mainContext
        importService = ImportService(modelContext: modelContext)
    }

    @MainActor
    func testImportSingleQSO() async throws {
        let adif = "<call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 <eor>"

        let result = try await importService.importADIF(
            content: adif,
            source: .adifFile,
            myCallsign: "N0CALL"
        )

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.duplicates, 0)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
        XCTAssertEqual(qsos[0].callsign, "W1AW")
    }

    @MainActor
    func testDeduplication() async throws {
        let adif = "<call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 <eor>"

        // Import twice
        _ = try await importService.importADIF(content: adif, source: .adifFile, myCallsign: "N0CALL")
        let result = try await importService.importADIF(content: adif, source: .adifFile, myCallsign: "N0CALL")

        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.duplicates, 1)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
    }

    @MainActor
    func testSyncRecordsCreated() async throws {
        let adif = "<call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 <eor>"

        _ = try await importService.importADIF(content: adif, source: .adifFile, myCallsign: "N0CALL")

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos[0].syncRecords.count, 2) // QRZ and POTA
        XCTAssertTrue(qsos[0].syncRecords.allSatisfy { $0.status == .pending })
    }
}
```

**Step 2: Run tests**

Run: Cmd+U
Expected: All tests PASS

**Step 3: Commit**

```bash
git add FullDuplexTests/ImportServiceTests.swift
git commit -m "test: add import service integration tests

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 25: Final Build and Run

**Step 1: Clean build**

Run: Cmd+Shift+K (Clean)
Run: Cmd+B (Build)
Expected: Build Succeeded with no warnings

**Step 2: Run on simulator**

Run: Cmd+R
Expected: App launches, all tabs work

**Step 3: Test basic flow**

1. Open Settings, verify QRZ/POTA login UI appears
2. Open Logs, verify empty state
3. Open Dashboard, verify summary shows 0 QSOs

**Step 4: Final commit**

```bash
git add .
git commit -m "chore: final cleanup and verification

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Summary

This implementation plan creates a fully functional iOS app with:

1. **Data Layer:** SwiftData models for QSO, SyncRecord, UploadDestination
2. **Services:** ADIF parser, QRZ client, POTA auth/client, iCloud monitor, import/sync services
3. **UI:** Dashboard with sync status, Logs list with filtering, Settings for authentication
4. **Infrastructure:** Keychain for credentials, iCloud for file monitoring

**Next steps after implementation:**
- Add LoFi client (requires API investigation)
- Add pull-to-refresh on logs
- Add export functionality
- App Store submission preparation
