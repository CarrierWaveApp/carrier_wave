import CarrierWaveData
import MapKit
import SwiftData
import SwiftUI

// MARK: - SessionDetailView

/// Unified detail view for sessions and POTA activations.
/// Shows metadata, equipment, photos, QSO list, and conditionally
/// POTA upload controls, jobs, timeline, and recording player.
struct SessionDetailView: View {
    // MARK: Internal

    /// The logging session (nil for orphan POTA activations)
    var session: LoggingSession?
    var onShare: (() -> Void)?
    var onExport: (() -> Void)?
    var onImport: (() -> Void)?
    var onReopen: (() -> Void)?
    var onMerge: (() -> Void)?

    // MARK: POTA Properties (nil/empty when not a POTA activation)

    var activation: POTAActivation?
    var activationMetadata: ActivationMetadata?
    var parkName: String?
    var matchingJobs: [POTAJob] = []
    var potaClient: POTAClient?
    var isAuthenticated: Bool = false
    var isInMaintenance: Bool = false
    var onUpload: (() async -> [String: String])?
    var onReject: (() -> Void)?
    var onForceReupload: (() -> Void)?

    // QRZ upload
    var qrzUploadCount: Int = 0
    var onQRZUpload: (() async -> String?)?

    @Environment(\.modelContext) var modelContext
    @AppStorage("statisticianMode") var statisticianMode = false
    @AppStorage("debugMode") var debugMode = false
    @AppStorage("shareMapStyle") var shareMapStyleRaw = "adaptive"
    @State var mapCamera: MapCameraPosition = .automatic
    @State var qsos: [QSO] = []
    @State var qsoToDelete: QSO?
    @State var qsoToEdit: QSO?
    @State var hiddenQSOIds: Set<UUID> = []

    // POTA state
    @State var recording: WebSDRRecording?
    @State var engine = RecordingPlaybackEngine()
    @State var isUploading = false
    @State var isUploadingQRZ = false
    @State var uploadErrors: [String: String] = [:]
    @State var qrzUploadError: String?
    @State var showingConditions = false
    @State var activationSession: LoggingSession?
    @State var activationStatistics: ActivationStatistics?

    @State var spotQSOMatch: SpotQSOMatch?
    @State var spotMismatches: [SpotContactMismatch] = []
    @State var spotMismatchesDismissed = false
    @State var showEditSheet = false
    @State var selectedPhoto: PhotoItem?
    @State var showGridEditSheet = false
    @State var showMultiOpExportSheet = false
    @State var showSplitExportSheet = false
    @State var showDebugInfoSheet = false
    @State var parkCards: [ParkCardItem] = []
    @State var percentiles: SessionPercentiles?
    @State var refreshingT3Spots = false
    @State var showTOTABragSheet = false
    @State var showRejectConfirmation = false
    @State var showReopenConfirmation = false
    @State var showAddQSOSheet = false

    /// QSOs for display — uses activation QSOs when available, filtered by hidden
    var displayQSOs: [QSO] {
        if activation != nil {
            return qsos.filter { !hiddenQSOIds.contains($0.id) }
        }
        return qsos
    }

    var hasActions: Bool {
        onShare != nil || onExport != nil || onImport != nil
    }

    // MARK: - Session Info Sections

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = statisticianMode
        List {
            // MARK: Tier 1 — Hero Summary

            heroSection

            // MARK: Tier 1.5 — TOTA enrichment (only when activationType == .tota)

            totaSection

            // MARK: Tier 2 — QSO List (primary content)

            if !spotMismatchesDismissed, !spotMismatches.isEmpty {
                Section {
                    SpotContactMismatchBanner(
                        mismatches: spotMismatches,
                        onDismiss: {
                            withAnimation { spotMismatchesDismissed = true }
                        },
                        onTapMismatch: { mismatch in
                            if let qso = qsos.first(where: { $0.id == mismatch.qsoId }) {
                                qsoToEdit = qso
                            }
                        }
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            qsoSection

            // MARK: Tier 3 — Insights & Details

            insightsCarousel

            if let session, session.isRove {
                roveStopsSection(session)
            }

            clubMembersSummarySection

            if let stats = activationStatistics, statisticianMode {
                Section("Statistics") {
                    ActivationStatsChartsView(stats: stats, qsos: displayQSOs)
                    ActivationStatsSummaryView(stats: stats)
                }
            }

            if let session, hasNotesOrPhotos(session) {
                notesAndPhotosSection(session)
            }

            if !matchingJobs.isEmpty {
                potaJobsSection
            }

            if let session {
                SessionSpotsSection(
                    session: session,
                    spotQSOMatch: spotQSOMatch
                )

                PSKReporterSenderSection(session: session)
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                actionsMenu
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let session {
                SessionMetadataEditSheet(
                    session: session,
                    metadata: nil,
                    userGrid: session.myGrid,
                    onSave: { result in
                        applyEditResult(result)
                        showEditSheet = false
                    },
                    onCancel: { showEditSheet = false }
                )
            }
        }
        .sheet(isPresented: $showMultiOpExportSheet) {
            if let session {
                MultiOpExportSheet(session: session, qsos: qsos)
            }
        }
        .sheet(isPresented: $showSplitExportSheet) {
            if let session {
                SplitADIFExportSheet(session: session, qsos: qsos)
            }
        }
        .sheet(isPresented: $showDebugInfoSheet) {
            if let session {
                SessionDebugInfoSheet(
                    session: session,
                    qsos: qsos,
                    activationMetadata: activationMetadata
                )
            }
        }
        .sheet(isPresented: $showGridEditSheet) {
            BatchGridEditSheet(
                currentGrid: session?.myGrid,
                parkGroups: session?.isRove == true ? roveGroupedQSOs : nil,
                roveStopGrids: roveStopGridMap
            ) { result in
                applyBatchGridEdit(result)
            }
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            if let session {
                PhotoViewer(
                    url: SessionPhotoManager.photoURL(
                        filename: photo.filename, sessionID: session.id
                    )
                )
            }
        }
        .alert(
            "Delete QSO",
            isPresented: Binding(
                get: { qsoToDelete != nil },
                set: { newValue in
                    if !newValue {
                        qsoToDelete = nil
                    }
                }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let qso = qsoToDelete {
                    hiddenQSOIds.insert(qso.id)
                    qso.isHidden = true
                    for presence in qso.servicePresence where presence.needsUpload {
                        presence.needsUpload = false
                    }
                    qsos.removeAll { $0.id == qso.id }
                    try? modelContext.save()
                }
                qsoToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                qsoToDelete = nil
            }
        } message: {
            if let qso = qsoToDelete {
                Text("Delete QSO with \(qso.callsign)?")
            }
        }
        .sheet(item: $qsoToEdit) { qso in
            QSOEditSheet(qso: qso) {
                Task { await loadQSOs() }
            }
        }
        .sheet(isPresented: $showAddQSOSheet) {
            addQSOSheet
        }
        .modifier(
            SessionDetailConfirmations(
                showRejectConfirmation: $showRejectConfirmation,
                showReopenConfirmation: $showReopenConfirmation,
                activation: activation,
                onReject: onReject,
                onReopen: onReopen
            )
        )
        .task {
            await loadQSOs()
            if activation != nil {
                await loadRecording()
                loadActivationSession()
            }
            computeStatistics()
            computePercentiles()
            await loadParkCards()
        }
        .onReceive(sessionImportPublisher, perform: handleSessionImportNotification)
        .onChange(of: statisticianMode) { _, _ in
            computeStatistics()
        }
    }

    // MARK: Private

    private var navigationTitle: String {
        if let activation {
            return activation.parkReference
        }
        return session?.displayTitle ?? "Session"
    }
}
