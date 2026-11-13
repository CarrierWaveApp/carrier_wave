import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "JttySidecarProcess")

// MARK: - JttySidecarProcess

/// Runs `jtty-sidecar serve <name> --parent <pid>` and relays its stderr. The
/// `--parent` flag makes the helper exit by itself if CW Sweep dies, so a
/// crash never leaves a modem process behind.
final class JttySidecarProcess: @unchecked Sendable {
    // MARK: Lifecycle

    init(executable: URL, segmentName: String) {
        self.executable = executable
        self.segmentName = segmentName
    }

    // MARK: Internal

    let executable: URL
    let segmentName: String

    /// One stderr line at a time, off the main thread.
    var onLog: (@Sendable (String) -> Void)?
    /// Fired once when the process exits, with its status.
    var onExit: (@Sendable (Int32) -> Void)?

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    var processIdentifier: Int32? {
        process?.processIdentifier
    }

    func start() throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["serve", segmentName, "--parent", String(getpid())]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        let onLog = onLog
        let lines = LineBuffer()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            for line in lines.append(String(decoding: data, as: UTF8.self)) {
                logger.debug("jtty-sidecar: \(line)")
                onLog?(line)
            }
        }
        let onExit = onExit
        process.terminationHandler = { finished in
            stderr.fileHandleForReading.readabilityHandler = nil
            onExit?(finished.terminationStatus)
        }
        try process.run()
        self.process = process
        let name = segmentName
        logger.info("Started jtty-sidecar pid \(process.processIdentifier) serving \(name)")
    }

    /// Ask nicely, then insist. The caller normally sends `JTTY_CMD_QUIT`
    /// through the segment first; this is the backstop.
    func terminate() {
        guard let process, process.isRunning else {
            return
        }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    // MARK: Private

    private var process: Process?
}

// MARK: - LineBuffer

/// Splits a byte stream into complete lines; safe to feed from the pipe's
/// readability handler, which runs on an arbitrary queue.
private final class LineBuffer: @unchecked Sendable {
    // MARK: Internal

    /// Append a chunk and return every complete, non-empty line it closed.
    func append(_ chunk: String) -> [String] {
        lock.withLock {
            pending += chunk
            var lines: [String] = []
            while let newline = pending.firstIndex(of: "\n") {
                let line = String(pending[..<newline])
                pending = String(pending[pending.index(after: newline)...])
                if !line.isEmpty {
                    lines.append(line)
                }
            }
            return lines
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var pending = ""
}
