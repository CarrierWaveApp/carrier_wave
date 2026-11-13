# POTA Activations View Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the POTA Uploads view with a new POTA Activations view that groups QSOs by activation (park + UTC date + callsign) and allows uploading individual activations to POTA.

**Architecture:** Create a view model struct `POTAActivation` to group QSOs. The view queries all QSOs with park references, groups them into activations, cross-references with local upload attempts and remote POTA jobs to determine upload status per-QSO, and displays activations grouped by park with upload buttons.

**Tech Stack:** SwiftUI, SwiftData, existing POTAClient/POTAAuthService

---

## Task 1: Create POTAActivation View Model

**Files:**
- Create: `CarrierWave/Models/POTAActivation.swift`

**Step 1: Create the POTAActivation struct**

```swift
// POTA Activation view model
//
// Groups QSOs by park reference, UTC date, and callsign for display
// in the POTA Activations view. Not persisted - computed from QSOs.

import Foundation

// MARK: - POTAActivationStatus

enum POTAActivationStatus {
    case uploaded      // All QSOs present in POTA
    case partial       // Some QSOs present
    case pending       // No QSOs present

    var iconName: String {
        switch self {
        case .uploaded: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .pending: "circle"
        }
    }

    var color: String {
        switch self {
        case .uploaded: "green"
        case .partial: "orange"
        case .pending: "gray"
        }
    }
}

// MARK: - POTAActivation

struct POTAActivation: Identifiable {
    let parkReference: String
    let utcDate: Date
    let callsign: String
    let qsos: [QSO]

    var id: String {
        let dateString = Self.utcDateFormatter.string(from: utcDate)
        return "\(parkReference)|\(callsign)|\(dateString)"
    }

    var utcDateString: String {
        Self.utcDateFormatter.string(from: utcDate)
    }

    var displayDate: String {
        Self.displayDateFormatter.string(from: utcDate)
    }

    var qsoCount: Int { qsos.count }

    /// QSOs that are present in POTA (uploaded or downloaded from POTA)
    func uploadedQSOs() -> [QSO] {
        qsos.filter { $0.isPresentInPOTA() }
    }

    /// QSOs that need to be uploaded to POTA
    func pendingQSOs() -> [QSO] {
        qsos.filter { !$0.isPresentInPOTA() }
    }

    var uploadedCount: Int { uploadedQSOs().count }
    var pendingCount: Int { pendingQSOs().count }

    var status: POTAActivationStatus {
        let uploaded = uploadedCount
        if uploaded == qsoCount {
            return .uploaded
        } else if uploaded > 0 {
            return .partial
        } else {
            return .pending
        }
    }

    var hasQSOsToUpload: Bool { pendingCount > 0 }

    // MARK: - Date Formatters

    private static let utcDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // MARK: - Grouping

    /// Group QSOs into activations by (parkReference, UTC date, callsign)
    static func groupQSOs(_ qsos: [QSO]) -> [POTAActivation] {
        let calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!

        // Filter to QSOs with park references
        let parkQSOs = qsos.filter { $0.parkReference?.isEmpty == false }

        // Group by (park, utcDate, callsign)
        var groups: [String: [QSO]] = [:]
        for qso in parkQSOs {
            let parkRef = qso.parkReference!.uppercased()
            let utcDate = calendar.startOfDay(for: qso.timestamp, in: utc)
            let callsign = qso.myCallsign.uppercased()
            let key = "\(parkRef)|\(callsign)|\(utcDateFormatter.string(from: utcDate))"
            groups[key, default: []].append(qso)
        }

        // Convert to POTAActivation structs
        return groups.map { key, qsos in
            let parts = key.split(separator: "|")
            let parkRef = String(parts[0])
            let callsign = String(parts[1])
            let dateStr = String(parts[2])
            let utcDate = utcDateFormatter.date(from: dateStr) ?? Date()
            return POTAActivation(
                parkReference: parkRef,
                utcDate: utcDate,
                callsign: callsign,
                qsos: qsos.sorted { $0.timestamp < $1.timestamp }
            )
        }.sorted { $0.utcDate > $1.utcDate }
    }

    /// Group activations by park reference for sectioning
    static func groupByPark(_ activations: [POTAActivation]) -> [(park: String, activations: [POTAActivation])] {
        let grouped = Dictionary(grouping: activations) { $0.parkReference }
        return grouped
            .map { (park: $0.key, activations: $0.value.sorted { $0.utcDate > $1.utcDate }) }
            .sorted { $0.park < $1.park }
    }
}

// MARK: - Calendar Extension

private extension Calendar {
    func startOfDay(for date: Date, in timeZone: TimeZone) -> Date {
        var cal = self
        cal.timeZone = timeZone
        return cal.startOfDay(for: date)
    }
}
```

**Step 2: Add QSO helper method for POTA presence check**

In `CarrierWave/Models/QSO.swift`, add after the existing `isPresent(in:)` method:

```swift
/// Check if QSO is present in POTA (uploaded or downloaded from POTA)
func isPresentInPOTA() -> Bool {
    // Downloaded from POTA
    if importSource == .pota { return true }
    // Has ServicePresence indicating present
    if isPresent(in: .pota) { return true }
    return false
}
```

**Step 3: Update CLAUDE.md file index**

Add to Models section in CLAUDE.md:
```
| `POTAActivation.swift` | POTA activation grouping view model |
```

**Step 4: Commit**

```bash
git add CarrierWave/Models/POTAActivation.swift CarrierWave/Models/QSO.swift CLAUDE.md
git commit -m "feat: add POTAActivation view model for grouping QSOs"
```

---

## Task 2: Create POTAActivationsView

**Files:**
- Create: `CarrierWave/Views/POTAActivations/POTAActivationsView.swift`

**Step 1: Create the main view file**

```swift
// POTA Activations view
//
// Displays activations grouped by park, with upload status per activation
// and ability to upload pending QSOs to POTA.

import SwiftData
import SwiftUI

// MARK: - POTAActivationsContentView

struct POTAActivationsContentView: View {
    // MARK: Internal

    let potaClient: POTAClient
    let potaAuth: POTAAuthService

    var body: some View {
        Group {
            if !isAuthenticated {
                notAuthenticatedView
            } else if activations.isEmpty {
                emptyStateView
            } else {
                activationsList
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isAuthenticated {
                    Button {
                        Task { await refreshJobs() }
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
        .sheet(item: $activationToUpload) { activation in
            UploadConfirmationSheet(
                activation: activation,
                parkName: parkName(for: activation.parkReference),
                onUpload: { await uploadActivation(activation) },
                onCancel: { activationToUpload = nil }
            )
        }
        .onAppear {
            if isAuthenticated, jobs.isEmpty {
                Task { await refreshJobs() }
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<QSO> { $0.parkReference != nil })
    private var allParkQSOs: [QSO]
    @Query(sort: \POTAUploadAttempt.timestamp, order: .reverse)
    private var uploadAttempts: [POTAUploadAttempt]

    @State private var jobs: [POTAJob] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var activationToUpload: POTAActivation?
    @State private var isUploading = false

    private var isAuthenticated: Bool {
        potaAuth.isAuthenticated
    }

    private var activations: [POTAActivation] {
        POTAActivation.groupQSOs(allParkQSOs)
    }

    private var activationsByPark: [(park: String, activations: [POTAActivation])] {
        POTAActivation.groupByPark(activations)
    }

    private func parkName(for reference: String) -> String? {
        jobs.first { $0.reference.uppercased() == reference.uppercased() }?.parkName
    }

    @ViewBuilder
    private var notAuthenticatedView: some View {
        ContentUnavailableView {
            Label("Not Authenticated", systemImage: "person.crop.circle.badge.xmark")
        } description: {
            Text("Sign in to POTA in Settings to view and upload activations.")
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Activations", systemImage: "tree")
        } description: {
            Text("QSOs with park references will appear here grouped by activation.")
        }
    }

    @ViewBuilder
    private var activationsList: some View {
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
                            Task { await refreshJobs() }
                        }
                        .font(.caption)
                    }
                }
            }

            ForEach(activationsByPark, id: \.park) { parkGroup in
                Section {
                    ForEach(parkGroup.activations) { activation in
                        ActivationRow(
                            activation: activation,
                            onUploadTapped: { activationToUpload = activation }
                        )
                    }
                } header: {
                    HStack {
                        Text(parkGroup.park)
                        if let name = parkName(for: parkGroup.park) {
                            Text("- \(name)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .refreshable {
            await refreshJobs()
        }
    }

    private func refreshJobs() async {
        guard isAuthenticated else { return }
        isLoading = true
        errorMessage = nil

        do {
            let fetchedJobs = try await potaClient.fetchJobs()
            await MainActor.run {
                jobs = fetchedJobs
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

    private func uploadActivation(_ activation: POTAActivation) async {
        isUploading = true
        activationToUpload = nil

        let pendingQSOs = activation.pendingQSOs()
        guard !pendingQSOs.isEmpty else {
            isUploading = false
            return
        }

        do {
            let result = try await potaClient.uploadActivationWithRecording(
                parkReference: activation.parkReference,
                qsos: pendingQSOs,
                modelContext: modelContext
            )

            if result.success {
                await MainActor.run {
                    for qso in pendingQSOs {
                        qso.markPresent(in: .pota, context: modelContext)
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Upload failed: \(error.localizedDescription)"
            }
        }

        await MainActor.run {
            isUploading = false
        }
    }
}

// MARK: - ActivationRow

private struct ActivationRow: View {
    let activation: POTAActivation
    let onUploadTapped: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(activation.displayDate)
                        .font(.headline)
                    Text(activation.callsign)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: activation.status.iconName)
                        .foregroundStyle(statusColor)
                    Text("\(activation.uploadedCount)/\(activation.qsoCount) QSOs uploaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if activation.hasQSOsToUpload {
                Button("Upload") {
                    onUploadTapped()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch activation.status {
        case .uploaded: .green
        case .partial: .orange
        case .pending: .gray
        }
    }
}

// MARK: - UploadConfirmationSheet

private struct UploadConfirmationSheet: View {
    let activation: POTAActivation
    let parkName: String?
    let onUpload: () async -> Void
    let onCancel: () -> Void

    @State private var isUploading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(activation.parkReference)
                        .font(.title)
                        .fontWeight(.bold)
                    if let name = parkName {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 12) {
                    DetailRow(label: "Date", value: activation.displayDate)
                    DetailRow(label: "Callsign", value: activation.callsign)
                    DetailRow(
                        label: "QSOs to Upload",
                        value: "\(activation.pendingCount) of \(activation.qsoCount)"
                    )
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                Spacer()

                if isUploading {
                    ProgressView("Uploading...")
                } else {
                    VStack(spacing: 12) {
                        Button {
                            isUploading = true
                            Task {
                                await onUpload()
                            }
                        } label: {
                            Text("Upload \(activation.pendingCount) QSOs")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button("Cancel", role: .cancel) {
                            onCancel()
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Upload Activation")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - DetailRow

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
```

**Step 2: Create directory and commit**

```bash
mkdir -p CarrierWave/Views/POTAActivations
git add CarrierWave/Views/POTAActivations/POTAActivationsView.swift
git commit -m "feat: add POTAActivationsView for grouped activation display"
```

---

## Task 3: Update LogsContainerView

**Files:**
- Modify: `CarrierWave/Views/Logs/LogsContainerView.swift`

**Step 1: Update the segment enum and references**

Change `LogsSegment` enum:
```swift
enum LogsSegment: String, CaseIterable {
    case qsos = "QSOs"
    case potaActivations = "POTA Activations"
}
```

Update `selectedContent`:
```swift
@ViewBuilder
private var selectedContent: some View {
    switch selectedSegment {
    case .qsos:
        LogsListContentView(
            lofiClient: lofiClient,
            qrzClient: qrzClient,
            hamrsClient: hamrsClient,
            lotwClient: lotwClient,
            potaAuth: potaAuth
        )
    case .potaActivations:
        if let potaClient {
            POTAActivationsContentView(potaClient: potaClient, potaAuth: potaAuth)
        }
    }
}
```

Update `availableSegments`:
```swift
private var availableSegments: [LogsSegment] {
    if potaClient != nil {
        LogsSegment.allCases
    } else {
        [.qsos]
    }
}
```

**Step 2: Commit**

```bash
git add CarrierWave/Views/Logs/LogsContainerView.swift
git commit -m "feat: replace POTA Uploads segment with POTA Activations"
```

---

## Task 4: Update CLAUDE.md File Index

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update file index**

In the Views - POTA Uploads section, rename to "Views - POTA Activations" and update:

```markdown
### Views - POTA Activations (`CarrierWave/Views/POTAActivations/`)
| File | Purpose |
|------|---------|
| `POTAActivationsView.swift` | POTA activations grouped by park with upload |
| `POTALogEntryRow.swift` | Individual POTA log entry display (legacy) |
```

In Models section, add:
```
| `POTAActivation.swift` | POTA activation grouping view model |
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update file index for POTA Activations view"
```

---

## Task 5: Move Old Files to New Directory

**Files:**
- Move: `CarrierWave/Views/POTAUploads/` contents to `CarrierWave/Views/POTAActivations/`
- Delete: `CarrierWave/Views/POTAUploads/POTAUploadsView.swift`

**Step 1: Move POTALogEntryRow (keep for potential future use)**

```bash
mkdir -p CarrierWave/Views/POTAActivations
git mv CarrierWave/Views/POTAUploads/POTALogEntryRow.swift CarrierWave/Views/POTAActivations/
```

**Step 2: Delete old view**

```bash
git rm CarrierWave/Views/POTAUploads/POTAUploadsView.swift
rmdir CarrierWave/Views/POTAUploads 2>/dev/null || true
```

**Step 3: Commit**

```bash
git add -A
git commit -m "refactor: reorganize POTA views into POTAActivations directory"
```

---

## Task 6: Manual Testing

**Files:** None (testing only)

**Step 1: Ask user to build and test**

Ask the user to:
1. Run `make build` to verify compilation
2. Run the app on simulator or device
3. Navigate to Logs tab and select "POTA Activations" segment
4. Verify:
   - Activations are grouped by park
   - Each activation shows date, callsign, QSO count, upload status
   - Upload button appears for activations with pending QSOs
   - Tapping Upload shows confirmation sheet
   - After upload, status updates to reflect uploaded QSOs

**Step 2: Report any issues for fixing**

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Create POTAActivation view model | `Models/POTAActivation.swift`, `Models/QSO.swift` |
| 2 | Create POTAActivationsView | `Views/POTAActivations/POTAActivationsView.swift` |
| 3 | Update LogsContainerView | `Views/Logs/LogsContainerView.swift` |
| 4 | Update CLAUDE.md | `CLAUDE.md` |
| 5 | Reorganize files | Move/delete old POTA views |
| 6 | Manual testing | User verification |
