import CarrierWaveCore
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

    @Environment(\.modelContext) var modelContext
    @AppStorage("statisticianMode") var statisticianMode = false
    @AppStorage("debugMode") var debugMode = false
    @State var qsos: [QSO] = []
    @State var qsoToDelete: QSO?
    @State var qsoToEdit: QSO?
    @State var hiddenQSOIds: Set<UUID> = []

    // POTA state
    @State var recording: WebSDRRecording?
    @State var engine = RecordingPlaybackEngine()
    @State var isUploading = false
    @State var uploadErrors: [String: String] = [:]
    @State var showingConditions = false
    @State var activationSession: LoggingSession?
    @State var activationStatistics: ActivationStatistics?

    @State var showEditSheet = false
    @State var selectedPhoto: PhotoItem?

    /// QSOs for display — uses activation QSOs when available, filtered by hidden
    var displayQSOs: [QSO] {
        if activation != nil {
            return qsos.filter { !hiddenQSOIds.contains($0.id) }
        }
        return qsos
    }

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = statisticianMode
        List {
            if activation != nil {
                potaInfoSection
            } else if let session {
                sessionSummarySection(session)
            }

            if let session, session.isRove {
                roveStopsSection(session)
            }

            mapSection

            qsoSection

            if let recording {
                recordingSection(recording)
            }

            if let stats = activationStatistics, statisticianMode {
                Section("Statistics") {
                    ActivationStatsChartsView(stats: stats, qsos: displayQSOs)
                    ActivationStatsSummaryView(stats: stats)
                }
            }

            if let session {
                detailsSection(session)
            }

            if !matchingJobs.isEmpty {
                potaJobsSection
            }

            if let session {
                SessionSpotsSection(session: session)
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
        .task {
            await loadQSOs()
            if activation != nil {
                await loadRecording()
                loadActivationSession()
            }
            computeStatistics()
        }
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

    private var hasActions: Bool {
        onShare != nil || onExport != nil
    }

    private var actionsMenu: some View {
        Group {
            if hasActions || activation != nil {
                Menu {
                    if session != nil {
                        Button {
                            showEditSheet = true
                        } label: {
                            Label("Edit Info", systemImage: "pencil")
                        }
                    }
                    if let onExport {
                        Button {
                            onExport()
                        } label: {
                            Label("Export ADIF", systemImage: "doc.text")
                        }
                    }
                    if let onShare {
                        Button {
                            onShare()
                        } label: {
                            Label("Brag Sheet", systemImage: "square.and.arrow.up")
                        }
                    }
                    if shouldShowUpload, let onReject {
                        Divider()
                        Button(role: .destructive) {
                            onReject()
                        } label: {
                            Label("Reject Upload", systemImage: "xmark.circle")
                        }
                    }
                    if debugMode, let onForceReupload {
                        Divider()
                        Button {
                            onForceReupload()
                        } label: {
                            Label(
                                "Force Reupload",
                                systemImage: "arrow.counterclockwise.circle"
                            )
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            } else if session != nil {
                Button("Edit") {
                    showEditSheet = true
                }
            }
        }
    }

    // MARK: - Session Info Sections
}
