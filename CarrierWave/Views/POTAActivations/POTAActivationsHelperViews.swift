// POTA Activations Helper Views
//
// Supporting views for the POTA Activations screen including
// row views, upload confirmation sheet, and detail components.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - ActivationRow

struct ActivationRow: View {
    // MARK: Internal

    let activation: POTAActivation
    var isUploadDisabled: Bool = false
    var showUploadButton: Bool = true
    let onUploadTapped: () -> Void
    let onRejectTapped: () -> Void
    let onShareTapped: () -> Void
    var showParkReference: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(activation.qsos.sorted { $0.timestamp > $1.timestamp }) { qso in
                POTAQSORow(qso: qso)
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
                onShareTapped()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)
        }
    }

    // MARK: Private

    @State private var isExpanded = false

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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(qso.callsign)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(timeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Text(qso.band)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(4)
                Text(qso.mode)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(4)
            }

            if qso.isPresentInPOTA() {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
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
}

// MARK: - UploadConfirmationSheet

struct UploadConfirmationSheet: View {
    // MARK: Internal

    let activation: POTAActivation
    let parkName: String?
    let onUpload: () async -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(activation.parkReference)
                        .font(.title)
                        .fontWeight(.bold)
                    if let name = parkName {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 12) {
                    UploadDetailRow(label: "Date", value: activation.displayDate)
                    UploadDetailRow(label: "Callsign", value: activation.callsign)
                    UploadDetailRow(
                        label: "QSOs to Upload",
                        value: "\(activation.pendingCount) of \(activation.qsoCount)"
                    )
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
                            Text("Upload \(activation.pendingCount) QSOs")
                                .frame(maxWidth: .infinity)
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

// MARK: - ActivationShareSheet

struct ActivationShareSheet: View {
    // MARK: Internal

    let activation: POTAActivation
    let parkName: String?
    let myGrid: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Preview of the share card - show rendered image if available, otherwise placeholder
                if let renderedImage {
                    Image(uiImage: renderedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 340, height: 510)
                } else {
                    // Placeholder while loading
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.12, green: 0.10, blue: 0.18))
                        .frame(width: 340, height: 510)
                        .overlay(
                            ProgressView()
                                .tint(.white)
                        )
                }

                Spacer()

                // Share button - uses pre-rendered image
                if let renderedImage {
                    ShareLink(
                        item: ShareableImage(uiImage: renderedImage),
                        preview: SharePreview(
                            "POTA Activation - \(activation.parkReference)",
                            image: Image(uiImage: renderedImage)
                        )
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {} label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(true)
                }
            }
            .padding()
            .navigationTitle("Share Activation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .task {
            // Small delay to let sheet animation complete before heavy rendering
            try? await Task.sleep(for: .milliseconds(100))
            await renderImage()
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: UIImage?

    private func renderImage() async {
        renderedImage = await ActivationShareRenderer.renderWithMap(
            activation: activation,
            parkName: parkName,
            myGrid: myGrid
        )
    }
}

// MARK: - ShareableImage

/// A transferable wrapper for sharing images that supports "Save Image"
struct ShareableImage: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        // Export as PNG to preserve transparency
        DataRepresentation(exportedContentType: .png) { item in
            item.uiImage.pngData() ?? Data()
        }
    }

    let uiImage: UIImage
}
