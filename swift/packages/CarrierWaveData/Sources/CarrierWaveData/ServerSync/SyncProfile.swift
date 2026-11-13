import Foundation

// MARK: - SyncRunSummary

/// Push/pull QSO counts + wall-clock duration from the last manual sync run.
public struct SyncRunSummary: Equatable, Sendable {
    // MARK: Lifecycle

    public init(pushed: Int, pulled: Int, seconds: Double) {
        self.pushed = pushed
        self.pulled = pulled
        self.seconds = seconds
    }

    // MARK: Public

    public let pushed: Int
    public let pulled: Int
    public let seconds: Double
}

// MARK: - SyncProfile

/// Detailed, shareable per-phase profile of a sync run.
public struct SyncProfile: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        startedAt: Date, server: String, fullUpload: Bool,
        prepareSeconds: Double, downloadSeconds: Double, uploadSeconds: Double, totalSeconds: Double,
        pushed: Int, pulled: Int, cursorBefore: Int64, cursorAfter: Int64
    ) {
        self.startedAt = startedAt
        self.server = server
        self.fullUpload = fullUpload
        self.prepareSeconds = prepareSeconds
        self.downloadSeconds = downloadSeconds
        self.uploadSeconds = uploadSeconds
        self.totalSeconds = totalSeconds
        self.pushed = pushed
        self.pulled = pulled
        self.cursorBefore = cursorBefore
        self.cursorAfter = cursorAfter
    }

    // MARK: Public

    public let startedAt: Date
    public let server: String
    public let fullUpload: Bool
    public let prepareSeconds: Double
    public let downloadSeconds: Double
    public let uploadSeconds: Double
    public let totalSeconds: Double
    public let pushed: Int
    public let pulled: Int
    public let cursorBefore: Int64
    public let cursorAfter: Int64

    public var report: String {
        let formatter = ISO8601DateFormatter()
        return """
        Carrier Wave — sync profile
        \(formatter.string(from: startedAt))
        Server: \(server)
        Mode: \(fullUpload ? "Full upload (mark-all-dirty)" : "Incremental")

        Total: \(String(format: "%.1fs", totalSeconds))
        • Prepare:  \(String(format: "%.2fs", prepareSeconds))
        • Download: \(String(format: "%.2fs", downloadSeconds))  \(pulled) QSOs  (\(rate(pulled, downloadSeconds)))
        • Upload:   \(String(format: "%.2fs", uploadSeconds))  \(pushed) QSOs  (\(rate(pushed, uploadSeconds)))

        Cursor: \(cursorBefore) → \(cursorAfter)
        """
    }

    // MARK: Private

    /// Throughput, or "—" when nothing moved / no meaningful time elapsed.
    private func rate(_ count: Int, _ seconds: Double) -> String {
        guard count > 0, seconds > 0.05 else {
            return "—"
        }
        return String(format: "%.0f QSO/s", Double(count) / seconds)
    }
}
