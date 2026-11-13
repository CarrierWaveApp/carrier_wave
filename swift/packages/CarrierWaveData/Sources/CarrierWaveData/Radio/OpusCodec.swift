import AVFoundation
import Foundation

// MARK: - OpusCodecError

/// Surfaced when AVAudioConverter can't be set up for Opus on this OS, or
/// when an encode/decode call fails. The encoder/decoder return nil from
/// their factory `init?` so callers can fall back to PCM gracefully.
public enum OpusCodecError: Error, Sendable {
    case unsupportedSampleRate(Int)
    case converterCreationFailed
    case encodeFailed(String)
    case decodeFailed(String)
    case bufferAllocationFailed
}

// MARK: - OpusCodecConfig

/// Wire-shape for one Opus session. Both ends must agree on `sampleRate`,
/// `channels`, and `framesPerPacket` — these are advertised in
/// `AudioFormatEvent` so the decoder side doesn't have to guess.
public struct OpusCodecConfig: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        sampleRate: Int,
        channels: Int = 1,
        framesPerPacket: Int? = nil,
        bitratePerSecond: Int = 24_000
    ) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.framesPerPacket = framesPerPacket ?? Self.defaultFramesPerPacket(for: sampleRate)
        self.bitratePerSecond = bitratePerSecond
    }

    // MARK: Public

    /// Apple's documented set of legal Opus sample rates.
    public static let supportedSampleRates: Set<Int> = [8_000, 12_000, 16_000, 24_000, 48_000]

    /// Opus accepts 8/12/16/24/48 kHz; we hand the source rate through
    /// directly to avoid a resample on either side.
    public let sampleRate: Int
    public let channels: Int
    /// Samples per packet. 20 ms at the chosen sample rate is the VOIP
    /// sweet spot — 320 at 16 kHz, 960 at 48 kHz. Smaller frames reduce
    /// latency at the cost of overhead; larger frames the opposite.
    public let framesPerPacket: Int
    /// Target encoded bitrate. Voice is fine at 24 kbps; bump to 32 for
    /// "broadcast clean" if you have headroom.
    public let bitratePerSecond: Int

    /// 20 ms worth of samples at the requested rate, the standard VOIP frame.
    public static func defaultFramesPerPacket(for sampleRate: Int) -> Int {
        sampleRate / 50
    }
}

// MARK: - OpusCodec

/// Thin namespace for codec-availability probes and shared format builders.
/// The encoder and decoder construct their `AVAudioFormat` instances through
/// the same helpers so the two sides stay byte-exact compatible.
public enum OpusCodec {
    // MARK: Public

    /// True iff this OS can build an `AVAudioConverter` from PCM to Opus.
    /// Sweep checks this once at startup; if false, the Opus toggle in
    /// Settings stays disabled and the wire format stays PCM.
    public static func isEncoderAvailable(config: OpusCodecConfig = .init(sampleRate: 16_000)) -> Bool {
        do {
            _ = try makeEncoderConverter(config: config)
            return true
        } catch {
            return false
        }
    }

    /// True iff this OS can build an `AVAudioConverter` from Opus to PCM.
    /// Field probes this on app launch; if false, it ignores Opus
    /// `AudioFormatEvent`s and stays subscribed in PCM-only mode.
    public static func isDecoderAvailable(config: OpusCodecConfig = .init(sampleRate: 16_000)) -> Bool {
        do {
            _ = try makeDecoderConverter(config: config)
            return true
        } catch {
            return false
        }
    }

    // MARK: Internal

    static func makePCMFormat(config: OpusCodecConfig) -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(config.sampleRate),
            channels: AVAudioChannelCount(config.channels),
            interleaved: config.channels > 1
        )
    }

    static func makeOpusFormat(config: OpusCodecConfig) -> AVAudioFormat? {
        guard OpusCodecConfig.supportedSampleRates.contains(config.sampleRate) else {
            return nil
        }
        var asbd = AudioStreamBasicDescription()
        asbd.mFormatID = kAudioFormatOpus
        asbd.mSampleRate = Double(config.sampleRate)
        asbd.mChannelsPerFrame = UInt32(config.channels)
        asbd.mFramesPerPacket = UInt32(config.framesPerPacket)
        // Compressed: bytes-per-frame / -packet are 0; codec sets them.
        asbd.mBitsPerChannel = 0
        asbd.mBytesPerFrame = 0
        asbd.mBytesPerPacket = 0
        asbd.mFormatFlags = 0
        asbd.mReserved = 0
        return AVAudioFormat(streamDescription: &asbd)
    }

    static func makeEncoderConverter(config: OpusCodecConfig) throws -> AVAudioConverter {
        guard let pcm = makePCMFormat(config: config) else {
            throw OpusCodecError.converterCreationFailed
        }
        guard let opus = makeOpusFormat(config: config) else {
            throw OpusCodecError.unsupportedSampleRate(config.sampleRate)
        }
        guard let converter = AVAudioConverter(from: pcm, to: opus) else {
            throw OpusCodecError.converterCreationFailed
        }
        converter.bitRate = config.bitratePerSecond
        return converter
    }

    static func makeDecoderConverter(config: OpusCodecConfig) throws -> AVAudioConverter {
        guard let pcm = makePCMFormat(config: config) else {
            throw OpusCodecError.converterCreationFailed
        }
        guard let opus = makeOpusFormat(config: config) else {
            throw OpusCodecError.unsupportedSampleRate(config.sampleRate)
        }
        guard let converter = AVAudioConverter(from: opus, to: pcm) else {
            throw OpusCodecError.converterCreationFailed
        }
        return converter
    }
}

// MARK: - OpusEncoder

/// Stateful Opus encoder. Accepts raw little-endian Int16 mono PCM bytes in
/// arbitrary chunk sizes and emits Opus packets one at a time, each
/// containing exactly `framesPerPacket` samples. Internally buffers any
/// trailing samples that don't fill a packet.
///
/// Thread model: this class is NOT thread-safe. Callers should wrap it in
/// an actor or only call from a single dispatch context. Sweep's audio
/// publisher is `@MainActor`, so that's where it lives there.
public final class OpusEncoder {
    // MARK: Lifecycle

    public init?(config: OpusCodecConfig) {
        do {
            converter = try OpusCodec.makeEncoderConverter(config: config)
        } catch {
            return nil
        }
        self.config = config
        bytesPerFrame = MemoryLayout<Int16>.size * config.channels
        bytesPerPacket = bytesPerFrame * config.framesPerPacket
        guard let pcmFormat = OpusCodec.makePCMFormat(config: config),
              let opusFormat = OpusCodec.makeOpusFormat(config: config)
        else {
            return nil
        }
        self.pcmFormat = pcmFormat
        self.opusFormat = opusFormat
    }

    // MARK: Public

    public let config: OpusCodecConfig

    /// Push `pcmBytes` into the encoder. Returns zero or more Opus packets
    /// (each ready to put on the wire as `AudioFrameEvent.samples`). Bytes
    /// past the last full packet are buffered for the next call.
    public func encode(pcmBytes: Data) throws -> [Data] {
        pendingPCM.append(pcmBytes)
        var packets: [Data] = []
        while pendingPCM.count >= bytesPerPacket {
            let packetBytes = pendingPCM.prefix(bytesPerPacket)
            pendingPCM.removeFirst(bytesPerPacket)
            if let packet = try encodeOnePacket(pcmPacketBytes: Data(packetBytes)) {
                packets.append(packet)
            }
        }
        return packets
    }

    /// Drop any partially-buffered audio. Call at end-of-stream or when
    /// the upstream codec resets so we don't emit a stale fragment.
    public func reset() {
        pendingPCM.removeAll(keepingCapacity: true)
        converter.reset()
    }

    // MARK: Private

    private let converter: AVAudioConverter
    private let pcmFormat: AVAudioFormat
    private let opusFormat: AVAudioFormat
    private let bytesPerFrame: Int
    private let bytesPerPacket: Int
    private var pendingPCM = Data()

    private func encodeOnePacket(pcmPacketBytes: Data) throws -> Data? {
        let frameCount = AVAudioFrameCount(config.framesPerPacket)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount) else {
            throw OpusCodecError.bufferAllocationFailed
        }
        inputBuffer.frameLength = frameCount
        guard let int16Channel = inputBuffer.int16ChannelData else {
            throw OpusCodecError.bufferAllocationFailed
        }
        pcmPacketBytes.withUnsafeBytes { rawBuf in
            guard let src = rawBuf.baseAddress else {
                return
            }
            memcpy(int16Channel[0], src, pcmPacketBytes.count)
        }

        // Compressed output: AVAudioCompressedBuffer takes a max packet-size
        // estimate. Opus packets at 24 kbps / 20 ms top out around 60 bytes
        // but can spike on transients; 1500 is a generous upper bound.
        let outputBuffer = AVAudioCompressedBuffer(
            format: opusFormat,
            packetCapacity: 1,
            maximumPacketSize: 1_500
        )

        var sentInput = false
        var encodeError: NSError?
        let status = converter.convert(to: outputBuffer, error: &encodeError) { _, outStatus in
            if sentInput {
                // `.noDataNow` keeps the converter's internal pipeline open
                // for the next call rather than tearing it down. `.endOfStream`
                // here causes the decoder to never emit subsequent packets'
                // PCM (verified empirically — total frames out went from
                // ~16000 to 280 with `.endOfStream`, full with `.noDataNow`).
                outStatus.pointee = .noDataNow
                return nil
            }
            sentInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        switch status {
        case .haveData,
             .inputRanDry,
             .endOfStream:
            // `.inputRanDry` is the normal "callback returned .noDataNow"
            // outcome; not an error. `.endOfStream` shouldn't fire here
            // since we never report it from the closure, but treat it
            // identically rather than throw.
            break
        case .error:
            throw OpusCodecError.encodeFailed(encodeError?.localizedDescription ?? "unknown")
        @unknown default:
            throw OpusCodecError.encodeFailed("unknown status \(status.rawValue)")
        }

        guard outputBuffer.packetCount > 0 else {
            return nil
        }
        let descriptions = outputBuffer.packetDescriptions
        let bytes = if let descriptions {
            Int(descriptions[0].mDataByteSize)
        } else {
            Int(outputBuffer.byteLength)
        }
        return Data(bytes: outputBuffer.data, count: bytes)
    }
}

// MARK: - OpusDecoder

/// Decoder counterpart of `OpusEncoder`. Each `decode(packet:)` call returns
/// `framesPerPacket` samples of Int16 PCM (or nil on error). Holds no
/// inter-packet state beyond what the underlying converter needs, so packet
/// loss only damages the affected packet.
public final class OpusDecoder {
    // MARK: Lifecycle

    public init?(config: OpusCodecConfig) {
        do {
            converter = try OpusCodec.makeDecoderConverter(config: config)
        } catch {
            return nil
        }
        self.config = config
        guard let pcmFormat = OpusCodec.makePCMFormat(config: config),
              let opusFormat = OpusCodec.makeOpusFormat(config: config)
        else {
            return nil
        }
        self.pcmFormat = pcmFormat
        self.opusFormat = opusFormat
    }

    // MARK: Public

    public let config: OpusCodecConfig

    public func decode(packet: Data) throws -> Data? {
        let inputBuffer = makeInputBuffer(for: packet)
        let frameCount = AVAudioFrameCount(config.framesPerPacket)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount) else {
            throw OpusCodecError.bufferAllocationFailed
        }
        var sentInput = false
        var decodeError: NSError?
        let status = converter.convert(to: outputBuffer, error: &decodeError) { _, outStatus in
            if sentInput {
                // `.noDataNow` keeps the converter's internal pipeline open
                // for the next call rather than tearing it down. `.endOfStream`
                // here causes the decoder to never emit subsequent packets'
                // PCM (verified empirically — total frames out went from
                // ~16000 to 280 with `.endOfStream`, full with `.noDataNow`).
                outStatus.pointee = .noDataNow
                return nil
            }
            sentInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
        switch status {
        case .haveData,
             .inputRanDry,
             .endOfStream:
            break
        case .error:
            throw OpusCodecError.decodeFailed(decodeError?.localizedDescription ?? "unknown")
        @unknown default:
            throw OpusCodecError.decodeFailed("unknown status \(status.rawValue)")
        }
        guard outputBuffer.frameLength > 0, let int16Channel = outputBuffer.int16ChannelData else {
            return nil
        }
        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size * config.channels
        return Data(bytes: int16Channel[0], count: byteCount)
    }

    // MARK: Private

    private let converter: AVAudioConverter
    private let pcmFormat: AVAudioFormat
    private let opusFormat: AVAudioFormat

    private func makeInputBuffer(for packet: Data) -> AVAudioCompressedBuffer {
        let buffer = AVAudioCompressedBuffer(
            format: opusFormat,
            packetCapacity: 1,
            maximumPacketSize: max(packet.count, 1_500)
        )
        buffer.byteLength = UInt32(packet.count)
        buffer.packetCount = 1
        if let descriptions = buffer.packetDescriptions {
            descriptions[0].mStartOffset = 0
            descriptions[0].mVariableFramesInPacket = 0
            descriptions[0].mDataByteSize = UInt32(packet.count)
        }
        packet.withUnsafeBytes { rawBuf in
            guard let src = rawBuf.baseAddress else {
                return
            }
            memcpy(buffer.data, src, packet.count)
        }
        return buffer
    }
}
