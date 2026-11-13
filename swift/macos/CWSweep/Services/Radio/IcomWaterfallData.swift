import CarrierWaveCore
import Foundation

// MARK: - IcomWaterfallData

/// Producer that turns Icom `27 00` scope frames (IC-9700 / IC-705 / IC-7300
/// family, over LAN or USB) into normalized lines in the shared
/// `WaterfallStore`. Mirrors `SCULAN10WaterfallData`: owns nothing observable,
/// the store is the single source of truth.
///
/// Geometry (center, span) comes from the frame itself rather than from
/// `RadioManager`, so the waterfall stays correct even when another
/// controller (a satellite tracker on the REMOTE jack) retunes the radio.
/// Each line is tagged with the band it came from; the IC-9700 streams one
/// band at a time and flips when the operator or tracker selects the other.
@MainActor
final class IcomWaterfallData {
    // MARK: Lifecycle

    init(store: WaterfallStore) {
        self.store = store
    }

    // MARK: Internal

    /// Band of the most recently rendered line, for the panel badge.
    private(set) var currentBand: CIVScopeBand?

    /// Whether a scope frame stream is currently attached.
    var isConsuming: Bool {
        consumeTask != nil
    }

    /// Start consuming scope frames from a transport's `scopeFrames` stream.
    func startConsuming(from stream: AsyncStream<CIVScopeFrame>) {
        stopConsuming()
        store.clear(producer: .icomMain)
        store.setReceiving(true, source: .icomMain)

        consumeTask = Task { [weak self] in
            var accumulator = CIVScopeAccumulator()
            for await frame in stream {
                guard !Task.isCancelled else {
                    break
                }
                if let line = accumulator.ingest(frame) {
                    self?.publish(line)
                }
            }
            self?.finishStream()
        }
    }

    func stopConsuming() {
        consumeTask?.cancel()
        consumeTask = nil
        finishStream()
    }

    // MARK: Private

    private let store: WaterfallStore
    private var consumeTask: Task<Void, Never>?

    private func publish(_ line: CIVScopeLine) {
        let source: WaterfallStore.Source = line.band == .sub ? .icomSub : .icomMain
        currentBand = line.band
        store.append(
            line: line.normalizedMagnitudes,
            centerMHz: line.centerMHz,
            spanKHz: line.spanKHz,
            source: source
        )
    }

    private func finishStream() {
        store.setReceiving(false, source: .icomMain)
        store.setReceiving(false, source: .icomSub)
        currentBand = nil
    }
}
