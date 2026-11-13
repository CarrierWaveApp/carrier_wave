// Activation Share Preview Sheet
//
// Shows the rendered share card image with Share and Save to Photos actions.
// Uses ShareableImage Transferable for rich share sheet preview.
//
// The displayed image is state, not a frozen input: when contacts are still
// missing grids the sheet retries callsign enrichment on open and re-renders
// through `SharePreviewData.rerender`, so Share / Save always export exactly
// what is on screen (see `ActivationSharePreviewSheet+Refresh`).

import CarrierWaveData
import Photos
import SwiftData
import SwiftUI

// MARK: - SharePreviewData

struct SharePreviewData: Identifiable {
    let id = UUID()
    let image: UIImage
    /// Present only when the share originated from a POTA activation. SOTA /
    /// casual sessions render the same card via `BragSheetSource` and pass
    /// nil here — the preview's footer reads from `referenceLabel` instead.
    let activation: POTAActivation?
    /// Friendly label shown under the card (park name for POTA, summit name
    /// for SOTA). Optional in both paths.
    let parkName: String?
    /// Reference code (park or summit) and SF Symbol icon for the footer
    /// chip. Used when `activation` is nil; falls back to the activation's
    /// fields otherwise.
    var referenceLabel: String?
    var referenceIcon: String = "tree"
    var displayDate: String?
    /// The QSOs the card was rendered from. The sheet inspects these for
    /// missing grids to decide whether to retry enrichment.
    var qsos: [QSO] = []
    /// Re-render the card from the current QSO records. Set by callers that
    /// can rebuild the card; `nil` leaves the image static.
    var rerender: (@MainActor () async -> UIImage?)?
}

// MARK: - ActivationSharePreviewSheet

struct ActivationSharePreviewSheet: View {
    // MARK: Internal

    let data: SharePreviewData
    let onDismiss: () -> Void

    @Environment(\.modelContext) var modelContext
    @State var refreshedImage: UIImage?
    @State var isRefreshing = false

    /// The image currently on screen — also what Share / Save export.
    var currentImage: UIImage {
        refreshedImage ?? data.image
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    cardPreview
                    activationInfo
                    locationStatus
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
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
        .task { await refreshMissingLocations() }
        .onReceive(NotificationCenter.default.publisher(for: .didRepairQSOGrids)) { _ in
            Task { await rerenderAfterExternalRepair() }
        }
    }

    // MARK: Private

    @State private var saveResult: SaveResult?
}

// MARK: - Subviews

private extension ActivationSharePreviewSheet {
    var cardPreview: some View {
        Image(uiImage: currentImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .cornerRadius(12)
            .shadow(radius: 4)
    }

    var activationInfo: some View {
        let label = data.referenceLabel ?? data.activation?.parkReference ?? ""
        let icon = data.activation != nil ? "tree" : data.referenceIcon
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.green)
            Text(label)
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

    /// One-line status under the card while contacts are still unplaced.
    @ViewBuilder
    var locationStatus: some View {
        if isRefreshing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Looking up contact locations…")
                Spacer()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else if let caption = missingLocationCaption {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                Text("\(caption) — reopen this sheet once you're online to fill in the map.")
                Spacer()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    var actionButtons: some View {
        VStack(spacing: 12) {
            shareLink
            saveToPhotosButton
        }
    }

    var shareLink: some View {
        ShareLink(
            item: ShareableImage(uiImage: currentImage),
            preview: SharePreview(
                shareTitle,
                image: Image(uiImage: currentImage)
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
        if let activation = data.activation {
            return "\(activation.parkReference) Activation - \(activation.displayDate)"
        }
        let label = data.referenceLabel ?? "Session"
        if let date = data.displayDate {
            return "\(label) Activation - \(date)"
        }
        return "\(label) Activation"
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
        let imageToSave = currentImage
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
