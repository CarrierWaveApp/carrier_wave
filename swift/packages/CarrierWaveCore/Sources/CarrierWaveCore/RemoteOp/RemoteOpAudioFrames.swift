import Foundation

// MARK: - AudioCodec

/// Wire-format audio codec identifier. Sweep advertises whichever it has
/// negotiated via `AudioFormatEvent`; clients dispatch on this enum to pick
/// the right decode path. `pcmS16LE` is the original raw mono PCM stream;
/// `opus` is `kAudioFormatOpus` packets carrying one frame each.
public enum AudioCodec: String, Codable, Sendable, Equatable {
    case pcmS16LE = "pcm_s16le"
    case opus
}

// MARK: - AudioFormatEvent

/// Server → client. Sent as the first event after a `radio.audio` subscribe
/// and again whenever the upstream radio's audio format changes (codec swap,
/// sample-rate change, source switch). Clients must reset their playback
/// pipeline to the new format on receipt.
public struct AudioFormatEvent: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        radioID: String,
        sourceLabel: String,
        codec: AudioCodec,
        sampleRate: Int,
        channels: Int,
        bitsPerSample: Int,
        framesPerPacket: Int? = nil,
        timestamp: Date
    ) {
        self.radioID = radioID
        self.sourceLabel = sourceLabel
        self.codec = codec
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
        self.framesPerPacket = framesPerPacket
        self.timestamp = timestamp
    }

    // MARK: Public

    public let radioID: String
    /// Human-readable source name (e.g. "SCU-LAN10"). Mirrors waterfall.
    public let sourceLabel: String
    public let codec: AudioCodec
    /// Frames per second per channel (e.g. 16_000).
    public let sampleRate: Int
    /// Channel count. v1 always emits 1 (mono); reserved for future stereo.
    public let channels: Int
    /// Bits per sample (16 for `pcm_s16le`, 0 for compressed codecs like Opus).
    public let bitsPerSample: Int
    /// Samples per packet. Required by the Opus decoder to allocate the
    /// PCM output buffer. Nil for `pcm_s16le` (frame size is implicit in
    /// the byte count). 320 = 20 ms at 16 kHz; 960 = 20 ms at 48 kHz.
    public let framesPerPacket: Int?
    public let timestamp: Date
}

// MARK: - AudioFrameEvent

/// Server → client. Carries one packet of audio samples in the format last
/// announced by `AudioFormatEvent`. `samples` is JSON-encoded as base64 by
/// default (Foundation `Data` Codable behaviour).
public struct AudioFrameEvent: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        radioID: String,
        sequence: UInt32,
        samples: Data,
        timestamp: Date
    ) {
        self.radioID = radioID
        self.sequence = sequence
        self.samples = samples
        self.timestamp = timestamp
    }

    // MARK: Public

    public let radioID: String
    /// Monotonic per-stream counter, wraps at UInt32.max. Receivers can use
    /// it to detect dropped frames and to ignore reorderings.
    public let sequence: UInt32
    /// Raw sample bytes in the announced codec/format.
    public let samples: Data
    public let timestamp: Date
}
