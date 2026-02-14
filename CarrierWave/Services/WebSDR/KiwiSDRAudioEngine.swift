import AVFoundation
import Foundation

// MARK: - KiwiSDRAudioEngine

/// Manages live audio playback from a KiwiSDR stream.
/// Uses AVAudioSourceNode to pull samples from a ring buffer on
/// the audio render thread, with adaptive rate to handle jitter.
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

    /// Error message if engine failed to start (visible in UI for diagnostics)
    private(set) var startError: String?

    /// Current buffer fill ratio (0.0 to 1.0)
    var fillRatio: Double {
        ringBuffer.fillRatio
    }

    /// Start the audio engine at the given input sample rate.
    /// The source node runs at the hardware sample rate; audio is
    /// resampled from the input rate in the render callback.
    /// Playback is deferred until the ring buffer accumulates 1 second
    /// of audio (pre-buffering) to absorb network jitter.
    func start(sampleRate: Double) {
        guard !isPlaying, !isBuffering else {
            return
        }

        inputSampleRate = sampleRate.rounded()
        prebufferThreshold = Int(inputSampleRate * 2) // 2 seconds of samples
        ringBuffer.reset()
        startError = nil
        isBuffering = true

        configureAudioSession()

        // Use the hardware sample rate for the audio graph
        outputSampleRate = AVAudioSession.sharedInstance().sampleRate
        if outputSampleRate <= 0 {
            outputSampleRate = 48_000
        }

        setupAudioGraph()
        // Don't start engine yet — wait for buffer to fill.
        // The prebuffer timer checks fill level periodically.
        startPrebufferTimer()
    }

    /// Stop the audio engine and tear down the graph.
    func stop() {
        prebufferTimer?.invalidate()
        prebufferTimer = nil
        rateTimer?.invalidate()
        rateTimer = nil

        engine.stop()
        removeNotifications()

        sourceNode = nil
        timePitchNode = nil
        isPlaying = false
        isBuffering = false
    }

    /// Write samples from the network into the ring buffer.
    func write(_ samples: [Int16]) {
        ringBuffer.write(samples)
    }

    /// Set muted state.
    func setMuted(_ muted: Bool) {
        isMuted = muted
        engine.mainMixerNode.outputVolume = muted ? 0 : 1
    }

    // MARK: Private

    // MARK: - Adaptive Rate Control

    /// Target fill ratio for the ring buffer. The adaptive rate controller
    /// adjusts playback speed to keep the buffer near this level.
    private static let targetFillRatio = 0.75

    /// Maximum rate adjustment (±8%). Inaudible for narrowband ham radio.
    private static let maxRateOffset: Float = 0.08

    /// Gain for the proportional controller. Maps fill deviation to rate
    /// adjustment: deviation of 0.4 → maxRateOffset.
    private static let rateGain: Float = 0.20

    private let ringBuffer: AudioRingBuffer
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var timePitchNode: AVAudioUnitTimePitch?
    private var prebufferTimer: Timer?
    private var rateTimer: Timer?
    private var notificationTokens: [Any] = []
    /// Input sample rate from KiwiSDR (e.g., 12000)
    private var inputSampleRate: Double = 12_000
    /// Hardware output sample rate (e.g., 48000)
    private var outputSampleRate: Double = 48_000
    /// Samples needed before starting playback (1 second at input rate)
    private var prebufferThreshold: Int = 12_000

    /// Create the AVAudioSourceNode with its render callback.
    /// Must be `nonisolated` so the closure doesn't inherit @MainActor
    /// isolation — the audio render thread would otherwise trip Swift 6's
    /// runtime actor-isolation check and crash.
    nonisolated private static func makeSourceNode(
        format: AVAudioFormat,
        buffer: AudioRingBuffer,
        ratio: Double,
        channelCount: Int
    ) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) {
            _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(
                audioBufferList
            )
            let count = Int(frameCount)

            // Fill the first channel with resampled audio
            if let rawBuffer = ablPointer[0].mData {
                let floatPtr = rawBuffer.assumingMemoryBound(to: Float.self)
                _ = buffer.readResampledAsFloat(
                    into: floatPtr,
                    outputCount: count,
                    ratio: ratio
                )

                // Copy mono to any additional channels
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

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            startError = "Session: \(error.localizedDescription)"
        }
        registerNotifications()
    }

    // MARK: - Audio Graph

    private func setupAudioGraph() {
        // Query the engine's actual hardware output format so we
        // produce exactly what the device expects — avoids -10868.
        let hwFormat = engine.outputNode.outputFormat(forBus: 0)
        outputSampleRate = hwFormat.sampleRate
        let channelCount = Int(hwFormat.channelCount)

        // Resampling ratio: e.g., 48000/12000 = 4.0
        let ratio = outputSampleRate / inputSampleRate

        // Create a mono format at the hardware sample rate for the source.
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            startError = "Cannot create audio format"
            return
        }

        // Build the source node in a nonisolated context so the render
        // callback doesn't inherit @MainActor isolation — it runs on
        // the real-time audio I/O thread.
        let node = Self.makeSourceNode(
            format: monoFormat,
            buffer: ringBuffer,
            ratio: ratio,
            channelCount: channelCount
        )
        sourceNode = node

        // TimePitch node for adaptive rate control — adjusts playback
        // speed ±5% to keep the ring buffer near 50% full.
        let pitchNode = AVAudioUnitTimePitch()
        pitchNode.rate = 1.0
        pitchNode.pitch = 0 // no pitch shift
        timePitchNode = pitchNode

        engine.attach(node)
        engine.attach(pitchNode)

        // Source → TimePitch → MainMixer → Output
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

        // Buffer has enough data — start playback
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

        // Proportional control: positive error (buffer filling up) → speed up,
        // negative error (buffer draining) → slow down
        let raw = error * Self.rateGain
        let adjustment = min(Self.maxRateOffset, max(-Self.maxRateOffset, raw))
        timePitchNode.rate = 1.0 + adjustment
    }

    // MARK: - Interruption Handling

    private func registerNotifications() {
        let nc = NotificationCenter.default
        notificationTokens.append(
            nc.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                let typeValue = notification.userInfo?[
                    AVAudioSessionInterruptionTypeKey
                ] as? UInt
                let optionValue = notification.userInfo?[
                    AVAudioSessionInterruptionOptionKey
                ] as? UInt
                Task { @MainActor in
                    self?.handleInterruption(
                        typeValue: typeValue,
                        optionValue: optionValue
                    )
                }
            }
        )
        notificationTokens.append(
            nc.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                let reasonValue = notification.userInfo?[
                    AVAudioSessionRouteChangeReasonKey
                ] as? UInt
                Task { @MainActor in
                    self?.handleRouteChange(reasonValue: reasonValue)
                }
            }
        )
    }

    private func removeNotifications() {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()
    }

    private func handleInterruption(
        typeValue: UInt?,
        optionValue: UInt?
    ) {
        guard let typeValue,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        switch type {
        case .began:
            break
        case .ended:
            let options = optionValue.flatMap {
                AVAudioSession.InterruptionOptions(rawValue: $0)
            }
            if options?.contains(.shouldResume) == true {
                startEngine()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonValue: UInt?) {
        guard let reasonValue,
              let reason = AVAudioSession.RouteChangeReason(
                  rawValue: reasonValue
              )
        else {
            return
        }

        if reason == .oldDeviceUnavailable {
            setMuted(true)
        }
    }
}
