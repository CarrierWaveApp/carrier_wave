import CarrierWaveData
import Foundation

// MARK: - CW Transcription from WebSDR Audio

extension CWTranscriptionService {
    /// Start CW transcription from a WebSDR audio frame stream.
    /// Converts Int16 KiwiSDR frames to the Float audio buffers the decoder expects.
    /// Does NOT use the microphone — processes SDR audio directly.
    func startListeningToSDR(
        frames: AsyncStream<[Int16]>,
        sampleRate: Double
    ) async {
        guard state != .listening else {
            return
        }

        // Create decoder without microphone capture
        signalProcessor = nil
        morseDecoder = MorseDecoder(initialWPM: estimatedWPM)

        state = .listening

        // Process SDR frames as CW audio
        captureTask = Task {
            await processSDRStream(frames, sampleRate: sampleRate)
        }

        startTimeoutChecker()
    }

    /// Process WebSDR Int16 audio frames through the CW decoder pipeline.
    /// Converts Int16 → Float and wraps into AudioBuffer format.
    func processSDRStream(
        _ stream: AsyncStream<[Int16]>,
        sampleRate: Double
    ) async {
        var timestamp: TimeInterval = 0
        let timePerSample = 1.0 / sampleRate

        for await samples in stream {
            guard !Task.isCancelled else {
                break
            }

            // Convert Int16 to Float [-1.0, 1.0]
            let floatSamples = samples.map { Float($0) / Float(Int16.max) }

            let buffer = CWAudioCapture.AudioBuffer(
                samples: floatSamples,
                sampleRate: sampleRate,
                timestamp: timestamp
            )

            await processAudioBuffer(buffer)
            timestamp += Double(samples.count) * timePerSample
        }
    }
}
