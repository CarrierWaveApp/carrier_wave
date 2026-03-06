import CarrierWaveData
import Foundation
import os
import SwiftData

private let sdrSessionLogger = Logger(subsystem: "com.jsvana.CWSweep", category: "WebSDRSession")

// MARK: - WebSDRSession

/// Coordinates WebSDR connection, recording, audio playback, and lifecycle.
@MainActor
@Observable
final class WebSDRSession {
    /// Overall session state
    enum State: Equatable {
        case idle
        case connecting
        case recording
        case paused
        case dormant
        case reconnecting(attempt: Int)
        case error(String)

        // MARK: Internal

        var isActive: Bool {
            switch self {
            case .recording,
                 .paused,
                 .dormant,
                 .connecting,
                 .reconnecting: true
            case .idle,
                 .error: false
            }
        }

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

    var state: State = .idle
    var receiver: KiwiSDRReceiver?
    var recordingDuration: TimeInterval = 0
    var peakLevel: Float = 0
    var sMeter: UInt16 = 0
    var isMuted = false
    var recordingFileURL: URL?

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

    var onAudioFrame: (([Int16]) -> Void)?
    var onReconnectsExhausted: (() async -> Void)?
    var tuneInSpotMetadata: TuneInSpotMetadata?
    var parameterChanges: [SDRParameterEvent] = []
    var recordingStartDate: Date?
    let maxDormantDuration: TimeInterval = 30 * 60
    var clipBookmarks: [ClipBookmark] = []

    var bufferFillRatio: Double {
        audioEngine?.fillRatio ?? 0
    }

    var currentKiwiMode: KiwiSDRMode {
        KiwiSDRMode.from(carrierWaveMode: lastMode, frequencyMHz: lastFrequencyMHz)
    }

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

    func start(
        receiver: KiwiSDRReceiver,
        frequencyMHz: Double,
        mode: String,
        loggingSessionId: UUID,
        modelContext: ModelContext
    ) async {
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

    func disconnect() async {
        guard state == .recording || state == .paused else {
            return
        }

        let wasReceiver = receiver?.host ?? ""

        streamTask?.cancel()
        streamTask = nil
        audioEngine?.stop()
        audioEngine = nil

        if let client {
            await client.disconnect()
        }
        client = nil

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
        clipBookmarks = []
        recordingStartDate = nil
        tuneInSpotMetadata = nil
        onReconnectsExhausted = nil
    }

    func stop() async {
        await disconnect()
    }

    // MARK: - Pause / Resume

    func pause() async {
        guard state == .recording else {
            return
        }
        startSilenceWriter()
        audioEngine?.setMuted(true)
        recordParameterChange(type: .pause, oldValue: "", newValue: "")
        state = .paused
    }

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

    func toggleMute() {
        isMuted.toggle()
        audioEngine?.setMuted(isMuted)
    }

    func addClipBookmark(_ bookmark: ClipBookmark) {
        clipBookmarks.append(bookmark)
    }

    // MARK: - Tuning

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
            recordParameterChange(type: .mode, oldValue: oldMode, newValue: mode)
        }

        let kiwiMode = KiwiSDRMode.from(
            carrierWaveMode: mode,
            frequencyMHz: frequencyMHz
        )
        try? await client?.changeMode(kiwiMode)
    }

    func recordParameterChange(
        type: SDRParameterEvent.ChangeType,
        oldValue: String,
        newValue: String
    ) {
        let now = Date()
        let offset = recordingStartDate.map { now.timeIntervalSince($0) } ?? 0

        let event = SDRParameterEvent(
            type: type,
            timestamp: now,
            offsetSeconds: offset,
            oldValue: oldValue,
            newValue: newValue
        )
        parameterChanges.append(event)
    }
}

// MARK: - WebSDRSession Internal Helpers

extension WebSDRSession {
    func connectAndRecord(
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

            UserDefaults.standard.set(
                "\(receiver.host):\(receiver.port)",
                forKey: "sdrLastReceiverHostPort"
            )
            UserDefaults.standard.set(receiver.name, forKey: "sdrLastReceiverName")

            streamTask = Task { [weak self] in
                await self?.processAudioStream(audioStream)
            }
            startDurationTimer()
        } catch {
            state = .error(error.localizedDescription)
            await cleanup()
        }
    }

    func setupRecording(
        loggingSessionId: UUID,
        receiver: KiwiSDRReceiver,
        frequencyKHz: Double,
        mode: String,
        modelContext: ModelContext
    ) async throws {
        guard let fileURL = WebSDRRecording.newRecordingURL(
            sessionId: loggingSessionId
        ) else {
            throw WebSDRSessionError.cannotCreateFile
        }

        recorder = WebSDRRecorder()
        let sampleRate = await client!.negotiatedSampleRate
        lastSampleRate = sampleRate
        try await recorder!.startRecording(to: fileURL, sampleRate: sampleRate)
        recordingFileURL = fileURL

        let engine = KiwiSDRAudioEngine()
        engine.start(sampleRate: sampleRate)
        if isMuted {
            engine.setMuted(true)
        }
        audioEngine = engine

        createRecordingModel(
            loggingSessionId: loggingSessionId,
            receiver: receiver,
            frequencyKHz: frequencyKHz,
            mode: mode,
            modelContext: modelContext
        )
    }

    func processAudioStream(
        _ stream: AsyncStream<KiwiSDRClient.AudioFrame>
    ) async {
        for await frame in stream {
            guard !Task.isCancelled else {
                break
            }

            audioEngine?.write(frame.samples)
            onAudioFrame?(frame.samples)
            sMeter = frame.sMeter
            peakLevel = computePeakLevel(frame.samples)

            do {
                try await recorder?.writeFrame(frame.samples)
            } catch {
                sdrSessionLogger.error("Write error: \(error.localizedDescription)")
            }
        }

        if state == .recording {
            await reconnect()
        }
    }

    private func computePeakLevel(_ samples: [Int16]) -> Float {
        var maxSample: Int16 = 0
        for sample in samples {
            let abs = sample == Int16.min ? Int16.max : abs(sample)
            if abs > maxSample {
                maxSample = abs
            }
        }
        return Float(maxSample) / Float(Int16.max)
    }

    private func attemptFailover() async -> Bool {
        if let onReconnectsExhausted {
            reconnectAttempts = 0
            await onReconnectsExhausted()
            if state == .recording || state == .connecting {
                return true
            }
        }
        stopSilenceWriter()
        state = .error("Connection lost")
        await finalizeOnError()
        return true
    }

    func reconnect() async {
        guard reconnectAttempts < maxReconnectAttempts, let receiver else {
            _ = await attemptFailover()
            return
        }

        reconnectAttempts += 1
        state = .reconnecting(attempt: reconnectAttempts)
        startSilenceWriter()

        if let client {
            await client.disconnect()
        }
        client = nil
        streamTask = nil

        let delay = pow(2.0, Double(reconnectAttempts))
        try? await Task.sleep(for: .seconds(delay))

        guard !Task.isCancelled else {
            return
        }

        let host = effectiveHost ?? receiver.host
        let port = effectivePort ?? receiver.port
        let frequencyKHz = lastFrequencyMHz * 1_000
        let kiwiMode = KiwiSDRMode.from(
            carrierWaveMode: lastMode,
            frequencyMHz: lastFrequencyMHz
        )

        do {
            let (newClient, audioStream) = try await connectFollowingRedirects(
                host: host, port: port,
                frequencyKHz: frequencyKHz, mode: kiwiMode
            )
            client = newClient
            stopSilenceWriter()
            reconnectAttempts = 0
            state = .recording

            streamTask = Task { [weak self] in
                await self?.processAudioStream(audioStream)
            }
        } catch {
            client = nil
            await reconnect()
        }
    }

    func connectFollowingRedirects(
        host: String,
        port: Int,
        frequencyKHz: Double,
        mode: KiwiSDRMode
    ) async throws -> (KiwiSDRClient, AsyncStream<KiwiSDRClient.AudioFrame>) {
        var currentHost = host
        var currentPort = port
        let maxRedirects = 3

        for _ in 0 ... maxRedirects {
            let newClient = KiwiSDRClient(host: currentHost, port: currentPort)
            do {
                let stream = try await newClient.connect(
                    frequencyKHz: frequencyKHz, mode: mode
                )
                if currentHost != host || currentPort != port {
                    effectiveHost = currentHost
                    effectivePort = currentPort
                }
                return (newClient, stream)
            } catch {
                await newClient.disconnect()
                if case let KiwiSDRError.serverRedirect(redirect) = error,
                   let target = Self.parseRedirectTarget(redirect)
                {
                    currentHost = target.host
                    currentPort = target.port
                } else {
                    throw error
                }
            }
        }

        throw KiwiSDRError.handshakeFailed("Too many redirects")
    }

    static func parseRedirectTarget(
        _ redirect: String
    ) -> (host: String, port: Int)? {
        var cleaned = redirect
        if let range = cleaned.range(of: "://") {
            cleaned = String(cleaned[range.upperBound...])
        }
        if let slashIndex = cleaned.firstIndex(of: "/") {
            cleaned = String(cleaned[..<slashIndex])
        }
        let parts = cleaned.components(separatedBy: ":")
        let host = parts[0]
        guard !host.isEmpty else {
            return nil
        }
        let port = parts.count > 1 ? Int(parts[1]) ?? 8_073 : 8_073
        return (host, port)
    }

    func finalizeOnError() async {
        stopSilenceWriter()
        durationTimer?.invalidate()
        durationTimer = nil

        if let recorder {
            _ = await recorder.stopRecording()
        }
        finalizeRecording()

        audioEngine?.stop()
        audioEngine = nil
        recorder = nil
    }

    func startDurationTimer() {
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

    func finalizeRecording() {
        guard let recordingId, let modelContext else {
            return
        }

        let id = recordingId
        let descriptor = FetchDescriptor<WebSDRRecording>(
            predicate: #Predicate { $0.id == id }
        )

        if let recording = try? modelContext.fetch(descriptor).first {
            if !parameterChanges.isEmpty {
                recording.parameterChanges = parameterChanges
            }
            if !clipBookmarks.isEmpty {
                recording.clipBookmarks = clipBookmarks
            }
            recording.finish()
            try? modelContext.save()
        }
    }

    func cleanup() async {
        stopSilenceWriter()
        if let recorder {
            _ = await recorder.stopRecording()
        }
        if let client {
            await client.disconnect()
        }
        audioEngine?.stop()
        audioEngine = nil
        client = nil
        recorder = nil
    }

    // MARK: - Silence Writer

    func startSilenceWriter() {
        silenceTask?.cancel()
        let sampleRate = lastSampleRate
        silenceTask = Task { [weak self] in
            let chunkSize = Int(sampleRate * 0.1)
            let silence = [Int16](repeating: 0, count: chunkSize)
            while !Task.isCancelled {
                try? await self?.recorder?.writeFrame(silence)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stopSilenceWriter() {
        silenceTask?.cancel()
        silenceTask = nil
    }

    // MARK: - Dormant Timeout

    func startDormantTimeout() {
        dormantTimeoutTask?.cancel()
        let timeout = maxDormantDuration
        dormantTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else {
                return
            }
            await self?.finalize()
        }
    }

    func stopDormantTimeout() {
        dormantTimeoutTask?.cancel()
        dormantTimeoutTask = nil
    }

    // MARK: - Dormant Resume

    func resumeFromDormant(
        receiver: KiwiSDRReceiver,
        frequencyMHz: Double,
        mode: String
    ) async {
        stopDormantTimeout()
        self.receiver = receiver
        effectiveHost = nil
        effectivePort = nil

        let frequencyKHz = trackParameterChanges(
            frequencyMHz: frequencyMHz, mode: mode
        )
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

            let sampleRate = await newClient.negotiatedSampleRate
            lastSampleRate = sampleRate
            let engine = KiwiSDRAudioEngine()
            engine.start(sampleRate: sampleRate)
            if isMuted {
                engine.setMuted(true)
            }
            audioEngine = engine

            stopSilenceWriter()

            recordParameterChange(
                type: .sdrConnected,
                oldValue: "",
                newValue: receiver.host
            )

            reconnectAttempts = 0
            state = .recording

            streamTask = Task { [weak self] in
                await self?.processAudioStream(audioStream)
            }
        } catch {
            state = .dormant
            startDormantTimeout()
        }
    }

    private func trackParameterChanges(
        frequencyMHz: Double, mode: String
    ) -> Double {
        let oldFreqKHz = lastFrequencyMHz * 1_000
        let newFreqKHz = frequencyMHz * 1_000
        lastFrequencyMHz = frequencyMHz

        if lastMode != mode {
            recordParameterChange(type: .mode, oldValue: lastMode, newValue: mode)
            lastMode = mode
        }
        if oldFreqKHz != newFreqKHz {
            recordParameterChange(
                type: .frequency,
                oldValue: String(format: "%.3f", oldFreqKHz),
                newValue: String(format: "%.3f", newFreqKHz)
            )
        }

        return newFreqKHz
    }

    private func createRecordingModel(
        loggingSessionId: UUID,
        receiver: KiwiSDRReceiver,
        frequencyKHz: Double,
        mode: String,
        modelContext: ModelContext
    ) {
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

        if let meta = tuneInSpotMetadata {
            recording.spotCallsign = meta.callsign
            recording.spotParkRef = meta.parkRef
            recording.spotParkName = meta.parkName
            recording.spotSummitCode = meta.summitCode
            recording.spotBand = meta.band
            recording.isTuneInRecording = true
        }

        modelContext.insert(recording)
        try? modelContext.save()
        recordingId = recording.id
    }
}

// MARK: - WebSDRSessionError

enum WebSDRSessionError: Error, LocalizedError {
    case cannotCreateFile

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .cannotCreateFile: "Cannot create recording file"
        }
    }
}
