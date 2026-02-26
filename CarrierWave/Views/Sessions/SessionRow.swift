// Unified session row for the merged Sessions list.
// Shows rich content for all session types: timeline, conditions, badges.
// POTA sessions additionally show upload status and upload button.

import SwiftUI

// MARK: - SessionRow

struct SessionRow: View {
    // MARK: Internal

    let session: LoggingSession
    let qsos: [QSO]
    var activations: [POTAActivation] = []
    var metadata: ActivationMetadata?
    var parkName: String?
    var hasRecording: Bool = false
    var hasFailedJob: Bool = false
    var hasCompletedJob: Bool = false

    /// POTA upload controls
    var showUploadButton: Bool = false
    var isUploadDisabled: Bool = false
    var onUploadTapped: (() async -> [String: String])?
    var onRejectTapped: (() -> Void)?
    var onShareTapped: (() -> Void)?
    var onExportTapped: (() -> Void)?
    var onMapTapped: (() -> Void)?
    var onEditTapped: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
            titleRow
            if !isLandscape {
                if !qsos.isEmpty {
                    QSOTimelineView(qsos: qsos, compact: true)
                }
            }
            statusRow
            if !isLandscape {
                conditionsRow
                if hasFailedJob {
                    failedJobBanner
                }
                if shouldShowUpload {
                    uploadSection
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu { contextMenuItems }
        .sheet(isPresented: $showingConditions) {
            ActivationConditionsSheet(metadata: session)
        }
    }

    // MARK: Private

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isUploading = false
    @State private var uploadErrors: [String: String] = [:]
    @State private var showingConditions = false

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    private var isPOTA: Bool {
        session.isPOTA && !activations.isEmpty
    }

    private var shouldShowUpload: Bool {
        guard !activations.isEmpty, showUploadButton, !hasCompletedJob else {
            return false
        }
        return activations.contains { $0.hasQSOsToUpload }
    }

    private var totalPendingCount: Int {
        activations.reduce(0) { $0 + $1.pendingCount }
    }

    /// Combined status view for one or more activations
    @ViewBuilder
    private var roveAwareStatusView: some View {
        if activations.count == 1, let activation = activations.first {
            HStack(spacing: 4) {
                Image(systemName: activation.displayIconName)
                    .foregroundStyle(activation.displayColor)
                Text(activation.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            let totalQSOs = activations.reduce(0) { $0 + $1.qsoCount }
            let totalUploaded = activations.reduce(0) { $0 + $1.uploadedCount }
            let allUploaded = activations.allSatisfy(\.isFullyUploaded)
            let uniqueParks = Set(activations.map { $0.parkReference.uppercased() }).count
            HStack(spacing: 4) {
                Image(systemName: allUploaded ? "checkmark.circle.fill" : "arrow.up.circle")
                    .foregroundStyle(allUploaded ? .green : .gray)
                Text(
                    allUploaded
                        ? "\(uniqueParks) parks, \(totalQSOs) QSOs accepted"
                        : "\(totalUploaded)/\(totalQSOs) QSOs across \(uniqueParks) parks"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Image(systemName: session.programsIcon)
                .foregroundStyle(.secondary)
            Text(session.startedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.headline)
                .lineLimit(1)
                .layoutPriority(1)
            if session.isRove {
                roveRefSummary
            } else if let ref = session.activationReference {
                Text(ref)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(session.myCallsign)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var roveRefSummary: some View {
        let stops = session.roveStops.sorted { $0.startedAt < $1.startedAt }
        let parks = stops.map {
            ParkReference.split($0.parkReference).first ?? $0.parkReference
        }
        let display = parks.prefix(3).joined(separator: " \u{2192} ")
        let suffix = parks.count > 3 ? " +\(parks.count - 3)" : ""
        Text(display + suffix)
            .font(.caption.monospaced())
            .foregroundStyle(.green)
            .lineLimit(1)
    }

    // MARK: - Title

    @ViewBuilder
    private var titleRow: some View {
        if let title = session.customTitle ?? metadata?.title, !title.isEmpty {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    // MARK: - Status Row

    private var statusRow: some View {
        HStack(spacing: 8) {
            // POTA upload status
            if !activations.isEmpty {
                roveAwareStatusView
            } else {
                // Non-POTA: QSO count and duration
                Text(
                    "\(session.qsoCount) QSO\(session.qsoCount == 1 ? "" : "s")"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(session.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Power badge
            if let watts = session.power ?? metadata?.watts {
                Text("\(watts)W")
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(4)
            }

            // WPM badge
            if let wpm = metadata?.averageWPM {
                Text("\(wpm) WPM")
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(4)
            }

            // Mode badge (non-POTA only, since POTA shows via timeline)
            if activations.isEmpty {
                Text(session.mode)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(4)
            }

            // Recording indicator
            if hasRecording {
                Label("Recording", systemImage: "waveform.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            // Photos indicator
            if !session.photoFilenames.isEmpty {
                Label(
                    "\(session.photoFilenames.count)",
                    systemImage: "photo"
                )
                .font(.caption2)
                .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Conditions

    @ViewBuilder
    private var conditionsRow: some View {
        if session.hasSolarData || session.hasWeatherData {
            ConditionsGaugeRow(metadata: session, showingSheet: $showingConditions)
        } else if let meta = metadata, meta.hasSolarData || meta.hasWeatherData {
            ConditionsGaugeRow(metadata: meta, showingSheet: $showingConditions)
        }
    }

    // MARK: - Failed Job Banner

    private var failedJobBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("POTA job failed — tap for details")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Upload Section

    @ViewBuilder
    private var uploadSection: some View {
        if !activations.isEmpty {
            if isUploading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Uploading...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 6) {
                    Button {
                        isUploading = true
                        Task {
                            let errors = await onUploadTapped?() ?? [:]
                            uploadErrors = errors
                            isUploading = false
                        }
                    } label: {
                        Label(
                            "Upload \(totalPendingCount) QSO\(totalPendingCount == 1 ? "" : "s") to POTA",
                            systemImage: "arrow.up.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUploadDisabled)

                    ForEach(
                        uploadErrors.sorted(by: { $0.key < $1.key }), id: \.key
                    ) { _, error in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if isPOTA {
            Button { onEditTapped?() } label: {
                Label("Edit Metadata", systemImage: "pencil")
            }
            Button { onMapTapped?() } label: {
                Label("View Map", systemImage: "map")
            }
            Button { onExportTapped?() } label: {
                Label("Export ADIF", systemImage: "doc.text")
            }
            Button { onShareTapped?() } label: {
                Label("Brag Sheet", systemImage: "square.and.arrow.up")
            }
            if shouldShowUpload {
                Divider()
                Button(role: .destructive) { onRejectTapped?() } label: {
                    Label("Reject Upload", systemImage: "xmark.circle")
                }
            }
        }
    }
}
