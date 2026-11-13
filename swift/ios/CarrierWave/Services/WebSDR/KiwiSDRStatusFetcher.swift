import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - KiwiSDRStatusFetcher

/// Fetches and parses `/status` from individual KiwiSDR receivers.
/// Delegates to the Rust core (`SdrApi`), which owns the HTTP fetch (5 s
/// timeout, max 5 in flight) and the key=value parsing; antenna descriptions
/// are re-parsed locally for the UI's `ParsedAntenna` display.
actor KiwiSDRStatusFetcher {
    // MARK: Internal

    /// Enriched receiver status from `/status` endpoint.
    /// Explicitly nonisolated — pure value type crossing actor boundaries.
    nonisolated struct ReceiverStatus {
        let hostPort: String
        let antenna: String
        let parsedAntenna: ParsedAntenna
        let bandsHz: String?
        let snrAll: Int?
        let snrHF: Int?
        let antConnected: Bool
        let grid: String?
        let asl: Int?
        let users: Int
        let usersMax: Int
        let uptime: Int?
        let softwareVersion: String?
    }

    static let shared = KiwiSDRStatusFetcher()

    /// Fetch /status for multiple receivers concurrently (max 5 in flight).
    /// Results stream back as they arrive.
    func fetchStatuses(
        for receivers: [KiwiSDRReceiver]
    ) -> AsyncStream<ReceiverStatus> {
        guard let api = try? SdrApiProvider.shared() else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        let (stream, continuation) = AsyncStream<ReceiverStatus>.makeStream()
        let listener = StatusListener(continuation: continuation)
        let targets = receivers.map(\.ffiReceiver)
        Task {
            await api.enrichStatuses(receivers: targets, listener: listener)
        }
        return stream
    }

    /// Fetch single receiver /status (5s timeout)
    func fetchStatus(host: String, port: Int) async -> ReceiverStatus? {
        guard let api = try? SdrApiProvider.shared() else {
            return nil
        }
        let status = await api.fetchReceiverStatus(host: host, port: UInt16(port))
        return status.map(ReceiverStatus.init(ffi:))
    }

    // MARK: Private

    /// Bridges Rust status callbacks into the AsyncStream. Called from Rust
    /// worker threads; the continuation is the only state touched.
    private final class StatusListener: SdrStatusListener, @unchecked Sendable {
        // MARK: Lifecycle

        init(continuation: AsyncStream<ReceiverStatus>.Continuation) {
            self.continuation = continuation
        }

        // MARK: Internal

        func onStatus(status: FfiReceiverStatus) {
            continuation.yield(ReceiverStatus(ffi: status))
        }

        func onComplete() {
            continuation.finish()
        }

        // MARK: Private

        private let continuation: AsyncStream<ReceiverStatus>.Continuation
    }
}

nonisolated extension KiwiSDRStatusFetcher.ReceiverStatus {
    /// Map from the Rust core's status record, re-parsing the antenna
    /// free-text for the UI.
    init(ffi: FfiReceiverStatus) {
        hostPort = ffi.hostPort
        antenna = ffi.antenna
        parsedAntenna = AntennaDescriptionParser.parse(ffi.antenna)
        bandsHz = ffi.bandsHz
        snrAll = ffi.snrAll.map(Int.init)
        snrHF = ffi.snrHf.map(Int.init)
        antConnected = ffi.antConnected
        grid = ffi.grid
        asl = ffi.asl.map(Int.init)
        users = Int(ffi.users)
        usersMax = Int(ffi.usersMax)
        uptime = ffi.uptime.map(Int.init)
        softwareVersion = ffi.softwareVersion
    }
}
