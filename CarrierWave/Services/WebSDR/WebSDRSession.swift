import Foundation
import SwiftData
import SwiftUI

// MARK: - WebSDRSession

/// Coordinates WebSDR connection, recording, and lifecycle.
/// Integrates with LoggingSessionManager for start/stop/pause/resume.
@MainActor
@Observable
final class WebSDRSession {
    // MARK: Internal

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

            // Start recorder
            guard let fileURL = WebSDRRecording.newRecordingURL(
                sessionId: loggingSessionId
            ) else {
                state = .error("Cannot create recording file")
                return
            }

            recorder = WebSDRRecorder()
            // Get sample rate from the first frame or default
            let sampleRate = 12_000.0
            try await recorder!.startRecording(to: fileURL, sampleRate: sampleRate)

            // Create recording model
            let recording = WebSDRRecording(
                loggingSessionId: loggingSessionId,
                kiwisdrHost: receiver.host,
                kiwisdrName: receiver.name,
                frequencyKHz: frequencyKHz,
                mode: mode
            )
            recording.relativeFilePath = WebSDRRecording.relativePath(
                sessionId: loggingSessionId
            )
            modelContext.insert(recording)
            try? modelContext.save()
            recordingId = recording.id

            state = .recording

            // Start processing audio stream
            streamTask = Task { [weak self] in
                await self?.processAudioStream(audioStream)
            }

            // Start duration timer
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
        peakLevel = 0
    }

    /// Pause recording (keeps WebSDR connection alive)
    func pause() async {
        guard state == .recording else {
            return
        }
        await recorder?.pause()
        durationTimer?.invalidate()
        state = .paused
    }

    /// Resume recording
    func resume() async {
        guard state == .paused else {
            return
        }
        await recorder?.resume()
        startDurationTimer()
        state = .recording
    }

    /// Retune to a new frequency (follows session frequency changes)
    func retune(frequencyMHz: Double) async {
        let frequencyKHz = frequencyMHz * 1_000
        try? await client?.retune(frequencyKHz: frequencyKHz)
    }

    /// Change mode (follows session mode changes)
    func changeMode(_ mode: String, frequencyMHz: Double?) async {
        let kiwiMode = KiwiSDRMode.from(
            carrierWaveMode: mode,
            frequencyMHz: frequencyMHz
        )
        try? await client?.changeMode(kiwiMode)
    }

    // MARK: Private

    private var client: KiwiSDRClient?
    private var recorder: WebSDRRecorder?
    private var streamTask: Task<Void, Never>?
    private var durationTimer: Timer?
    private var loggingSessionId: UUID?
    private var recordingId: UUID?
    private var modelContext: ModelContext?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5

    /// Process incoming audio frames from the KiwiSDR
    private func processAudioStream(
        _ stream: AsyncStream<KiwiSDRClient.AudioFrame>
    ) async {
        for await frame in stream {
            guard !Task.isCancelled else {
                break
            }

            // Write to recorder
            do {
                try await recorder?.writeFrame(frame.samples)
            } catch {
                // Recording write error — continue receiving but log it
                print("[WebSDR] Write error: \(error.localizedDescription)")
            }

            // Update UI state on main actor
            await MainActor.run {
                self.sMeter = frame.sMeter
            }

            // Update peak level from recorder
            if let level = await recorder?.peakLevel {
                await MainActor.run {
                    self.peakLevel = level
                }
            }
        }

        // Stream ended — try to reconnect if unexpected
        if state == .recording {
            await attemptReconnect()
        }
    }

    /// Attempt to reconnect after connection loss
    private func attemptReconnect() async {
        guard reconnectAttempts < maxReconnectAttempts,
              let receiver, let loggingSessionId, let modelContext
        else {
            state = .error("Connection lost")
            return
        }

        reconnectAttempts += 1
        state = .reconnecting(attempt: reconnectAttempts)

        // Exponential backoff: 2s, 4s, 8s, 16s, 32s
        let delay = pow(2.0, Double(reconnectAttempts))
        try? await Task.sleep(for: .seconds(delay))

        guard !Task.isCancelled else {
            return
        }

        // Re-read the current frequency/mode from the receiver
        // For now just try reconnecting with the original settings
        await start(
            receiver: receiver,
            frequencyMHz: 14.060, // Will be overridden by session
            mode: "CW",
            loggingSessionId: loggingSessionId,
            modelContext: modelContext
        )
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                if let recorder = self.recorder {
                    self.recordingDuration = await recorder.recordedDuration
                }
            }
        }
    }

    private func finalizeRecording() {
        guard let recordingId, let modelContext else {
            return
        }

        let id = recordingId
        let descriptor = FetchDescriptor<WebSDRRecording>(
            predicate: #Predicate { $0.id == id }
        )

        if let recording = try? modelContext.fetch(descriptor).first {
            recording.finish()
            try? modelContext.save()
        }
    }

    private func cleanup() async {
        if let recorder {
            _ = await recorder.stopRecording()
        }
        if let client {
            await client.disconnect()
        }
        client = nil
        recorder = nil
    }
}
