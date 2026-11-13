import AVFoundation
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "SCULAN10AudioPlayer")

// MARK: - SCULAN10AudioPlayer

/// Plays SCU-LAN10 RX audio through the default Mac output device.
///
/// The transport yields raw PCM bytes from the audio channel after stripping
/// the 6-byte transport header and 4-byte frame_seq/config prefix. SCU-LAN10
/// defaults to 16-bit signed little-endian PCM at 16 kHz mono (FT-Control
/// "PCM(16kHz)" setting); we treat that as the sole supported format for now.
@MainActor
@Observable
final class SCULAN10AudioPlayer {
    // MARK: Lifecycle

    init() {
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        // AVAudioPlayerNode only accepts the standard (Float32, deinterleaved)
        // format; connecting it with Int16 raises an NSException on macOS 15.
        // Int16 LE samples from the transport are converted in makeBuffer.
        sourceFormat = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: sourceFormat)
    }

    // MARK: Internal

    private(set) var isPlaying = false

    /// Output gain (0.0–1.0). Applied to the player node so the mainMixer
    /// stays neutral.
    var volume: Float = 1.0 {
        didSet {
            playerNode.volume = max(0, min(1, volume))
        }
    }

    /// Spin up AVAudioEngine and begin scheduling buffers. Frames arrive via
    /// `feed(_:)` from a `RadioAudioBroadcaster` listener.
    func start() {
        guard !isPlaying else {
            return
        }
        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            logger.error("Failed to start AVAudioEngine: \(error)")
            return
        }
        playerNode.volume = max(0, min(1, volume))
        playerNode.play()
        isPlaying = true
    }

    /// Push one PCM frame into the player. No-op if `start()` hasn't been
    /// called or the byte count isn't aligned to a sample boundary.
    func feed(_ pcmBytes: Data) {
        guard isPlaying else {
            return
        }
        guard let buffer = Self.makeBuffer(pcmBytes: pcmBytes, format: sourceFormat) else {
            return
        }
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// Stop playback and tear down the engine. Safe to call when not playing.
    func stop() {
        if playerNode.isPlaying {
            playerNode.stop()
        }
        if engine.isRunning {
            engine.stop()
        }
        isPlaying = false
    }

    // MARK: Private

    private let engine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private let sourceFormat: AVAudioFormat

    /// Convert a chunk of mono Int16 LE PCM bytes into a Float32 `AVAudioPCMBuffer`.
    /// The transport already de-interleaves the SCU-LAN10's stereo source
    /// to channel 0 before yielding (see `SCULAN10Transport.extractLeft`).
    private static func makeBuffer(
        pcmBytes: Data,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let bytesPerSample = MemoryLayout<Int16>.size
        let sampleCount = pcmBytes.count / bytesPerSample
        guard sampleCount > 0 else {
            return nil
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)

        guard let floatChannel = buffer.floatChannelData else {
            return nil
        }
        let dst = floatChannel[0]
        pcmBytes.withUnsafeBytes { rawBuf in
            for i in 0 ..< sampleCount {
                let sample = Int16(littleEndian: rawBuf.loadUnaligned(
                    fromByteOffset: i * bytesPerSample,
                    as: Int16.self
                ))
                dst[i] = Float(sample) / 32_768
            }
        }
        return buffer
    }
}
