import AVFoundation
import CarrierWaveCore
import CarrierWaveData
import UIKit

// MARK: - RemoteSweepAudioPlayer

/// Foreground-only iOS player for audio frames forwarded from CW Sweep over
/// the `radio.audio` Remote topic. Configures `AVAudioSession` for `.playback`
/// when starting and tears it down on stop. Background playback is out of
/// scope for v1 — that needs `UIBackgroundModes: audio` plus session
/// interruption handling.
@MainActor
@Observable
final class RemoteSweepAudioPlayer {
    // MARK: Lifecycle

    init() {
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
    }

    // MARK: Internal

    private(set) var isPlaying = false

    var volume: Float = 1.0 {
        didSet {
            playerNode.volume = max(0, min(1, volume))
        }
    }

    /// (Re)configure the engine for `format` and start playback. Calling
    /// again with a new format will reconnect the graph; calling with the
    /// same format is a no-op so frames continue to flow uninterrupted.
    /// Supports both `pcm_s16le` (raw Int16) and `opus` (decoded with
    /// `OpusDecoder` before scheduling on the player node).
    func start(format: AudioFormatEvent) {
        switch format.codec {
        case .pcmS16LE:
            startPCM(format: format)
        case .opus:
            startOpus(format: format)
        }
    }

    /// Push one frame from the wire. For PCM the bytes are Int16 LE PCM and
    /// scheduled directly; for Opus the bytes are one Opus packet that gets
    /// decoded to PCM first. Drops on misconfiguration or decode error.
    func feed(_ payload: Data) {
        guard isPlaying, let format = sourceFormat else {
            return
        }
        if let decoder = opusDecoder {
            do {
                guard let pcmBytes = try decoder.decode(packet: payload) else {
                    return
                }
                guard let buffer = Self.makeBuffer(pcmBytes: pcmBytes, format: format) else {
                    return
                }
                playerNode.scheduleBuffer(buffer, completionHandler: nil)
            } catch {
                return
            }
        } else {
            guard let buffer = Self.makeBuffer(pcmBytes: payload, format: format) else {
                return
            }
            playerNode.scheduleBuffer(buffer, completionHandler: nil)
        }
    }

    func stop() {
        stopInternal()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: Private

    private let engine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private var sourceFormat: AVAudioFormat?
    /// Live decoder when Sweep is encoding the wire stream as Opus. Nil for
    /// the legacy raw-PCM path. Recreated on every `start(format:)` so a
    /// codec swap doesn't leak the old decoder's internal state.
    private var opusDecoder: OpusDecoder?

    private static func makeBuffer(
        pcmBytes: Data,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let bytesPerSample = MemoryLayout<Int16>.size
        let channelCount = Int(format.channelCount)
        let bytesPerFrame = bytesPerSample * channelCount
        let frameCount = pcmBytes.count / bytesPerFrame
        guard frameCount > 0 else {
            return nil
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let int16Channel = buffer.int16ChannelData else {
            return nil
        }
        let dst = int16Channel[0]
        pcmBytes.withUnsafeBytes { rawBuf in
            guard let src = rawBuf.baseAddress else {
                return
            }
            memcpy(dst, src, frameCount * bytesPerFrame)
        }
        return buffer
    }

    private func startPCM(format: AudioFormatEvent) {
        guard let avFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(format.sampleRate),
            channels: AVAudioChannelCount(format.channels),
            interleaved: format.channels > 1
        ) else {
            return
        }
        if isPlaying, sourceFormat == avFormat, opusDecoder == nil {
            return
        }
        opusDecoder = nil
        applyEngineFormat(avFormat)
    }

    private func startOpus(format: AudioFormatEvent) {
        let framesPerPacket = format.framesPerPacket ?? OpusCodecConfig.defaultFramesPerPacket(for: format.sampleRate)
        let config = OpusCodecConfig(
            sampleRate: format.sampleRate,
            channels: format.channels,
            framesPerPacket: framesPerPacket
        )
        guard let decoder = OpusDecoder(config: config),
              let avFormat = AVAudioFormat(
                  commonFormat: .pcmFormatInt16,
                  sampleRate: Double(format.sampleRate),
                  channels: AVAudioChannelCount(format.channels),
                  interleaved: format.channels > 1
              )
        else {
            return
        }
        // Fast path: decoder swap + same target PCM format means skip the
        // full engine teardown so playback continues uninterrupted.
        if isPlaying, sourceFormat == avFormat {
            opusDecoder = decoder
            return
        }
        opusDecoder = decoder
        applyEngineFormat(avFormat)
    }

    private func applyEngineFormat(_ avFormat: AVAudioFormat) {
        if isPlaying {
            stopInternal()
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            return
        }

        engine.connect(playerNode, to: engine.mainMixerNode, format: avFormat)
        sourceFormat = avFormat

        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            sourceFormat = nil
            return
        }

        playerNode.volume = max(0, min(1, volume))
        playerNode.play()
        isPlaying = true
    }

    private func stopInternal() {
        if playerNode.isPlaying {
            playerNode.stop()
        }
        if engine.isRunning {
            engine.stop()
        }
        sourceFormat = nil
        opusDecoder = nil
        isPlaying = false
    }
}
