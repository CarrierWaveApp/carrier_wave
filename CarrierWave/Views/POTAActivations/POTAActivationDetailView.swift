// POTA Activation Detail View
//
// Full detail view for a single POTA activation, shown when tapping
// an activation card in the list. Displays activation info, upload
// controls, POTA jobs, and QSO list.

import SwiftUI

// MARK: - POTAActivationDetailView

struct POTAActivationDetailView: View {
    // MARK: Internal

    let activation: POTAActivation
    let metadata: ActivationMetadata?
    let parkName: String?
    let matchingJobs: [POTAJob]
    let potaClient: POTAClient?
    let isAuthenticated: Bool
    let isInMaintenance: Bool
    /// Returns upload errors by park reference (empty dict on success)
    let onUpload: () async -> [String: String]
    let onReject: () -> Void
    let onEdit: () -> Void
    let onShare: () -> Void
    let onExport: () -> Void
    let onMap: () -> Void
    var onForceReupload: () -> Void = {}

    var body: some View {
        List {
            activationInfoSection
            if shouldShowUpload {
                uploadSection
            }
            if !matchingJobs.isEmpty {
                jobsSection
            }
            qsosSection
        }
        .navigationTitle(activation.parkReference)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                actionsMenu
            }
        }
    }

    // MARK: Private

    @AppStorage("debugMode") private var debugMode = false
    @State private var isUploading = false
    @State private var uploadErrors: [String: String] = [:]

    private var hasCompletedJob: Bool {
        matchingJobs.contains { $0.status == .completed }
    }

    private var shouldShowUpload: Bool {
        activation.hasQSOsToUpload && isAuthenticated && !hasCompletedJob
    }

    private var sortedQSOs: [QSO] {
        activation.qsos.sorted { $0.timestamp > $1.timestamp }
    }

    private var activationRadio: String? {
        activation.qsos.compactMap(\.myRig).first
    }

    private var hasMetadata: Bool {
        metadata?.watts != nil || metadata?.averageWPM != nil
            || activationRadio != nil
            || (metadata?.weather != nil && !(metadata?.weather?.isEmpty ?? true))
            || (metadata?.solarConditions != nil && !(metadata?.solarConditions?.isEmpty ?? true))
    }

    // MARK: - Activation Info Section

    private var activationInfoSection: some View {
        Section {
            if let parkName {
                Text(parkName)
                    .font(.headline)
            }

            HStack {
                Text(activation.displayDate)
                    .font(.subheadline)
                Spacer()
                Text(activation.callsign)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            statsRow

            if hasMetadata {
                metadataRow
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statBadge(
                "\(activation.qsoCount) QSO\(activation.qsoCount == 1 ? "" : "s")",
                icon: "antenna.radiowaves.left.and.right"
            )
            if activation.duration > 0 {
                statBadge(activation.formattedDuration, icon: "clock")
            }
            if !activation.uniqueBands.isEmpty {
                statBadge(
                    activation.uniqueBands.sorted().joined(separator: ", "),
                    icon: "dial.medium.fill"
                )
            }
            if !activation.uniqueModes.isEmpty {
                statBadge(
                    activation.uniqueModes.sorted().joined(separator: ", "),
                    icon: "waveform"
                )
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var metadataRow: some View {
        HStack(spacing: 8) {
            if let watts = metadata?.watts {
                Text("\(watts)W")
                    .font(.caption)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(4)
            }
            if let radio = activationRadio {
                Text(radio)
                    .font(.caption)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(4)
            }
            if let wpm = metadata?.averageWPM {
                Text("\(wpm) WPM")
                    .font(.caption)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(4)
            }
            if let weather = metadata?.weather, !weather.isEmpty {
                Label(weather, systemImage: "cloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let solar = metadata?.solarConditions, !solar.isEmpty {
                Label(solar, systemImage: "sun.max")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Upload Section

    private var uploadSection: some View {
        Section {
            if isUploading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Uploading...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                Button {
                    isUploading = true
                    Task {
                        let errors = await onUpload()
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
                .disabled(isInMaintenance)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            if !uploadErrors.isEmpty {
                ForEach(uploadErrors.sorted(by: { $0.key < $1.key }), id: \.key) { park, error in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(park).font(.subheadline).fontWeight(.medium)
                            Text(error).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Label("Upload", systemImage: "arrow.up.circle")
        }
    }

    // MARK: - Jobs Section

    private var jobsSection: some View {
        Section {
            ForEach(matchingJobs) { job in
                POTAJobRow(job: job, potaClient: potaClient)
            }
        } header: {
            Text("POTA Jobs")
        }
    }

    // MARK: - QSOs Section

    private var qsosSection: some View {
        Section {
            ForEach(sortedQSOs) { qso in
                POTAQSORow(qso: qso, parks: activation.parks)
            }
        } header: {
            Text("\(activation.qsoCount) QSO\(activation.qsoCount == 1 ? "" : "s")")
        }
    }

    // MARK: - Toolbar Menu

    private var actionsMenu: some View {
        Menu {
            Button {
                onEdit()
            } label: {
                Label("Edit Metadata", systemImage: "pencil")
            }
            Button {
                onMap()
            } label: {
                Label("View Map", systemImage: "map")
            }
            Button {
                onExport()
            } label: {
                Label("Export ADIF", systemImage: "doc.text")
            }
            Button {
                onShare()
            } label: {
                Label("Share Card", systemImage: "square.and.arrow.up")
            }
            if shouldShowUpload {
                Divider()
                Button(role: .destructive) {
                    onReject()
                } label: {
                    Label("Reject Upload", systemImage: "xmark.circle")
                }
            }
            if debugMode {
                Divider()
                Button {
                    onForceReupload()
                } label: {
                    Label("Force Reupload", systemImage: "arrow.counterclockwise.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - Helpers

    private func statBadge(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .lineLimit(1)
    }
}
