// End Session Flow — POTA Upload and Brag Sheet Steps

import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - POTA Upload Step

extension EndSessionFlowView {
    var potaUploadStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                potaUploadHeader
                    .padding(.top, 8)

                if !roveStops.isEmpty {
                    roveBreakdown
                }

                if uploadState == .success {
                    potaSuccessView
                } else if uploadState == .uploading {
                    potaUploadingView
                } else if uploadState == .failed {
                    potaFailedView
                }

                if isInMaintenance, uploadState == .idle {
                    maintenanceWarningView
                }

                if uploadState == .idle || uploadState == .failed {
                    potaActions
                        .padding(.horizontal)
                }
            }
            .padding()
        }
    }

    private var potaUploadHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: roveStops.isEmpty ? "tree.fill" : "arrow.triangle.swap")
                .font(.largeTitle)
                .foregroundStyle(.green)

            if let parkRef = potaParkRef, roveStops.isEmpty {
                Text(parkRef)
                    .font(.title2.weight(.bold))
                if let name = potaParkName {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("Rove Complete")
                    .font(.title2.weight(.bold))
                Text("\(roveStops.count) parks activated")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("\(potaQSOsNeedingUpload)")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.green)
            Text(
                roveStops.isEmpty
                    ? "QSOs ready to upload"
                    : "QSOs across \(roveStops.count) parks"
            )
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

    private var potaSuccessView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.blue)
            Text("Submitted!")
                .font(.title2.weight(.semibold))
            Text("Awaiting POTA confirmation")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var potaUploadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Uploading to POTA...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var potaFailedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Upload failed")
                .font(.headline)
            Text(uploadError ?? "You can retry or upload later from Sessions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var maintenanceWarningView: some View {
        VStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("POTA Maintenance Window")
                .font(.headline)
            if let remaining = maintenanceTimeRemaining {
                Text("Uploads unavailable for ~\(remaining)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var potaActions: some View {
        VStack(spacing: 12) {
            if !isInMaintenance {
                Button {
                    Task { await performUpload() }
                } label: {
                    Text(roveStops.isEmpty ? "Upload Now" : "Upload All Parks")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            Button {
                advanceToBragSheet()
            } label: {
                Text(isInMaintenance ? "Continue" : "Skip")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Brag Sheet Step

extension EndSessionFlowView {
    @MainActor
    func shareTOTABragSheet(session: LoggingSession) async {
        guard let image = await TOTABragSheetRenderer.render(
            session: session, qsos: totaQSOs
        ) else {
            return
        }
        let controller = UIActivityViewController(
            activityItems: [image], applicationActivities: nil
        )
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let presenter = scene.windows.first?.rootViewController?.topMostPresented
        else {
            return
        }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0, height: 0
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }

    var bragSheetStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isTOTA, let session = totaSession {
                    TOTABragSheetView(session: session, qsos: totaQSOs)
                        .padding(.horizontal)
                    Button {
                        Task { await shareTOTABragSheet(session: session) }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                } else if let item = activityItem {
                    SessionBragSheetCard(item: item)
                        .padding(.horizontal)
                } else {
                    basicBragSheet
                }

                Button {
                    onComplete()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .padding(.top)
        }
    }

    private var basicBragSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy.fill")
                .font(.largeTitle)
                .foregroundStyle(.yellow)

            Text("Session Complete!")
                .font(.title2.weight(.bold))

            VStack(spacing: 8) {
                Text("\(qsoCount) QSOs")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.green)
                Text(duration)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !bands.isEmpty {
                    Text(bands.joined(separator: " / "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("View the full brag sheet in Activity.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
