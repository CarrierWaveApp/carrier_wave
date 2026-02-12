import CarrierWaveCore
import Foundation

/// LoFiLogger that prints to stderr with level prefixes
struct ConsoleLogger: LoFiLogger {
    // MARK: Internal

    func info(_ message: String) {
        log("INFO", message)
    }

    func warning(_ message: String) {
        log("WARN", message)
    }

    func error(_ message: String) {
        log("ERROR", message)
    }

    func debug(_ message: String) {
        log("DEBUG", message)
    }

    // MARK: Private

    private func log(_ level: String, _ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        FileHandle.standardError.write(
            Data("[\(timestamp)] [\(level)] \(message)\n".utf8)
        )
    }
}
