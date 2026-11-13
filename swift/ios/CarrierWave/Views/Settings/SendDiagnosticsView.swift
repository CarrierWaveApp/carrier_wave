import SwiftData
import SwiftUI
import UIKit

// MARK: - SendDiagnosticsView

struct SendDiagnosticsView: View {
    // MARK: Internal

    @Binding var showingSendDiagnostics: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .confirm:
                    confirmPhase
                case .collecting:
                    collectingPhase
                case .ready:
                    readyPhase
                case .failed:
                    failedPhase
                }
            }
            .navigationTitle("Send Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    switch phase {
                    case .confirm,
                         .ready,
                         .failed:
                        Button("Done") {
                            showingSendDiagnostics = false
                        }
                    case .collecting:
                        Button("Cancel") {
                            collectionTask?.cancel()
                            phase = .confirm
                        }
                    }
                }
            }
            .interactiveDismissDisabled(phase == .collecting)
        }
    }

    // MARK: Private

    private enum Phase {
        case confirm
        case collecting
        case ready
        case failed
    }

    @Environment(\.modelContext) private var modelContext

    @State private var phase: Phase = .confirm
    @State private var descriptionText = ""
    @State private var includeDatabase = false
    @State private var statusMessage = "Collecting app logs..."
    @State private var zipURL: URL?
    @State private var zipSizeBytes: Int64 = 0
    @State private var collectionFailures: [String] = []
    @State private var errorMessage = ""
    @State private var collectionTask: Task<Void, Never>?
}

// MARK: - Phase Views

extension SendDiagnosticsView {
    var confirmPhase: some View {
        Form {
            Section {
                TextField(
                    "Describe what happened — optional, but helpful",
                    text: $descriptionText,
                    axis: .vertical
                )
                .lineLimit(3 ... 8)
            } header: {
                Text("What went wrong?")
            }

            Section {
                DisclosureGroup("What's included") {
                    includedItemRow(
                        "App logs from this session and past 14 days"
                    )
                    includedItemRow(
                        "Sync history (QRZ, POTA, LoFi, LoTW, HAMRS)"
                    )
                    includedItemRow(
                        "iCloud sync state and events"
                    )
                    includedItemRow("Backup inventory (not content)")
                    includedItemRow("Storage sizes and disk space")
                    includedItemRow("Recent 50 QSOs (notes redacted)")
                    includedItemRow(
                        "Device info (iOS version, model, app version)"
                    )
                    includedItemRow(
                        "QSO safety ledger (last 2 months)"
                    )
                    includedItemRow("System log (last hour)")
                }
            } footer: {
                Text(
                    "Callsigns from recent sync activity may appear "
                        + "in logs. This file is never sent "
                        + "automatically — you choose where it goes."
                )
            }

            Section {
                Toggle(
                    "Include database snapshot",
                    isOn: $includeDatabase
                )
            } footer: {
                Text(
                    "Includes a copy of your QSO database. "
                        + "Helpful for data-loss issues but makes "
                        + "the file much larger."
                )
            }

            Section {
                Button {
                    startCollection()
                } label: {
                    HStack {
                        Spacer()
                        Text("Collect & Share")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Collecting Phase

    private var collectingPhase: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .accessibilityLabel("Collecting diagnostics")

            Text(statusMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(
                    .easeInOut(duration: 0.3),
                    value: statusMessage
                )
                .accessibilityValue(statusMessage)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Ready Phase

    private var readyPhase: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Ready to Share")
                .font(.title2)
                .fontWeight(.semibold)

            if let url = zipURL {
                VStack(spacing: 4) {
                    Text(url.lastPathComponent)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(formattedSize(zipSizeBytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !collectionFailures.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(
                            systemName:
                            "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.yellow)
                        .font(.caption)
                        Text("Some data couldn't be collected:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(
                        collectionFailures, id: \.self
                    ) { failure in
                        Text("• \(failure)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    presentShareSheet()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Diagnostics")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint(
                    "Opens the iOS share sheet with your "
                        + "diagnostics file"
                )
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Failed Phase

    private var failedPhase: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Something Went Wrong")
                .font(.title2)
                .fontWeight(.semibold)

            Text(errorMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button {
                phase = .confirm
            } label: {
                Text("Try Again")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
    }

    private func includedItemRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
            Text(text)
                .font(.subheadline)
        }
    }

    private func startCollection() {
        phase = .collecting
        statusMessage = "Collecting app logs..."

        collectionTask = Task {
            let collector = DiagnosticsCollector()
            let container = modelContext.container
            let options = DiagnosticsCollector.CollectionOptions(
                userDescription: descriptionText.isEmpty
                    ? nil : descriptionText,
                includeDatabase: includeDatabase
            )

            do {
                let result = try await collector.collect(
                    options: options,
                    container: container
                ) { status in
                    Task { @MainActor in
                        switch status {
                        case .collectingLogs:
                            statusMessage = "Collecting app logs..."
                        case .packagingSyncHistory:
                            statusMessage =
                                "Packaging sync history..."
                        case .checkingStorage:
                            statusMessage = "Checking storage..."
                        case .creatingPackage:
                            statusMessage = "Creating package..."
                        case .done:
                            statusMessage = "Done!"
                        }
                    }
                }

                await MainActor.run {
                    zipURL = result.zipURL
                    zipSizeBytes = result.sizeBytes
                    collectionFailures = result.failures
                    phase = .ready
                    UINotificationFeedbackGenerator()
                        .notificationOccurred(.success)
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        phase = .failed
                    }
                }
            }
        }
    }

    private func presentShareSheet() {
        guard let url = zipURL else {
            return
        }

        // Delay to let any SwiftUI transitions settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let activityVC = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )

            guard
                let scene = UIApplication.shared.connectedScenes
                .first as? UIWindowScene,
                let rootVC = scene.keyWindow?.rootViewController
            else {
                return
            }

            var presenter = rootVC
            while let presented = presenter.presentedViewController {
                presenter = presented
            }

            // iPad popover anchor
            activityVC
                .popoverPresentationController?
                .sourceView = presenter.view
            activityVC
                .popoverPresentationController?
                .sourceRect = CGRect(
                    x: presenter.view.bounds.midX,
                    y: presenter.view.bounds.midY,
                    width: 0,
                    height: 0
                )

            presenter.present(activityVC, animated: true)
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file
        )
    }
}
