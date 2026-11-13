import Foundation

// MARK: - WaterfallStore

/// Central, source-agnostic store for spectrum waterfall data displayed in
/// CW Sweep. Different radios produce magnitudes through different paths
/// (SCU-LAN10 over its proprietary scope channel, FlexRadio over VITA-49
/// UDP, etc.); each producer normalizes its lines to 0..1 floats and pushes
/// them through `append(_:)`. The view layer reads from this store, so the
/// `WaterfallPanel` does not need to know which radio is connected.
///
/// `magnitudes[0]` is the newest line (matches `SCULAN10WaterfallData`'s
/// previous behavior so the existing renderers don't change orientation).
@MainActor
@Observable
final class WaterfallStore {
    // MARK: Internal

    /// Identifier for the producer feeding the store. `none` means no radio
    /// is currently pushing — the panel renders an "unavailable" placeholder.
    enum Source: String {
        case none
        case sculan10
        case flex
        case sdr
        case icomMain
        case icomSub

        // MARK: Internal

        var label: String {
            switch self {
            case .none: "None"
            case .sculan10: "SCU-LAN10"
            case .flex: "SmartSDR"
            case .sdr: "SDR"
            case .icomMain: "Icom Main"
            case .icomSub: "Icom Sub"
            }
        }

        /// Both Icom bands share one producer; treat them as one source when
        /// deciding whether a stream is still live.
        var isIcom: Bool {
            self == .icomMain || self == .icomSub
        }
    }

    /// Rolling buffer of normalized spectrum lines (newest first, value 0..1).
    private(set) var magnitudes: [[Float]] = []

    /// Number of active spectrum bins in the most recent line.
    private(set) var activeBinCount: Int = 0

    /// Whether a producer is actively pushing lines.
    private(set) var isReceiving = false

    /// Maximum number of lines to retain.
    var maxLines: Int = 200

    /// Center frequency of the spectrum window in MHz.
    private(set) var centerFrequencyMHz: Double = 0

    /// Total span of the spectrum window in kHz.
    private(set) var spanKHz: Double = 0

    /// Identifier of the producer currently feeding the store.
    private(set) var source: Source = .none

    /// Monotonic counter incremented on every appended line. Used by remote
    /// publishers to detect "a new line arrived" without diffing the magnitudes
    /// array each time.
    private(set) var lineSequence: UInt64 = 0

    /// Timestamp of the most recent appended line.
    private(set) var lastLineTimestamp: Date?

    /// When set, only this producer may write to the store. The external SDR
    /// input claims the store while enabled so a connected SCU-LAN10 / Flex
    /// doesn't interleave its own lines with the SDR's.
    private(set) var exclusiveSource: Source?

    /// Claim (or release, with `nil`) exclusive ownership of the store.
    /// Clears any lines left over from a different producer.
    func setExclusiveSource(_ exclusive: Source?) {
        exclusiveSource = exclusive
        if let exclusive, source != exclusive {
            clear()
        }
    }

    /// Reset the store to empty state. Producers call this when their stream
    /// ends or the radio is disconnected, passing themselves as `producer` so
    /// the call is ignored while another source holds exclusive ownership.
    func clear(producer: Source? = nil) {
        if let producer, !accepts(producer) {
            return
        }
        magnitudes.removeAll(keepingCapacity: true)
        activeBinCount = 0
        centerFrequencyMHz = 0
        spanKHz = 0
        source = .none
        isReceiving = false
        lastLineTimestamp = nil
    }

    /// Mark the producer as receiving (or not) and identify the source so the
    /// panel can label the data and the placeholder can stay accurate when no
    /// stream is live.
    func setReceiving(_ receiving: Bool, source: Source) {
        guard accepts(source) else {
            return
        }
        isReceiving = receiving
        if receiving {
            self.source = source
        } else if self.source == source || (self.source.isIcom && source.isIcom) {
            self.source = .none
        }
    }

    /// Update the geometry (center frequency / span) without appending a line.
    /// Producers call this when the radio reports a span change but no new
    /// spectrum data has arrived yet.
    func updateGeometry(centerMHz: Double, spanKHz: Double) {
        guard accepts(source) else {
            return
        }
        centerFrequencyMHz = centerMHz
        self.spanKHz = spanKHz
    }

    /// Append one normalized line. `centerMHz` and `spanKHz` describe the
    /// frequency window the line covers; they may change between lines (e.g.
    /// when the operator retunes), in which case the renderer treats the new
    /// geometry as authoritative for everything from this line backward.
    func append(
        line: [Float],
        centerMHz: Double,
        spanKHz: Double,
        source: Source
    ) {
        guard !line.isEmpty, accepts(source) else {
            return
        }
        self.source = source
        centerFrequencyMHz = centerMHz
        self.spanKHz = spanKHz
        activeBinCount = line.count

        magnitudes.insert(line, at: 0)
        if magnitudes.count > maxLines {
            magnitudes.removeLast(magnitudes.count - maxLines)
        }

        lineSequence &+= 1
        lastLineTimestamp = Date()
    }

    // MARK: Private

    private func accepts(_ producer: Source) -> Bool {
        exclusiveSource.map { $0 == producer } ?? true
    }
}
