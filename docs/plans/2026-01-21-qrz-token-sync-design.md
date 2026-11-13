# QRZ Logbook Token Auth & Bidirectional Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace username/password auth with API token, add bidirectional QSO sync with QRZ, and display upload/download statistics on dashboard.

**Architecture:** QRZClient becomes token-based with new fetch capability. QSO model gets QRZ-specific fields for tracking. ImportService handles merge logic. Dashboard shows cumulative stats stored in Keychain.

**Tech Stack:** Swift, SwiftUI, SwiftData, Keychain Services

---

### Task 1: Add New Keychain Keys

**Files:**
- Modify: `FullDuplex/Utilities/KeychainHelper.swift:94-107`

**Step 1: Add new keys for QRZ token auth and stats**

Add these keys to the `Keys` enum, replacing the old session-based keys:

```swift
extension KeychainHelper {
    enum Keys {
        // QRZ - token-based auth
        static let qrzApiKey = "qrz.api.key"
        static let qrzCallsign = "qrz.callsign"
        static let qrzTotalUploaded = "qrz.total.uploaded"
        static let qrzTotalDownloaded = "qrz.total.downloaded"
        static let qrzLastUploadDate = "qrz.last.upload.date"
        static let qrzLastDownloadDate = "qrz.last.download.date"

        // POTA
        static let potaIdToken = "pota.id.token"
        static let potaTokenExpiry = "pota.token.expiry"

        // LoFi
        static let lofiAuthToken = "lofi.auth.token"
        static let lofiClientKey = "lofi.client.key"
        static let lofiClientSecret = "lofi.client.secret"
        static let lofiCallsign = "lofi.callsign"
        static let lofiEmail = "lofi.email"
        static let lofiDeviceLinked = "lofi.device.linked"
        static let lofiLastSyncMillis = "lofi.last.sync.millis"
    }
}
```

**Step 2: Run tests**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

**Step 3: Commit**

```bash
git add FullDuplex/Utilities/KeychainHelper.swift
git commit -m "feat(qrz): add keychain keys for token auth and sync stats"
```

---

### Task 2: Add QRZ Fields to QSO Model

**Files:**
- Modify: `FullDuplex/Models/QSO.swift`

**Step 1: Add QRZ-specific fields to QSO model**

Add these properties after the existing properties (around line 21):

```swift
    // QRZ sync tracking
    var qrzLogId: String?
    var qrzConfirmed: Bool = false
    var lotwConfirmedDate: Date?
```

Update the init to include them (add parameters after `rawADIF`):

```swift
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
        rawADIF: String? = nil,
        qrzLogId: String? = nil,
        qrzConfirmed: Bool = false,
        lotwConfirmedDate: Date? = nil
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
        self.qrzLogId = qrzLogId
        self.qrzConfirmed = qrzConfirmed
        self.lotwConfirmedDate = lotwConfirmedDate
    }
```

**Step 2: Build to verify model compiles**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

**Step 3: Commit**

```bash
git add FullDuplex/Models/QSO.swift
git commit -m "feat(qrz): add qrzLogId, qrzConfirmed, lotwConfirmedDate fields to QSO"
```

---

### Task 3: Add QRZ Import Source

**Files:**
- Modify: `FullDuplex/Models/Types.swift`

**Step 1: Add qrz case to ImportSource enum**

```swift
enum ImportSource: String, Codable {
    case lofi
    case adifFile
    case icloud
    case qrz
}
```

**Step 2: Build to verify**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

**Step 3: Commit**

```bash
git add FullDuplex/Models/Types.swift
git commit -m "feat(qrz): add qrz import source type"
```

---

### Task 4: Refactor QRZClient for Token Auth

**Files:**
- Modify: `FullDuplex/Services/QRZClient.swift`
- Test: `FullDuplexTests/QRZClientTests.swift`

**Step 1: Write test for STATUS response parsing**

Add to `QRZClientTests.swift`:

```swift
    func testParseStatusResponse() throws {
        let response = "RESULT=OK&CALLSIGN=W1ABC&COUNT=1234&CONFIRMED=567"

        let result = QRZClient.parseResponse(response)

        XCTAssertEqual(result["RESULT"], "OK")
        XCTAssertEqual(result["CALLSIGN"], "W1ABC")
        XCTAssertEqual(result["COUNT"], "1234")
    }
```

**Step 2: Run test to verify it passes** (existing parseResponse should handle it)

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

**Step 3: Rewrite QRZClient with token-based auth**

Replace the entire `QRZClient.swift` content:

```swift
import Foundation

enum QRZError: Error, LocalizedError {
    case invalidApiKey
    case sessionExpired
    case uploadFailed(String)
    case networkError(Error)
    case invalidResponse
    case noQSOs

    var errorDescription: String? {
        switch self {
        case .invalidApiKey:
            return "Invalid QRZ API key"
        case .sessionExpired:
            return "QRZ session expired, please re-authenticate"
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from QRZ"
        case .noQSOs:
            return "No QSOs found"
        }
    }
}

struct QRZStatusResponse {
    let callsign: String
    let qsoCount: Int
    let confirmedCount: Int
}

struct QRZFetchedQSO {
    let callsign: String
    let band: String
    let mode: String
    let frequency: Double?
    let timestamp: Date
    let rstSent: String?
    let rstReceived: String?
    let myCallsign: String?
    let myGrid: String?
    let theirGrid: String?
    let qrzLogId: String
    let qrzConfirmed: Bool
    let lotwConfirmedDate: Date?
    let rawADIF: String
}

actor QRZClient {
    private let baseURL = "https://logbook.qrz.com/api"
    private let keychain = KeychainHelper.shared
    private let userAgent = "FullDuplex/1.0"

    static func parseResponse(_ response: String) -> [String: String] {
        var result: [String: String] = [:]
        let pairs = response.components(separatedBy: "&")

        for pair in pairs {
            let parts = pair.components(separatedBy: "=")
            if parts.count == 2 {
                result[parts[0]] = parts[1]
            } else if parts.count > 2 {
                result[parts[0]] = parts.dropFirst().joined(separator: "=")
            }
        }

        return result
    }

    // MARK: - API Key Management

    func saveApiKey(_ key: String) throws {
        try keychain.save(key, for: KeychainHelper.Keys.qrzApiKey)
    }

    func getApiKey() throws -> String {
        try keychain.readString(for: KeychainHelper.Keys.qrzApiKey)
    }

    func hasApiKey() -> Bool {
        (try? getApiKey()) != nil
    }

    func clearApiKey() {
        try? keychain.delete(for: KeychainHelper.Keys.qrzApiKey)
        try? keychain.delete(for: KeychainHelper.Keys.qrzCallsign)
    }

    func saveCallsign(_ callsign: String) throws {
        try keychain.save(callsign, for: KeychainHelper.Keys.qrzCallsign)
    }

    func getCallsign() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.qrzCallsign)
    }

    // MARK: - Stats Tracking

    func getTotalUploaded() -> Int {
        guard let str = try? keychain.readString(for: KeychainHelper.Keys.qrzTotalUploaded),
              let value = Int(str) else { return 0 }
        return value
    }

    func getTotalDownloaded() -> Int {
        guard let str = try? keychain.readString(for: KeychainHelper.Keys.qrzTotalDownloaded),
              let value = Int(str) else { return 0 }
        return value
    }

    func getLastUploadDate() -> Date? {
        guard let str = try? keychain.readString(for: KeychainHelper.Keys.qrzLastUploadDate),
              let interval = Double(str) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    func getLastDownloadDate() -> Date? {
        guard let str = try? keychain.readString(for: KeychainHelper.Keys.qrzLastDownloadDate),
              let interval = Double(str) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private func incrementUploaded(by count: Int) {
        let current = getTotalUploaded()
        try? keychain.save(String(current + count), for: KeychainHelper.Keys.qrzTotalUploaded)
        try? keychain.save(String(Date().timeIntervalSince1970), for: KeychainHelper.Keys.qrzLastUploadDate)
    }

    private func incrementDownloaded(by count: Int) {
        let current = getTotalDownloaded()
        try? keychain.save(String(current + count), for: KeychainHelper.Keys.qrzTotalDownloaded)
        try? keychain.save(String(Date().timeIntervalSince1970), for: KeychainHelper.Keys.qrzLastDownloadDate)
    }

    // MARK: - API Calls

    func validateApiKey(_ key: String) async throws -> QRZStatusResponse {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "KEY", value: key),
            URLQueryItem(name: "ACTION", value: "STATUS")
        ]

        guard let url = components.url else {
            throw QRZError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw QRZError.invalidResponse
        }

        let parsed = Self.parseResponse(responseString)

        if parsed["RESULT"] == "AUTH" {
            throw QRZError.invalidApiKey
        }

        guard parsed["RESULT"] == "OK",
              let callsign = parsed["CALLSIGN"] else {
            throw QRZError.invalidApiKey
        }

        let qsoCount = Int(parsed["COUNT"] ?? "0") ?? 0
        let confirmedCount = Int(parsed["CONFIRMED"] ?? "0") ?? 0

        return QRZStatusResponse(
            callsign: callsign,
            qsoCount: qsoCount,
            confirmedCount: confirmedCount
        )
    }

    func uploadQSOs(_ qsos: [QSO]) async throws -> (uploaded: Int, duplicates: Int) {
        let apiKey = try getApiKey()

        let adifContent = qsos.map { qso in
            qso.rawADIF ?? generateADIF(for: qso)
        }.joined(separator: "\n")

        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "KEY", value: apiKey),
            URLQueryItem(name: "ACTION", value: "INSERT"),
            URLQueryItem(name: "ADIF", value: adifContent)
        ]

        guard let url = components.url else {
            throw QRZError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw QRZError.invalidResponse
        }

        let parsed = Self.parseResponse(responseString)

        if parsed["RESULT"] == "AUTH" {
            throw QRZError.sessionExpired
        }

        guard parsed["RESULT"] == "OK" || parsed["RESULT"] == "REPLACE" else {
            throw QRZError.uploadFailed(parsed["REASON"] ?? "Unknown error")
        }

        let count = Int(parsed["COUNT"] ?? "0") ?? 0
        let dupes = Int(parsed["DUPES"] ?? "0") ?? 0

        if count > 0 {
            incrementUploaded(by: count)
        }

        return (uploaded: count, duplicates: dupes)
    }

    func fetchQSOs(since: Date? = nil) async throws -> [QRZFetchedQSO] {
        let apiKey = try getApiKey()
        var allQSOs: [QRZFetchedQSO] = []
        var offset = 0
        let maxPerPage = 250

        while true {
            var optionParts = ["MAX:\(maxPerPage)", "OFFSET:\(offset)"]

            if let since = since {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone(identifier: "UTC")
                optionParts.append("MODSINCE:\(formatter.string(from: since))")
            }

            var components = URLComponents(string: baseURL)!
            components.queryItems = [
                URLQueryItem(name: "KEY", value: apiKey),
                URLQueryItem(name: "ACTION", value: "FETCH"),
                URLQueryItem(name: "OPTION", value: optionParts.joined(separator: ","))
            ]

            guard let url = components.url else {
                throw QRZError.invalidResponse
            }

            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

            let (data, _) = try await URLSession.shared.data(for: request)

            guard let responseString = String(data: data, encoding: .utf8) else {
                throw QRZError.invalidResponse
            }

            let parsed = Self.parseResponse(responseString)

            if parsed["RESULT"] == "AUTH" {
                throw QRZError.sessionExpired
            }

            // "no log entries found" is not an error, just empty
            if parsed["RESULT"] == "FAIL" && parsed["REASON"]?.contains("no log entries") == true {
                break
            }

            guard parsed["RESULT"] == "OK" else {
                throw QRZError.uploadFailed(parsed["REASON"] ?? "Unknown error")
            }

            guard let adifEncoded = parsed["ADIF"] else {
                break
            }

            // Decode URL encoding, then HTML entities
            let adifDecoded = decodeADIF(adifEncoded)
            let qsos = parseADIFRecords(adifDecoded)
            allQSOs.append(contentsOf: qsos)

            let count = Int(parsed["COUNT"] ?? "0") ?? 0
            if count < maxPerPage {
                break
            }

            offset += maxPerPage

            // Small delay between pages
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        if !allQSOs.isEmpty {
            incrementDownloaded(by: allQSOs.count)
        }

        return allQSOs
    }

    // MARK: - ADIF Helpers

    private func decodeADIF(_ encoded: String) -> String {
        var decoded = encoded.removingPercentEncoding ?? encoded
        // Decode HTML entities
        decoded = decoded
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return decoded
    }

    private func parseADIFRecords(_ adif: String) -> [QRZFetchedQSO] {
        var results: [QRZFetchedQSO] = []

        let rawRecords = adif.components(separatedBy: "<eor>")
            .flatMap { $0.components(separatedBy: "<EOR>") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for rawRecord in rawRecords {
            let fields = parseADIFFields(rawRecord)

            guard let callsign = fields["call"],
                  let band = fields["band"],
                  let mode = fields["mode"],
                  let qrzLogId = fields["app_qrzlog_logid"] else {
                continue
            }

            guard let timestamp = parseTimestamp(date: fields["qso_date"], time: fields["time_on"]) else {
                continue
            }

            let qrzConfirmed = fields["app_qrzlog_status"] == "C"
            let lotwDate = parseLotwDate(fields["lotw_qslrdate"])

            let qso = QRZFetchedQSO(
                callsign: callsign.uppercased(),
                band: band.lowercased(),
                mode: mode.uppercased(),
                frequency: fields["freq"].flatMap { Double($0) },
                timestamp: timestamp,
                rstSent: fields["rst_sent"],
                rstReceived: fields["rst_rcvd"],
                myCallsign: fields["station_callsign"],
                myGrid: fields["my_gridsquare"],
                theirGrid: fields["gridsquare"],
                qrzLogId: qrzLogId,
                qrzConfirmed: qrzConfirmed,
                lotwConfirmedDate: lotwDate,
                rawADIF: "<" + rawRecord + "<eor>"
            )

            results.append(qso)
        }

        return results
    }

    private func parseADIFFields(_ record: String) -> [String: String] {
        var fields: [String: String] = [:]

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

    private func parseTimestamp(date: String?, time: String?) -> Date? {
        guard let dateStr = date else { return nil }
        let timeStr = time ?? "0000"

        let formatter = DateFormatter()
        formatter.dateFormat = timeStr.count == 6 ? "yyyyMMddHHmmss" : "yyyyMMddHHmm"
        formatter.timeZone = TimeZone(identifier: "UTC")

        return formatter.date(from: dateStr + timeStr)
    }

    private func parseLotwDate(_ dateStr: String?) -> Date? {
        guard let dateStr = dateStr, !dateStr.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: dateStr)
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
        addField("sig_info", qso.parkReference)
        addField("comment", qso.notes)

        return fields.joined(separator: " ") + " <eor>"
    }

    func logout() {
        clearApiKey()
    }
}
```

**Step 4: Run all tests**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

**Step 5: Commit**

```bash
git add FullDuplex/Services/QRZClient.swift FullDuplexTests/QRZClientTests.swift
git commit -m "feat(qrz): refactor QRZClient for token auth with fetch support"
```

---

### Task 5: Add QRZ Import/Merge to ImportService

**Files:**
- Modify: `FullDuplex/Services/ImportService.swift`

**Step 1: Add QRZ import method to ImportService**

Add this method after `importFromLoFi`:

```swift
    // MARK: - QRZ Import (with merge)

    func importFromQRZ(qsos: [QRZFetchedQSO], myCallsign: String) async throws -> ImportResult {
        isImporting = true
        defer { isImporting = false }

        var imported = 0
        var updated = 0
        var duplicates = 0

        // Fetch existing QSOs for matching
        let descriptor = FetchDescriptor<QSO>()
        let existingQSOs = try modelContext.fetch(descriptor)

        // Build lookup maps
        let byQrzLogId = Dictionary(grouping: existingQSOs.filter { $0.qrzLogId != nil }) { $0.qrzLogId! }
        let byDedupeKey = Dictionary(grouping: existingQSOs) { $0.deduplicationKey }

        for qrzQso in qsos {
            // Try to find existing by QRZ log ID first
            if let existing = byQrzLogId[qrzQso.qrzLogId]?.first {
                // Update confirmation status
                existing.qrzConfirmed = qrzQso.qrzConfirmed
                existing.lotwConfirmedDate = qrzQso.lotwConfirmedDate
                updated += 1
                continue
            }

            // Try to find by deduplication key
            let tempQso = QSO(
                callsign: qrzQso.callsign,
                band: qrzQso.band,
                mode: qrzQso.mode,
                timestamp: qrzQso.timestamp,
                myCallsign: qrzQso.myCallsign ?? myCallsign,
                importSource: .qrz
            )
            let dedupeKey = tempQso.deduplicationKey

            if let existing = byDedupeKey[dedupeKey]?.first {
                // Update with QRZ data
                existing.qrzLogId = qrzQso.qrzLogId
                existing.qrzConfirmed = qrzQso.qrzConfirmed
                existing.lotwConfirmedDate = qrzQso.lotwConfirmedDate
                updated += 1
                continue
            }

            // Create new QSO
            let newQso = QSO(
                callsign: qrzQso.callsign,
                band: qrzQso.band,
                mode: qrzQso.mode,
                frequency: qrzQso.frequency,
                timestamp: qrzQso.timestamp,
                rstSent: qrzQso.rstSent,
                rstReceived: qrzQso.rstReceived,
                myCallsign: qrzQso.myCallsign ?? myCallsign,
                myGrid: qrzQso.myGrid,
                theirGrid: qrzQso.theirGrid,
                importSource: .qrz,
                rawADIF: qrzQso.rawADIF,
                qrzLogId: qrzQso.qrzLogId,
                qrzConfirmed: qrzQso.qrzConfirmed,
                lotwConfirmedDate: qrzQso.lotwConfirmedDate
            )

            modelContext.insert(newQso)

            // Create sync records for other destinations (not QRZ since it came from there)
            let potaSyncRecord = SyncRecord(destinationType: .pota, qso: newQso)
            modelContext.insert(potaSyncRecord)
            newQso.syncRecords.append(potaSyncRecord)

            // Mark QRZ as already uploaded
            let qrzSyncRecord = SyncRecord(destinationType: .qrz, status: .uploaded, uploadedAt: Date(), qso: newQso)
            modelContext.insert(qrzSyncRecord)
            newQso.syncRecords.append(qrzSyncRecord)

            imported += 1
        }

        try modelContext.save()

        let result = ImportResult(
            totalRecords: qsos.count,
            imported: imported,
            duplicates: updated,  // Using duplicates field for "updated" count
            errors: 0
        )

        lastImportResult = result
        return result
    }
```

**Step 2: Build to verify**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

**Step 3: Commit**

```bash
git add FullDuplex/Services/ImportService.swift
git commit -m "feat(qrz): add importFromQRZ method with merge logic"
```

---

### Task 6: Update Settings UI for Token Auth

**Files:**
- Modify: `FullDuplex/Views/Settings/SettingsView.swift`

**Step 1: Replace QRZ login sheet with token entry**

Replace `QRZLoginSheet` and update the QRZ section in `SettingsMainView`. Find the QRZ section (around line 19-39) and replace with:

```swift
                Section {
                    if qrzIsAuthenticated {
                        HStack {
                            VStack(alignment: .leading) {
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                if let callsign = qrzCallsign {
                                    Text(callsign)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Logout") {
                                logoutQRZ()
                            }
                            .foregroundStyle(.red)
                        }
                    } else {
                        NavigationLink {
                            QRZTokenSetupView(isAuthenticated: $qrzIsAuthenticated, callsign: $qrzCallsign)
                        } label: {
                            Label("Connect to QRZ", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                } header: {
                    Text("QRZ Logbook")
                } footer: {
                    Text("Upload and download logs with QRZ.com logbook")
                }
```

Add `@State private var qrzCallsign: String?` near the other state variables.

Update `checkQRZAuth()`:

```swift
    private func checkQRZAuth() {
        let client = QRZClient()
        Task {
            qrzIsAuthenticated = await client.hasApiKey()
            qrzCallsign = await client.getCallsign()
        }
    }
```

Update `logoutQRZ()`:

```swift
    private func logoutQRZ() {
        Task {
            let client = QRZClient()
            await client.logout()
            qrzIsAuthenticated = false
            qrzCallsign = nil
        }
    }
```

Remove the `qrzUsername` and `qrzPassword` state variables and `showingQRZLogin`.
Remove the `.sheet(isPresented: $showingQRZLogin)` modifier.

**Step 2: Create new QRZTokenSetupView**

Replace the old `QRZLoginSheet` with:

```swift
struct QRZTokenSetupView: View {
    @Binding var isAuthenticated: Bool
    @Binding var callsign: String?

    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        Form {
            Section {
                Text("Enter your QRZ Logbook API key. You can find this in your QRZ logbook settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Link(destination: URL(string: "https://logbook.qrz.com/logbook")!) {
                    Label("Get API key from QRZ Logbook", systemImage: "arrow.up.right.square")
                }

                TextField("API Key", text: $apiKey)
                    .textContentType(.password)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    Task { await validateAndSave() }
                } label: {
                    if isValidating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(apiKey.isEmpty || isValidating)
            }
        }
        .navigationTitle("QRZ Setup")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    private func validateAndSave() async {
        isValidating = true
        defer { isValidating = false }

        do {
            let client = QRZClient()
            let status = try await client.validateApiKey(apiKey)

            try await client.saveApiKey(apiKey)
            try await client.saveCallsign(status.callsign)

            isAuthenticated = true
            callsign = status.callsign
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
```

**Step 3: Build to verify**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

**Step 4: Commit**

```bash
git add FullDuplex/Views/Settings/SettingsView.swift
git commit -m "feat(qrz): replace username/password with token-based auth UI"
```

---

### Task 7: Update Dashboard QRZ Card

**Files:**
- Modify: `FullDuplex/Views/Dashboard/DashboardView.swift`

**Step 1: Add QRZ stats state variables**

Add near other state variables (around line 32):

```swift
    @State private var qrzTotalUploaded: Int = 0
    @State private var qrzTotalDownloaded: Int = 0
    @State private var qrzLastUploadDate: Date?
    @State private var qrzLastDownloadDate: Date?
    @State private var qrzCallsign: String?
    @State private var qrzIsConfigured: Bool = false
```

Add a QRZClient instance:

```swift
    private let qrzClient = QRZClient()
```

**Step 2: Replace the destinationCard for QRZ with a dedicated qrzCard**

Add this new view property:

```swift
    // MARK: - QRZ Card

    private var qrzCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("QRZ Logbook")
                    .font(.headline)
                Spacer()
                if qrzIsConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let callsign = qrzCallsign {
                        Text(callsign)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if qrzIsConfigured {
                // Upload stats
                HStack {
                    Image(systemName: "arrow.up.circle")
                        .foregroundStyle(.blue)
                    Text("\(qrzTotalUploaded) uploaded")
                    Spacer()
                    if let lastUpload = qrzLastUploadDate {
                        Text(lastUpload, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Download stats
                HStack {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.green)
                    Text("\(qrzTotalDownloaded) downloaded")
                    Spacer()
                    if let lastDownload = qrzLastDownloadDate {
                        Text(lastDownload, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Pending uploads
                let pending = pendingSyncs.filter { $0.destinationType == .qrz }.count
                if pending > 0 {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundStyle(.orange)
                        Text("\(pending) pending upload")
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                NavigationLink {
                    QRZTokenSetupView(isAuthenticated: $qrzIsConfigured, callsign: $qrzCallsign)
                } label: {
                    Label("Configure QRZ", systemImage: "gear")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
```

**Step 3: Update the body to use qrzCard**

Replace the `HStack` containing destination cards (around line 50-53):

```swift
                    // Destination Cards
                    qrzCard
                    destinationCard(for: .pota)
```

**Step 4: Add method to load QRZ stats and call it in onAppear**

Add this method:

```swift
    private func loadQRZStats() async {
        qrzIsConfigured = await qrzClient.hasApiKey()
        qrzCallsign = await qrzClient.getCallsign()
        qrzTotalUploaded = await qrzClient.getTotalUploaded()
        qrzTotalDownloaded = await qrzClient.getTotalDownloaded()
        qrzLastUploadDate = await qrzClient.getLastUploadDate()
        qrzLastDownloadDate = await qrzClient.getLastDownloadDate()
    }
```

Add `.task { await loadQRZStats() }` modifier to the ScrollView.

**Step 5: Update performSync to include QRZ download**

Update `performSync`:

```swift
    private func performSync() async {
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        // LoFi sync
        if lofiClient.isConfigured && lofiClient.isLinked {
            await syncFromLoFi()
        }

        // QRZ download
        if await qrzClient.hasApiKey() {
            await syncFromQRZ()
        }

        // Upload to all destinations
        do {
            let result = try await syncService.syncAll()
            print("Sync complete: QRZ uploaded \(result.qrzUploaded), POTA uploaded \(result.potaUploaded)")
        } catch {
            print("Sync error: \(error.localizedDescription)")
        }

        // Reload QRZ stats
        await loadQRZStats()
    }
```

Add new `syncFromQRZ` method:

```swift
    private func syncFromQRZ() async {
        do {
            let qsos = try await qrzClient.fetchQSOs(since: qrzLastDownloadDate)
            if qsos.isEmpty {
                return
            }

            let callsign = await qrzClient.getCallsign() ?? "UNKNOWN"
            _ = try await importService.importFromQRZ(qsos: qsos, myCallsign: callsign)
        } catch {
            print("QRZ sync error: \(error.localizedDescription)")
        }
    }
```

**Step 6: Build to verify**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

**Step 7: Commit**

```bash
git add FullDuplex/Views/Dashboard/DashboardView.swift
git commit -m "feat(qrz): add QRZ stats card with upload/download counts and timestamps"
```

---

### Task 8: Run Full Test Suite and Fix Issues

**Step 1: Run all tests**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

**Step 2: Fix any test failures**

Address any compilation or test errors that arise.

**Step 3: Final commit**

```bash
git add -A
git commit -m "test: ensure all tests pass after QRZ token auth refactor"
```

---

## Summary

This plan implements:
1. Token-based authentication for QRZ (replacing username/password)
2. Bidirectional sync (upload and download QSOs)
3. QSO merge logic that updates existing records with QRZ data
4. Dashboard showing cumulative upload/download counts with timestamps
5. Settings UI with link to QRZ logbook for getting API key
