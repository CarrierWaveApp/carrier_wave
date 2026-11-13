import AVFoundation
import Foundation

// MARK: - RadioAudioFormat

/// Sample geometry for audio bytes pushed through `RadioAudioBroadcaster`.
/// Wire-side serialization uses `AudioCodec`/`AudioFormatEvent` from
/// `CarrierWaveCore`; this struct stays platform-local so the broadcaster
/// has no dependency on the protocol module.
struct RadioAudioFormat: Equatable {
    /// Default for SCU-LAN10's FT-Control "PCM(16kHz)" setting.
    static let pcmInt16Mono16k = RadioAudioFormat(
        sampleRate: 16_000,
        channels: 1,
        bitsPerSample: 16,
        codecTag: "pcm_s16le"
    )

    let sampleRate: Int
    let channels: Int
    let bitsPerSample: Int
    /// Codec tag matching `AudioCodec.rawValue`. v1 is always `pcm_s16le`.
    let codecTag: String
}

// MARK: - RadioAudioBroadcaster

/// Multicasts a single radio's audio packets to multiple in-process listeners
/// (the local Mac player, the Remote LAN audio publisher, future processors).
/// AsyncStream is single-consumer; this type takes one upstream stream and
/// fans out each frame to N callbacks.
@MainActor
@Observable
final class RadioAudioBroadcaster {
    // MARK: Internal

    /// Most recently announced format. `nil` while no upstream is consuming.
    private(set) var currentFormat: RadioAudioFormat?
    /// Human-readable source label (e.g. "SCU-LAN10"). Mirrors how
    /// `WaterfallStore` tags its origin so remote subscribers can render it.
    private(set) var sourceLabel: String = ""
    /// Identifier the publisher should attach to outbound events. Stable for
    /// the lifetime of one upstream connection.
    private(set) var radioID: String = ""

    var hasListeners: Bool {
        !listeners.isEmpty
    }

    /// Set or update the announced format and source. Listeners installed
    /// before this call see the format via `currentFormat`; new listeners
    /// installed after a format change must read it themselves.
    func setFormat(
        _ format: RadioAudioFormat,
        sourceLabel: String,
        radioID: String
    ) {
        currentFormat = format
        self.sourceLabel = sourceLabel
        self.radioID = radioID
    }

    /// Begin draining `stream` and forwarding each frame to all listeners.
    /// Replaces any previous upstream.
    func startConsuming(from stream: AsyncStream<Data>) {
        consumeTask?.cancel()
        consumeTask = Task { [weak self] in
            for await data in stream {
                guard !Task.isCancelled else {
                    break
                }
                guard let self else {
                    return
                }
                deliver(data)
            }
        }
    }

    func stopConsuming() {
        consumeTask?.cancel()
        consumeTask = nil
        currentFormat = nil
        sourceLabel = ""
        radioID = ""
    }

    /// Adds a listener. Returns a token to pass to `removeListener(id:)`.
    @discardableResult
    func addListener(_ listener: @escaping @Sendable @MainActor (Data) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = listener
        return id
    }

    func removeListener(id: UUID) {
        listeners.removeValue(forKey: id)
    }

    // MARK: Private

    private var listeners: [UUID: @Sendable @MainActor (Data) -> Void] = [:]
    private var consumeTask: Task<Void, Never>?

    private func deliver(_ data: Data) {
        for listener in listeners.values {
            listener(data)
        }
    }
}
