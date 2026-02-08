// POTA Activations Helper Views

import SwiftUI

// MARK: - ActivationRow

struct ActivationRow: View {
    // MARK: Lifecycle

    init(
        activation: POTAActivation,
        metadata: ActivationMetadata? = nil,
        isUploadDisabled: Bool = false,
        showUploadButton: Bool = true,
        onUploadTapped: @escaping () async -> Void,
        onRejectTapped: @escaping () -> Void,
        onShareTapped: @escaping () -> Void,
        onExportTapped: @escaping () -> Void,
        onMapTapped: @escaping () -> Void,
        onEditTapped: @escaping () -> Void,
        onForceReuploadTapped: @escaping () -> Void = {},
        showParkReference: Bool = false,
        parkName: String? = nil,
        uploadErrors: [String: String] = [:],
        matchingJobs: [POTAJob] = [],
        potaClient: POTAClient? = nil,
        isSelecting: Bool = false,
        isSelected: Bool = false,
        onSelectionToggled: (() -> Void)? = nil
    ) {
        self.activation = activation
        self.metadata = metadata
        self.isUploadDisabled = isUploadDisabled
        self.showUploadButton = showUploadButton
        self.onUploadTapped = onUploadTapped
        self.onRejectTapped = onRejectTapped
        self.onShareTapped = onShareTapped
        self.onExportTapped = onExportTapped
        self.onMapTapped = onMapTapped
        self.onEditTapped = onEditTapped
        self.onForceReuploadTapped = onForceReuploadTapped
        self.showParkReference = showParkReference
        self.parkName = parkName
        self.uploadErrors = uploadErrors
        self.matchingJobs = matchingJobs
        self.potaClient = potaClient
        self.isSelecting = isSelecting
        self.isSelected = isSelected
        self.onSelectionToggled = onSelectionToggled
        // Auto-expand rows that have pending uploads
        let hasCompletedJob = matchingJobs.contains { $0.status == .completed }
        _isExpanded = State(
            initialValue: showUploadButton && activation.hasQSOsToUpload && !hasCompletedJob
        )
    }

    // MARK: Internal

    let activation: POTAActivation
    var metadata: ActivationMetadata?
    var isUploadDisabled: Bool = false
    var showUploadButton: Bool = true
    let onUploadTapped: () async -> Void
    let onRejectTapped: () -> Void
    let onShareTapped: () -> Void
    let onExportTapped: () -> Void
    let onMapTapped: () -> Void
    let onEditTapped: () -> Void
    let onForceReuploadTapped: () -> Void
    var showParkReference: Bool = false
    var parkName: String?
    /// Upload errors by park (for two-fer error display)
    var uploadErrors: [String: String] = [:]
    /// Pre-computed matching jobs for this activation (computed by parent)
    var matchingJobs: [POTAJob] = []
    /// POTA client for fetching job details
    var potaClient: POTAClient?
    /// Whether multi-select mode is active
    var isSelecting: Bool = false
    /// Whether this row is selected in multi-select mode
    var isSelected: Bool = false
    /// Callback when selection is toggled
    var onSelectionToggled: (() -> Void)?

    var body: some View {
        if isSelecting {
            selectionModeRow
        } else {
            normalModeRow
        }
    }

    // MARK: Private

    @AppStorage("debugMode") private var debugMode = false

    /// Auto-expand when there are QSOs to upload so the upload button is visible
    @State private var isExpanded: Bool
    @State private var isUploading = false
    @State private var showingErrorSheet = false

    /// QSOs sorted by timestamp descending (computed once)
    private var sortedQSOs: [QSO] {
        activation.qsos.sorted { $0.timestamp > $1.timestamp }
    }

    /// Check if any matching job has completed status
    private var hasCompletedJob: Bool {
        matchingJobs.contains { $0.status == .completed }
    }

    /// Check if any matching job has failed status
    private var hasFailedJob: Bool {
        matchingJobs.contains { $0.status.isFailure }
    }

    /// Whether upload controls should be shown — hide if a completed job exists
    private var shouldShowUpload: Bool {
        activation.hasQSOsToUpload && showUploadButton && !hasCompletedJob
    }

    // MARK: - Selection Mode Row

    private var selectionModeRow: some View {
        Button {
            onSelectionToggled?()
        } label: {
            HStack(spacing: 12) {
                SelectionCircleView(isSelected: isSelected)
                activationLabel
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(activation.parkReference) activation, \(isSelected ? "selected" : "not selected")"
        )
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Normal Mode Row

    private var normalModeRow: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            // Park info header
            if showParkReference {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activation.parkReference)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let parkName {
                        Text(parkName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Upload row inside disclosure content where button taps work reliably
            if shouldShowUpload {
                uploadRow
            }

            // Jobs section (shown first when there are matching jobs)
            if !matchingJobs.isEmpty {
                Section {
                    ForEach(matchingJobs) { job in
                        POTAJobRow(job: job, potaClient: potaClient)
                    }
                } header: {
                    Text("POTA Jobs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            // QSOs section
            ForEach(sortedQSOs) { qso in
                POTAQSORow(qso: qso, parks: activation.parks)
            }
        } label: {
            HStack {
                activationLabel

                Spacer()

                // Warning indicator for failed POTA jobs
                if hasFailedJob {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.body)
                }

                // Upload pending indicator
                if shouldShowUpload {
                    if isUploading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.body)
                    }
                }

                // Actions menu
                Menu {
                    Button {
                        onEditTapped()
                    } label: {
                        Label("Edit Metadata", systemImage: "pencil")
                    }
                    Button {
                        onMapTapped()
                    } label: {
                        Label("View Map", systemImage: "map")
                    }
                    Button {
                        onExportTapped()
                    } label: {
                        Label("Export ADIF", systemImage: "doc.text")
                    }
                    Button {
                        onShareTapped()
                    } label: {
                        Label("Share Card", systemImage: "square.and.arrow.up")
                    }
                    if !uploadErrors.isEmpty {
                        Button {
                            showingErrorSheet = true
                        } label: {
                            Label("Upload Errors", systemImage: "exclamationmark.circle")
                        }
                    }
                    if shouldShowUpload {
                        Divider()
                        Button(role: .destructive) {
                            onRejectTapped()
                        } label: {
                            Label("Reject Upload", systemImage: "xmark.circle")
                        }
                    }
                    if debugMode {
                        Divider()
                        Button {
                            onForceReuploadTapped()
                        } label: {
                            Label("Force Reupload", systemImage: "arrow.counterclockwise.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if shouldShowUpload {
                Button {
                    onRejectTapped()
                } label: {
                    Label("Reject", systemImage: "xmark.circle")
                }
                .tint(.red)
            }
        }
        .sheet(isPresented: $showingErrorSheet) {
            UploadErrorSheet(
                parkReference: activation.parkReference,
                errors: uploadErrors
            )
        }
    }

    private var activationLabel: some View {
        ActivationLabel(
            activation: activation,
            metadata: metadata,
            showParkReference: showParkReference
        )
    }

    private var uploadRow: some View {
        HStack {
            if isUploading {
                ProgressView()
                    .controlSize(.small)
                Text("Uploading...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    isUploading = true
                    Task {
                        await onUploadTapped()
                        isUploading = false
                    }
                } label: {
                    Label(
                        "Upload \(activation.pendingCount) QSO(s) to POTA",
                        systemImage: "arrow.up.circle.fill"
                    )
                    .font(.subheadline)
                }
                .disabled(isUploadDisabled)
            }
            Spacer()
        }
    }
}

// MARK: - POTAActivation Display Helpers

extension POTAActivation {
    var displayIconName: String {
        isRejected ? "xmark.circle.fill" : status.iconName
    }

    var displayColor: Color {
        if isRejected {
            return .secondary
        }
        switch status {
        case .uploaded: return .green
        case .partial: return .orange
        case .submitted: return .blue
        case .pending: return .gray
        }
    }

    var statusText: String {
        let rejectedCount = rejectedQSOs().count
        let accepted = uploadedCount
        let submitted = submittedCount
        let total = qsoCount

        if isMultiPark, let summary = uploadStatusSummary {
            return rejectedCount > 0 ? "\(summary), \(rejectedCount) rejected" : summary
        }

        if isRejected || rejectedCount > 0 {
            return "\(accepted)/\(total) accepted, \(rejectedCount) rejected"
        } else if accepted == total {
            return "\(total) QSOs accepted"
        } else if accepted > 0, submitted > 0 {
            return "\(accepted) accepted, \(submitted) submitted"
        } else if submitted > 0 {
            return "\(submitted)/\(total) QSOs submitted"
        } else if accepted > 0 {
            return "\(accepted)/\(total) QSOs accepted"
        }
        return "\(total) QSOs"
    }
}

// MARK: - POTAQSORow

struct POTAQSORow: View {
    // MARK: Internal

    let qso: QSO
    var parks: [String] = [] // For two-fer per-park status display

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(qso.callsign).font(.subheadline).fontWeight(.medium)
                Text(timeString).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                badgeView(qso.band, color: .blue)
                badgeView(qso.mode, color: .green)
            }
            uploadStatusView
        }
        .padding(.vertical, 2)
    }

    // MARK: Private

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: qso.timestamp) + " UTC"
    }

    private var singleParkStatusIcon: String {
        // Use park-aware check so per-park presence records are found
        if parks.count == 1, let park = parks.first {
            return parkStatusIcon(for: park)
        }
        if qso.isPresentInPOTA() {
            return "checkmark.circle.fill"
        } else if qso.isSubmittedToAnyPark() {
            return "clock.arrow.circlepath"
        }
        return "circle"
    }

    private var singleParkStatusColor: Color {
        // Use park-aware check so per-park presence records are found
        if parks.count == 1, let park = parks.first {
            return parkStatusColor(for: park)
        }
        if qso.isPresentInPOTA() {
            return .green
        } else if qso.isSubmittedToAnyPark() {
            return .blue
        }
        return .secondary
    }

    @ViewBuilder private var uploadStatusView: some View {
        if parks.count > 1 {
            HStack(spacing: 2) {
                ForEach(parks, id: \.self) { park in
                    Image(systemName: parkStatusIcon(for: park))
                        .foregroundStyle(parkStatusColor(for: park))
                        .font(.caption2)
                }
            }
        } else {
            Image(systemName: singleParkStatusIcon)
                .foregroundStyle(singleParkStatusColor)
                .font(.caption)
        }
    }

    private func badgeView(_ text: String, color: Color) -> some View {
        Text(text).font(.caption)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15)).cornerRadius(4)
    }

    private func parkStatusIcon(for park: String) -> String {
        if qso.isUploadedToPark(park) {
            return "checkmark.circle.fill"
        } else if qso.isSubmittedToPark(park) {
            return "clock.arrow.circlepath"
        }
        return "circle"
    }

    private func parkStatusColor(for park: String) -> Color {
        if qso.isUploadedToPark(park) {
            return .green
        } else if qso.isSubmittedToPark(park) {
            return .blue
        }
        return .secondary
    }
}

// MARK: - UploadErrorSheet

struct UploadErrorSheet: View {
    // MARK: Internal

    let parkReference: String
    let errors: [String: String]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(errors.sorted(by: { $0.key < $1.key }), id: \.key) { park, error in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(park).font(.headline)
                            Text(error).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Failed Parks")
                } footer: {
                    Text("Tap Upload to retry.")
                }
            }
            .navigationTitle("Upload Errors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}
