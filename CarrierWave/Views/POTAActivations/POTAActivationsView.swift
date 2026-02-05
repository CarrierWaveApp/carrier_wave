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
        .sheet(item: $activationToUpload) { activation in
            UploadConfirmationSheet(
                activation: activation,
                parkName: parkName(for: activation.parkReference),
                onUpload: { await uploadActivation(activation) },
                onCancel: { activationToUpload = nil }
            )
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
    @State private var activationToUpload: POTAActivation?
    @State private var activationToReject: POTAActivation?
    @State private var activationToShare: POTAActivation?
    @State private var activationToExport: POTAActivation?
    @State private var activationToMap: POTAActivation?
    @State private var isGeneratingShareImage = false
    @State private var maintenanceTimeRemaining: String?
    @State private var maintenanceTimer: Timer?
    @State private var cachedParkNames: [String: String] = [:]
    /// Upload errors by activation ID -> (park -> error message) for two-fer error display
    @State private var uploadErrorsByActivation: [String: [String: String]] = [:]
    /// Pre-computed job index: activation ID -> matching jobs (rebuilt when jobs change)
    @State private var jobsByActivationId: [String: [POTAJob]] = [:]

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

    private var activationsByPark: [(park: String, activations: [POTAActivation])] {
        POTAActivation.groupByPark(activations)
    }

    /// Activations with pending uploads (not fully uploaded and not rejected), sorted by date descending
    private var pendingActivations: [POTAActivation] {
        activations
            .filter { $0.hasQSOsToUpload && !$0.isRejected }
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

            // All activations grouped by park
            ForEach(activationsByPark, id: \.park) { parkGroup in
                Section {
                    ForEach(parkGroup.activations) { activation in activationRow(activation) }
                } header: {
                    HStack {
                        Text(parkGroup.park)
                        if let name = parkName(for: parkGroup.park) {
                            Text("- \(name)").foregroundStyle(.secondary)
                        }
                    }
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
            isUploadDisabled: isInMaintenance || potaClient == nil,
            showUploadButton: isAuthenticated,
            onUploadTapped: { activationToUpload = activation },
            onRejectTapped: { activationToReject = activation },
            onShareTapped: { activationToShare = activation },
            onExportTapped: { activationToExport = activation },
            onMapTapped: { activationToMap = activation },
            showParkReference: showParkReference,
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

    func uploadActivation(_ activation: POTAActivation) async {
        activationToUpload = nil

        guard let potaClient else {
            await MainActor.run { errorMessage = "POTA client not available." }
            return
        }

        let parksToUpload = activation.parksNeedingUpload
        guard !parksToUpload.isEmpty else {
            return
        }

        var errors: [String: String] = [:]
        for park in parksToUpload {
            if let error = await uploadPark(park, activation: activation, client: potaClient) {
                errors[park] = error
            }
        }

        await MainActor.run {
            if errors.isEmpty {
                uploadErrorsByActivation.removeValue(forKey: activation.id)
            } else {
                uploadErrorsByActivation[activation.id] = errors
                let msg =
                    errors.count == parksToUpload.count
                        ? "all" : "\(errors.count) of \(parksToUpload.count)"
                errorMessage = "Upload failed for \(msg) parks"
            }
        }
    }

    private func uploadPark(_ park: String, activation: POTAActivation, client: POTAClient) async
        -> String?
    {
        let pendingQSOs = activation.pendingQSOs(forPark: park)
        guard !pendingQSOs.isEmpty else {
            return nil
        }

        do {
            let result = try await client.uploadActivationWithRecording(
                parkReference: park, qsos: pendingQSOs, modelContext: modelContext
            )
            if result.success {
                await MainActor.run {
                    pendingQSOs.forEach { $0.markUploadedToPark(park, context: modelContext) }
                }
                return nil
            }
            return "Upload returned success=false"
        } catch {
            return error.localizedDescription
        }
    }

    func rejectActivation(_ activation: POTAActivation) {
        let pendingQSOs = activation.pendingQSOs()
        for qso in pendingQSOs {
            qso.markUploadRejected(for: .pota, context: modelContext)
        }
        activationToReject = nil
    }

    func generateAndShare(activation: POTAActivation) async {
        isGeneratingShareImage = true
        activationToShare = nil

        // Render the image in background
        let image = await ActivationShareRenderer.renderWithMap(
            activation: activation,
            parkName: parkName(for: activation.parkReference),
            myGrid: activation.qsos.first?.myGrid
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
