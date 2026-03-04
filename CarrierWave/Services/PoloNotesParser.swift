import CarrierWaveData
import Foundation

// MARK: - PoloNotesParser

/// Parses Ham2K Polo notes list files into CallsignInfo entries
enum PoloNotesParser {
    // MARK: Internal

    // MARK: - Public API

    /// Parse a Polo notes list file content into CallsignInfo entries
    /// - Parameter content: The raw text content of the notes file
    /// - Returns: Dictionary mapping callsigns (uppercase) to their info
    static func parse(_ content: String) -> [String: CallsignInfo] {
        var result: [String: CallsignInfo] = [:]

        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }

            // Parse the line: CALLSIGN note text
            if let entry = parseLine(trimmed) {
                result[entry.callsign.uppercased()] = entry
            }
        }

        return result
    }

    /// Parse a single line from a Polo notes file
    /// - Parameter line: A single line (not empty, not a comment)
    /// - Returns: CallsignInfo if the line could be parsed
    static func parseLine(_ line: String) -> CallsignInfo? {
        // Split on first whitespace to get callsign and note
        let components = line.components(separatedBy: .whitespaces)
        guard !components.isEmpty else {
            return nil
        }

        let callsign = components[0].uppercased()

        // Validate it looks like a callsign (basic check)
        guard isLikelyCallsign(callsign) else {
            return nil
        }

        // Everything after the callsign is the note
        let noteText = components.dropFirst().joined(separator: " ").trimmingCharacters(
            in: .whitespaces
        )

        if noteText.isEmpty {
            // Callsign only, no note
            return CallsignInfo(callsign: callsign, source: .poloNotes)
        }

        // Use the CallsignInfo helper to parse the note
        return CallsignInfo.fromPoloNotes(callsign: callsign, noteText: noteText)
    }

    // MARK: Private

    // MARK: - Private Helpers

    /// Basic check if string looks like a callsign
    private static func isLikelyCallsign(_ text: String) -> Bool {
        // Must be at least 3 characters
        guard text.count >= 3 else {
            return false
        }

        // Must contain letters
        guard text.contains(where: \.isLetter) else {
            return false
        }

        // Must contain at least one number
        guard text.contains(where: \.isNumber) else {
            return false
        }

        // Must not be all uppercase letters that could be words
        let commonWords = Set(["THE", "AND", "FOR", "ARE", "BUT", "NOT", "YOU", "ALL"])
        if commonWords.contains(text) {
            return false
        }

        return true
    }
}

// MARK: - Async Loading

extension PoloNotesParser {
    /// Load and parse a Polo notes file from a URL
    /// - Parameter url: The URL to the notes file
    /// - Returns: Dictionary mapping callsigns to their info
    static func load(from url: URL) async throws -> [String: CallsignInfo] {
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let content = String(data: data, encoding: .utf8) else {
            throw PoloNotesError.invalidEncoding
        }

        return parse(content)
    }

    /// Load and parse multiple Polo notes files, merging results
    /// - Parameter urls: Array of URLs to notes files
    /// - Returns: Merged dictionary mapping callsigns to their info
    static func load(from urls: [URL]) async -> [String: CallsignInfo] {
        var merged: [String: CallsignInfo] = [:]

        await withTaskGroup(of: [String: CallsignInfo].self) { group in
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

enum PoloNotesError: LocalizedError {
    case invalidEncoding
    case networkError(Error)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            "Unable to decode notes file as UTF-8"
        case let .networkError(error):
            "Failed to download notes file: \(error.localizedDescription)"
        }
    }
}
