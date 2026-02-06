// POTA Activations Helper Views

import SwiftUI

// MARK: - ActivationRow

struct ActivationRow: View {
    // MARK: Internal

    let activation: POTAActivation
    var isUploadDisabled: Bool = false
    var showUploadButton: Bool = true
    let onUploadTapped: () -> Void
    let onRejectTapped: () -> Void
    let onShareTapped: () -> Void
    let onExportTapped: () -> Void
    let onMapTapped: () -> Void
    var showParkReference: Bool = false
    var parkName: String?
    /// Upload errors by park (for two-fer error display)
    var uploadErrors: [String: String] = [:]
    /// Pre-computed matching jobs for this activation (computed by parent)
    var matchingJobs: [POTAJob] = []
    /// POTA client for fetching job details
    var potaClient: POTAClient?

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
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

            // QSOs section - use activation.qsos directly (already sorted in POTAActivation.groupQSOs)
            ForEach(sortedQSOs) { qso in
                POTAQSORow(qso: qso, parks: activation.parks)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(activation.displayDate)
                            .font(.headline)
                        if showParkReference {
                            Text(activation.parkReference)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let parkName {
                                Text("- \(parkName)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Text(activation.callsign)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Image(systemName: statusIconName)
                            .foregroundStyle(statusColor)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Warning indicator for failed POTA jobs
                if hasFailedJob {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.body)
                }

                // Error indicator for failed park uploads (two-fer support)
                if !uploadErrors.isEmpty {
                    Button {
                        showingErrorSheet = true
                    } label: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }

                // Map button
                Button {
                    onMapTapped()
                } label: {
                    Image(systemName: "map")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.green)

                // Export ADIF button
                Button {
                    onExportTapped()
                } label: {
                    Image(systemName: "doc.text")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.orange)

                // Share button
                Button {
                    onShareTapped()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)

                if activation.hasQSOsToUpload, showUploadButton {
                    Button("Upload") {
                        onUploadTapped()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isUploadDisabled)
                }
            }
            .padding(.vertical, 4)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if activation.hasQSOsToUpload {
                Button {
                    onRejectTapped()
                } label: {
                    Label("Reject", systemImage: "xmark.circle")
                }
                .tint(.red)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onMapTapped()
            } label: {
                Label("Map", systemImage: "map")
            }
            .tint(.green)

            Button {
                onExportTapped()
            } label: {
                Label("Export ADIF", systemImage: "doc.text")
            }
            .tint(.orange)

            Button {
                onShareTapped()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)
        }
        .sheet(isPresented: $showingErrorSheet) {
            UploadErrorSheet(
                parkReference: activation.parkReference,
                errors: uploadErrors
            )
        }
    }

    // MARK: Private

    @State private var isExpanded = false
    @State private var showingErrorSheet = false

    /// QSOs sorted by timestamp descending (computed once)
    private var sortedQSOs: [QSO] {
        activation.qsos.sorted { $0.timestamp > $1.timestamp }
    }

    /// Check if any matching job has failed status
    private var hasFailedJob: Bool {
        matchingJobs.contains { $0.status.isFailure }
    }

    private var statusIconName: String {
        if activation.isRejected {
            return "xmark.circle.fill"
        }
        return activation.status.iconName
    }

    private var statusColor: Color {
        if activation.isRejected {
            return .secondary
        }
        switch activation.status {
        case .uploaded: return .green
        case .partial: return .orange
        case .pending: return .gray
        }
    }

    private var statusText: String {
        let rejectedCount = activation.rejectedQSOs().count

        // For two-fers, show park upload status
        if activation.isMultiPark {
            if let summary = activation.uploadStatusSummary {
                if activation.isRejected {
                    return "\(summary), \(rejectedCount) rejected"
                } else if rejectedCount > 0 {
                    return "\(summary), \(rejectedCount) rejected"
                }
                return "\(summary) uploaded"
            }
        }

        if activation.isRejected {
            return
                "\(activation.uploadedCount)/\(activation.qsoCount) uploaded, \(rejectedCount) rejected"
        } else if rejectedCount > 0 {
            return
                "\(activation.uploadedCount)/\(activation.qsoCount) uploaded, \(rejectedCount) rejected"
        }
        return "\(activation.uploadedCount)/\(activation.qsoCount) QSOs uploaded"
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

    @ViewBuilder private var uploadStatusView: some View {
        if parks.count > 1 {
            HStack(spacing: 2) {
                ForEach(parks, id: \.self) { park in
                    Image(
                        systemName: qso.isUploadedToPark(park) ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(qso.isUploadedToPark(park) ? .green : .secondary)
                    .font(.caption2)
                }
            }
        } else {
            Image(systemName: qso.isPresentInPOTA() ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(qso.isPresentInPOTA() ? .green : .secondary)
                .font(.caption)
        }
    }

    private func badgeView(_ text: String, color: Color) -> some View {
        Text(text).font(.caption)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15)).cornerRadius(4)
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

// MARK: - UploadConfirmationSheet

struct UploadConfirmationSheet: View {
    // MARK: Internal

    let activation: POTAActivation
    let parkName: String?
    /// Park names by reference (for two-fer display)
    var parkNames: [String: String] = [:]
    let onUpload: () async -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    if activation.isMultiPark {
                        // Show all parks for two-fer
                        Text("Two-fer Activation")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        ForEach(activation.parks, id: \.self) { park in
                            HStack {
                                Text(park)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                if let name = parkNames[park] {
                                    Text("- \(name)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Text(activation.parkReference)
                            .font(.title)
                            .fontWeight(.bold)
                        if let name = parkName {
                            Text(name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(spacing: 12) {
                    UploadDetailRow(label: "Date", value: activation.displayDate)
                    UploadDetailRow(label: "Callsign", value: activation.callsign)
                    UploadDetailRow(
                        label: "QSOs to Upload",
                        value: "\(activation.pendingCount) of \(activation.qsoCount)"
                    )
                    if activation.isMultiPark {
                        UploadDetailRow(
                            label: "Parks to Upload",
                            value:
                            "\(activation.parksNeedingUpload.count) of \(activation.parks.count)"
                        )
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                Spacer()

                if isUploading {
                    ProgressView("Uploading...")
                } else {
                    VStack(spacing: 12) {
                        Button {
                            isUploading = true
                            Task {
                                await onUpload()
                            }
                        } label: {
                            if activation.isMultiPark {
                                Text("Upload to \(activation.parksNeedingUpload.count) Parks")
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Upload \(activation.pendingCount) QSOs")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button("Cancel", role: .cancel) {
                            onCancel()
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Upload Activation")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    // MARK: Private

    @State private var isUploading = false
}

// MARK: - UploadDetailRow

struct UploadDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
