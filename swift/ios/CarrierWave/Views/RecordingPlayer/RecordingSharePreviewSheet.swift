import CarrierWaveData
import Photos
import SwiftUI

// MARK: - RecordingSharePreviewSheet

/// Preview sheet for the rendered recording share card image.
/// Offers Share and Save to Photos actions.
struct RecordingSharePreviewSheet: View {
    // MARK: Internal

    let data: RecordingShareCardData
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    cardPreview
                    clipInfo
                }
                .padding(.horizontal)
            }
            .safeAreaInset(edge: .bottom) {
                actionButtons
                    .padding()
                    .background(.bar)
            }
            .navigationTitle("Share Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
    }

    // MARK: Private

    @State private var saveResult: SaveResult?
}

// MARK: - Subviews

private extension RecordingSharePreviewSheet {
    var cardPreview: some View {
        Image(uiImage: data.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .cornerRadius(12)
            .shadow(radius: 4)
    }

    var clipInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(data.recording.kiwisdrName)
                .fontWeight(.semibold)
            Text(formatClipRange())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .font(.subheadline)
    }

    var actionButtons: some View {
        VStack(spacing: 12) {
            shareLink
            saveToPhotosButton
        }
    }

    var shareLink: some View {
        ShareLink(
            item: ShareableImage(uiImage: data.image),
            preview: SharePreview(
                shareTitle,
                image: Image(uiImage: data.image)
            )
        ) {
            Label("Share", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
    }

    var saveToPhotosButton: some View {
        Button {
            Task { await saveToPhotos() }
        } label: {
            Group {
                switch saveResult {
                case .none:
                    Label("Save to Photos", systemImage: "photo.on.rectangle")
                case .success:
                    Label("Saved", systemImage: "checkmark.circle.fill")
                case .denied:
                    Label("Photo Access Denied", systemImage: "xmark.circle.fill")
                case .error:
                    Label("Save Failed", systemImage: "exclamationmark.triangle.fill")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .disabled(saveResult != nil)
    }

    var shareTitle: String {
        let freq = formatFrequency(data.recording.frequencyKHz)
        return "\(freq) \(data.recording.mode) - SDR Recording"
    }

    func formatClipRange() -> String {
        let startMins = Int(data.clipStart) / 60
        let startSecs = Int(data.clipStart) % 60
        let endMins = Int(data.clipEnd) / 60
        let endSecs = Int(data.clipEnd) % 60
        return String(
            format: "%d:%02d – %d:%02d",
            startMins, startSecs, endMins, endSecs
        )
    }

    func formatFrequency(_ kHz: Double) -> String {
        let mHz = kHz / 1_000
        if mHz == mHz.rounded() {
            return String(format: "%.0f MHz", mHz)
        }
        return String(format: "%.3f MHz", mHz)
    }
}

// MARK: - Save to Photos

private extension RecordingSharePreviewSheet {
    enum SaveResult {
        case success
        case denied
        case error
    }

    func saveToPhotos() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        switch status {
        case .authorized,
             .limited:
            await performSave()
        default:
            saveResult = .denied
        }
    }

    func performSave() async {
        let imageToSave = data.image
        let success = await Task.detached {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: imageToSave)
                }
                return true
            } catch {
                return false
            }
        }.value
        saveResult = success ? .success : .error
    }
}
