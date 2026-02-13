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
        ringBuffer = AudioRingBuffer()
    }

    // MARK: Internal

    /// Whether audio is currently playing
    private(set) var isPlaying = false

    /// Whether audio output is muted
    private(set) var isMuted = false

    /// Current buffer fill ratio (0.0 to 1.0)
    var fillRatio: Double {
        ringBuffer.fillRatio
    }

    /// Start the audio engine at the given sample rate.
    func start(sampleRate: Double) {
        guard !isPlaying else {
            return
        }

        self.sampleRate = sampleRate
        ringBuffer.reset()

        configureAudioSession()
        setupAudioGraph()
        startEngine()
        startRateTimer()

        isPlaying = true
    }

    /// Stop the audio engine and tear down the graph.
    func stop() {
        rateTimer?.invalidate()
        rateTimer = nil

        engine.stop()
        removeNotifications()

        sourceNode = nil
        timePitchNode = nil
        isPlaying = false
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

    private let ringBuffer: AudioRingBuffer
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var timePitchNode: AVAudioUnitTimePitch?
    private var rateTimer: Timer?
    private var notificationTokens: [Any] = []
    private var sampleRate: Double = 12_000
    private var currentRate: Float = 1.0

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: .mixWithOthers)
        try? session.setActive(true)
        registerNotifications()
    }

    // MARK: - Audio Graph

    private func setupAudioGraph() {
        // AVAudioEngine requires Float32 format internally
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        )!

        // Source node pulls Int16 from ring buffer, converts to Float32
        let buffer = ringBuffer
        let node = AVAudioSourceNode(format: format) {
            _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let rawBuffer = ablPointer[0].mData else {
                return noErr
            }

            let count = Int(frameCount)
            let floatPtr = rawBuffer.assumingMemoryBound(to: Float.self)

            // Read Int16 samples into a stack buffer, then convert to Float32
            let int16Buf = UnsafeMutablePointer<Int16>.allocate(capacity: count)
            defer { int16Buf.deallocate() }
            _ = buffer.read(into: int16Buf, count: count)

            let scale: Float = 1.0 / Float(Int16.max)
            for i in 0 ..< count {
                floatPtr[i] = Float(int16Buf[i]) * scale
            }

            return noErr
        }
        sourceNode = node

        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = 1.0
        timePitchNode = timePitch

        engine.attach(node)
        engine.attach(timePitch)

        // Source → TimePitch → MainMixer → Output
        engine.connect(node, to: timePitch, format: format)
        engine.connect(
            timePitch,
            to: engine.mainMixerNode,
            format: nil
        )

        engine.mainMixerNode.outputVolume = isMuted ? 0 : 1
    }

    private func startEngine() {
        do {
            try engine.start()
        } catch {
            print("[AudioEngine] Start failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Adaptive Rate

    private func startRateTimer() {
        rateTimer?.invalidate()
        rateTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustRate()
            }
        }
    }

    private func adjustRate() {
        guard let timePitch = timePitchNode else {
            return
        }

        let fill = ringBuffer.fillRatio
        let targetRate: Float = if fill < 0.25 {
            0.97 // Buffer low — slow down to let it fill
        } else if fill > 0.75 {
            1.03 // Buffer high — speed up to drain
        } else {
            1.0 // Normal range
        }

        // Smooth rate changes to avoid jarring shifts
        let smoothed = currentRate + (targetRate - currentRate) * 0.3
        currentRate = smoothed
        timePitch.rate = smoothed
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
