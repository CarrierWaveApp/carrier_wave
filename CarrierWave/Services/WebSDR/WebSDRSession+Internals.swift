import CarrierWaveData
import Foundation
import SwiftData

// MARK: - WebSDRSession Internal Helpers

extension WebSDRSession {
    /// Set up recorder and audio engine after connecting
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

    /// Process incoming audio frames from the KiwiSDR
    func processAudioStream(
        _ stream: AsyncStream<KiwiSDRClient.AudioFrame>
    ) async {
        for await frame in stream {
            guard !Task.isCancelled else {
                break
            }

            // Feed audio engine immediately for low-latency playback
            audioEngine?.write(frame.samples)

            // Forward to CW decoder if attached (Tune In transcription)
            onAudioFrame?(frame.samples)

            // Update UI directly (already on @MainActor)
            sMeter = frame.sMeter
            peakLevel = computePeakLevel(frame.samples)

            // Write to recorder file (async, may involve I/O)
            do {
                try await recorder?.writeFrame(frame.samples)
            } catch {
                print("[WebSDR] Write error: \(error.localizedDescription)")
            }
        }

        if state == .recording {
            await reconnect()
        }
    }

    /// Compute peak level from audio samples (0.0 to 1.0)
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

    /// Reconnect after connection loss, preserving recorder, audio engine,
    /// recording model, and duration timer. Writes silence to the recording
    /// during the gap so the timer keeps advancing.
    /// Attempt receiver failover when reconnects are exhausted.
    /// Returns true if the caller handled the failure (either by
    /// switching receivers or finalizing).
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
        guard reconnectAttempts < maxReconnectAttempts,
              let receiver
        else {
            _ = await attemptFailover()
            return
        }

        reconnectAttempts += 1
        state = .reconnecting(attempt: reconnectAttempts)

        // Keep timer running and write silence to fill the gap
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

        // Use cached redirect target if available, otherwise original host
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

    /// Connect to a KiwiSDR, following server redirects up to 3 times.
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
            let newClient = KiwiSDRClient(
                host: currentHost, port: currentPort
            )
            do {
                let stream = try await newClient.connect(
                    frequencyKHz: frequencyKHz, mode: mode
                )
                // Cache effective host/port if redirected
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

    /// Parse a KiwiSDR redirect target into host and port.
    /// Handles "http://host:port", "host:port", and bare "host" formats.
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
            // Persist parameter change events before finishing
            if !parameterChanges.isEmpty {
                recording.parameterChanges = parameterChanges
            }
            // Persist clip bookmarks
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

    /// Write silence frames to the recorder during disconnects
    /// so the recording duration keeps advancing and the gap is
    /// filled with silence in the audio file.
    func startSilenceWriter() {
        silenceTask?.cancel()
        let sampleRate = lastSampleRate
        silenceTask = Task { [weak self] in
            let chunkSize = Int(sampleRate * 0.1) // ~100ms of silence
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

    /// Start a timeout that auto-finalizes the recording if the WebSDR
    /// isn't reconnected within `maxDormantDuration`.
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

    /// Resume a dormant recording by reconnecting to a WebSDR.
    /// The gap since disconnect is already filled with silence by the
    /// silence writer. Reconnects, resumes real audio streaming, and
    /// records parameter change events for any tuning differences.
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

            // Set up audio engine for the new connection
            let sampleRate = await newClient.negotiatedSampleRate
            lastSampleRate = sampleRate
            let engine = KiwiSDRAudioEngine()
            engine.start(sampleRate: sampleRate)
            if isMuted {
                engine.setMuted(true)
            }
            audioEngine = engine

            // Stop silence and start real audio
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
            // Reconnect failed — stay dormant, keep writing silence
            state = .dormant
            startDormantTimeout()
        }
    }

    // MARK: - Private Helpers

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

        // Apply Tune In spot metadata if present
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
        case .cannotCreateFile:
            "Cannot create recording file"
        }
    }
}
