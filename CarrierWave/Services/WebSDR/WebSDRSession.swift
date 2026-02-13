import Foundation
import SwiftData
import SwiftUI

// MARK: - WebSDRSession

/// Coordinates WebSDR connection, recording, audio playback, and lifecycle.
/// Integrates with LoggingSessionManager for start/stop/pause/resume.
@MainActor
@Observable
final class WebSDRSession {
    /// Overall session state
    enum State: Equatable {
        case idle
        case connecting
        case recording
        case paused
        case reconnecting(attempt: Int)
        case error(String)

        // MARK: Internal

        var isActive: Bool {
            switch self {
            case .recording,
                 .paused,
                 .connecting,
                 .reconnecting:
                true
            case .idle,
                 .error:
                false
            }
        }

        var statusText: String {
            switch self {
            case .idle: "Not connected"
            case .connecting: "Connecting..."
            case .recording: "Recording"
            case .paused: "Paused"
            case let .reconnecting(attempt): "Reconnecting (\(attempt))..."
            case let .error(msg): msg
            }
        }

        var statusIcon: String {
            switch self {
            case .idle: "antenna.radiowaves.left.and.right.slash"
            case .connecting,
                 .reconnecting: "antenna.radiowaves.left.and.right"
            case .recording: "record.circle.fill"
            case .paused: "pause.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            }
        }
    }

    /// Current state
    private(set) var state: State = .idle

    /// Connected receiver info
    private(set) var receiver: KiwiSDRReceiver?

    /// Recording duration in seconds
    private(set) var recordingDuration: TimeInterval = 0

    /// Audio peak level for level meter (0.0 to 1.0)
    private(set) var peakLevel: Float = 0

    /// S-meter reading from the KiwiSDR
    private(set) var sMeter: UInt16 = 0

    /// Whether audio output is muted
    private(set) var isMuted = false

    /// URL of the current recording file (for sharing)
    private(set) var recordingFileURL: URL?

    // MARK: Internal (accessed by WebSDRSession+Internals)

    var client: KiwiSDRClient?
    var recorder: WebSDRRecorder?
    var audioEngine: KiwiSDRAudioEngine?
    var streamTask: Task<Void, Never>?
    var durationTimer: Timer?
    var loggingSessionId: UUID?
    var recordingId: UUID?
    var modelContext: ModelContext?
    var reconnectAttempts = 0
    let maxReconnectAttempts = 5
    var lastFrequencyMHz: Double = 14.060
    var lastMode: String = "CW"
    /// Frozen duration preserved across reconnects
    var frozenDuration: TimeInterval = 0

    /// Buffer fill ratio for UI indicator (0.0 to 1.0)
    var bufferFillRatio: Double {
        audioEngine?.fillRatio ?? 0
    }

    /// Start recording from a WebSDR
    func start(
        receiver: KiwiSDRReceiver,
        frequencyMHz: Double,
        mode: String,
        loggingSessionId: UUID,
        modelContext: ModelContext
    ) async {
        self.receiver = receiver
        self.loggingSessionId = loggingSessionId
        self.modelContext = modelContext
        lastFrequencyMHz = frequencyMHz
        lastMode = mode

        let frequencyKHz = frequencyMHz * 1_000
        let kiwiMode = KiwiSDRMode.from(
            carrierWaveMode: mode,
            frequencyMHz: frequencyMHz
        )

        state = .connecting
        client = KiwiSDRClient(host: receiver.host, port: receiver.port)

        do {
            let audioStream = try await client!.connect(
                frequencyKHz: frequencyKHz,
                mode: kiwiMode
            )

            try await setupRecording(
                loggingSessionId: loggingSessionId,
                receiver: receiver,
                frequencyKHz: frequencyKHz,
                mode: mode,
                modelContext: modelContext
            )

            reconnectAttempts = 0
            state = .recording

            streamTask = Task { [weak self] in
                await self?.processAudioStream(audioStream)
            }
            startDurationTimer()
        } catch {
            state = .error(error.localizedDescription)
            await cleanup()
        }
    }

    /// Stop recording and disconnect
    func stop() async {
        durationTimer?.invalidate()
        durationTimer = nil
        streamTask?.cancel()
        streamTask = nil

        // Stop audio engine
        audioEngine?.stop()
        audioEngine = nil

        // Stop recorder and get file URL
        if let recorder {
            _ = await recorder.stopRecording()
        }

        // Disconnect client
        if let client {
            await client.disconnect()
        }

        // Update recording model
        finalizeRecording()

        client = nil
        recorder = nil
        state = .idle
        receiver = nil
        recordingDuration = 0
        recordingFileURL = nil
        peakLevel = 0
        isMuted = false
    }

    /// Pause recording (keeps WebSDR connection alive)
    func pause() async {
        guard state == .recording else {
            return
        }
        await recorder?.pause()
        audioEngine?.setMuted(true)
        durationTimer?.invalidate()
        state = .paused
    }

    /// Resume recording
    func resume() async {
        guard state == .paused else {
            return
        }
        await recorder?.resume()
        if !isMuted {
            audioEngine?.setMuted(false)
        }
        startDurationTimer()
        state = .recording
    }

    /// Toggle mute state
    func toggleMute() {
        isMuted.toggle()
        audioEngine?.setMuted(isMuted)
    }

    /// Retune to a new frequency (follows session frequency changes)
    func retune(frequencyMHz: Double) async {
        lastFrequencyMHz = frequencyMHz
        let frequencyKHz = frequencyMHz * 1_000
        try? await client?.retune(frequencyKHz: frequencyKHz)
    }

    /// Change mode (follows session mode changes)
    func changeMode(_ mode: String, frequencyMHz: Double?) async {
        lastMode = mode
        if let frequencyMHz {
            lastFrequencyMHz = frequencyMHz
        }
        let kiwiMode = KiwiSDRMode.from(
            carrierWaveMode: mode,
            frequencyMHz: frequencyMHz
        )
        try? await client?.changeMode(kiwiMode)
    }
}
