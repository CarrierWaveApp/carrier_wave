import Foundation

// MARK: - TextProtocolParser

/// Shared parsing utilities for text-based radio protocols (Kenwood, Yaesu).
public enum TextProtocolParser {
    /// Extract complete `;`-terminated responses from a text buffer.
    /// Returns parsed response strings (without terminator) and bytes consumed.
    /// Unconsumed characters should be retained for subsequent calls.
    public static func extractResponses(
        from buffer: String
    ) -> (responses: [String], consumed: Int) {
        var responses: [String] = []
        var consumed = 0
        var remaining = buffer[...]

        while let semiIdx = remaining.firstIndex(of: ";") {
            let response = String(remaining[remaining.startIndex ..< semiIdx])
            if !response.isEmpty {
                responses.append(response)
            }
            let afterSemi = remaining.index(after: semiIdx)
            consumed = buffer.distance(from: buffer.startIndex, to: afterSemi)
            remaining = remaining[afterSemi...]
        }

        return (responses, consumed)
    }
}
