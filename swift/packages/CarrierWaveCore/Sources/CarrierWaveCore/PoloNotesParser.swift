// Polo Notes Parser
//
// Parses Ham2K Polo notes list files into PoloNotesEntry objects.
// Shared between Carrier Wave (iOS) and CW Sweep (macOS).

import CarrierWaveCwFfi
import Foundation

// MARK: - PoloNotesParser

/// Parses Ham2K Polo notes list files into PoloNotesEntry objects.
///
/// The line grammar and the leading-emoji / name / note split live in the
/// shared Rust core (`cw_domain::polo_notes`); this enum is a thin facade.
public enum PoloNotesParser {
    /// Parse a Polo notes list file content into entries.
    /// - Parameter content: The raw text content of the notes file
    /// - Returns: Dictionary mapping callsigns (uppercase) to their entry
    public static func parse(_ content: String) -> [String: PoloNotesEntry] {
        parsePoloNotes(content: content).mapValues(PoloNotesEntry.init(ffi:))
    }

    /// Parse a single line from a Polo notes file.
    /// - Parameter line: A single line (not empty, not a comment)
    /// - Returns: PoloNotesEntry if the line could be parsed
    public static func parseLine(_ line: String) -> PoloNotesEntry? {
        parsePoloNoteLine(line: line).map(PoloNotesEntry.init(ffi:))
    }
}

// MARK: - Async Loading

public extension PoloNotesParser {
    /// Load and parse a Polo notes file from a URL
    /// - Parameter url: The URL to the notes file
    /// - Returns: Dictionary mapping callsigns to their entry
    static func load(from url: URL) async throws -> [String: PoloNotesEntry] {
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let content = String(data: data, encoding: .utf8) else {
            throw PoloNotesError.invalidEncoding
        }

        return parse(content)
    }

    /// Load and parse multiple Polo notes files, merging results
    /// - Parameter urls: Array of URLs to notes files
    /// - Returns: Merged dictionary mapping callsigns to their entry
    static func load(from urls: [URL]) async -> [String: PoloNotesEntry] {
        var merged: [String: PoloNotesEntry] = [:]

        await withTaskGroup(of: [String: PoloNotesEntry].self) { group in
            for url in urls {
                group.addTask {
                    await (try? load(from: url)) ?? [:]
                }
            }

            for await result in group {
                // Later entries override earlier ones
                merged.merge(result) { _, new in new }
            }
        }

        return merged
    }
}

// MARK: - PoloNotesError

public enum PoloNotesError: LocalizedError {
    case invalidEncoding
    case networkError(Error)

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            "Unable to decode notes file as UTF-8"
        case let .networkError(error):
            "Failed to download notes file: \(error.localizedDescription)"
        }
    }
}
