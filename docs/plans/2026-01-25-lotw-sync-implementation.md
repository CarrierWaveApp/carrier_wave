# LoTW Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add ARRL Logbook of the World (LoTW) as a download-only sync source for QSOs and QSL confirmations.

**Architecture:** LoTW is download-only (no upload API). Uses username/password auth via query parameters, returns ADIF format. Stores confirmation status directly on QSO model. Integrates with existing sync orchestration.

**Tech Stack:** Swift, SwiftUI, SwiftData, URLSession, Keychain

---

## Task 1: Add LoTW to ServiceType and ImportSource

**Files:**
- Modify: `CarrierWave/Models/Types.swift`

**Step 1: Add lotw case to ImportSource enum**

In `Types.swift`, add `lotw` to the `ImportSource` enum:

```swift
enum ImportSource: String, Codable {
    case lofi
    case adifFile
    case icloud
    case qrz
    case pota
    case hamrs
    case lotw
}
```

**Step 2: Add lotw case to ServiceType enum**

Add `lotw` to `ServiceType` enum and update computed properties:

```swift
enum ServiceType: String, Codable, CaseIterable {
    case qrz
    case pota
    case lofi
    case hamrs
    case lotw

    var displayName: String {
        switch self {
        case .qrz: "QRZ"
        case .pota: "POTA"
        case .lofi: "LoFi"
        case .hamrs: "HAMRS"
        case .lotw: "LoTW"
        }
    }

    var supportsUpload: Bool {
        switch self {
        case .qrz, .pota: true
        case .lofi, .hamrs, .lotw: false
        }
    }

    var toImportSource: ImportSource {
        switch self {
        case .qrz: .qrz
        case .pota: .pota
        case .lofi: .lofi
        case .hamrs: .hamrs
        case .lotw: .lotw
        }
    }
}
```

**Step 3: Commit**

```bash
git add CarrierWave/Models/Types.swift
git commit -m "feat: add LoTW to ServiceType and ImportSource enums"
```

---

## Task 2: Add lotwConfirmed field to QSO model

**Files:**
- Modify: `CarrierWave/Models/QSO.swift`

**Step 1: Add lotwConfirmed property**

The `lotwConfirmedDate` field already exists on QSO. Add `lotwConfirmed` boolean property after it:

```swift
// QRZ sync tracking
var qrzLogId: String?
var qrzConfirmed: Bool = false
var lotwConfirmedDate: Date?
var lotwConfirmed: Bool = false
```

**Step 2: Update init to include lotwConfirmed**

Add `lotwConfirmed: Bool = false` parameter to init and set it:

```swift
init(
    // ... existing params ...
    lotwConfirmedDate: Date? = nil,
    lotwConfirmed: Bool = false
) {
    // ... existing assignments ...
    self.lotwConfirmedDate = lotwConfirmedDate
    self.lotwConfirmed = lotwConfirmed
}
```

**Step 3: Commit**

```bash
git add CarrierWave/Models/QSO.swift
git commit -m "feat: add lotwConfirmed field to QSO model"
```

---

## Task 3: Add LoTW Keychain keys

**Files:**
- Modify: `CarrierWave/Utilities/KeychainHelper.swift`

**Step 1: Add LoTW keys to Keys enum**

Add after the HAMRS keys section:

```swift
/// LoTW
static let lotwUsername = "lotw.username"
static let lotwPassword = "lotw.password"
static let lotwLastQSL = "lotw.last.qsl"
static let lotwLastQSORx = "lotw.last.qso.rx"
```

**Step 2: Commit**

```bash
git add CarrierWave/Utilities/KeychainHelper.swift
git commit -m "feat: add LoTW keychain keys"
```

---

## Task 4: Create LoTWError enum

**Files:**
- Create: `CarrierWave/Services/LoTWError.swift`

**Step 1: Create the error file**

```swift
import Foundation

enum LoTWError: Error, LocalizedError {
    case authenticationFailed
    case serviceError(String)
    case invalidResponse(String)
    case noCredentials

    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            "LoTW authentication failed. Check your username and password."
        case let .serviceError(message):
            "LoTW service error: \(message)"
        case let .invalidResponse(details):
            "Invalid response from LoTW: \(details)"
        case .noCredentials:
            "LoTW credentials not configured"
        }
    }
}
```

**Step 2: Commit**

```bash
git add CarrierWave/Services/LoTWError.swift
git commit -m "feat: add LoTWError enum"
```

---

## Task 5: Create LoTWClient actor

**Files:**
- Create: `CarrierWave/Services/LoTWClient.swift`

**Step 1: Create the client file**

```swift
import Foundation

struct LoTWResponse {
    let qsos: [LoTWFetchedQSO]
    let lastQSL: Date?
    let lastQSORx: Date?
    let recordCount: Int
}

struct LoTWFetchedQSO {
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
    let state: String?
    let country: String?
    let dxcc: Int?
    let qslReceived: Bool
    let qslReceivedDate: Date?
    let rawADIF: String
}

actor LoTWClient {
    private let baseURL = "https://lotw.arrl.org/lotwuser/lotwreport.adi"
    nonisolated let keychain = KeychainHelper.shared
    private let userAgent = "CarrierWave/1.0"

    // MARK: - Credential Management

    func saveCredentials(username: String, password: String) throws {
        try keychain.save(username, for: KeychainHelper.Keys.lotwUsername)
        try keychain.save(password, for: KeychainHelper.Keys.lotwPassword)
    }

    func getCredentials() throws -> (username: String, password: String) {
        let username = try keychain.readString(for: KeychainHelper.Keys.lotwUsername)
        let password = try keychain.readString(for: KeychainHelper.Keys.lotwPassword)
        return (username, password)
    }

    func hasCredentials() -> Bool {
        do {
            _ = try getCredentials()
            return true
        } catch {
            return false
        }
    }

    func clearCredentials() {
        try? keychain.delete(for: KeychainHelper.Keys.lotwUsername)
        try? keychain.delete(for: KeychainHelper.Keys.lotwPassword)
        try? keychain.delete(for: KeychainHelper.Keys.lotwLastQSL)
        try? keychain.delete(for: KeychainHelper.Keys.lotwLastQSORx)
    }

    // MARK: - Sync Timestamps

    func getLastQSLDate() -> Date? {
        guard let dateString = try? keychain.readString(for: KeychainHelper.Keys.lotwLastQSL) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: dateString)
    }

    func saveLastQSLDate(_ date: Date) throws {
        let dateString = ISO8601DateFormatter().string(from: date)
        try keychain.save(dateString, for: KeychainHelper.Keys.lotwLastQSL)
    }

    func getLastQSORxDate() -> Date? {
        guard let dateString = try? keychain.readString(for: KeychainHelper.Keys.lotwLastQSORx) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: dateString)
    }

    func saveLastQSORxDate(_ date: Date) throws {
        let dateString = ISO8601DateFormatter().string(from: date)
        try keychain.save(dateString, for: KeychainHelper.Keys.lotwLastQSORx)
    }

    // MARK: - API Methods

    func fetchQSOs(qslSince: Date? = nil, qsoRxSince: Date? = nil) async throws -> LoTWResponse {
        let credentials = try getCredentials()

        var components = URLComponents(string: baseURL)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "login", value: credentials.username),
            URLQueryItem(name: "password", value: credentials.password),
            URLQueryItem(name: "qso_query", value: "1"),
            URLQueryItem(name: "qso_qsl", value: "yes"),
            URLQueryItem(name: "qso_mydetail", value: "yes"),
            URLQueryItem(name: "qso_qsldetail", value: "yes"),
            URLQueryItem(name: "qso_withown", value: "yes"),
        ]

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        if let since = qslSince {
            queryItems.append(URLQueryItem(name: "qso_qslsince", value: dateFormatter.string(from: since)))
        }

        if let since = qsoRxSince {
            queryItems.append(URLQueryItem(name: "qso_qsorxsince", value: dateFormatter.string(from: since)))
        }

        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw LoTWError.invalidResponse("Cannot decode response as UTF-8")
        }

        // Check for EOH tag to verify success
        guard responseString.contains("<EOH>") || responseString.contains("<eoh>") else {
            // Check for common error patterns
            if responseString.lowercased().contains("password incorrect") ||
                responseString.lowercased().contains("username not found") {
                throw LoTWError.authenticationFailed
            }
            throw LoTWError.serviceError(String(responseString.prefix(200)))
        }

        return parseADIFResponse(responseString)
    }

    /// Test credentials by fetching recent QSLs only
    func testCredentials(username: String, password: String) async throws {
        var components = URLComponents(string: baseURL)!

        // Use a recent date to minimize data transfer
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let recentDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        components.queryItems = [
            URLQueryItem(name: "login", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "qso_query", value: "1"),
            URLQueryItem(name: "qso_qsl", value: "yes"),
            URLQueryItem(name: "qso_qslsince", value: dateFormatter.string(from: recentDate)),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw LoTWError.invalidResponse("Cannot decode response as UTF-8")
        }

        guard responseString.contains("<EOH>") || responseString.contains("<eoh>") else {
            if responseString.lowercased().contains("password incorrect") ||
                responseString.lowercased().contains("username not found") {
                throw LoTWError.authenticationFailed
            }
            throw LoTWError.serviceError(String(responseString.prefix(200)))
        }
    }

    // MARK: - ADIF Parsing

    private func parseADIFResponse(_ adif: String) -> LoTWResponse {
        var qsos: [LoTWFetchedQSO] = []
        var lastQSL: Date?
        var lastQSORx: Date?
        var recordCount = 0

        // Parse header for metadata
        if let headerEnd = adif.range(of: "<EOH>", options: .caseInsensitive) {
            let header = String(adif[..<headerEnd.lowerBound])
            lastQSL = parseHeaderDate(header, field: "APP_LoTW_LASTQSL")
            lastQSORx = parseHeaderDate(header, field: "APP_LoTW_LASTQSORX")
            if let count = parseHeaderField(header, field: "APP_LoTW_NUMREC") {
                recordCount = Int(count) ?? 0
            }
        }

        // Split into records
        let records = adif.components(separatedBy: "<EOR>")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.contains("<") }

        for record in records {
            // Skip header
            if record.uppercased().contains("<EOH>") {
                continue
            }

            if let qso = parseQSORecord(record) {
                qsos.append(qso)
            }
        }

        return LoTWResponse(
            qsos: qsos,
            lastQSL: lastQSL,
            lastQSORx: lastQSORx,
            recordCount: recordCount
        )
    }

    private func parseHeaderField(_ header: String, field: String) -> String? {
        let pattern = "<\(field):([0-9]+)>([^<]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
              let valueRange = Range(match.range(at: 2), in: header)
        else {
            return nil
        }
        return String(header[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseHeaderDate(_ header: String, field: String) -> Date? {
        guard let value = parseHeaderField(header, field: field) else {
            return nil
        }
        // Format: YYYY-MM-DD HH:MM:SS
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: value)
    }

    private func parseQSORecord(_ record: String) -> LoTWFetchedQSO? {
        func field(_ name: String) -> String? {
            let pattern = "<\(name):([0-9]+)>([^<]*)"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: record, range: NSRange(record.startIndex..., in: record)),
                  let valueRange = Range(match.range(at: 2), in: record)
            else {
                return nil
            }
            let value = String(record[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        guard let callsign = field("CALL"),
              let band = field("BAND"),
              let mode = field("MODE"),
              let qsoDateStr = field("QSO_DATE")
        else {
            return nil
        }

        let timeOnStr = field("TIME_ON") ?? "0000"

        // Parse date/time
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyyMMddHHmm"

        let dateTimeStr = qsoDateStr + timeOnStr.prefix(4)
        guard let timestamp = dateFormatter.date(from: dateTimeStr) else {
            return nil
        }

        // Parse QSL received date
        var qslReceivedDate: Date?
        if let qslDateStr = field("QSLRDATE") {
            dateFormatter.dateFormat = "yyyyMMdd"
            qslReceivedDate = dateFormatter.date(from: qslDateStr)
        }

        let qslReceived = field("QSL_RCVD")?.uppercased() == "Y"

        return LoTWFetchedQSO(
            callsign: callsign,
            band: band,
            mode: mode,
            frequency: field("FREQ").flatMap { Double($0) },
            timestamp: timestamp,
            rstSent: field("RST_SENT"),
            rstReceived: field("RST_RCVD"),
            myCallsign: field("STATION_CALLSIGN") ?? field("APP_LoTW_OWNCALL"),
            myGrid: field("MY_GRIDSQUARE"),
            theirGrid: field("GRIDSQUARE"),
            state: field("STATE"),
            country: field("COUNTRY"),
            dxcc: field("DXCC").flatMap { Int($0) },
            qslReceived: qslReceived,
            qslReceivedDate: qslReceivedDate,
            rawADIF: record
        )
    }
}
```

**Step 2: Commit**

```bash
git add CarrierWave/Services/LoTWClient.swift
git commit -m "feat: add LoTWClient actor for LoTW API integration"
```

---

## Task 6: Add FetchedQSO.fromLoTW factory method

**Files:**
- Modify: `CarrierWave/Services/FetchedQSO.swift`

**Step 1: Add lotwConfirmed to FetchedQSO struct**

Add after `lotwConfirmedDate`:

```swift
let lotwConfirmed: Bool
```

**Step 2: Update all existing factory methods to include lotwConfirmed**

In `fromQRZ`:
```swift
lotwConfirmed: false,
```

In `fromPOTA`:
```swift
lotwConfirmed: false,
```

In `fromLoFi`:
```swift
lotwConfirmed: false,
```

In `fromHAMRS`:
```swift
lotwConfirmed: false,
```

**Step 3: Add fromLoTW factory method**

```swift
/// Create from LoTW fetched QSO
static func fromLoTW(_ lotw: LoTWFetchedQSO) -> FetchedQSO {
    FetchedQSO(
        callsign: lotw.callsign,
        band: lotw.band,
        mode: lotw.mode,
        frequency: lotw.frequency,
        timestamp: lotw.timestamp,
        rstSent: lotw.rstSent,
        rstReceived: lotw.rstReceived,
        myCallsign: lotw.myCallsign ?? "",
        myGrid: lotw.myGrid,
        theirGrid: lotw.theirGrid,
        parkReference: nil,
        theirParkReference: nil,
        notes: nil,
        rawADIF: lotw.rawADIF,
        name: nil,
        qth: nil,
        state: lotw.state,
        country: lotw.country,
        power: nil,
        sotaRef: nil,
        qrzLogId: nil,
        qrzConfirmed: false,
        lotwConfirmedDate: lotw.qslReceivedDate,
        lotwConfirmed: lotw.qslReceived,
        source: .lotw
    )
}
```

**Step 4: Commit**

```bash
git add CarrierWave/Services/FetchedQSO.swift
git commit -m "feat: add FetchedQSO.fromLoTW factory method"
```

---

## Task 7: Update SyncService+Process to handle LoTW confirmation

**Files:**
- Modify: `CarrierWave/Services/SyncService+Process.swift`

**Step 1: Update mergeIntoExisting to handle LoTW confirmation**

Add after the QRZ-specific section:

```swift
// LoTW-specific: update confirmation status
if fetched.source == .lotw {
    if fetched.lotwConfirmed {
        existing.lotwConfirmed = true
        existing.lotwConfirmedDate = existing.lotwConfirmedDate ?? fetched.lotwConfirmedDate
    }
}
```

**Step 2: Update mergeFetchedGroup to include lotwConfirmed**

In the `FetchedQSO` constructor inside `mergeFetchedGroup`, add:

```swift
lotwConfirmed: merged.lotwConfirmed || other.lotwConfirmed,
```

**Step 3: Update createQSO to include lotwConfirmed**

Add to the `QSO` constructor in `createQSO`:

```swift
lotwConfirmed: fetched.lotwConfirmed
```

**Step 4: Commit**

```bash
git add CarrierWave/Services/SyncService+Process.swift
git commit -m "feat: update SyncService+Process to handle LoTW confirmation"
```

---

## Task 8: Add LoTW download to SyncService

**Files:**
- Modify: `CarrierWave/Services/SyncService.swift`
- Modify: `CarrierWave/Services/SyncService+Download.swift`

**Step 1: Add lotwClient to SyncService**

In `SyncService.swift`, add property:

```swift
let lotwClient: LoTWClient
```

Update init:

```swift
init(
    modelContext: ModelContext, potaAuthService: POTAAuthService,
    lofiClient: LoFiClient = LoFiClient(),
    hamrsClient: HAMRSClient = HAMRSClient(),
    lotwClient: LoTWClient = LoTWClient()
) {
    self.modelContext = modelContext
    qrzClient = QRZClient()
    self.potaAuthService = potaAuthService
    potaClient = POTAClient(authService: potaAuthService)
    self.lofiClient = lofiClient
    self.hamrsClient = hamrsClient
    self.lotwClient = lotwClient
}
```

**Step 2: Add syncLoTW method to SyncService**

Add after `syncHAMRS`:

```swift
/// Sync only with LoTW (download only)
func syncLoTW() async throws -> Int {
    isSyncing = true
    defer {
        isSyncing = false
        syncPhase = nil
    }

    syncPhase = .downloading(service: .lotw)
    let qslSince = await lotwClient.getLastQSLDate()
    let response = try await withTimeout(seconds: syncTimeoutSeconds, service: .lotw) {
        try await self.lotwClient.fetchQSOs(qslSince: qslSince)
    }
    let fetched = response.qsos.map { FetchedQSO.fromLoTW($0) }

    syncPhase = .processing
    let processResult = try processDownloadedQSOs(fetched)

    // Save timestamps for incremental sync
    if let lastQSL = response.lastQSL {
        try await lotwClient.saveLastQSLDate(lastQSL)
    }
    if let lastQSORx = response.lastQSORx {
        try await lotwClient.saveLastQSORxDate(lastQSORx)
    }

    try modelContext.save()
    return processResult.created
}
```

**Step 3: Add downloadFromLoTW to SyncService+Download**

Add the download method:

```swift
private func downloadFromLoTW(timeout: TimeInterval) async -> (ServiceType, Result<[FetchedQSO], Error>) {
    await MainActor.run { self.syncPhase = .downloading(service: .lotw) }
    let debugLog = SyncDebugLog.shared
    debugLog.info("Starting LoTW download", service: .lotw)
    do {
        let qslSince = await lotwClient.getLastQSLDate()
        let response = try await withTimeout(seconds: timeout, service: .lotw) {
            try await self.lotwClient.fetchQSOs(qslSince: qslSince)
        }
        debugLog.info("Downloaded \(response.qsos.count) QSOs from LoTW", service: .lotw)

        let fetched = response.qsos.map { FetchedQSO.fromLoTW($0) }

        // Save timestamps for incremental sync
        if let lastQSL = response.lastQSL {
            try await lotwClient.saveLastQSLDate(lastQSL)
        }
        if let lastQSORx = response.lastQSORx {
            try await lotwClient.saveLastQSORxDate(lastQSORx)
        }

        for (index, qso) in response.qsos.prefix(5).enumerated() {
            debugLog.logRawQSO(
                service: .lotw,
                rawJSON: qso.rawADIF,
                parsedFields: fetched[index].debugFields
            )
        }
        return (.lotw, .success(fetched))
    } catch {
        debugLog.error("LoTW download failed: \(error.localizedDescription)", service: .lotw)
        return (.lotw, .failure(error))
    }
}
```

**Step 4: Add LoTW to downloadFromAllSources**

In `downloadFromAllSources()`, add after HAMRS:

```swift
// LoTW download
if await lotwClient.hasCredentials() {
    group.addTask {
        await self.downloadFromLoTW(timeout: timeout)
    }
}
```

**Step 5: Commit**

```bash
git add CarrierWave/Services/SyncService.swift CarrierWave/Services/SyncService+Download.swift
git commit -m "feat: integrate LoTW into sync service"
```

---

## Task 9: Create LoTWSettingsView

**Files:**
- Create: `CarrierWave/Views/Settings/LoTWSettingsView.swift`

**Step 1: Create the settings view**

```swift
import SwiftUI

struct LoTWSettingsView: View {
    @State private var isAuthenticated = false
    @State private var username = ""
    @State private var password = ""
    @State private var showingLogin = false
    @State private var errorMessage = ""
    @State private var showingError = false

    private let lotwClient = LoTWClient()

    var body: some View {
        List {
            if isAuthenticated {
                Section {
                    HStack {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text(username)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Status")
                }

                Section {
                    Button("Logout", role: .destructive) {
                        logout()
                    }
                }
            } else {
                Section {
                    Text("Connect your LoTW account to import QSOs and QSL confirmations.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Connect to LoTW") {
                        showingLogin = true
                    }
                } header: {
                    Text("Setup")
                } footer: {
                    Text("Uses your LoTW website username and password.")
                }

                Section {
                    Link(destination: URL(string: "https://lotw.arrl.org")!) {
                        Label("Visit LoTW Website", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .navigationTitle("LoTW")
        .sheet(isPresented: $showingLogin) {
            LoTWLoginSheet(
                isAuthenticated: $isAuthenticated,
                storedUsername: $username,
                errorMessage: $errorMessage,
                showingError: $showingError
            )
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .task {
            await checkStatus()
        }
    }

    private func checkStatus() async {
        isAuthenticated = await lotwClient.hasCredentials()
        if isAuthenticated {
            if let creds = try? await lotwClient.getCredentials() {
                username = creds.username
            }
        }
    }

    private func logout() {
        Task {
            await lotwClient.clearCredentials()
            await checkStatus()
        }
    }
}

struct LoTWLoginSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var isAuthenticated: Bool
    @Binding var storedUsername: String
    @Binding var errorMessage: String
    @Binding var showingError: Bool

    @State private var username = ""
    @State private var password = ""
    @State private var isValidating = false

    private let lotwClient = LoTWClient()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter your LoTW website login credentials.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                Section {
                    Button {
                        Task { await validateAndSave() }
                    } label: {
                        if isValidating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || isValidating)
                }
            }
            .navigationTitle("LoTW Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func validateAndSave() async {
        isValidating = true
        defer { isValidating = false }

        do {
            try await lotwClient.testCredentials(username: username, password: password)
            try await lotwClient.saveCredentials(username: username, password: password)
            storedUsername = username
            isAuthenticated = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
```

**Step 2: Commit**

```bash
git add CarrierWave/Views/Settings/LoTWSettingsView.swift
git commit -m "feat: add LoTWSettingsView"
```

---

## Task 10: Add LoTW to SettingsMainView

**Files:**
- Modify: `CarrierWave/Views/Settings/SettingsView.swift`

**Step 1: Add lotwClient property**

Add after `hamrsClient`:

```swift
private let lotwClient = LoTWClient()
```

**Step 2: Add LoTW state**

Add after `qrzCallsign`:

```swift
@State private var lotwIsConfigured = false
@State private var lotwUsername: String?
```

**Step 3: Add LoTW navigation row**

Add after the HAMRS NavigationLink, before iCloud:

```swift
// LoTW
NavigationLink {
    LoTWSettingsView()
} label: {
    HStack {
        Label("LoTW", systemImage: "envelope.badge.shield.half.filled")
        Spacer()
        if lotwIsConfigured {
            if let username = lotwUsername {
                Text(username)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}
```

**Step 4: Update loadServiceStatus**

Add at the end of `loadServiceStatus()`:

```swift
lotwIsConfigured = await lotwClient.hasCredentials()
if lotwIsConfigured {
    if let creds = try? await lotwClient.getCredentials() {
        lotwUsername = creds.username
    }
}
```

**Step 5: Commit**

```bash
git add CarrierWave/Views/Settings/SettingsView.swift
git commit -m "feat: add LoTW to settings navigation"
```

---

## Task 11: Update CLAUDE.md file index

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add new files to index**

In the Services section, add:

```markdown
| `LoTWClient.swift` | LoTW API client (download-only, username/password auth) |
| `LoTWError.swift` | LoTW-specific errors |
```

In the Views - Settings section, add:

```markdown
| `LoTWSettingsView.swift` | LoTW login configuration |
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add LoTW files to CLAUDE.md index"
```

---

## Task 12: Update sync documentation

**Files:**
- Modify: `docs/features/sync.md`

**Step 1: Add LoTW section**

Add after the Ham2K LoFi section:

```markdown
### ARRL LoTW

- **Auth**: Username/password via query params
- **Download**: ADIF via `lotwreport.adi` endpoint
- **Upload**: Not supported (requires TQSL application)
- **Keychain keys**: `lotw_username`, `lotw_password`, `lotw_last_qsl`, `lotw_last_qso_rx`
- **Special handling**: Provides QSL confirmation status (`lotwConfirmed`, `lotwConfirmedDate`)
```

**Step 2: Update data flow diagram**

Update the diagram to include LoTW:

```markdown
```
ADIF Import → ADIFParser → ImportService → QSO + SyncRecord (pending)
                                              ↓
                                         SyncService
                                              ↓
                              ┌───────────────┼───────────────┬───────────────┐
                              ↓               ↓               ↓               ↓
                          QRZClient      POTAClient      LoFiClient      LoTWClient
                              ↓               ↓               ↓               ↓
                         SyncRecord status updated       (download only, no SyncRecord)
```
```

**Step 3: Commit**

```bash
git add docs/features/sync.md
git commit -m "docs: add LoTW to sync documentation"
```

---

## Task 13: Final verification and push

**Step 1: Ask user to build and test**

Ask the user to run:
- `make build` to verify compilation
- Test the app manually to verify LoTW settings and sync work

**Step 2: Push to remote**

```bash
git push
```
