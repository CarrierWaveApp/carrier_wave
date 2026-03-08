// Unified Sessions list merging POTA Activations and Sessions.
// Each session shows rich content: timeline, conditions, badges.
// POTA sessions additionally show upload status and upload controls.
// Orphan POTA activations (without sessions) appear as virtual entries.
//
// Data loading, POTA actions, and helpers are in SessionsView+Actions.swift.

import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SessionsView

struct SessionsView: View {
    // MARK: - Unified Row List

    /// A display item: either a real session or an orphan POTA activation
    enum ListItem: Identifiable {
        case session(LoggingSession)
        case orphanActivation(POTAActivation)

        // MARK: Internal

        var id: String {
            switch self {
            case let .session(session): "session-\(session.id)"
            case let .orphanActivation(activation): "orphan-\(activation.id)"
            }
        }

        var date: Date {
            switch self {
            case let .session(session): session.startedAt
            case let .orphanActivation(activation): activation.utcDate
            }
        }
    }

    let potaClient: POTAClient?
    let potaAuth: POTAAuthService
    let tourState: TourState
    var isEmbedded = false
    var activeSessionsHeader: (() -> AnyView)?

    // MARK: - Shared State (accessed by +Actions extension)

    @Environment(\.modelContext) var modelContext

    @State var sessions: [LoggingSession] = []
    @State var qsosBySessionId: [UUID: [QSO]] = [:]
    @State var recordingsBySessionId: [UUID: WebSDRRecording] = [:]
    @State var engines: [UUID: RecordingPlaybackEngine] = [:]

    @State var orphanActivations: [POTAActivation] = []
    @State var activationsBySessionId: [UUID: [POTAActivation]] = [:]
    @State var metadataByKey: [String: ActivationMetadata] = [:]
    @State var cachedParkNames: [String: String] = [:]
    @State var jobs: [POTAJob] = []
    @State var jobsByActivationId: [String: [POTAJob]] = [:]
    @State var isLoadingJobs = false
    @State var errorMessage: String?
    @State var maintenanceTimeRemaining: String?
    @State var maintenanceTimer: Timer?

    @State var itemToDelete: ListItem?
    @State var activationToReject: POTAActivation?
    @State var activationToShare: POTAActivation?
    @State var activationToExport: POTAActivation?
    @State var activationToMap: POTAActivation?
    @State var roveStopsForMap: [RoveStop] = []
    @State var activationToEdit: POTAActivation?
    @State var isGeneratingShareImage = false
    @State var sharePreviewData: SharePreviewData?

    @AppStorage("debugMode") var debugMode = false
    @AppStorage("bypassPOTAMaintenance") var bypassMaintenance = false

    var isInMaintenance: Bool {
        if debugMode, bypassMaintenance {
            return false
        }
        return POTAClient.isInMaintenanceWindow()
    }

    var isAuthenticated: Bool {
        potaAuth.isConfigured
    }

    var allActivations: [POTAActivation] {
        activationsBySessionId.values.flatMap { $0 } + orphanActivations
    }

    var allItems: [ListItem] {
        var items: [ListItem] = sessions
            .filter { (qsosBySessionId[$0.id] ?? []).isEmpty == false }
            .map { .session($0) }
        items.append(contentsOf: orphanActivations.map { .orphanActivation($0) })
        return items.sorted { $0.date > $1.date }
    }

    var itemsByMonth: [(month: String, items: [ListItem])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")

        let grouped = Dictionary(grouping: allItems) { item in
            formatter.string(from: item.date)
        }

        return grouped
            .sorted { $0.value[0].date > $1.value[0].date }
            .map { (month: $0.key, items: $0.value) }
    }

    var body: some View {
        Group {
            if sessions.isEmpty, orphanActivations.isEmpty, activeSessionsHeader == nil {
                emptyState
            } else {
                sessionsList
            }
        }
        .miniTour(.potaActivations, tourState: tourState)
        .navigationTitle(isEmbedded ? "" : "Sessions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isAuthenticated, potaClient != nil {
                    Button {
                        Task { await refreshJobs() }
                    } label: {
                        if isLoadingJobs {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoadingJobs)
                    .accessibilityLabel("Refresh upload status")
                }
            }
        }
        .confirmationDialog(
            "Reject Upload",
            isPresented: Binding(
                get: { activationToReject != nil },
                set: { newValue in
                    if !newValue {
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
                Text(
                    "Reject upload for \(activation.parkReference)? "
                        + "This will hide \(activation.pendingCount) QSO(s) "
                        + "from POTA uploads."
                )
            }
        }
        .alert(
            "Delete Session",
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { newValue in
                    if !newValue {
                        itemToDelete = nil
                    }
                }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    deleteItem(item)
                }
                itemToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .overlay { shareImageOverlay }
        .onChange(of: activationToShare) { _, newValue in
            if let activation = newValue {
                Task { await generateAndShare(activation: activation) }
            }
        }
        .sheet(item: $activationToExport) { activation in
            ADIFExportSheet(
                activation: activation,
                parkName: parkName(for: activation.parkReference)
            )
        }
        .sheet(item: $activationToMap) { activation in
            NavigationStack {
                ActivationMapView(
                    activation: activation,
                    parkName: parkName(for: activation.parkReference),
                    metadata: activationMetadata(for: activation),
                    roveStops: roveStopsForMap
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            activationToMap = nil
                            roveStopsForMap = []
                        }
                    }
                }
            }
        }
        .sheet(item: $activationToEdit) { activation in
            ActivationMetadataEditSheet(
                activation: activation,
                metadata: activationMetadata(for: activation),
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
        .task {
            await loadSessions()
            await loadOrphanActivations()
            await loadRecordings()
            await loadCachedParkNames()
            if isAuthenticated, potaClient != nil, jobs.isEmpty {
                await refreshJobs()
            }
        }
        .onAppear { startMaintenanceTimer() }
        .onDisappear { stopMaintenanceTimer() }
    }
}

// MARK: - Subviews

extension SessionsView {
    var emptyState: some View {
        ContentUnavailableView(
            "No Sessions",
            systemImage: "clock",
            description: Text(
                "Completed logging sessions will appear here."
            )
        )
    }

    @ViewBuilder var shareImageOverlay: some View {
        if isGeneratingShareImage {
            Color.black.opacity(0.4).ignoresSafeArea().overlay {
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.5).tint(.white)
                    Text("Generating share image...")
                        .foregroundStyle(.white)
                }
                .padding(24)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .accessibilityLabel("Generating share image")
            }
        }
    }

    var sessionsList: some View {
        List {
            if let header = activeSessionsHeader {
                header()
            }

            Section {
                NavigationLink {
                    POTAAwardsView()
                } label: {
                    Label("POTA Awards", systemImage: "trophy.fill")
                }
            }

            if isInMaintenance {
                Section { maintenanceBanner }
            }

            if let error = errorMessage {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error).font(.caption)
                        Spacer()
                        Button("Retry") {
                            Task { await refreshJobs() }
                        }
                        .font(.caption)
                    }
                }
            }

            ForEach(itemsByMonth, id: \.month) { group in
                Section(group.month) {
                    ForEach(group.items) { item in
                        listItemRow(item)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    itemToDelete = item
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .refreshable {
            await loadSessions()
            await loadOrphanActivations()
            if isAuthenticated, potaClient != nil {
                await refreshJobs()
            }
        }
    }

    @ViewBuilder
    func listItemRow(_ item: ListItem) -> some View {
        switch item {
        case let .session(session):
            sessionNavigationRow(session)
        case let .orphanActivation(activation):
            orphanActivationRow(activation)
        }
    }

    func sessionRowContent(_ session: LoggingSession) -> SessionRow {
        let activations = activationsBySessionId[session.id] ?? []
        let primaryActivation = activations.first
        let qsos = qsosBySessionId[session.id] ?? []
        let meta = primaryActivation.flatMap { activationMetadata(for: $0) }
        let sessionJobs = activations.flatMap {
            jobsByActivationId[$0.id] ?? []
        }

        return SessionRow(
            session: session,
            qsos: qsos,
            activations: activations,
            metadata: meta,
            parkName: primaryActivation.flatMap { parkName(for: $0.parkReference) },
            hasRecording: recordingsBySessionId[session.id] != nil,
            hasFailedJob: sessionJobs.contains { $0.status.isFailure },
            hasCompletedJob: sessionJobs.contains {
                $0.status == .completed
            },
            showUploadButton: isAuthenticated,
            isUploadDisabled: isInMaintenance || potaClient == nil,
            onUploadTapped: buildUploadHandler(activations: activations),
            onRejectTapped: primaryActivation.map { act in
                { activationToReject = act }
            },
            onShareTapped: buildShareHandler(session: session, activations: activations),
            onExportTapped: primaryActivation.map { act in
                { activationToExport = act }
            },
            onMapTapped: primaryActivation == nil ? nil : {
                self.showMap(session: session, activations: activations)
            },
            onEditTapped: primaryActivation.map { act in
                { activationToEdit = act }
            }
        )
    }

    @ViewBuilder
    func sessionNavigationRow(_ session: LoggingSession) -> some View {
        let rowContent = sessionRowContent(session)
        let activations = activationsBySessionId[session.id] ?? []
        let recording = recordingsBySessionId[session.id]

        if session.isRove {
            NavigationLink {
                roveSessionDetail(session: session, activations: activations)
            } label: { rowContent }
        } else if let activation = activations.first {
            NavigationLink {
                sessionDetailForActivation(
                    activation, session: session
                )
            } label: { rowContent }
        } else if let recording {
            NavigationLink {
                RecordingPlayerView(
                    recording: recording,
                    engine: engineFor(session.id)
                )
            } label: { rowContent }
        } else {
            NavigationLink {
                SessionDetailView(session: session)
            } label: { rowContent }
        }
    }

    @ViewBuilder
    func orphanActivationRow(
        _ activation: POTAActivation
    ) -> some View {
        let orphanJobs = jobsByActivationId[activation.id] ?? []
        let meta = activationMetadata(for: activation)

        NavigationLink {
            SessionDetailView(
                activation: activation,
                activationMetadata: meta,
                parkName: parkName(for: activation.parkReference),
                matchingJobs: orphanJobs,
                potaClient: potaClient,
                isAuthenticated: isAuthenticated,
                isInMaintenance: isInMaintenance,
                onUpload: {
                    await performUploadReturningErrors(for: activation)
                },
                onReject: { activationToReject = activation },
                onForceReupload: { forceReupload(activation) }
            )
        } label: {
            ActivationRow(
                activation: activation,
                metadata: meta,
                isUploadDisabled: isInMaintenance || potaClient == nil,
                showUploadButton: isAuthenticated,
                onUploadTapped: {
                    await performUploadReturningErrors(for: activation)
                },
                onRejectTapped: { activationToReject = activation },
                onShareTapped: { activationToShare = activation },
                onExportTapped: { activationToExport = activation },
                onMapTapped: { activationToMap = activation },
                onEditTapped: { activationToEdit = activation },
                parkName: parkName(for: activation.parkReference),
                hasFailedJob: orphanJobs.contains {
                    $0.status.isFailure
                },
                hasCompletedJob: orphanJobs.contains {
                    $0.status == .completed
                }
            )
        }
    }

    var maintenanceBanner: some View {
        HStack {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("POTA Maintenance Window")
                    .font(.subheadline).fontWeight(.medium)
                Text(
                    maintenanceTimeRemaining.map {
                        "Uploads disabled. Resumes in \($0)"
                    } ?? "Uploads temporarily disabled (2330-0400 UTC)"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
