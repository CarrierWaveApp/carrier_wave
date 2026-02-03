// POTA Activations view
//
// Displays activations grouped by park, with upload status per activation
// and ability to upload pending QSOs to POTA.

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
        .overlay {
            if isGeneratingShareImage {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Generating share image...")
                                .foregroundStyle(.white)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
            }
        }
        .onChange(of: activationToShare) { _, newValue in
            if let activation = newValue {
                Task {
                    await generateAndShare(activation: activation)
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
        .onAppear {
            startMaintenanceTimer()
        }
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
    @State private var isGeneratingShareImage = false
    @State private var maintenanceTimeRemaining: String?
    @State private var maintenanceTimer: Timer?
    @State private var cachedParkNames: [String: String] = [:]

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

    private var maintenanceBanner: some View {
        HStack {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("POTA Maintenance Window")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let remaining = maintenanceTimeRemaining {
                    Text("Uploads disabled. Resumes in \(remaining)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Uploads temporarily disabled (2330-0400 UTC)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                        ActivationRow(
                            activation: activation,
                            isUploadDisabled: isInMaintenance || potaClient == nil,
                            showUploadButton: isAuthenticated,
                            onUploadTapped: { activationToUpload = activation },
                            onRejectTapped: { activationToReject = activation },
                            onShareTapped: { activationToShare = activation },
                            showParkReference: true
                        )
                    }
                } header: {
                    Label("Ready to Upload", systemImage: "arrow.up.circle")
                }
            }

            // All activations grouped by park
            ForEach(activationsByPark, id: \.park) { parkGroup in
                Section {
                    ForEach(parkGroup.activations) { activation in
                        ActivationRow(
                            activation: activation,
                            isUploadDisabled: isInMaintenance || potaClient == nil,
                            showUploadButton: isAuthenticated,
                            onUploadTapped: { activationToUpload = activation },
                            onRejectTapped: { activationToReject = activation },
                            onShareTapped: { activationToShare = activation }
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

    func uploadActivation(_ activation: POTAActivation) async {
        activationToUpload = nil

        guard let potaClient else {
            await MainActor.run {
                errorMessage = "POTA client not available. Please sign in to POTA in Settings."
            }
            return
        }

        let pendingQSOs = activation.pendingQSOs()
        guard !pendingQSOs.isEmpty else {
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

// Helper views are in POTAActivationsHelperViews.swift
