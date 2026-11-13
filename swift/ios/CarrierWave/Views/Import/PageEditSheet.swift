import SwiftUI
import UIKit

// MARK: - PageEditSheet

/// Full-screen editor for a single scanned page image.
/// Supports 90-degree rotation and interactive crop.
struct PageEditSheet: View {
    // MARK: Lifecycle

    init(
        image: UIImage,
        onSave: @escaping (UIImage) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _editedImage = State(initialValue: image)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    // MARK: Internal

    let onSave: (UIImage) -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    Image(uiImage: editedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxWidth: geometry.size.width,
                            maxHeight: geometry.size.height
                        )
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .clipped()
                        .overlay {
                            if isCropping {
                                cropOverlay
                            }
                        }
                        .gesture(
                            isCropping
                                ? cropDragGesture(in: geometry.size)
                                : nil
                        )
                        .onAppear {
                            lastViewSize = geometry.size
                        }
                        .onChange(of: geometry.size) { _, newSize in
                            lastViewSize = newSize
                        }
                }

                editToolbar
            }
            .navigationTitle("Edit Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(editedImage)
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Remove Page",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("This page will be removed from the scan.")
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var editedImage: UIImage
    @State private var isCropping = false
    @State private var cropRect: CGRect = .zero
    @State private var showDeleteConfirm = false
    @State private var lastViewSize: CGSize = .zero

    private var editToolbar: some View {
        HStack(spacing: 32) {
            Button {
                rotateImage(clockwise: false)
            } label: {
                Label("Rotate Left", systemImage: "rotate.left")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }

            Button {
                rotateImage(clockwise: true)
            } label: {
                Label("Rotate Right", systemImage: "rotate.right")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }

            Button {
                if isCropping {
                    applyCrop()
                } else {
                    startCrop()
                }
            } label: {
                Label(
                    isCropping ? "Apply Crop" : "Crop",
                    systemImage: isCropping ? "checkmark.crop" : "crop"
                )
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(isCropping ? .green : .accentColor)
            }

            if isCropping {
                Button {
                    cancelCrop()
                } label: {
                    Label("Cancel Crop", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            Button {
                showDeleteConfirm = true
            } label: {
                Label("Remove Page", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var cropOverlay: some View {
        if cropRect.width > 0, cropRect.height > 0 {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.4))
                    .reverseMask {
                        Rectangle()
                            .frame(
                                width: cropRect.width,
                                height: cropRect.height
                            )
                            .position(
                                x: cropRect.midX,
                                y: cropRect.midY
                            )
                    }

                Rectangle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
            }
            .allowsHitTesting(false)
        } else {
            Text("Drag to select crop area")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.6), in: .capsule)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Rotation

    private func rotateImage(clockwise: Bool) {
        guard let cgImage = editedImage.cgImage else {
            return
        }
        let angle: CGFloat = clockwise ? .pi / 2 : -.pi / 2
        let rotatedSize = CGSize(
            width: editedImage.size.height,
            height: editedImage.size.width
        )

        UIGraphicsBeginImageContextWithOptions(rotatedSize, false, editedImage.scale)
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        context.rotate(by: angle)
        context.scaleBy(x: 1, y: -1)

        let drawRect = CGRect(
            x: -editedImage.size.width / 2,
            y: -editedImage.size.height / 2,
            width: editedImage.size.width,
            height: editedImage.size.height
        )
        context.draw(cgImage, in: drawRect)

        if let rotated = UIGraphicsGetImageFromCurrentImageContext() {
            editedImage = rotated
        }
        UIGraphicsEndImageContext()
    }

    // MARK: - Crop

    /// Compute the rect where the image is actually displayed within the view
    /// (accounting for `scaledToFit` centering).
    private func imageDisplayRect(in viewSize: CGSize) -> CGRect {
        let imageSize = editedImage.size
        let displayScale = min(
            viewSize.width / imageSize.width,
            viewSize.height / imageSize.height
        )
        let scaledW = imageSize.width * displayScale
        let scaledH = imageSize.height * displayScale
        let originX = (viewSize.width - scaledW) / 2
        let originY = (viewSize.height - scaledH) / 2
        return CGRect(x: originX, y: originY, width: scaledW, height: scaledH)
    }

    private func startCrop() {
        isCropping = true
        cropRect = .zero
    }

    private func cancelCrop() {
        isCropping = false
        cropRect = .zero
    }

    private func cropDragGesture(in viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let imgRect = imageDisplayRect(in: viewSize)
                let startX = max(value.startLocation.x, imgRect.minX)
                let startY = max(value.startLocation.y, imgRect.minY)
                let endX = min(
                    max(value.location.x, imgRect.minX),
                    imgRect.maxX
                )
                let endY = min(
                    max(value.location.y, imgRect.minY),
                    imgRect.maxY
                )

                cropRect = CGRect(
                    x: min(startX, endX),
                    y: min(startY, endY),
                    width: abs(endX - startX),
                    height: abs(endY - startY)
                )
            }
    }

    private func applyCrop() {
        guard cropRect.width > 20, cropRect.height > 20,
              let cgImage = editedImage.cgImage
        else {
            cancelCrop()
            return
        }

        let imgRect = imageDisplayRect(in: lastViewSize)
        guard imgRect.width > 0, imgRect.height > 0 else {
            cancelCrop()
            return
        }

        // Map view-space cropRect to normalized [0,1] coordinates relative to
        // the displayed image area, then scale to pixel coordinates.
        let pixelW = CGFloat(cgImage.width)
        let pixelH = CGFloat(cgImage.height)

        let normX = (cropRect.minX - imgRect.minX) / imgRect.width
        let normY = (cropRect.minY - imgRect.minY) / imgRect.height
        let normW = cropRect.width / imgRect.width
        let normH = cropRect.height / imgRect.height

        let clampedX = max(0, min(normX, 1))
        let clampedY = max(0, min(normY, 1))
        let clampedW = max(0, min(normW, 1 - clampedX))
        let clampedH = max(0, min(normH, 1 - clampedY))

        let pixelCropRect = CGRect(
            x: clampedX * pixelW,
            y: clampedY * pixelH,
            width: clampedW * pixelW,
            height: clampedH * pixelH
        )

        if pixelCropRect.width > 10, pixelCropRect.height > 10,
           let cropped = cgImage.cropping(to: pixelCropRect)
        {
            editedImage = UIImage(cgImage: cropped)
        }

        isCropping = false
        cropRect = .zero
    }
}

// MARK: - ReverseMask

private extension View {
    func reverseMask(
        @ViewBuilder _ mask: () -> some View
    ) -> some View {
        self.mask {
            Rectangle()
                .overlay {
                    mask()
                        .blendMode(.destinationOut)
                }
        }
    }
}
