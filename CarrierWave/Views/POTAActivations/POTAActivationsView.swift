// POTA Activations view - displays activations grouped by park with upload status

import CarrierWaveCore
import SwiftData
import SwiftUI
import UIKit

// MARK: - POTAActivationsContentView

struct POTAActivationsContentView: View {
    // MARK: Internal

    let potaClient: POTAClient?
    let potaAuth: POTAAuthService
    let tourState: TourState

    /// Park QSOs loaded on demand (not using @Query to avoid full table scan)
    @State var allParkQSOs: [QSO] = []

    @State var jobs: [POTAJob] = []
    @State var isLoading = false
    @State var errorMessage: String?
    @State var activationToReject: POTAActivation?
    @State var activationToShare: POTAActivation?
    @State var activationToExport: POTAActivation?
    @State var activationToMap: POTAActivation?
    @State var activationToEdit: POTAActivation?
    @State var isGeneratingShareImage = false
    @State var sharePreviewData: SharePreviewData?
    @State var maintenanceTimeRemaining: String?
    @State var maintenanceTimer: Timer?
    @State var cachedParkNames: [String: String] = [:]
    /// Upload errors by activation ID -> (park -> error message) for two-fer error display
    @State var uploadErrorsByActivation: [String: [String: String]] = [:]
    /// Pre-computed job index: activation ID -> matching jobs (rebuilt when jobs change)
    @State var jobsByActivationId: [String: [POTAJob]] = [:]
    /// Activation metadata keyed by "parkReference|yyyy-MM-dd"
    @State var metadataByKey: [String: ActivationMetadata] = [:]
    /// Session IDs that are rove sessions (for "Part of rove" badge)
    @State var roveSessionIds: Set<UUID> = []

    // MARK: - Bulk Selection State

    @State var isSelecting = false
    @State var selectedActivationIds: Set<String> = []
    @State var bulkUploadProgress: BulkUploadProgress?
    @State var bulkExportActivations: [POTAActivation]?

    @Environment(\.modelContext) var modelContext

    var isInMaintenance: Bool {
        if debugMode, bypassMaintenance {
            return false
        }
        return POTAClient.isInMaintenanceWindow()
    }

    var isAuthenticated: Bool {
        // Use isConfigured to show upload buttons even if token expired
        // Will re-authenticate automatically when user taps upload
        potaAuth.isConfigured
    }

    var activations: [POTAActivation] {
        POTAActivation.groupQSOs(allParkQSOs)
    }

    var activationsByDate: [(date: String, activations: [POTAActivation])] {
        POTAActivation.groupByDate(activations)
    }

    /// Activations with pending uploads (not fully uploaded, not rejected, no completed job),
    /// sorted by date descending
    var pendingActivations: [POTAActivation] {
        activations
            .filter { activation in
                activation.hasQSOsToUpload && !activation.isRejected
                    && !(jobsByActivationId[activation.id]?.contains { $0.status == .completed }
                        ?? false)
            }
            .sorted { $0.utcDate > $1.utcDate }
    }

    var body: some View {
        Group {
            if activations.isEmpty {
                emptyStateView
            } else {
                activationsList
            }
        }
        .miniTour(.potaActivations, tourState: tourState)
        .navigationTitle(
            isSelecting ? "\(selectedActivationIds.count) Selected" : "POTA Activations"
        )
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        isSelecting = false
                        selectedActivationIds.removeAll()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        selectedActivationIds.count == activations.count
                            ? "Deselect All" : "Select All"
                    ) {
                        if selectedActivationIds.count == activations.count {
                            selectedActivationIds.removeAll()
                        } else {
                            selectedActivationIds = Set(activations.map(\.id))
                        }
                    }
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 16) {
                        if !activations.isEmpty {
                            Button("Select") {
                                isSelecting = true
                                selectedActivationIds.removeAll()
                            }
                        }
                        if isAuthenticated, potaClient != nil {
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
            }
        }
        .confirmationDialog(
            "Reject Upload",
            isPresented: Binding(
                get: { activationToReject != nil },
                set: {
                    if !$0 {
                        activationToReject = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Reject Upload", role: .destructive) {
                if let activation = activationToReject {
                    rejectActivation(activation)
                }
            }
            Button("Cancel", role: .cancel) {
                activationToReject = nil
            }
        } message: {
            if let activation = activationToReject {
                let parkDisplay =
                    if let name = parkName(for: activation.parkReference) {
                        "\(activation.parkReference) - \(name)"
                    } else {
                        activation.parkReference
                    }
                Text(rejectMessage(for: parkDisplay, pendingCount: activation.pendingCount))
            }
        }
        .overlay { shareImageOverlay }
        .onChange(of: activationToShare) { _, newValue in
            if let activation = newValue {
                Task { await generateAndShare(activation: activation) }
            }
        }
        .sheet(item: $activationToExport) { activation in
            ADIFExportSheet(
                activation: activation, parkName: parkName(for: activation.parkReference)
            )
        }
        .sheet(item: $activationToMap) { activation in
            NavigationStack {
                ActivationMapView(
                    activation: activation,
                    parkName: parkName(for: activation.parkReference),
                    metadata: metadata(for: activation)
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            activationToMap = nil
                        }
                    }
                }
            }
        }
        .sheet(item: $activationToEdit) { activation in
            ActivationMetadataEditSheet(
                activation: activation,
                metadata: metadata(for: activation),
                userGrid: activation.qsos.first?.myGrid,
                onSave: { result in
                    saveMetadataEdit(result, for: activation)
                    activationToEdit = nil
                },
                onCancel: { activationToEdit = nil }
            )
        }
        .sheet(item: $sharePreviewData) { data in
            ActivationSharePreviewSheet(
                data: data,
                onDismiss: { sharePreviewData = nil }
            )
        }
        .confirmationDialog(
            "Reject \(selectedActivationsWithPendingCount) Activations?",
            isPresented: $showBulkRejectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reject Uploads", role: .destructive) {
                performBulkReject()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let qsoCount = bulkSelectedPendingQSOCount
            let actCount = selectedActivationsWithPendingCount
            Text(
                "This will hide \(qsoCount) QSO(s) from POTA uploads across "
                    + "\(actCount) activations. They will remain in your log but "
                    + "won't be prompted for upload again."
            )
        }
        .sheet(
            isPresented: Binding(
                get: { bulkExportActivations != nil },
                set: {
                    if !$0 {
                        bulkExportActivations = nil
                    }
                }
            )
        ) {
            if let activations = bulkExportActivations {
                BulkADIFExportSheet(
                    activations: activations,
                    parkNames: cachedParkNames
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                BulkActionToolbar(
                    pendingQSOCount: bulkSelectedPendingQSOCount,
                    selectedCount: selectedActivationIds.count,
                    hasSelectedPending: selectedActivationsWithPendingCount > 0,
                    isAuthenticated: isAuthenticated,
                    isInMaintenance: isInMaintenance,
                    onUpload: { Task { await performBulkUpload() } },
                    onReject: { showBulkRejectConfirmation = true },
                    onExport: { performBulkExport() }
                )
            }
        }
        .task {
            await loadParkQSOs()
            loadRoveSessionIds()
            if isAuthenticated, potaClient != nil, jobs.isEmpty {
                await refreshJobs()
            }
            await loadCachedParkNames()
        }
        .onAppear { startMaintenanceTimer() }
        .onDisappear { stopMaintenanceTimer() }
    }

    // MARK: Private

    /// Batch size for loading QSOs
    private static let batchSize = 500

    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("bypassPOTAMaintenance") private var bypassMaintenance = false
    @State private var isLoadingQSOs = false
    @State private var showBulkRejectConfirmation = false

    // MARK: - Bulk Selection Computed Properties

    private var bulkSelectedPendingQSOCount: Int {
        selectedPendingQSOCount(activations: activations, selectedIds: selectedActivationIds)
    }

    private var selectedActivationsWithPendingCount: Int {
        selectedActivationsWithPending(
            activations: activations, selectedIds: selectedActivationIds
        ).count
    }
}

// MARK: - Actions

extension POTAActivationsContentView {
    /// Load park QSOs in background with batch processing
    func loadParkQSOs() async {
        isLoadingQSOs = true
        defer { isLoadingQSOs = false }

        var loadedQSOs: [QSO] = []

        // Get count of park QSOs
        let countDescriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.parkReference != nil && !$0.isHidden }
        )
        let totalCount = (try? modelContext.fetchCount(countDescriptor)) ?? 0

        // Load in batches
        var offset = 0
        while offset < totalCount {
            var descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate { $0.parkReference != nil && !$0.isHidden }
            )
            descriptor.sortBy = [SortDescriptor(\QSO.timestamp, order: .reverse)]
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = Self.batchSize

            guard let batch = try? modelContext.fetch(descriptor) else {
                break
            }

            if batch.isEmpty {
                break
            }

            loadedQSOs.append(contentsOf: batch)
            offset += Self.batchSize
            await Task.yield()
        }

        allParkQSOs = loadedQSOs
        // Rebuild job index since activations changed
        rebuildJobIndex()
        // Load activation metadata
        loadMetadata()
    }

    /// Load all activation metadata into a lookup dictionary
    func loadMetadata() {
        let descriptor = FetchDescriptor<ActivationMetadata>()
        let allMetadata = (try? modelContext.fetch(descriptor)) ?? []

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        var dict: [String: ActivationMetadata] = [:]
        for item in allMetadata {
            let dateStr = formatter.string(from: item.date)
            dict["\(item.parkReference)|\(dateStr)"] = item
        }
        metadataByKey = dict
    }

    func loadCachedParkNames() async {
        await POTAParksCache.shared.ensureLoaded()
        // Pre-load names for all parks in our activations
        var names: [String: String] = [:]
        for activation in activations {
            let ref = activation.parkReference.uppercased()
            if let name = await POTAParksCache.shared.name(for: ref) {
                names[ref] = name
            }
        }
        await MainActor.run {
            cachedParkNames = names
        }
    }

    func refreshJobs() async {
        guard isAuthenticated, let potaClient else {
            return
        }
        isLoading = true
        errorMessage = nil

        do {
            let fetchedJobs = try await potaClient.fetchJobs()
            await MainActor.run {
                jobs = fetchedJobs
                rebuildJobIndex()
                let didReconcile = confirmUploadsFromJobs()
                if didReconcile {
                    // Reload QSOs from DB so SwiftUI picks up relationship changes
                    Task { await loadParkQSOs() }
                }
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

    /// Confirm or reset submitted uploads based on POTA job statuses. Returns true if changed.
    @discardableResult
    private func confirmUploadsFromJobs() -> Bool {
        var confirmedCount = 0
        var resetCount = 0

        for activation in activations {
            let matching = jobsByActivationId[activation.id] ?? []
            guard !matching.isEmpty else {
                continue
            }

            let hasCompletedJob = matching.contains { $0.status == .completed }
            let hasFailedJob = !hasCompletedJob && matching.contains { $0.status.isFailure }

            for park in activation.parks {
                if hasCompletedJob {
                    for qso in activation.qsos where !qso.isUploadedToPark(park) {
                        qso.confirmUploadedToPark(park, context: modelContext)
                        confirmedCount += 1
                    }
                } else if hasFailedJob {
                    for qso in activation.qsos where qso.isSubmittedToPark(park) {
                        qso.resetSubmittedToPark(park, context: modelContext)
                        resetCount += 1
                    }
                }
            }
        }

        if confirmedCount > 0 || resetCount > 0 {
            try? modelContext.save()
            return true
        }
        return false
    }

    /// Rebuild the job index: exact match first, then fuzzy match nil-date jobs.
    private func rebuildJobIndex() {
        var index: [String: [POTAJob]] = [:]
        var matchedJobIds = Set<Int>()

        for activation in activations {
            let matching = activation.matchingJobs(from: jobs)
            if !matching.isEmpty {
                index[activation.id] = matching
                matchedJobIds.formUnion(matching.map(\.jobId))
            }
        }

        fuzzyMatchNilDateJobs(into: &index, excluding: matchedJobIds)
        jobsByActivationId = index
    }

    /// Assign nil-date jobs to the closest unmatched activation by submitted date,
    /// preventing jobs from old activations leaking onto newer ones.
    private func fuzzyMatchNilDateJobs(
        into index: inout [String: [POTAJob]], excluding matchedJobIds: Set<Int>
    ) {
        let nilDateJobs = jobs.filter { $0.firstQSO == nil && !matchedJobIds.contains($0.jobId) }
        guard !nilDateJobs.isEmpty else {
            return
        }

        let unmatchedActivations = activations.filter { index[$0.id] == nil }
        guard !unmatchedActivations.isEmpty else {
            return
        }

        var fuzzyIndex: [String: [POTAJob]] = [:]
        for job in nilDateJobs {
            let candidates = unmatchedActivations.filter {
                job.matchesParkAndCallsign(
                    parkReference: $0.parkReference,
                    callsign: $0.callsign
                ) && $0.utcDate <= job.submitted
            }
            guard let bestMatch = candidates.max(by: { $0.utcDate < $1.utcDate }) else {
                continue
            }
            fuzzyIndex[bestMatch.id, default: []].append(job)
        }

        for (activationId, matchedJobs) in fuzzyIndex {
            index[activationId] = matchedJobs.sorted { $0.submitted > $1.submitted }
        }
    }
}
