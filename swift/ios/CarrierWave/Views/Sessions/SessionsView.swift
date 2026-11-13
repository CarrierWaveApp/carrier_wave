// Unified Sessions list with POTA activations, upload controls, and import.
// Data loading and actions in SessionsView+Actions.swift.

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

        var key: SessionsListEntryKey {
            switch self {
            case let .session(session): .session(session.id)
            case let .orphanActivation(activation): .orphanActivation(activation.id)
            }
        }

        var id: String {
            key.listItemID
        }

        var date: Date {
            switch self {
            case let .session(session): session.startedAt
            case let .orphanActivation(activation): activation.utcDate
            }
        }
    }

    /// One month section of the list, cached in `itemsByMonth`.
    struct MonthSection {
        let month: String
        let items: [ListItem]
    }

    let potaClient: POTAClient?
    let potaAuth: POTAAuthService
    let tourState: TourState
    let qrzClient: QRZClient?
    var sessionManager: LoggingSessionManager?
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
    @State var qrzPendingBySessionId: [UUID: Int] = [:]
    @State var isLoadingJobs = false
    @State var errorMessage: String?
    @State var maintenanceTimeRemaining: String?
    @State var maintenanceTimer: Timer?

    @State var itemToDelete: ListItem?
    @State var activationToReject: POTAActivation?
    @State var activationToShare: POTAActivation?
    @State var activationToExport: ActivationExportRequest?
    @State var activationToMap: POTAActivation?
    @State var roveStopsForMap: [RoveStop] = []
    @State var activationToEdit: POTAActivation?
    @State var sessionToImport: LoggingSession?
    @State var sessionToSplitExport: LoggingSession?
    @State var sessionToReopen: LoggingSession?
    @State var sessionToMerge: LoggingSession?
    @State var sessionToShare: LoggingSession?
    @State var sessionToExportADIF: LoggingSession?
    @State var isGeneratingShareImage = false
    @State var sharePreviewData: SharePreviewData?
    @State var experimentRefreshID = UUID()

    /// Cached, pre-grouped rows. Rebuilt off the main thread by
    /// `scheduleListRebuild` whenever `listEntries` changes (CAR-154) — never
    /// derived in `body`.
    @State var itemsByMonth: [MonthSection] = []
    @State var listRebuildTask: Task<Void, Never>?
    @State var listGrouping = SessionsListGroupingActor()

    @AppStorage("debugMode") var debugMode = false
    @AppStorage("bypassPOTAMaintenance") var bypassMaintenance = false

    var isReopenPresented: Binding<Bool> {
        Binding(
            get: { sessionToReopen != nil },
            set: { newValue in
                if !newValue {
                    sessionToReopen = nil
                }
            }
        )
    }

    var isInMaintenance: Bool {
        if debugMode, bypassMaintenance {
            return false
        }
        return POTAClient.isInMaintenanceWindow()
    }

    var isAuthenticated: Bool {
        potaAuth.isConfigured
    }

    var hasQRZApiKey: Bool {
        qrzClient?.hasApiKey() ?? false
    }

    var allActivations: [POTAActivation] {
        activationsBySessionId.values.flatMap { $0 } + orphanActivations
    }

    /// Identity + date snapshot of every row the list should show. This is the
    /// only per-render pass over `sessions`; it does no sorting, grouping, or
    /// date formatting, and `sessions` is capped at 200 by `loadSessions`.
    var listEntries: [SessionsListEntry] {
        var entries: [SessionsListEntry] = []
        entries.reserveCapacity(sessions.count + orphanActivations.count)
        for session in sessions where qsosBySessionId[session.id]?.isEmpty == false {
            entries.append(SessionsListEntry(key: .session(session.id), date: session.startedAt))
        }
        for activation in orphanActivations {
            entries.append(
                SessionsListEntry(key: .orphanActivation(activation.id), date: activation.utcDate)
            )
        }
        return entries
    }

    var body: some View {
        Group {
            if sessions.isEmpty, orphanActivations.isEmpty, activeSessionsHeader == nil {
                emptyState
            } else {
                sessionsList
            }
        }
        .id(experimentRefreshID)
        .miniTour(.potaActivations, tourState: tourState)
        .navigationTitle(isEmbedded ? "" : "Sessions")
        .onReceive(
            NotificationCenter.default.publisher(for: .tabConfigurationChanged)
        ) { _ in
            experimentRefreshID = UUID()
        }
        .onChange(of: listEntries, initial: true) { _, entries in
            scheduleListRebuild(entries)
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
        .modifier(shareAndExportModifiers)
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
        .sessionADIFImportable(session: $sessionToImport) {
            await loadSessions()
            await loadOrphanActivations()
        }
        .confirmationDialog(
            "Reopen Session",
            isPresented: isReopenPresented,
            titleVisibility: .visible
        ) {
            Button("Reopen") { reopenSession() }
            Button("Cancel", role: .cancel) { sessionToReopen = nil }
        } message: {
            Text("This session will become active and you can log more QSOs.")
        }
        .sheet(item: $sessionToSplitExport) { session in
            SplitADIFExportSheet(
                session: session,
                qsos: qsosBySessionId[session.id] ?? []
            )
        }
        .sheet(item: $sessionToMerge) { source in
            MergeSessionPickerSheet(
                sourceSession: source,
                onMerge: { target in
                    mergeSession(source, into: target)
                }
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
            Color.primary.opacity(0.4).ignoresSafeArea().overlay {
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
                    Label("Awards & Certificates", systemImage: "trophy.fill")
                }

                if isInMaintenance {
                    maintenanceBanner
                }

                if let error = errorMessage {
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
            } header: {
                Text("More")
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
        buildSessionRow(session)
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
        } else if session.activationType == .tota {
            // TOTA: skip RecordingPlayer and go to the detail view (which
            // renders the TOTA section).
            NavigationLink { nonPOTASessionDetail(session) } label: { rowContent }
        } else if let recording {
            NavigationLink {
                RecordingPlayerView(
                    recording: recording,
                    engine: engineFor(session.id)
                )
            } label: { rowContent }
        } else {
            NavigationLink {
                nonPOTASessionDetail(session)
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
                showUploadButton: isAuthenticated,
                onRejectTapped: { activationToReject = activation },
                onShareTapped: { activationToShare = activation },
                onExportTapped: {
                    activationToExport = ActivationExportRequest(activation: activation)
                },
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
