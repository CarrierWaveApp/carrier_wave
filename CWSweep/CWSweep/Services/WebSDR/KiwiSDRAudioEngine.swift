import AVFoundation
import Foundation

// MARK: - KiwiSDRAudioEngine

/// Manages live audio playback from a KiwiSDR stream on macOS.
/// Uses AVAudioSourceNode to pull samples from a ring buffer on
/// the audio render thread, with adaptive rate to handle jitter.
///
/// macOS differences from iOS:
/// - No AVAudioSession (macOS manages audio automatically)
/// - No interruption/route change notifications
@MainActor
final class KiwiSDRAudioEngine {
    // MARK: Lifecycle

    init() {
        ringBuffer = AudioRingBuffer(capacity: 60_000) // 5s at 12kHz
    }

    // MARK: Internal

    /// Whether audio is currently playing
    private(set) var isPlaying = false

    /// Whether we're buffering before playback starts
    private(set) var isBuffering = false

    /// Whether audio output is muted
    private(set) var isMuted = false

    /// Error message if engine failed to start
    private(set) var startError: String?

    /// Current audio level (0.0 to 1.0) for UI meters
    private(set) var audioLevel: Float = 0

    /// Current buffer fill ratio (0.0 to 1.0)
    var fillRatio: Double {
        ringBuffer.fillRatio
    }

    /// Start the audio engine at the given input sample rate.
    func start(sampleRate: Double) {
        guard !isPlaying, !isBuffering else {
            return
        }

        inputSampleRate = sampleRate.rounded()
        prebufferThreshold = Int(inputSampleRate * 2) // 2 seconds
        ringBuffer.reset()
        startError = nil
        isBuffering = true

        // Query hardware output sample rate
        let hwFormat = engine.outputNode.outputFormat(forBus: 0)
        outputSampleRate = hwFormat.sampleRate
        if outputSampleRate <= 0 {
            outputSampleRate = 48_000
        }

        setupAudioGraph()
        startPrebufferTimer()
    }

    /// Stop the audio engine and tear down the graph.
    func stop() {
        prebufferTimer?.invalidate()
        prebufferTimer = nil
        rateTimer?.invalidate()
        rateTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        engine.stop()

        sourceNode = nil
        timePitchNode = nil
        isPlaying = false
        isBuffering = false
        audioLevel = 0
    }

    /// Write samples from the network into the ring buffer.
    func write(_ samples: [Int16]) {
        ringBuffer.write(samples)
        updateAudioLevel(samples)
    }

    /// Set muted state.
    func setMuted(_ muted: Bool) {
        isMuted = muted
        engine.mainMixerNode.outputVolume = muted ? 0 : 1
    }

    // MARK: Private

    private static let targetFillRatio = 0.75
    private static let maxRateOffset: Float = 0.08
    private static let rateGain: Float = 0.20

    private let ringBuffer: AudioRingBuffer
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var timePitchNode: AVAudioUnitTimePitch?
    private var prebufferTimer: Timer?
    private var rateTimer: Timer?
    private var levelTimer: Timer?

    private var inputSampleRate: Double = 12_000
    private var outputSampleRate: Double = 48_000
    private var prebufferThreshold: Int = 12_000

    /// Create the AVAudioSourceNode with its render callback.
    /// Must be `nonisolated` so the closure doesn't inherit @MainActor isolation.
    nonisolated private static func makeSourceNode(
        format: AVAudioFormat,
        buffer: AudioRingBuffer,
        ratio: Double,
        channelCount: Int
    ) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) {
            _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let count = Int(frameCount)

            if let rawBuffer = ablPointer[0].mData {
                let floatPtr = rawBuffer.assumingMemoryBound(to: Float.self)
                _ = buffer.readResampledAsFloat(
                    into: floatPtr,
                    outputCount: count,
                    ratio: ratio
                )

                for ch in 1 ..< min(channelCount, ablPointer.count) {
                    if let chBuf = ablPointer[ch].mData {
                        chBuf.copyMemory(
                            from: rawBuffer,
                            byteCount: count * MemoryLayout<Float>.size
                        )
                    }
                }
            }

            return noErr
        }
    }

    // MARK: - Audio Graph

    private func setupAudioGraph() {
        let hwFormat = engine.outputNode.outputFormat(forBus: 0)
        outputSampleRate = hwFormat.sampleRate
        let channelCount = Int(hwFormat.channelCount)

        let ratio = outputSampleRate / inputSampleRate

        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            startError = "Cannot create audio format"
            return
        }

        let node = Self.makeSourceNode(
            format: monoFormat,
            buffer: ringBuffer,
            ratio: ratio,
            channelCount: channelCount
        )
        sourceNode = node

        let pitchNode = AVAudioUnitTimePitch()
        pitchNode.rate = 1.0
        pitchNode.pitch = 0
        timePitchNode = pitchNode

        engine.attach(node)
        engine.attach(pitchNode)

        engine.connect(node, to: pitchNode, format: monoFormat)
        engine.connect(pitchNode, to: engine.mainMixerNode, format: monoFormat)

        engine.mainMixerNode.outputVolume = isMuted ? 0 : 1
    }

    private func startEngine() {
        do {
            try engine.start()
        } catch {
            startError = "Engine: \(error.localizedDescription)"
        }
    }

    // MARK: - Pre-buffer & Adaptive Rate

    private func startPrebufferTimer() {
        prebufferTimer?.invalidate()
        prebufferTimer = Timer.scheduledTimer(
            withTimeInterval: 0.1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkPrebuffer()
            }
        }
    }

    private func checkPrebuffer() {
        guard isBuffering else {
            return
        }
        let available = ringBuffer.availableSamples
        guard available >= prebufferThreshold else {
            return
        }

        prebufferTimer?.invalidate()
        prebufferTimer = nil
        isBuffering = false

        startEngine()
        isPlaying = true
        startRateTimer()
    }

    private func startRateTimer() {
        rateTimer?.invalidate()
        rateTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustPlaybackRate()
            }
        }
    }

    private func adjustPlaybackRate() {
        guard let timePitchNode, isPlaying else {
            return
        }

        let fill = ringBuffer.fillRatio
        let error = Float(fill - Self.targetFillRatio)

        let raw = error * Self.rateGain
        let adjustment = min(Self.maxRateOffset, max(-Self.maxRateOffset, raw))
        timePitchNode.rate = 1.0 + adjustment
    }

    private func updateAudioLevel(_ samples: [Int16]) {
        var maxSample: Int16 = 0
        for sample in samples {
            let abs = sample == Int16.min ? Int16.max : abs(sample)
            if abs > maxSample {
                maxSample = abs
            }
        }
        audioLevel = Float(maxSample) / Float(Int16.max)
    }
}
