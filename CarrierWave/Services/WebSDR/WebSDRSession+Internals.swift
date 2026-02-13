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
    /// recording model, and duration timer.
    func reconnect() async {
        guard reconnectAttempts < maxReconnectAttempts,
              let receiver
        else {
            state = .error("Connection lost")
            await finalizeOnError()
            return
        }

        reconnectAttempts += 1
        state = .reconnecting(attempt: reconnectAttempts)

        frozenDuration = recordingDuration
        durationTimer?.invalidate()
        durationTimer = nil

        await recorder?.pause()

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

        let newClient = KiwiSDRClient(
            host: receiver.host, port: receiver.port
        )
        client = newClient

        let frequencyKHz = lastFrequencyMHz * 1_000
        let kiwiMode = KiwiSDRMode.from(
            carrierWaveMode: lastMode,
            frequencyMHz: lastFrequencyMHz
        )

        do {
            let audioStream = try await newClient.connect(
                frequencyKHz: frequencyKHz,
                mode: kiwiMode
            )
            await recorder?.resume()
            recordingDuration = frozenDuration
            startDurationTimer()
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

    func finalizeOnError() async {
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
            recording.finish()
            try? modelContext.save()
        }
    }

    func cleanup() async {
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

    // MARK: - Private Helpers

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
