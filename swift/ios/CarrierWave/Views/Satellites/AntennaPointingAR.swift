import AVFoundation
import CoreMotion
import SwiftUI

// MARK: - PointingCameraController

/// Owns the AVCaptureSession for the pointing screen's AR overlay: back
/// wide camera, video only. Configuration is lazy and the session is
/// started/stopped as the overlay is toggled.
@MainActor
@Observable
final class PointingCameraController {
    // MARK: Internal

    let session = AVCaptureSession()
    private(set) var isAuthorized = false

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            isAuthorized = false
        }
        guard isAuthorized else {
            return
        }
        configureIfNeeded()
        if !session.isRunning {
            session.startRunning()
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    // MARK: Private

    private var isConfigured = false

    private func configureIfNeeded() {
        guard !isConfigured else {
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
        isConfigured = true
    }
}

// MARK: - PointingCameraPreview

/// Live camera passthrough behind the pointing instruments.
struct PointingCameraPreview: UIViewRepresentable {
    final class PreviewView: UIView {
        // MARK: Lifecycle

        override init(frame: CGRect) {
            super.init(frame: frame)
            previewLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(previewLayer)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        // MARK: Internal

        let previewLayer = AVCaptureVideoPreviewLayer()

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }
    }

    let session: AVCaptureSession

    func makeUIView(context _: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_: PreviewView, context _: Context) {}
}

// MARK: - PointingARMarker

/// The satellite projected onto the boom-boresight targeting display
/// (~70° FOV pinhole looking along device +Y): centered in the crosshair
/// when the flat-mounted antenna is on target. Rendered over the optional
/// camera passthrough, which faces 90° away on a flat mount — the marker
/// tracks the antenna, not the camera image. Orange fly-to ring, green
/// when locked.
struct PointingARMarker: View {
    let matrix: CMRotationMatrix
    let boomAxis: SIMD3<Double>
    let azDeg: Double
    let elDeg: Double
    let isLocked: Bool
    let name: String

    var body: some View {
        GeometryReader { geo in
            let projector = SkyProjector(matrix: matrix, size: geo.size, boomAxis: boomAxis)
            if let point = projector.boomProject(azDeg: azDeg, elDeg: elDeg) {
                ZStack {
                    Circle()
                        .stroke(
                            isLocked ? Color.green : PointingInstrumentStyle.flyTo,
                            lineWidth: 4
                        )
                        .frame(width: 60, height: 60)
                    Text(name)
                        .font(.caption.weight(.bold).monospaced())
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 2)
                        .offset(y: 44)
                }
                .position(point)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - PointingARCrosshair

/// Fixed crosshair at the center of the boom-boresight targeting display:
/// the satellite marker sits inside it when the antenna is on target.
struct PointingARCrosshair: View {
    var body: some View {
        ZStack {
            Rectangle()
                .frame(width: 34, height: 3)
            Rectangle()
                .frame(width: 3, height: 34)
            Circle()
                .stroke(lineWidth: 2)
                .frame(width: 16, height: 16)
        }
        .foregroundStyle(.white.opacity(0.9))
        .allowsHitTesting(false)
    }
}
