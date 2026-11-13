import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "SCULAN10WaterfallData")

/// Display timer rate — matches the nominal ~25 fps scope source rate.
/// The intermediate buffer absorbs network jitter so the visual scroll
/// stays even regardless of packet arrival timing.
private let displayTickRate: TimeInterval = 1.0 / 25.0

// MARK: - SCULAN10WaterfallData

/// Producer that decrypts FTDX10 scope packets and pushes normalized lines
/// into the shared `WaterfallStore`. Was previously the store itself — now
/// it owns nothing observable; the store is the single source of truth so
/// any radio can publish through the same channel.
///
/// The FTDX10 scope packet contains 4096 bytes. Only the first ~1700 bins are
/// actual spectrum data (amplitude values where ~200=noise, lower=signal). The
/// boundary is marked by a fixed value of 1 at the separator bin. Everything
/// after is metadata, reference blocks, or secondary scope data.
@MainActor
final class SCULAN10WaterfallData {
    // MARK: Lifecycle

    init(store: WaterfallStore, geometryProvider: @escaping @MainActor () -> (centerMHz: Double, spanKHz: Double)) {
        self.store = store
        self.geometryProvider = geometryProvider
    }

    // MARK: Internal

    /// Number of pending lines waiting in the playback buffer (display only).
    private(set) var pendingLineCount: Int = 0

    /// Start consuming scope data from a transport's scope stream.
    func startConsuming(from stream: AsyncStream<Data>) {
        stopConsuming()
        store.clear(producer: .sculan10)
        store.setReceiving(true, source: .sculan10)

        consumeTask = Task { [weak self] in
            for await spectrumData in stream {
                guard !Task.isCancelled else {
                    break
                }
                self?.enqueueLine(spectrumData)
            }
            self?.store.setReceiving(false, source: .sculan10)
        }

        startDisplayTimer()
    }

    func stopConsuming() {
        consumeTask?.cancel()
        consumeTask = nil
        stopDisplayTimer()
        pendingBuffer.removeAll()
        pendingLineCount = 0
        store.setReceiving(false, source: .sculan10)
    }

    // MARK: Private

    private let store: WaterfallStore
    private let geometryProvider: @MainActor () -> (centerMHz: Double, spanKHz: Double)
    private var consumeTask: Task<Void, Never>?
    private var displayTimer: Timer?

    /// Intermediate buffer: parsed lines waiting to be promoted to the store.
    private var pendingBuffer: [[Float]] = []

    /// Parse a raw scope packet and queue the normalized line for display.
    private func enqueueLine(_ data: Data) {
        guard data.count >= 4_096 else {
            return
        }

        let spectrumEnd = findSpectrumEnd(data) / 2
        guard spectrumEnd > 50 else {
            return
        }

        var line = [Float](repeating: 0, count: spectrumEnd)
        for idx in 0 ..< spectrumEnd {
            line[idx] = max(0, 1.0 - (Float(data[idx]) / 255.0))
        }

        pendingBuffer.append(line)
        // Safety cap: if source outpaces the drain, drop oldest to prevent unbounded growth
        if pendingBuffer.count > 50 {
            pendingBuffer.removeFirst(pendingBuffer.count - 50)
        }
        pendingLineCount = pendingBuffer.count
    }

    /// Drain one line from the pending buffer into the shared store.
    private func drainBuffer() {
        guard !pendingBuffer.isEmpty else {
            return
        }

        let line = pendingBuffer.removeFirst()
        pendingLineCount = pendingBuffer.count

        let geometry = geometryProvider()
        store.append(
            line: line,
            centerMHz: geometry.centerMHz,
            spanKHz: geometry.spanKHz,
            source: .sculan10
        )
    }

    private func startDisplayTimer() {
        stopDisplayTimer()
        displayTimer = Timer.scheduledTimer(
            withTimeInterval: displayTickRate,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.drainBuffer()
            }
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    /// Find where actual spectrum data ends by looking for the structural
    /// marker (a bin with value 1 followed by a sharp transition).
    /// Falls back to scanning for the reference block (avg > 230).
    private func findSpectrumEnd(_ data: Data) -> Int {
        // Look for the marker: a single bin with value <= 1 after bin 500
        // (to avoid false positives from strong signals in the spectrum)
        if let marker = (500 ..< min(data.count, 3_000)).first(where: { data[$0] <= 1 }) {
            return marker
        }
        // Fallback: find the reference block (64-bin avg > 225)
        let blockSize = 64
        for blk in stride(from: 500, to: min(data.count - blockSize, 3_000), by: blockSize) {
            var blockSum = 0
            for idx in blk ..< blk + blockSize {
                blockSum += Int(data[idx])
            }
            if blockSum / blockSize > 225 {
                return max(100, blk - 100)
            }
        }
        return min(data.count, 2_000)
    }
}
