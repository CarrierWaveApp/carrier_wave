// POTA Activations Helper Views

import CarrierWaveData
import SwiftUI

// MARK: - ActivationRow

/// Card-style activation row for the list. Tapping navigates to detail view.
/// The upload button is shown prominently on the card for pending activations.
/// Secondary actions are in a context menu (long press) and swipe actions.
struct ActivationRow: View {
    // MARK: Internal

    let activation: POTAActivation
    var metadata: ActivationMetadata?
    var showUploadButton: Bool = true
    let onRejectTapped: () -> Void
    let onShareTapped: () -> Void
    let onExportTapped: () -> Void
    let onMapTapped: () -> Void
    let onEditTapped: () -> Void
    var onForceReuploadTapped: () -> Void = {}
    var parkName: String?
    var hasFailedJob: Bool = false
    var hasCompletedJob: Bool = false
    /// Whether this activation is part of a rove session
    var isPartOfRove: Bool = false
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
                ActivationLabel(
                    activation: activation,
                    metadata: metadata,
                    showParkReference: true,
                    isPartOfRove: isPartOfRove
                )
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
        VStack(alignment: .leading, spacing: 8) {
            ActivationLabel(
                activation: activation,
                metadata: metadata,
                showParkReference: true,
                isPartOfRove: isPartOfRove
            )

            if hasFailedJob {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("POTA job failed — tap for details")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if shouldShowUpload {
                uploadButton
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
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
                Label("Brag Sheet", systemImage: "square.and.arrow.up")
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
    }

    private var uploadButton: some View {
        Button {
            onExportTapped()
        } label: {
            Label(
                "Upload \(activation.pendingCount) QSO\(activation.pendingCount == 1 ? "" : "s") to POTA",
                systemImage: "arrow.up.forward.app.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
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
    var isSpotted: Bool = false
    var sessionCallsign: String?
    var sessionPark: String?

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            SessionQSOExpandedDetail(qso: qso)
        } label: {
            HStack(spacing: 8) {
                if isSpotted {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.teal)
                }

                Text(qso.callsign)
                    .font(.subheadline.monospaced().weight(.semibold))
                    .lineLimit(1)
                if showMyCallsign {
                    badgeView(qso.myCallsign, color: .cyan)
                        .lineLimit(1)
                }
                if showMyPark, let park = qso.parkReference {
                    badgeView(park, color: .mint)
                        .lineLimit(1)
                }
                if let theirPark = qso.theirParkReference, !theirPark.isEmpty {
                    badgeView("P2P", color: .orange)
                }
                Spacer(minLength: 4)
                if let rst = compactRST {
                    Text(rst)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.orange)
                }
                badgeView(qso.band, color: .blue)
                badgeView(qso.mode, color: .green)
                uploadStatusView
                Text(Self.timeFormatter.string(from: qso.timestamp))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .animation(nil, value: isExpanded)
    }

    // MARK: Private

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @State private var isExpanded = false

    private var showMyCallsign: Bool {
        guard let sessionCallsign else {
            return false
        }
        return qso.myCallsign.uppercased() != sessionCallsign.uppercased()
    }

    private var showMyPark: Bool {
        guard let sessionPark, let qsoPark = qso.parkReference else {
            return false
        }
        return qsoPark.uppercased() != sessionPark.uppercased()
    }

    /// Compact RST: "S/R" format, nil if both missing
    private var compactRST: String? {
        let sent = qso.rstSent
        let rcvd = qso.rstReceived
        guard sent != nil || rcvd != nil else {
            return nil
        }
        return "\(sent ?? "-")/\(rcvd ?? "-")"
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
        .landscapeAdaptiveDetents(portrait: [.medium])
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}
