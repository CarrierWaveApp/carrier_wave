import Foundation

/// Platform-agnostic audio capture abstraction.
/// iOS uses AVAudioSession routing; macOS uses CoreAudio device selection.
public protocol AudioCaptureProtocol: Sendable {
    func startCapture() async throws
    func stopCapture() async
    var audioSamples: AsyncStream<Data> { get }
    var isCapturing: Bool { get async }
}
