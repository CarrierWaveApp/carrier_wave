import SwiftUI
import VisionKit

// MARK: - LogScannerView

/// Wraps `VNDocumentCameraViewController` for scanning handwritten log pages.
struct LogScannerView: UIViewControllerRepresentable {
    let onScanComplete: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(
        _: VNDocumentCameraViewController,
        context _: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanComplete: onScanComplete, onCancel: onCancel)
    }
}

// MARK: LogScannerView.Coordinator

extension LogScannerView {
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        // MARK: Lifecycle

        init(
            onScanComplete: @escaping ([UIImage]) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onScanComplete = onScanComplete
            self.onCancel = onCancel
        }

        // MARK: Internal

        let onScanComplete: ([UIImage]) -> Void
        let onCancel: () -> Void

        func documentCameraViewController(
            _: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images = (0 ..< scan.pageCount).map { scan.imageOfPage(at: $0) }
            onScanComplete(images)
        }

        func documentCameraViewControllerDidCancel(
            _: VNDocumentCameraViewController
        ) {
            onCancel()
        }

        func documentCameraViewController(
            _: VNDocumentCameraViewController,
            didFailWithError _: Error
        ) {
            onCancel()
        }
    }
}
