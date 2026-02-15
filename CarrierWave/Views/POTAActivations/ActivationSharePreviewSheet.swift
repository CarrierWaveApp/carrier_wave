// Activation Share Preview Sheet
//
// Shows the rendered share card image with Share and Save to Photos actions.
// Uses ShareableImage Transferable for rich share sheet preview.

import Photos
import SwiftUI

// MARK: - SharePreviewData

struct SharePreviewData: Identifiable {
    let id = UUID()
    let image: UIImage
    let activation: POTAActivation
    let parkName: String?
}

// MARK: - ActivationSharePreviewSheet

struct ActivationSharePreviewSheet: View {
    // MARK: Internal

    let data: SharePreviewData
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    cardPreview
                    activationInfo
                }
                .padding(.horizontal)
            }
            .safeAreaInset(edge: .bottom) {
                actionButtons
                    .padding()
                    .background(.bar)
            }
            .navigationTitle("Brag Sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Private

    @State private var saveResult: SaveResult?
}

// MARK: - Subviews

private extension ActivationSharePreviewSheet {
    var cardPreview: some View {
        Image(uiImage: data.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .cornerRadius(12)
            .shadow(radius: 4)
    }

    var activationInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: "tree")
                .foregroundStyle(.green)
            Text(data.activation.parkReference)
                .fontWeight(.semibold)
            if let name = data.parkName {
                Text("- \(name)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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
        let park = data.activation.parkReference
        let date = data.activation.displayDate
        return "\(park) Activation - \(date)"
    }
}

// MARK: - Save to Photos

private extension ActivationSharePreviewSheet {
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
