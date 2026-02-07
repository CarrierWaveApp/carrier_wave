// POTA Activations view - displays activations grouped by park with upload status
// swiftlint:disable file_length

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

    var body: some View {
        Group {
            if activations.isEmpty {
                emptyStateView
            } else {
                activationsList
            }
        }
        .miniTour(.potaActivations, tourState: tourState)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
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
                    parkName: parkName(for: activation.parkReference)
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
        .task {
            await loadParkQSOs()
            if isAuthenticated, potaClient != nil, jobs.isEmpty {
                await refreshJobs()
            }
            await loadCachedParkNames()
        }
        .onAppear { startMaintenanceTimer() }
        .onDisappear {
            stopMaintenanceTimer()
        }
    }

    // MARK: Private

    /// Batch size for loading QSOs
    private static let batchSize = 500

    @Environment(\.modelContext) private var modelContext
    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("bypassPOTAMaintenance") private var bypassMaintenance = false

    /// Park QSOs loaded on demand (not using @Query to avoid full table scan)
    @State private var allParkQSOs: [QSO] = []

    @State private var jobs: [POTAJob] = []
    @State private var isLoading = false
    @State private var isLoadingQSOs = false
    @State private var errorMessage: String?
    @State private var activationToReject: POTAActivation?
    @State private var activationToShare: POTAActivation?
    @State private var activationToExport: POTAActivation?
    @State private var activationToMap: POTAActivation?
    @State private var activationToEdit: POTAActivation?
    @State private var isGeneratingShareImage = false
    @State private var maintenanceTimeRemaining: String?
    @State private var maintenanceTimer: Timer?
    @State private var cachedParkNames: [String: String] = [:]
    /// Upload errors by activation ID -> (park -> error message) for two-fer error display
    @State private var uploadErrorsByActivation: [String: [String: String]] = [:]
    /// Pre-computed job index: activation ID -> matching jobs (rebuilt when jobs change)
    @State private var jobsByActivationId: [String: [POTAJob]] = [:]
    /// Activation metadata keyed by "parkReference|yyyy-MM-dd"
    @State private var metadataByKey: [String: ActivationMetadata] = [:]

    private var isInMaintenance: Bool {
        if debugMode, bypassMaintenance {
            return false
        }
        return POTAClient.isInMaintenanceWindow()
    }

    private var isAuthenticated: Bool {
        // Use isConfigured to show upload buttons even if token expired
        // Will re-authenticate automatically when user taps upload
        potaAuth.isConfigured
    }

    private var activations: [POTAActivation] {
        POTAActivation.groupQSOs(allParkQSOs)
    }

    private var activationsByDate: [(date: String, activations: [POTAActivation])] {
        POTAActivation.groupByDate(activations)
    }

    /// Activations with pending uploads (not fully uploaded, not rejected, no completed job),
    /// sorted by date descending
    private var pendingActivations: [POTAActivation] {
        activations
            .filter { activation in
                activation.hasQSOsToUpload && !activation.isRejected
                    && !(jobsByActivationId[activation.id]?.contains { $0.status == .completed }
                        ?? false)
            }
            .sorted { $0.utcDate > $1.utcDate }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Activations", systemImage: "tree")
        } description: {
            Text("QSOs with park references will appear here grouped by activation.")
        }
    }

    @ViewBuilder private var shareImageOverlay: some View {
        if isGeneratingShareImage {
            Color.black.opacity(0.4).ignoresSafeArea().overlay {
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.5).tint(.white)
                    Text("Generating share image...").foregroundStyle(.white)
                }.padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var maintenanceBanner: some View {
        HStack {
            Image(systemName: "wrench.and.screwdriver").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("POTA Maintenance Window").font(.subheadline).fontWeight(.medium)
                Text(
                    maintenanceTimeRemaining.map { "Uploads disabled. Resumes in \($0)" }
                        ?? "Uploads temporarily disabled (2330-0400 UTC)"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var activationsList: some View {
        List {
            if isInMaintenance {
                Section {
                    maintenanceBanner
                }
            }

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

            // Ready to Upload section - pending activations sorted by date
            if !pendingActivations.isEmpty, isAuthenticated {
                Section {
                    ForEach(pendingActivations) { activation in
                        activationRow(activation, showParkReference: true)
                    }
                } header: {
                    Label("Ready to Upload", systemImage: "arrow.up.circle")
                }
            }

            // All activations grouped by date
            ForEach(activationsByDate, id: \.date) { dateGroup in
                Section {
                    ForEach(dateGroup.activations) { activation in
                        activationRow(activation, showParkReference: true)
                    }
                } header: {
                    Text(dateGroup.date)
                }
            }
        }
        .refreshable {
            await refreshJobs()
        }
    }

    private func activationRow(_ activation: POTAActivation, showParkReference: Bool = false)
        -> some View
    {
        ActivationRow(
            activation: activation,
            metadata: metadata(for: activation),
            isUploadDisabled: isInMaintenance || potaClient == nil,
            showUploadButton: isAuthenticated,
            onUploadTapped: { await performUpload(for: activation) },
            onRejectTapped: { activationToReject = activation },
            onShareTapped: { activationToShare = activation },
            onExportTapped: { activationToExport = activation },
            onMapTapped: { activationToMap = activation },
            onEditTapped: { activationToEdit = activation },
            onForceReuploadTapped: { forceReupload(activation) },
            showParkReference: showParkReference,
            parkName: parkName(for: activation.parkReference),
            uploadErrors: uploadErrorsByActivation[activation.id] ?? [:],
            matchingJobs: jobsByActivationId[activation.id] ?? [],
            potaClient: potaClient
        )
    }

    private func startMaintenanceTimer() {
        updateMaintenanceTime()
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [self] _ in
            Task { @MainActor in
                updateMaintenanceTime()
            }
        }
    }

    private func stopMaintenanceTimer() {
        maintenanceTimer?.invalidate()
        maintenanceTimer = nil
    }

    private func updateMaintenanceTime() {
        maintenanceTimeRemaining = POTAClient.formatMaintenanceTimeRemaining()
    }

    private func parkName(for reference: String) -> String? {
        // First try from fetched jobs (most accurate for user's parks)
        if let name = jobs.first(where: {
            $0.reference.uppercased() == reference.uppercased()
        })?.parkName {
            return name
        }
        // Fall back to cached park names
        return cachedParkNames[reference.uppercased()]
    }

    private func metadata(for activation: POTAActivation) -> ActivationMetadata? {
        metadataByKey["\(activation.parkReference)|\(activation.utcDateString)"]
    }

    private func rejectMessage(for parkDisplay: String, pendingCount: Int) -> String {
        """
        Reject upload for \(parkDisplay)?

        This will hide \(pendingCount) QSO(s) from POTA uploads. \
        They will remain in your log but won't be prompted for upload again.
        """
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

    /// Confirm or reset submitted uploads based on POTA job statuses.
    /// Called after jobs are refreshed to reconcile local state with remote job log.
    /// Returns true if any changes were made.
    @discardableResult
    private func confirmUploadsFromJobs() -> Bool {
        var confirmedCount = 0
        var resetCount = 0

        for activation in activations {
            let matching = jobsByActivationId[activation.id] ?? []
            guard !matching.isEmpty else {
                continue
            }

            // Check for completed jobs — confirm submitted QSOs
            let hasCompletedJob = matching.contains { $0.status == .completed }
            // Check for failed jobs (only if no completed job exists)
            let hasFailedJob = !hasCompletedJob && matching.contains { $0.status.isFailure }

            for park in activation.parks {
                if hasCompletedJob {
                    // Confirm all non-uploaded QSOs for this park
                    // (covers both submitted QSOs and QSOs uploaded before the submitted state existed)
                    for qso in activation.qsos where !qso.isUploadedToPark(park) {
                        qso.confirmUploadedToPark(park, context: modelContext)
                        confirmedCount += 1
                    }
                } else if hasFailedJob {
                    // Reset submitted QSOs back to needing upload
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

    /// Rebuild the job index mapping activation IDs to their matching jobs
    /// Called when jobs or activations change
    private func rebuildJobIndex() {
        var index: [String: [POTAJob]] = [:]
        for activation in activations {
            let matching = activation.matchingJobs(from: jobs)
            if !matching.isEmpty {
                index[activation.id] = matching
            }
        }
        jobsByActivationId = index
    }

    /// Upload an activation to POTA. Called from ActivationRow's upload button.
    func performUpload(for activation: POTAActivation) async {
        let debugLog = SyncDebugLog.shared
        guard let potaClient else {
            debugLog.error("performUpload: POTA client not available", service: .pota)
            errorMessage = "POTA client not available."
            return
        }

        let parksToUpload = activation.parksNeedingUpload
        guard !parksToUpload.isEmpty else {
            debugLog.debug(
                "performUpload: no parks need upload for \(activation.parkReference)",
                service: .pota
            )
            return
        }

        debugLog.info(
            "performUpload: \(activation.parkReference) - "
                + "\(parksToUpload.count) park(s) to upload: \(parksToUpload.joined(separator: ", ")), "
                + "\(activation.qsoCount) total QSOs, \(activation.pendingCount) pending",
            service: .pota
        )

        var errors: [String: String] = [:]
        for park in parksToUpload {
            if let error = await uploadPark(park, activation: activation, client: potaClient) {
                errors[park] = error
            }
        }

        if errors.isEmpty {
            uploadErrorsByActivation.removeValue(forKey: activation.id)
            debugLog.info(
                "performUpload: all parks uploaded successfully for \(activation.parkReference)",
                service: .pota
            )
        } else {
            uploadErrorsByActivation[activation.id] = errors
            let msg =
                errors.count == parksToUpload.count
                    ? "all" : "\(errors.count) of \(parksToUpload.count)"
            errorMessage = "Upload failed for \(msg) parks"
            debugLog.error(
                "performUpload: \(errors.count) park(s) failed for \(activation.parkReference): "
                    + errors.map { "\($0.key): \($0.value)" }.joined(separator: "; "),
                service: .pota
            )
        }
    }

    private func uploadPark(_ park: String, activation: POTAActivation, client: POTAClient) async
        -> String?
    {
        let debugLog = SyncDebugLog.shared
        let pendingQSOs = activation.pendingQSOs(forPark: park)
        guard !pendingQSOs.isEmpty else {
            debugLog.debug("uploadPark: no pending QSOs for park \(park)", service: .pota)
            return nil
        }

        debugLog.info(
            "uploadPark: uploading \(pendingQSOs.count) QSO(s) to park \(park)",
            service: .pota
        )
        logPendingParkQSOs(pendingQSOs, park: park)

        do {
            let result = try await client.uploadActivationWithRecording(
                parkReference: park, qsos: pendingQSOs, modelContext: modelContext
            )
            debugLog.info(
                "uploadPark: result for \(park) - success=\(result.success), "
                    + "qsosAccepted=\(result.qsosAccepted), "
                    + "message=\(result.message ?? "nil")",
                service: .pota
            )
            if result.success {
                await markQSOsSubmitted(pendingQSOs, park: park)
                return nil
            }
            debugLog.warning(
                "uploadPark: upload returned success=false for \(park)", service: .pota
            )
            return "Upload returned success=false"
        } catch {
            debugLog.error(
                "uploadPark: exception for \(park): \(error.localizedDescription)",
                service: .pota
            )
            return error.localizedDescription
        }
    }

    /// Log details of pending QSOs before upload
    private func logPendingParkQSOs(_ qsos: [QSO], park: String) {
        let debugLog = SyncDebugLog.shared
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        for qso in qsos.prefix(20) {
            let dateStr = dateFormatter.string(from: qso.timestamp)
            let presenceState =
                qso.potaPresence(forPark: park).map {
                    "isPresent=\($0.isPresent), isSubmitted=\($0.isSubmitted), "
                        + "needsUpload=\($0.needsUpload), rejected=\($0.uploadRejected)"
                } ?? "no presence"
            debugLog.debug(
                "  - \(qso.callsign) @ \(dateStr) | band=\(qso.band) mode=\(qso.mode) "
                    + "| park=\(qso.parkReference ?? "nil") | [\(presenceState)]",
                service: .pota
            )
        }
        if qsos.count > 20 {
            debugLog.debug("  ... and \(qsos.count - 20) more", service: .pota)
        }
    }

    /// Mark QSOs as submitted and log state transitions
    @MainActor
    private func markQSOsSubmitted(_ qsos: [QSO], park: String) {
        let debugLog = SyncDebugLog.shared
        for qso in qsos {
            let beforeState =
                qso.potaPresence(forPark: park).map {
                    "isPresent=\($0.isPresent), isSubmitted=\($0.isSubmitted)"
                } ?? "no presence"
            qso.markSubmittedToPark(park, context: modelContext)
            let afterState =
                qso.potaPresence(forPark: park).map {
                    "isPresent=\($0.isPresent), isSubmitted=\($0.isSubmitted)"
                } ?? "no presence"
            debugLog.debug(
                "markSubmittedToPark \(park): \(qso.callsign) "
                    + "[\(beforeState)] -> [\(afterState)]",
                service: .pota
            )
        }
    }

    func rejectActivation(_ activation: POTAActivation) {
        let pendingQSOs = activation.pendingQSOs()
        for qso in pendingQSOs {
            qso.markUploadRejected(for: .pota, context: modelContext)
        }
        activationToReject = nil
    }

    /// Force reset all QSOs in an activation back to needing upload, then upload (debug feature)
    func forceReupload(_ activation: POTAActivation) {
        let debugLog = SyncDebugLog.shared
        debugLog.info(
            "forceReupload: resetting \(activation.qsoCount) QSO(s) for "
                + "\(activation.parkReference) parks=\(activation.parks.joined(separator: ", "))",
            service: .pota
        )

        for qso in activation.qsos {
            for park in activation.parks {
                qso.forceResetParkUpload(park, context: modelContext)
            }
        }

        try? modelContext.save()
        debugLog.info(
            "forceReupload: reset complete for \(activation.parkReference), triggering upload",
            service: .pota
        )

        // Reload QSOs then trigger the actual upload
        Task {
            await loadParkQSOs()
            // Re-derive the activation with fresh QSO state
            let freshActivation = rebuildActivation(matching: activation)
            await performUpload(for: freshActivation ?? activation)
            await loadParkQSOs()
        }
    }

    /// Rebuild an activation from the current allParkQSOs to pick up fresh presence state
    private func rebuildActivation(matching original: POTAActivation) -> POTAActivation? {
        let matchingQSOs = allParkQSOs.filter { qso in
            guard let ref = qso.parkReference else {
                return false
            }
            return original.parks.contains(where: { ParkReference.hasOverlap(ref, $0) })
        }
        guard !matchingQSOs.isEmpty else {
            return nil
        }
        return POTAActivation(
            parkReference: original.parkReference,
            utcDate: original.utcDate,
            callsign: original.callsign,
            qsos: matchingQSOs
        )
    }

    /// Save metadata edits for an activation
    func saveMetadataEdit(_ result: ActivationMetadataEditResult, for activation: POTAActivation) {
        let parkRef = result.newParkReference ?? activation.parkReference

        // Handle park reference change
        if let newPark = result.newParkReference {
            for qso in activation.qsos {
                qso.parkReference = newPark
                // Remove POTA service presence (clears upload status)
                let potaPresence = qso.potaPresenceRecords()
                for presence in potaPresence {
                    modelContext.delete(presence)
                }
            }
        }

        // Find or create metadata record
        let existingMetadata = metadata(for: activation)
        let meta: ActivationMetadata
        if let existing = existingMetadata {
            meta = existing
            // If park changed, update the metadata key
            if result.newParkReference != nil {
                meta.parkReference = parkRef
            }
        } else {
            meta = ActivationMetadata(parkReference: parkRef, date: activation.utcDate)
            modelContext.insert(meta)
        }

        meta.title = result.title
        meta.watts = result.watts

        try? modelContext.save()

        // Reload data to reflect changes
        Task {
            await loadParkQSOs()
            await loadCachedParkNames()
        }
    }

    func generateAndShare(activation: POTAActivation) async {
        isGeneratingShareImage = true
        activationToShare = nil

        // Render the image in background
        let image = await ActivationShareRenderer.renderWithMap(
            activation: activation,
            parkName: parkName(for: activation.parkReference),
            myGrid: activation.qsos.first?.myGrid,
            metadata: metadata(for: activation)
        )

        isGeneratingShareImage = false

        guard let image else {
            return
        }

        // Present share sheet
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController
        else {
            return
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(
                x: topVC.view.bounds.midX,
                y: topVC.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }

        topVC.present(activityVC, animated: true)
    }
}
