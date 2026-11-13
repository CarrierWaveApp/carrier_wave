import CryptoKit
import Darwin
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "JttySidecarInstaller")

// MARK: - JttySidecarRelease

/// The jtty-sidecar release CW Sweep drives. The helper is GPLv3 and runs as
/// its own process, so it is fetched on first use rather than bundled; the
/// SHA-256 is pinned here and checked before the download is ever executed.
enum JttySidecarRelease {
    static let version = "v0.2.1"
    static let downloadURL = URL(
        string: "https://github.com/DorsetDevStudio/jtty-sidecar/releases/download/"
            + "\(version)/jtty-sidecar-macos-universal"
    )!
    static let sha256 = "fed6380731915001e54773552482bf86b7b1dbb7ac7e5174fd9aa7ce675d7511"
    static let sourceURL = URL(string: "https://github.com/DorsetDevStudio/jtty-sidecar")!
    /// What `jtty-sidecar version` reports for the shared-memory contract we implement.
    static let protocolVersion: UInt32 = JttyShmLayout.version
}

// MARK: - JttySidecarInstaller

/// Downloads, verifies and stages the helper under Application Support, and
/// resolves which executable to run (a user-supplied path wins).
enum JttySidecarInstaller {
    // MARK: Internal

    enum InstallError: LocalizedError {
        case badResponse(Int)
        case checksumMismatch(expected: String, actual: String)
        case notExecutable(String)
        case unexpectedVersionOutput(String)

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case let .badResponse(code):
                "Download failed (HTTP \(code))"
            case let .checksumMismatch(expected, actual):
                "Downloaded helper did not match the pinned checksum (expected \(expected.prefix(12))…, got \(actual.prefix(12))…)"
            case let .notExecutable(path):
                "\(path) is not an executable file"
            case let .unexpectedVersionOutput(output):
                "Helper did not identify itself: \(output)"
            }
        }
    }

    /// `~/Library/Application Support/CWSweep/jtty-sidecar/<version>/`.
    static var installDirectory: URL {
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport
            .appendingPathComponent("CWSweep", isDirectory: true)
            .appendingPathComponent("jtty-sidecar", isDirectory: true)
            .appendingPathComponent(JttySidecarRelease.version, isDirectory: true)
    }

    static var installedURL: URL {
        installDirectory.appendingPathComponent("jtty-sidecar")
    }

    /// The executable to run: a user-chosen path if it exists, else the staged download.
    static func resolve(customPath: String?) -> URL? {
        if let customPath, !customPath.isEmpty {
            let url = URL(fileURLWithPath: (customPath as NSString).expandingTildeInPath)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        return FileManager.default.isExecutableFile(atPath: installedURL.path) ? installedURL : nil
    }

    /// Fetch the pinned release, verify its SHA-256, mark it executable and
    /// strip the quarantine flag (we verified the bytes ourselves). Returns
    /// the staged executable.
    static func install(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: JttySidecarRelease.downloadURL)
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw InstallError.badResponse(http.statusCode)
        }
        let expected = response.expectedContentLength
        var data = Data()
        data.reserveCapacity(expected > 0 ? Int(expected) : 6_000_000)
        var lastReport = Date.distantPast
        for try await byte in bytes {
            data.append(byte)
            if expected > 0, Date().timeIntervalSince(lastReport) > 0.2 {
                lastReport = Date()
                progress(Double(data.count) / Double(expected))
            }
        }
        progress(1)

        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == JttySidecarRelease.sha256 else {
            throw InstallError.checksumMismatch(expected: JttySidecarRelease.sha256, actual: digest)
        }

        let directory = installDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = installedURL
        try data.write(to: destination, options: .atomic)
        guard chmod(destination.path, 0o755) == 0 else {
            throw InstallError.notExecutable(destination.path)
        }
        // URLSession may tag the file; the bytes were just verified against
        // the pinned digest, so let it run without a Gatekeeper prompt.
        _ = removexattr(destination.path, "com.apple.quarantine", 0)
        logger.info("Installed jtty-sidecar \(JttySidecarRelease.version) at \(destination.path)")
        return destination
    }

    /// Run `jtty-sidecar version` and return its first line (e.g. "jtty-sidecar 0.2.1").
    static func reportedVersion(of executable: URL) async throws -> String {
        let output = try await run(executable, arguments: ["version"])
        guard let first = output.split(separator: "\n").first, first.contains("jtty-sidecar") else {
            throw InstallError.unexpectedVersionOutput(output)
        }
        return String(first)
    }

    // MARK: Private

    private static func run(_ executable: URL, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
