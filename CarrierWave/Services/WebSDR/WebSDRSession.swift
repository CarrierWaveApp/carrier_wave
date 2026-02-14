import Foundation
import SwiftData
import SwiftUI

// MARK: - WebSDRSession

/// Coordinates WebSDR connection, recording, audio playback, and lifecycle.
///
/// Recording lifecycle:
/// - `start()` connects to a WebSDR and begins recording audio.
/// - `pause()` / `resume()` keep the recording open with silence during pauses.
/// - `disconnect()` disconnects the WebSDR but keeps the recording alive with
///   silence so a subsequent `start()` stitches onto the same file.
/// - `finalize()` fully stops and persists the recording (called on session end).
@MainActor
@Observable
final class WebSDRSession {
    /// Overall session state
    enum State: Equatable {
        case idle
        case connecting
        case recording
        case paused
        /// WebSDR disconnected mid-session; recording continues with silence
        case dormant
        case reconnecting(attempt: Int)
        case error(String)

        // MARK: Internal

        /// Whether there is an active recording (even if silent)
        var isActive: Bool {
            switch self {
            case .recording,
                 .paused,
                 .dormant,
                 .connecting,
                 .reconnecting:
                true
            case .idle,
                 .error:
                false
            }
        }

        /// Whether the WebSDR is connected and streaming audio
        var isStreaming: Bool {
            self == .recording
        }

        var statusText: String {
            switch self {
            case .idle: "Not connected"
            case .connecting: "Connecting..."
            case .recording: "Recording"
            case .paused: "Paused"
            case .dormant: "Disconnected"
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
            case .dormant: "record.circle"
            case .error: "exclamationmark.triangle.fill"
            }
        }
    }

    /// Current state
    var state: State = .idle

    /// Connected receiver info
    var receiver: KiwiSDRReceiver?

    /// Recording duration in seconds
    var recordingDuration: TimeInterval = 0

    /// Audio peak level for level meter (0.0 to 1.0)
    var peakLevel: Float = 0

    /// S-meter reading from the KiwiSDR
    var sMeter: UInt16 = 0

    /// Whether audio output is muted
    var isMuted = false

    /// URL of the current recording file (for sharing)
    var recordingFileURL: URL?

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
    var lastSampleRate: Double = 12_000
    var silenceTask: Task<Void, Never>?
    var effectiveHost: String?
    var effectivePort: Int?
    var dormantTimeoutTask: Task<Void, Never>?

    /// Accumulated parameter change events for the current recording
    var parameterChanges: [SDRParameterEvent] = []

    /// When the current recording started (for computing offsets)
    var recordingStartDate: Date?

    /// Maximum time to keep a dormant recording alive (30 minutes)
    let maxDormantDuration: TimeInterval = 30 * 60

    /// Buffer fill ratio for UI indicator (0.0 to 1.0)
    var bufferFillRatio: Double {
        audioEngine?.fillRatio ?? 0
    }

    /// Current KiwiSDR mode derived from session mode and frequency
    var currentKiwiMode: KiwiSDRMode {
        KiwiSDRMode.from(carrierWaveMode: lastMode, frequencyMHz: lastFrequencyMHz)
    }

    /// URL to open this receiver in a web browser with current tuning
    var webURL: URL? {
        guard let receiver else {
            return nil
        }
        let freqKHz = lastFrequencyMHz * 1_000
        let mode = currentKiwiMode
        let urlString = "http://\(receiver.host):\(receiver.port)"
            + "/?f=\(String(format: "%.3f", freqKHz))"
            + "/\(mode.kiwiName)/\(mode.lowCut),\(mode.highCut)"
        return URL(string: urlString)
    }

    // MARK: - Connection Lifecycle

    /// Start recording from a WebSDR.
    /// If a dormant recording exists for the same session, resumes it
    /// (filling the gap with silence) instead of creating a new file.
    func start(
        receiver: KiwiSDRReceiver,
        frequencyMHz: Double,
        mode: String,
        loggingSessionId: UUID,
        modelContext: ModelContext
    ) async {
        // Resume existing dormant recording for the same session
        if state == .dormant,
           recorder != nil,
           self.loggingSessionId == loggingSessionId
        {
            await resumeFromDormant(
                receiver: receiver,
                frequencyMHz: frequencyMHz,
                mode: mode
            )
            return
        }

        // Finalize any stale recording from a different session
        if recorder != nil {
            await finalize()
        }

        self.receiver = receiver
        self.loggingSessionId = loggingSessionId
        self.modelContext = modelContext
        lastFrequencyMHz = frequencyMHz
        lastMode = mode
        effectiveHost = nil
        effectivePort = nil
        parameterChanges = []
        recordingStartDate = Date()

        await connectAndRecord(
            receiver: receiver,
            frequencyMHz: frequencyMHz,
            mode: mode,
            loggingSessionId: loggingSessionId,
            modelContext: modelContext
        )
    }

    /// Disconnect from the WebSDR but keep the recording alive with silence.
    /// Call `start()` again to reconnect, or `finalize()` to close out.
    func disconnect() async {
        guard state == .recording || state == .paused else {
            return
        }

        let wasReceiver = receiver?.host ?? ""

        // Stop audio stream
        streamTask?.cancel()
        streamTask = nil
        audioEngine?.stop()
        audioEngine = nil

        if let client {
            await client.disconnect()
        }
        client = nil

        // Keep recording alive with silence
        startSilenceWriter()
        startDormantTimeout()

        recordParameterChange(
            type: .sdrDisconnected,
            oldValue: wasReceiver,
            newValue: ""
        )

        state = .dormant
        receiver = nil
        peakLevel = 0
        effectiveHost = nil
        effectivePort = nil
    }

    /// Fully stop and persist the recording. Called when the logging session ends.
    func finalize() async {
        stopSilenceWriter()
        stopDormantTimeout()
        durationTimer?.invalidate()
        durationTimer = nil
        streamTask?.cancel()
        streamTask = nil

        audioEngine?.stop()
        audioEngine = nil

        if let recorder {
            _ = await recorder.stopRecording()
        }
        if let client {
            await client.disconnect()
        }

        finalizeRecording()

        client = nil
        recorder = nil
        state = .idle
        receiver = nil
        recordingDuration = 0
        recordingFileURL = nil
        peakLevel = 0
        isMuted = false
        effectiveHost = nil
        effectivePort = nil
        parameterChanges = []
        recordingStartDate = nil
    }

    /// Legacy stop — disconnects but keeps recording for stitching.
    /// Use `finalize()` for full teardown.
    func stop() async {
        await disconnect()
    }

    // MARK: - Pause / Resume

    /// Pause recording. Writes silence to maintain timeline alignment.
    func pause() async {
        guard state == .recording else {
            return
        }
        // Write silence instead of pausing recorder — keeps timeline aligned
        startSilenceWriter()
        audioEngine?.setMuted(true)

        recordParameterChange(type: .pause, oldValue: "", newValue: "")
        state = .paused
    }

    /// Resume recording from pause.
    func resume() async {
        guard state == .paused else {
            return
        }
        stopSilenceWriter()
        if !isMuted {
            audioEngine?.setMuted(false)
        }

        recordParameterChange(type: .resume, oldValue: "", newValue: "")
        state = .recording
    }

    /// Toggle mute state
    func toggleMute() {
        isMuted.toggle()
        audioEngine?.setMuted(isMuted)
    }

    // MARK: - Tuning

    /// Retune to a new frequency (follows session frequency changes)
    func retune(frequencyMHz: Double) async {
        let oldFreqKHz = lastFrequencyMHz * 1_000
        let newFreqKHz = frequencyMHz * 1_000
        lastFrequencyMHz = frequencyMHz
        try? await client?.retune(frequencyKHz: newFreqKHz)

        recordParameterChange(
            type: .frequency,
            oldValue: String(format: "%.3f", oldFreqKHz),
            newValue: String(format: "%.3f", newFreqKHz)
        )
    }

    /// Change mode (follows session mode changes)
    func changeMode(_ mode: String, frequencyMHz: Double?) async {
        let oldMode = lastMode
        lastMode = mode

        if let frequencyMHz, frequencyMHz != lastFrequencyMHz {
            let oldFreqKHz = lastFrequencyMHz * 1_000
            lastFrequencyMHz = frequencyMHz
            recordParameterChange(
                type: .frequency,
                oldValue: String(format: "%.3f", oldFreqKHz),
                newValue: String(format: "%.3f", frequencyMHz * 1_000)
            )
        } else if let frequencyMHz {
            lastFrequencyMHz = frequencyMHz
        }

        if oldMode != mode {
            recordParameterChange(
                type: .mode,
                oldValue: oldMode,
                newValue: mode
            )
        }

        let kiwiMode = KiwiSDRMode.from(
            carrierWaveMode: mode,
            frequencyMHz: frequencyMHz
        )
        try? await client?.changeMode(kiwiMode)
    }

    // MARK: - Parameter Change Tracking

    /// Record a parameter change event with timestamp and offset
    func recordParameterChange(
        type: SDRParameterEvent.ChangeType,
        oldValue: String,
        newValue: String
    ) {
        let now = Date()
        let offset = recordingStartDate.map {
            now.timeIntervalSince($0)
        } ?? 0

        let event = SDRParameterEvent(
            type: type,
            timestamp: now,
            offsetSeconds: offset,
            oldValue: oldValue,
            newValue: newValue
        )
        parameterChanges.append(event)
    }

    // MARK: - Private

    /// Connect to the WebSDR and begin streaming audio into the recorder.
    private func connectAndRecord(
        receiver: KiwiSDRReceiver,
        frequencyMHz: Double,
        mode: String,
        loggingSessionId: UUID,
        modelContext: ModelContext
    ) async {
        let frequencyKHz = frequencyMHz * 1_000
        let kiwiMode = KiwiSDRMode.from(
            carrierWaveMode: mode,
            frequencyMHz: frequencyMHz
        )

        state = .connecting

        do {
            let (newClient, audioStream) = try await connectFollowingRedirects(
                host: receiver.host, port: receiver.port,
                frequencyKHz: frequencyKHz, mode: kiwiMode
            )
            client = newClient

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

}
