import Foundation

/// Byte layout of the jtty-sidecar shared-memory segment (`JttyShm`, protocol
/// v1 — `src/protocol.h` in https://github.com/DorsetDevStudio/jtty-sidecar).
///
/// The segment is one fixed little-endian structure: a 64-byte header, 48
/// bytes of counters, the transmit request/response, a ring of 256 decode
/// results, the rendered transmit audio and a 60 s ring of receive audio.
/// Every offset below is derived from the C struct; `JttyShmLayoutTests`
/// pins them so a drift from the C side is caught at test time, and
/// `JttySidecarClient` additionally checks `magic`, `version` and
/// `struct_size` against the live segment before touching anything else.
enum JttyShmLayout {
    // MARK: Enumerations

    enum ServerState: Int32 {
        case starting = 0
        case running = 1
        case quitting = 2
    }

    enum Command: Int32 {
        case none = 0
        case quit = 1
        case reset = 2
    }

    enum TxStatus: Int32 {
        case ok = 0
        case empty = 1
        case failed = 2
        case badProfile = 3
        case badRate = 4
        case tooLong = 5

        // MARK: Internal

        var description: String {
            switch self {
            case .ok: "ok"
            case .empty: "nothing to send"
            case .failed: "the helper could not encode the message"
            case .badProfile: "unsupported exchange profile"
            case .badRate: "unsupported sample rate"
            case .tooLong: "message is too long"
            }
        }
    }

    static let magic: UInt32 = 0x3159_5454 // "TTY1"
    static let version: UInt32 = 1
    static let headerSize = 64

    /// Receive audio is always 12 kHz mono int16.
    static let sampleRate = 12_000
    static let rxRingSamples = sampleRate * 60
    static let resultRing = 256
    /// 16 frames at 48 kHz plus one symbol.
    static let txMaxSamples = 59 * 16 * 1_536 + 1_536
    static let textLength = 80

    // MARK: Header (64 bytes)

    static let magicOffset = 0
    static let versionOffset = 4
    static let structSizeOffset = 8
    static let headerSizeOffset = 12
    static let serverStateOffset = 16
    static let commandOffset = 20
    static let heartbeatOffset = 24
    static let decoderRestartsOffset = 28
    static let nfaOffset = 32
    static let nfbOffset = 36
    static let f0Offset = 40
    static let ftolOffset = 44
    static let serverPidOffset = 48

    // MARK: Counters (48 bytes at 64)

    static let rxWrittenOffset = 64
    static let rxConsumedOffset = 72
    static let rxDroppedOffset = 80
    static let resultsWrittenOffset = 88

    // MARK: Transmit request (112 bytes at 112)

    static let txRequestSeqOffset = 112
    static let txRequestProfileOffset = 116
    static let txRequestSampleRateOffset = 120
    static let txRequestChainedOffset = 124
    static let txRequestF0Offset = 128
    static let txRequestTextOffset = 144

    // MARK: Transmit response (96 bytes at 224)

    static let txResponseSeqDoneOffset = 224
    static let txResponseStatusOffset = 228
    static let txResponseSamplesOffset = 232
    static let txResponseFramesOffset = 236
    static let txResponseTextOffset = 240

    // MARK: Rings

    static let resultsOffset = 320
    static let resultStride = 120
    static let resultMessageIdOffset = 0
    static let resultStartSampleOffset = 8
    static let resultFrequencyOffset = 16
    static let resultEomOffset = 20
    static let resultTextOffset = 24

    static let txPcmOffset = resultsOffset + resultRing * resultStride
    static let rxPcmOffset = txPcmOffset + 2 * txMaxSamples
    static let totalSize = rxPcmOffset + 2 * rxRingSamples
}
