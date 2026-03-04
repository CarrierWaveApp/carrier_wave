// POTA Upload Prompt Sheet
//
// Shown after ending a POTA logging session with unuploaded QSOs.
// Offers options to upload now, later, or disable the prompt.
// Supports rove sessions with per-park QSO counts.

import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - RoveUploadSummary

/// Per-park QSO count for rove upload prompt
struct RoveUploadSummary: Identifiable {
    let parkReference: String
    let parkName: String?
    let qsoCount: Int

    var id: String {
        parkReference
    }
}

// MARK: - POTAUploadPromptSheet

struct POTAUploadPromptSheet: View {
    // MARK: Internal

    let parkReference: String
    let parkName: String?
    let qsoCount: Int
    let roveStops: [RoveUploadSummary]
    let isInMaintenance: Bool
    let maintenanceTimeRemaining: String?
    let onUpload: () async -> Bool
    let onLater: () -> Void
    let onDontAskAgain: () -> Void

    var isRove: Bool {
        !roveStops.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        if isRove {
                            roveHeader
                        } else {
                            singleParkHeader
                        }

                        // QSO count
                        VStack(spacing: 4) {
                            Text("\(qsoCount)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                            Text(
                                isRove
                                    ? "QSOs across \(roveStops.count) parks"
                                    : "QSOs ready to upload"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }

                        // Per-park breakdown for roves
                        if isRove {
                            roveBreakdown
                        }

                        // Success state
                        if uploadState == .success {
                            successView
                        } else if uploadState == .uploading {
                            uploadingView
                        } else if uploadState == .failed {
                            failedView
                        }

                        // Maintenance warning
                        if isInMaintenance, uploadState == .idle {
                            maintenanceWarning
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }

                // Action buttons pinned at bottom
                if uploadState == .idle || uploadState == .failed {
                    Group {
                        if isInMaintenance {
                            maintenanceActions
                        } else {
                            uploadActions
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Upload to POTA?")
            .navigationBarTitleDisplayMode(.inline)
        }
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
        .interactiveDismissDisabled(uploadState == .uploading)
    }

    // MARK: Private

    private enum UploadState {
        case idle
        case uploading
        case success
        case failed
    }

    @State private var uploadState: UploadState = .idle
    @State private var errorMessage: String?

    // MARK: - Headers

    private var singleParkHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "tree.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text(parkReference)
                .font(.title2)
                .fontWeight(.bold)

            if let name = parkName {
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var roveHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.swap")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Rove Complete")
                .font(.title2)
                .fontWeight(.bold)

            Text("\(roveStops.count) parks activated")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var roveBreakdown: some View {
        VStack(spacing: 6) {
            ForEach(roveStops) { stop in
                HStack {
                    Text(stop.parkReference)
                        .font(.subheadline.monospaced().weight(.medium))
                        .foregroundStyle(.green)
                    if let name = stop.parkName {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(stop.qsoCount) QSOs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Status Views

    private var successView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            Text("Submitted!")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Awaiting POTA confirmation")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var uploadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Uploading to POTA...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var failedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Upload failed")
                .font(.headline)
            Text(errorMessage ?? "Please try again from the Sessions tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Maintenance

    private var maintenanceWarning: some View {
        VStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("POTA Maintenance Window")
                .font(.headline)
            if let remaining = maintenanceTimeRemaining {
                Text("Uploads unavailable for ~\(remaining)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Uploads temporarily unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Upload later from the Sessions tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var maintenanceActions: some View {
        VStack(spacing: 12) {
            Button {
                onLater()
            } label: {
                Text("OK")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var uploadActions: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await performUpload()
                }
            } label: {
                Text(isRove ? "Upload All Parks" : "Upload Now")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button {
                onLater()
            } label: {
                Text("Later")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)

            Button {
                onDontAskAgain()
            } label: {
                Text("Don't Ask Again")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    private func performUpload() async {
        uploadState = .uploading
        errorMessage = nil

        let success = await onUpload()

        await MainActor.run {
            withAnimation {
                if success {
                    uploadState = .success
                    // Auto-dismiss after showing success
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        onLater() // Use onLater to dismiss
                    }
                } else {
                    uploadState = .failed
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Normal") {
    POTAUploadPromptSheet(
        parkReference: "US-0001",
        parkName: "Acadia National Park",
        qsoCount: 15,
        roveStops: [],
        isInMaintenance: false,
        maintenanceTimeRemaining: nil,
        onUpload: {
            try? await Task.sleep(for: .seconds(1))
            return true
        },
        onLater: {},
        onDontAskAgain: {}
    )
}

#Preview("Rove") {
    POTAUploadPromptSheet(
        parkReference: "US-0001",
        parkName: nil,
        qsoCount: 32,
        roveStops: [
            RoveUploadSummary(
                parkReference: "US-0001",
                parkName: "Acadia National Park",
                qsoCount: 15
            ),
            RoveUploadSummary(
                parkReference: "US-0002",
                parkName: "Yellowstone National Park",
                qsoCount: 10
            ),
            RoveUploadSummary(
                parkReference: "US-0003",
                parkName: "Grand Canyon National Park",
                qsoCount: 7
            ),
        ],
        isInMaintenance: false,
        maintenanceTimeRemaining: nil,
        onUpload: {
            try? await Task.sleep(for: .seconds(1))
            return true
        },
        onLater: {},
        onDontAskAgain: {}
    )
}

#Preview("Maintenance") {
    POTAUploadPromptSheet(
        parkReference: "US-0001",
        parkName: "Acadia National Park",
        qsoCount: 15,
        roveStops: [],
        isInMaintenance: true,
        maintenanceTimeRemaining: "2h 15m",
        onUpload: { false },
        onLater: {},
        onDontAskAgain: {}
    )
}
