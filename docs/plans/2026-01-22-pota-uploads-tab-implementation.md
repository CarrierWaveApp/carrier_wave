# POTA Uploads Tab Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a tab showing POTA upload history with local attempts, POTA job statuses, and correlation between them.

**Architecture:** New SwiftData model for local upload attempts, in-memory structs for POTA jobs, unified timeline view merging both with expandable detail rows. POTAClient extended with job fetching and upload instrumentation.

**Tech Stack:** SwiftUI, SwiftData, async/await networking

---

## Task 1: Create POTAJob Model

**Files:**
- Create: `FullDuplex/Models/POTAJob.swift`

**Step 1: Create the POTAJob struct and status enum**

```swift
import Foundation

enum POTAJobStatus: Int, Codable {
    case pending = 0
    case processing = 1
    case completed = 2
    case failed = 3
    case duplicate = 7
    case error = -1

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .processing: return "Processing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .duplicate: return "Duplicate"
        case .error: return "Error"
        }
    }

    var color: String {
        switch self {
        case .pending, .processing: return "orange"
        case .completed: return "green"
        case .failed, .error: return "red"
        case .duplicate: return "yellow"
        }
    }
}

struct POTAJob: Identifiable, Codable {
    let jobId: Int
    let status: POTAJobStatus
    let submitted: Date
    let processed: Date?
    let reference: String
    let parkName: String?
    let location: String?
    let totalQsos: Int
    let insertedQsos: Int
    let callsignUsed: String?
    let userComment: String?

    var id: Int { jobId }

    enum CodingKeys: String, CodingKey {
        case jobId, status, submitted, processed, reference, location
        case parkName = "parkName"
        case totalQsos = "total"
        case insertedQsos = "inserted"
        case callsignUsed = "callsignUsed"
        case userComment = "userComment"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decode(Int.self, forKey: .jobId)
        let statusInt = try container.decode(Int.self, forKey: .status)
        status = POTAJobStatus(rawValue: statusInt) ?? .error
        reference = try container.decode(String.self, forKey: .reference)
        parkName = try container.decodeIfPresent(String.self, forKey: .parkName)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        totalQsos = try container.decodeIfPresent(Int.self, forKey: .totalQsos) ?? -1
        insertedQsos = try container.decodeIfPresent(Int.self, forKey: .insertedQsos) ?? -1
        callsignUsed = try container.decodeIfPresent(String.self, forKey: .callsignUsed)
        userComment = try container.decodeIfPresent(String.self, forKey: .userComment)

        // Parse dates
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        let submittedStr = try container.decode(String.self, forKey: .submitted)
        submitted = dateFormatter.date(from: submittedStr)
            ?? fallbackFormatter.date(from: submittedStr)
            ?? Date()

        if let processedStr = try container.decodeIfPresent(String.self, forKey: .processed) {
            processed = dateFormatter.date(from: processedStr)
                ?? fallbackFormatter.date(from: processedStr)
        } else {
            processed = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jobId, forKey: .jobId)
        try container.encode(status.rawValue, forKey: .status)
        try container.encode(reference, forKey: .reference)
        try container.encodeIfPresent(parkName, forKey: .parkName)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(totalQsos, forKey: .totalQsos)
        try container.encode(insertedQsos, forKey: .insertedQsos)
        try container.encodeIfPresent(callsignUsed, forKey: .callsignUsed)
        try container.encodeIfPresent(userComment, forKey: .userComment)

        let dateFormatter = ISO8601DateFormatter()
        try container.encode(dateFormatter.string(from: submitted), forKey: .submitted)
        if let processed = processed {
            try container.encode(dateFormatter.string(from: processed), forKey: .processed)
        }
    }

    // For testing/previews
    init(jobId: Int, status: POTAJobStatus, submitted: Date, processed: Date?,
         reference: String, parkName: String?, location: String?,
         totalQsos: Int, insertedQsos: Int, callsignUsed: String?, userComment: String?) {
        self.jobId = jobId
        self.status = status
        self.submitted = submitted
        self.processed = processed
        self.reference = reference
        self.parkName = parkName
        self.location = location
        self.totalQsos = totalQsos
        self.insertedQsos = insertedQsos
        self.callsignUsed = callsignUsed
        self.userComment = userComment
    }
}
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add FullDuplex/Models/POTAJob.swift
git commit -m "feat(pota): add POTAJob struct and status enum for job tracking"
```

---

## Task 2: Create POTAUploadAttempt SwiftData Model

**Files:**
- Create: `FullDuplex/Models/POTAUploadAttempt.swift`

**Step 1: Create the SwiftData model**

```swift
import Foundation
import SwiftData

@Model
class POTAUploadAttempt {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var parkReference: String = ""
    var qsoCount: Int = 0
    var callsign: String = ""
    var location: String = ""

    // Request details
    var adifContent: String = ""
    @Attribute(.transformable(by: DictionaryTransformer.self))
    var requestHeaders: [String: String] = [:]
    var filename: String = ""

    // Response details
    var httpStatusCode: Int?
    var responseBody: String?
    var errorMessage: String?
    var success: Bool = false

    // Timing
    var requestDurationMs: Int?

    // Correlation
    var correlatedJobId: Int?

    init(
        timestamp: Date = Date(),
        parkReference: String,
        qsoCount: Int,
        callsign: String,
        location: String,
        adifContent: String,
        requestHeaders: [String: String],
        filename: String
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.parkReference = parkReference
        self.qsoCount = qsoCount
        self.callsign = callsign
        self.location = location
        self.adifContent = adifContent
        self.requestHeaders = requestHeaders
        self.filename = filename
    }

    func markCompleted(httpStatusCode: Int, responseBody: String?, durationMs: Int) {
        self.httpStatusCode = httpStatusCode
        self.responseBody = responseBody
        self.requestDurationMs = durationMs
        self.success = (200...299).contains(httpStatusCode)
        self.errorMessage = nil
    }

    func markFailed(httpStatusCode: Int?, responseBody: String?, errorMessage: String, durationMs: Int?) {
        self.httpStatusCode = httpStatusCode
        self.responseBody = responseBody
        self.errorMessage = errorMessage
        self.requestDurationMs = durationMs
        self.success = false
    }
}

// Custom transformer for [String: String] dictionary
final class DictionaryTransformer: ValueTransformer {
    override class func transformedValueClass() -> AnyClass {
        NSData.self
    }

    override class func allowsReverseTransformation() -> Bool {
        true
    }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let dict = value as? [String: String] else { return nil }
        return try? JSONEncoder().encode(dict)
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    static func register() {
        ValueTransformer.setValueTransformer(
            DictionaryTransformer(),
            forName: NSValueTransformerName("DictionaryTransformer")
        )
    }
}
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add FullDuplex/Models/POTAUploadAttempt.swift
git commit -m "feat(pota): add POTAUploadAttempt SwiftData model for upload history"
```

---

## Task 3: Register Model in App Container

**Files:**
- Modify: `FullDuplex/FullDuplexApp.swift:7-12`

**Step 1: Update the schema to include POTAUploadAttempt**

In `FullDuplexApp.swift`, update the `sharedModelContainer` property:

```swift
    var sharedModelContainer: ModelContainer = {
        // Register value transformer before creating container
        DictionaryTransformer.register()

        let schema = Schema([
            QSO.self,
            ServicePresence.self,
            UploadDestination.self,
            POTAUploadAttempt.self,
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
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add FullDuplex/FullDuplexApp.swift
git commit -m "feat(pota): register POTAUploadAttempt in SwiftData container"
```

---

## Task 4: Add fetchJobs Method to POTAClient

**Files:**
- Modify: `FullDuplex/Services/POTAClient.swift`

**Step 1: Add the fetchJobs method after fetchAllQSOs (around line 510)**

Add this method to `POTAClient` actor:

```swift
    // MARK: - Job Status Methods

    /// Fetch upload job statuses from POTA API
    func fetchJobs() async throws -> [POTAJob] {
        let debugLog = await SyncDebugLog.shared
        let token = try await authService.ensureValidToken()

        guard let url = URL(string: "\(baseURL)/user/jobs") else {
            await debugLog.error("Invalid URL for POTA jobs", service: .pota)
            throw POTAError.fetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")

        await debugLog.debug("GET /user/jobs", service: .pota)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            await debugLog.error("Invalid response (not HTTP)", service: .pota)
            throw POTAError.fetchFailed("Invalid response")
        }

        await debugLog.debug("Jobs response: \(httpResponse.statusCode)", service: .pota)

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw POTAError.notAuthenticated
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            await debugLog.error("Jobs fetch failed: \(httpResponse.statusCode) - \(body)", service: .pota)
            throw POTAError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        let jobs = try JSONDecoder().decode([POTAJob].self, from: data)
        await debugLog.info("Fetched \(jobs.count) POTA jobs", service: .pota)
        return jobs
    }
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add FullDuplex/Services/POTAClient.swift
git commit -m "feat(pota): add fetchJobs method to POTAClient"
```

---

## Task 5: Instrument Upload with Attempt Recording

**Files:**
- Modify: `FullDuplex/Services/POTAClient.swift:162-282`

**Step 1: Add modelContext parameter and recording logic**

Replace the `uploadActivation` method signature and add instrumentation. The method needs access to a ModelContext to save attempts. Create a new instrumented version:

```swift
    /// Upload activation with attempt recording for debugging
    func uploadActivationWithRecording(
        parkReference: String,
        qsos: [QSO],
        modelContext: ModelContext
    ) async throws -> POTAUploadResult {
        let debugLog = await SyncDebugLog.shared
        let startTime = Date()

        // Validate park reference format
        let parkPattern = #"^[A-Za-z]{1,4}-\d{1,6}$"#
        guard parkReference.range(of: parkPattern, options: .regularExpression) != nil else {
            await debugLog.error("Invalid park reference format: '\(parkReference)' (expected format like K-1234)", service: .pota)
            throw POTAError.invalidParkReference
        }

        let normalizedParkRef = parkReference.uppercased()

        // Get token (don't record attempt yet in case auth fails)
        let token = try await authService.ensureValidToken()

        // Filter QSOs for this park
        let parkQSOs = qsos.filter { $0.parkReference?.uppercased() == normalizedParkRef }
        guard !parkQSOs.isEmpty else {
            await debugLog.info("No QSOs to upload for park \(normalizedParkRef)", service: .pota)
            return POTAUploadResult(success: true, qsosAccepted: 0, message: "No QSOs for this park")
        }

        await debugLog.info("Uploading \(parkQSOs.count) QSOs to park \(normalizedParkRef)", service: .pota)

        let callsign = parkQSOs.first?.myCallsign ?? "UNKNOWN"
        let parkPrefix = normalizedParkRef.split(separator: "-").first.map(String.init) ?? "US"
        let myGrid = parkQSOs.first?.myGrid
        let derivedState = myGrid.flatMap { Self.gridToUSState($0) }
        let location: String
        if parkPrefix == "US" || parkPrefix == "K", let state = derivedState {
            location = "US-\(state)"
        } else {
            location = parkPrefix
        }

        let adifContent = generateADIF(for: parkQSOs, parkReference: normalizedParkRef)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyMMdd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = parkQSOs.first.map { dateFormatter.string(from: $0.timestamp) } ?? "000000"
        let filename = "\(callsign)@\(normalizedParkRef)-\(dateStr).adi"

        // Build request
        let boundary = UUID().uuidString
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"adif\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(adifContent.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        for (name, value) in [("reference", normalizedParkRef), ("location", location), ("callsign", callsign)] {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        guard let url = URL(string: "\(baseURL)/adif") else {
            await debugLog.error("Invalid URL for POTA upload", service: .pota)
            throw POTAError.uploadFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        // Capture headers for recording (redact auth token)
        let recordedHeaders = [
            "Content-Type": "multipart/form-data; boundary=\(boundary)",
            "Authorization": "[REDACTED]"
        ]

        // Create upload attempt record
        let attempt = await MainActor.run {
            let attempt = POTAUploadAttempt(
                timestamp: startTime,
                parkReference: normalizedParkRef,
                qsoCount: parkQSOs.count,
                callsign: callsign,
                location: location,
                adifContent: adifContent,
                requestHeaders: recordedHeaders,
                filename: filename
            )
            modelContext.insert(attempt)
            return attempt
        }

        await debugLog.debug("POST /adif - callsign=\(callsign), location=\(location), reference=\(normalizedParkRef), filename=\(filename)", service: .pota)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    attempt.markFailed(httpStatusCode: nil, responseBody: nil, errorMessage: "Invalid response (not HTTP)", durationMs: durationMs)
                }
                await debugLog.error("Invalid response (not HTTP)", service: .pota)
                throw POTAError.uploadFailed("Invalid response")
            }

            let responseBody = String(data: data, encoding: .utf8) ?? "(binary data)"
            await debugLog.debug("Response \(httpResponse.statusCode): \(responseBody.prefix(500))", service: .pota)

            switch httpResponse.statusCode {
            case 200...299:
                await MainActor.run {
                    attempt.markCompleted(httpStatusCode: httpResponse.statusCode, responseBody: responseBody, durationMs: durationMs)
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let count = json["qsosAccepted"] as? Int ?? parkQSOs.count
                    let message = json["message"] as? String
                    await debugLog.info("Upload success: \(count) QSOs accepted for \(normalizedParkRef)", service: .pota)
                    return POTAUploadResult(success: true, qsosAccepted: count, message: message)
                }
                await debugLog.info("Upload success: \(parkQSOs.count) QSOs for \(normalizedParkRef) (no count in response)", service: .pota)
                return POTAUploadResult(success: true, qsosAccepted: parkQSOs.count, message: nil)

            case 401:
                await MainActor.run {
                    attempt.markFailed(httpStatusCode: httpResponse.statusCode, responseBody: responseBody, errorMessage: "Unauthorized - token may be expired", durationMs: durationMs)
                }
                await debugLog.error("Upload failed: 401 Unauthorized - token may be expired", service: .pota)
                throw POTAError.notAuthenticated

            case 400...499:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Client error"
                await MainActor.run {
                    attempt.markFailed(httpStatusCode: httpResponse.statusCode, responseBody: responseBody, errorMessage: errorMessage, durationMs: durationMs)
                }
                await debugLog.error("Upload failed: \(httpResponse.statusCode) - \(errorMessage)", service: .pota)
                throw POTAError.uploadFailed(errorMessage)

            default:
                await MainActor.run {
                    attempt.markFailed(httpStatusCode: httpResponse.statusCode, responseBody: responseBody, errorMessage: "Server error: \(httpResponse.statusCode)", durationMs: durationMs)
                }
                await debugLog.error("Upload failed: \(httpResponse.statusCode) - Server error", service: .pota)
                throw POTAError.uploadFailed("Server error: \(httpResponse.statusCode)")
            }
        } catch let error as POTAError {
            throw error
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            await MainActor.run {
                attempt.markFailed(httpStatusCode: nil, responseBody: nil, errorMessage: error.localizedDescription, durationMs: durationMs)
            }
            throw POTAError.networkError(error)
        }
    }
```

**Step 2: Add SwiftData import at top of file**

Add after the Foundation import:

```swift
import SwiftData
```

**Step 3: Build to verify compilation**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add FullDuplex/Services/POTAClient.swift
git commit -m "feat(pota): add uploadActivationWithRecording for upload instrumentation"
```

---

## Task 6: Create POTALogEntry Enum for Unified Timeline

**Files:**
- Create: `FullDuplex/Models/POTALogEntry.swift`

**Step 1: Create the unified entry type**

```swift
import Foundation

enum POTALogEntry: Identifiable {
    case localAttempt(POTAUploadAttempt)
    case potaJob(POTAJob)
    case correlated(attempt: POTAUploadAttempt, job: POTAJob)

    var id: String {
        switch self {
        case .localAttempt(let attempt):
            return "local-\(attempt.id.uuidString)"
        case .potaJob(let job):
            return "job-\(job.jobId)"
        case .correlated(let attempt, _):
            return "correlated-\(attempt.id.uuidString)"
        }
    }

    var timestamp: Date {
        switch self {
        case .localAttempt(let attempt):
            return attempt.timestamp
        case .potaJob(let job):
            return job.submitted
        case .correlated(let attempt, _):
            return attempt.timestamp
        }
    }

    var parkReference: String {
        switch self {
        case .localAttempt(let attempt):
            return attempt.parkReference
        case .potaJob(let job):
            return job.reference
        case .correlated(let attempt, _):
            return attempt.parkReference
        }
    }

    /// Merge local attempts with POTA jobs, correlating by park reference and time
    static func merge(attempts: [POTAUploadAttempt], jobs: [POTAJob]) -> [POTALogEntry] {
        var entries: [POTALogEntry] = []
        var usedJobIds = Set<Int>()
        var usedAttemptIds = Set<UUID>()

        // First, find correlations
        for attempt in attempts {
            // Look for a matching job within 5 minutes
            let matchingJob = jobs.first { job in
                job.reference.uppercased() == attempt.parkReference.uppercased() &&
                abs(job.submitted.timeIntervalSince(attempt.timestamp)) < 300 // 5 minutes
            }

            if let job = matchingJob {
                entries.append(.correlated(attempt: attempt, job: job))
                usedJobIds.insert(job.jobId)
                usedAttemptIds.insert(attempt.id)
            }
        }

        // Add uncorrelated attempts
        for attempt in attempts where !usedAttemptIds.contains(attempt.id) {
            entries.append(.localAttempt(attempt))
        }

        // Add uncorrelated jobs
        for job in jobs where !usedJobIds.contains(job.jobId) {
            entries.append(.potaJob(job))
        }

        // Sort by timestamp descending (most recent first)
        return entries.sorted { $0.timestamp > $1.timestamp }
    }
}
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add FullDuplex/Models/POTALogEntry.swift
git commit -m "feat(pota): add POTALogEntry for unified timeline merging"
```

---

## Task 7: Create POTALogEntryRow View Component

**Files:**
- Create: `FullDuplex/Views/POTAUploads/POTALogEntryRow.swift`

**Step 1: Create the directory and row view**

```swift
import SwiftUI

struct POTALogEntryRow: View {
    let entry: POTALogEntry
    @State private var isExpanded = false

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                collapsedContent
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var collapsedContent: some View {
        HStack(spacing: 8) {
            entryIcon
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.parkReference)
                        .fontWeight(.semibold)
                    Spacer()
                    statusBadge
                }

                HStack {
                    Text(dateFormatter.string(from: entry.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    qsoCountText
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var entryIcon: some View {
        switch entry {
        case .localAttempt:
            Image(systemName: "arrow.up.doc")
                .foregroundStyle(.blue)
        case .potaJob:
            Image(systemName: "cloud")
                .foregroundStyle(.purple)
        case .correlated:
            Image(systemName: "link")
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch entry {
        case .localAttempt(let attempt):
            if attempt.success {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("Failed", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

        case .potaJob(let job):
            jobStatusBadge(job.status)

        case .correlated(let attempt, let job):
            HStack(spacing: 4) {
                if attempt.success {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                Image(systemName: "arrow.right")
                    .font(.caption2)
                jobStatusBadge(job.status)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func jobStatusBadge(_ status: POTAJobStatus) -> some View {
        Text(status.displayName)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(jobStatusColor(status).opacity(0.2))
            .foregroundStyle(jobStatusColor(status))
            .clipShape(Capsule())
    }

    private func jobStatusColor(_ status: POTAJobStatus) -> Color {
        switch status {
        case .pending, .processing: return .orange
        case .completed: return .green
        case .failed, .error: return .red
        case .duplicate: return .yellow
        }
    }

    @ViewBuilder
    private var qsoCountText: some View {
        switch entry {
        case .localAttempt(let attempt):
            Text("\(attempt.qsoCount) QSOs")

        case .potaJob(let job):
            if job.totalQsos >= 0 {
                Text("\(job.insertedQsos)/\(job.totalQsos) QSOs")
            } else {
                Text("QSOs: --")
            }

        case .correlated(let attempt, let job):
            if job.insertedQsos >= 0 {
                Text("\(attempt.qsoCount) → \(job.insertedQsos) inserted")
            } else {
                Text("\(attempt.qsoCount) QSOs")
            }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch entry {
            case .localAttempt(let attempt):
                localAttemptDetails(attempt)

            case .potaJob(let job):
                jobDetails(job)

            case .correlated(let attempt, let job):
                localAttemptDetails(attempt)
                Divider()
                jobDetails(job)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func localAttemptDetails(_ attempt: POTAUploadAttempt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local Upload Attempt")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            detailRow("Callsign", attempt.callsign)
            detailRow("Location", attempt.location)
            detailRow("Filename", attempt.filename)

            if let status = attempt.httpStatusCode {
                detailRow("HTTP Status", "\(status)")
            }
            if let duration = attempt.requestDurationMs {
                detailRow("Duration", "\(duration)ms")
            }
            if let error = attempt.errorMessage {
                detailRow("Error", error)
                    .foregroundStyle(.red)
            }

            // Headers
            if !attempt.requestHeaders.isEmpty {
                Text("Request Headers")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.top, 4)

                ForEach(attempt.requestHeaders.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    Text("\(key): \(value)")
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
            }

            // Response
            if let response = attempt.responseBody, !response.isEmpty {
                Text("Response")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.top, 4)

                ScrollView(.horizontal, showsIndicators: true) {
                    Text(response.prefix(1000))
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 80)
            }

            // ADIF
            DisclosureGroup("ADIF Content") {
                ScrollView {
                    Text(attempt.adifContent)
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }
            .font(.caption2)
        }
    }

    @ViewBuilder
    private func jobDetails(_ job: POTAJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("POTA Job #\(job.jobId)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            detailRow("Status", job.status.displayName)
            if let parkName = job.parkName {
                detailRow("Park", parkName)
            }
            if let location = job.location {
                detailRow("Location", location)
            }
            if let callsign = job.callsignUsed {
                detailRow("Callsign", callsign)
            }
            detailRow("Submitted", dateFormatter.string(from: job.submitted))
            if let processed = job.processed {
                detailRow("Processed", dateFormatter.string(from: processed))
            }
            if job.totalQsos >= 0 {
                detailRow("Total QSOs", "\(job.totalQsos)")
                detailRow("Inserted", "\(job.insertedQsos)")
            }
            if let comment = job.userComment, !comment.isEmpty {
                detailRow("Comment", comment)
            }
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption2)
                .textSelection(.enabled)
        }
    }
}
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add FullDuplex/Views/POTAUploads/POTALogEntryRow.swift
git commit -m "feat(pota): add POTALogEntryRow view component for timeline"
```

---

## Task 8: Create POTAUploadsView

**Files:**
- Create: `FullDuplex/Views/POTAUploads/POTAUploadsView.swift`

**Step 1: Create the main tab view**

```swift
import SwiftUI
import SwiftData

struct POTAUploadsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \POTAUploadAttempt.timestamp, order: .reverse) private var attempts: [POTAUploadAttempt]

    let potaClient: POTAClient
    let potaAuth: POTAAuthService

    @State private var jobs: [POTAJob] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastFetchTime: Date?

    private var entries: [POTALogEntry] {
        POTALogEntry.merge(attempts: Array(attempts), jobs: jobs)
    }

    private var isAuthenticated: Bool {
        potaAuth.isAuthenticated
    }

    var body: some View {
        NavigationStack {
            Group {
                if !isAuthenticated {
                    notAuthenticatedView
                } else if entries.isEmpty && !isLoading {
                    emptyStateView
                } else {
                    timelineList
                }
            }
            .navigationTitle("POTA Uploads")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if isAuthenticated {
                        Button {
                            Task { await fetchJobs() }
                        } label: {
                            if isLoading {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(isLoading)
                    }
                }
            }
            .onAppear {
                if isAuthenticated && jobs.isEmpty {
                    Task { await fetchJobs() }
                }
            }
        }
    }

    @ViewBuilder
    private var notAuthenticatedView: some View {
        ContentUnavailableView {
            Label("Not Authenticated", systemImage: "person.crop.circle.badge.xmark")
        } description: {
            Text("Sign in to POTA in Settings to view upload history and job status.")
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Upload History", systemImage: "doc.badge.arrow.up")
        } description: {
            Text("Upload QSOs to POTA to see them here. Jobs from POTA will appear after refresh.")
        } actions: {
            Button("Refresh") {
                Task { await fetchJobs() }
            }
        }
    }

    @ViewBuilder
    private var timelineList: some View {
        List {
            if let error = errorMessage {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                        Spacer()
                        Button("Retry") {
                            Task { await fetchJobs() }
                        }
                        .font(.caption)
                    }
                }
            }

            if let lastFetch = lastFetchTime {
                Section {
                    HStack {
                        Text("Last refreshed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lastFetch, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ForEach(entries) { entry in
                    POTALogEntryRow(entry: entry)
                }
            } header: {
                HStack {
                    Text("Upload Timeline")
                    Spacer()
                    Text("\(entries.count) entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .refreshable {
            await fetchJobs()
        }
    }

    private func fetchJobs() async {
        guard isAuthenticated else { return }

        isLoading = true
        errorMessage = nil

        do {
            let fetchedJobs = try await potaClient.fetchJobs()
            await MainActor.run {
                self.jobs = fetchedJobs
                self.lastFetchTime = Date()
                self.correlateJobsWithAttempts()
            }
        } catch POTAError.notAuthenticated {
            await MainActor.run {
                errorMessage = "Session expired. Please re-authenticate in Settings."
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }

    private func correlateJobsWithAttempts() {
        for attempt in attempts where attempt.correlatedJobId == nil {
            if let matchingJob = jobs.first(where: { job in
                job.reference.uppercased() == attempt.parkReference.uppercased() &&
                abs(job.submitted.timeIntervalSince(attempt.timestamp)) < 300
            }) {
                attempt.correlatedJobId = matchingJob.jobId
            }
        }
    }
}
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add FullDuplex/Views/POTAUploads/POTAUploadsView.swift
git commit -m "feat(pota): add POTAUploadsView main tab view"
```

---

## Task 9: Add Tab to ContentView

**Files:**
- Modify: `FullDuplex/ContentView.swift`

**Step 1: Add potaUploads case to AppTab enum**

Update the enum at the top of the file:

```swift
enum AppTab: Hashable {
    case dashboard
    case logs
    case potaUploads
    case settings
}
```

**Step 2: Add POTAClient state and the new tab in TabView**

Add state property after `syncService`:

```swift
    @State private var potaClient: POTAClient?
```

Update the TabView body to include the new tab after LogsListView:

```swift
            if let potaClient = potaClient {
                POTAUploadsView(potaClient: potaClient, potaAuth: potaAuthService)
                    .tabItem {
                        Label("POTA Uploads", systemImage: "arrow.up.doc")
                    }
                    .tag(AppTab.potaUploads)
            }
```

**Step 3: Initialize POTAClient in onAppear**

Add after syncService initialization:

```swift
            if potaClient == nil {
                potaClient = POTAClient(authService: potaAuthService)
            }
```

**Step 4: Build to verify compilation**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add FullDuplex/ContentView.swift
git commit -m "feat(pota): add POTA Uploads tab to main navigation"
```

---

## Task 10: Update SyncService to Use Instrumented Upload

**Files:**
- Modify: `FullDuplex/Services/SyncService.swift`

**Step 1: Find where SyncService calls POTAClient.uploadActivation and update to use uploadActivationWithRecording**

This requires passing the modelContext to the upload call. Find the POTA upload call in SyncService and update it to use the new instrumented method, passing the modelContext.

Search for `uploadActivation` in SyncService and replace with `uploadActivationWithRecording`, adding `modelContext: modelContext` parameter.

**Step 2: Build to verify compilation**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add FullDuplex/Services/SyncService.swift
git commit -m "feat(pota): use instrumented upload in SyncService for attempt recording"
```

---

## Task 11: Update Preview Container

**Files:**
- Modify: `FullDuplex/ContentView.swift:68-71`

**Step 1: Add POTAUploadAttempt to the preview container**

Update the #Preview at the bottom:

```swift
#Preview {
    ContentView()
        .modelContainer(for: [QSO.self, ServicePresence.self, UploadDestination.self, POTAUploadAttempt.self], inMemory: true)
}
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add FullDuplex/ContentView.swift
git commit -m "chore: add POTAUploadAttempt to preview container"
```

---

## Task 12: Full Build and Test

**Step 1: Run full build**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -30`
Expected: BUILD SUCCEEDED

**Step 2: Run tests**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -50`
Expected: All tests pass

**Step 3: Final commit if any cleanup needed**

```bash
git status
# If clean, done. Otherwise commit any remaining changes.
```
