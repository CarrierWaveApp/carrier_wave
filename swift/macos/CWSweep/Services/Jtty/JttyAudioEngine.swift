import AudioToolbox
import AVFoundation
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "JttyAudioEngine")

// MARK: - JttyAudioEngine

/// Audio I/O for the JTTY modem: captures the radio's receive audio, converts
/// it to the 12 kHz mono int16 the helper decodes, and plays the helper's
/// rendered transmit audio (48 kHz) to the radio.
///
/// Input and output may be different CoreAudio devices (set by UID before the
/// engine starts). The capture tap runs on CoreAudio's thread; `sink` must be
/// cheap and non-blocking — `JttySidecarClient.writeReceiveAudio` is a memcpy
/// into shared memory, which is fine.
final class JttyAudioEngine: @unchecked Sendable {
    // MARK: Internal

    typealias SampleSink = @Sendable (UnsafeBufferPointer<Int16>) -> Void

    enum EngineError: LocalizedError {
        case noInputDevice
        case unsupportedInputFormat(String)
        case converterUnavailable
        case deviceSelectionFailed(String, OSStatus)

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .noInputDevice:
                "No audio input device is available"
            case let .unsupportedInputFormat(description):
                "Unsupported input format: \(description)"
            case .converterUnavailable:
                "Could not create the 12 kHz audio converter"
            case let .deviceSelectionFailed(name, status):
                "Could not select audio device \(name) (CoreAudio error \(status))"
            }
        }
    }

    static let playbackSampleRate = 48_000.0

    /// Peak input level 0…1, reported at most ~10 times a second.
    var onLevel: (@Sendable (Float) -> Void)?

    var isRunning: Bool {
        engine.isRunning
    }

    /// Select devices (nil = system default), install the capture tap and start.
    func start(inputDeviceUID: String?, outputDeviceUID: String?, sink: @escaping SampleSink) throws {
        stop()
        try select(uid: inputDeviceUID, on: engine.inputNode, input: true)
        try select(uid: outputDeviceUID, on: engine.outputNode, input: false)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw EngineError.noInputDevice
        }
        guard inputFormat.commonFormat == .pcmFormatFloat32, !inputFormat.isInterleaved else {
            throw EngineError.unsupportedInputFormat(inputFormat.description)
        }
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: false
        ),
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Double(JttyShmLayout.sampleRate),
                channels: 1,
                interleaved: true
            ),
            let converter = AVAudioConverter(from: monoFormat, to: targetFormat)
        else {
            throw EngineError.converterUnavailable
        }
        self.converter = converter

        if !playerAttached {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
            playerAttached = true
        }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let onLevel = onLevel
        var lastLevel = Date.distantPast
        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let channels = buffer.floatChannelData else {
                return
            }
            let frames = Int(buffer.frameLength)
            guard frames > 0,
                  let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(frames)),
                  let monoData = mono.floatChannelData
            else {
                return
            }
            mono.frameLength = AVAudioFrameCount(frames)
            monoData[0].update(from: channels[0], count: frames)

            if let onLevel, Date().timeIntervalSince(lastLevel) > 0.1 {
                lastLevel = Date()
                var peak: Float = 0
                for i in 0 ..< frames {
                    peak = max(peak, abs(channels[0][i]))
                }
                onLevel(min(1, peak))
            }

            let capacity = AVAudioFrameCount(Double(frames) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
                return
            }
            var consumed = false
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return mono
            }
            guard status != .error, let int16 = out.int16ChannelData, out.frameLength > 0 else {
                return
            }
            sink(UnsafeBufferPointer(start: int16[0], count: Int(out.frameLength)))
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        player.play()
        logger.info("JTTY audio running: in \(inputFormat.sampleRate) Hz × \(inputFormat.channelCount)")
    }

    func stop() {
        stopPlayback()
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        converter = nil
    }

    /// Play rendered audio and return once it has left the output device.
    /// Returns early (false) if playback was stopped.
    @discardableResult
    func play(samples: [Int16], sampleRate: Double) async -> Bool {
        guard engine.isRunning, !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let data = buffer.floatChannelData
        else {
            return false
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let scale = 1 / Float(Int16.max)
        for i in 0 ..< samples.count {
            data[0][i] = Float(samples[i]) * scale
        }
        if !player.isPlaying {
            player.play()
        }
        let token = UUID()
        return await withCheckedContinuation { continuation in
            playbackLock.withLock { pending[token] = continuation }
            player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) {
                [weak self] _ in
                self?.resume(token, played: true)
            }
        }
    }

    /// Stop whatever is playing; any awaiting `play` returns false.
    func stopPlayback() {
        if player.isPlaying {
            player.stop()
        }
        let waiting = playbackLock.withLock { () -> [CheckedContinuation<Bool, Never>] in
            let all = Array(pending.values)
            pending.removeAll()
            return all
        }
        waiting.forEach { $0.resume(returning: false) }
        if engine.isRunning {
            player.play()
        }
    }

    // MARK: Private

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: playbackSampleRate, channels: 1)!
    private var playerAttached = false
    private var converter: AVAudioConverter?
    private let playbackLock = NSLock()
    private var pending: [UUID: CheckedContinuation<Bool, Never>] = [:]

    private func resume(_ token: UUID, played: Bool) {
        let continuation = playbackLock.withLock { pending.removeValue(forKey: token) }
        continuation?.resume(returning: played)
    }

    /// Point an engine I/O node at a specific device. Must happen before the
    /// engine starts and before the node's format is read.
    private func select(uid: String?, on node: AVAudioIONode, input: Bool) throws {
        guard let uid, !uid.isEmpty else {
            return
        }
        guard let device = MacAudioDevices.device(uid: uid) else {
            logger.warning("JTTY audio device \(uid) not present; using the system default")
            return
        }
        guard let unit = node.audioUnit else {
            return
        }
        var id = device.id
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw EngineError.deviceSelectionFailed(device.name, status)
        }
        logger.info("JTTY \(input ? "input" : "output") device: \(device.name)")
    }
}
