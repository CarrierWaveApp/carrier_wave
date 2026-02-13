// POTA Upload Prompt Sheet
//
// Shown after ending a POTA logging session with unuploaded QSOs.
// Offers options to upload now, later, or disable the prompt.

import SwiftData
import SwiftUI

// MARK: - POTAUploadPromptSheet

struct POTAUploadPromptSheet: View {
    // MARK: Internal

    let parkReference: String
    let parkName: String?
    let qsoCount: Int
    let isInMaintenance: Bool
    let maintenanceTimeRemaining: String?
    let onUpload: () async -> Bool
    let onLater: () -> Void
    let onDontAskAgain: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // Park info header
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

                        // QSO count
                        VStack(spacing: 4) {
                            Text("\(qsoCount)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                            Text("QSOs ready to upload")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        // Success state
                        if uploadState == .success {
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
                        } else if uploadState == .uploading {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text("Uploading to POTA...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else if uploadState == .failed {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.orange)
                                Text("Upload failed")
                                    .font(.headline)
                                Text(errorMessage ?? "Please try again from the POTA Activations tab.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .transition(.scale.combined(with: .opacity))
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
        .presentationDetents([.medium, .large])
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

    // MARK: - Subviews

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
            Text("Upload later from the POTA Activations tab.")
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
                Text("Upload Now")
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
        isInMaintenance: true,
        maintenanceTimeRemaining: "2h 15m",
        onUpload: { false },
        onLater: {},
        onDontAskAgain: {}
    )
}
