// Unified session row for the merged Sessions list.
// Shows rich content for all session types: timeline, conditions, badges.
// POTA sessions additionally show upload status and upload button.

import SwiftUI

// MARK: - SessionRow

struct SessionRow: View {
    // MARK: Internal

    let session: LoggingSession
    let qsos: [QSO]
    var activation: POTAActivation?
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
            if !qsos.isEmpty {
                QSOTimelineView(qsos: qsos, compact: true)
            }
            statusRow
            conditionsRow
            if hasFailedJob {
                failedJobBanner
            }
            if shouldShowUpload {
                uploadSection
            }
        }
        .padding(.vertical, 4)
        .contextMenu { contextMenuItems }
        .sheet(isPresented: $showingConditions) {
            ActivationConditionsSheet(metadata: session)
        }
    }

    // MARK: Private

    @State private var isUploading = false
    @State private var uploadErrors: [String: String] = [:]
    @State private var showingConditions = false

    private var isPOTA: Bool {
        session.activationType == .pota && activation != nil
    }

    private var shouldShowUpload: Bool {
        guard let activation, showUploadButton, !hasCompletedJob else {
            return false
        }
        return activation.hasQSOsToUpload
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Image(systemName: session.activationType.icon)
                .foregroundStyle(.secondary)
            Text(session.startedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.headline)
                .lineLimit(1)
                .layoutPriority(1)
            if let ref = session.activationReference {
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
            if let activation {
                HStack(spacing: 4) {
                    Image(systemName: activation.displayIconName)
                        .foregroundStyle(activation.displayColor)
                    Text(activation.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(4)
            }

            // WPM badge
            if let wpm = metadata?.averageWPM {
                Text("\(wpm) WPM")
                    .font(.caption)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(4)
            }

            // Mode badge (non-POTA only, since POTA shows via timeline)
            if activation == nil {
                Text(session.mode)
                    .font(.caption)
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
        if let activation {
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
                            "Upload \(activation.pendingCount) QSO\(activation.pendingCount == 1 ? "" : "s") to POTA",
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
