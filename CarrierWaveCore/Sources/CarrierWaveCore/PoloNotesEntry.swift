// Polo Notes Entry
//
// Shared data type for parsed Polo notes entries.
// Used by both Carrier Wave (iOS) and CW Sweep (macOS).

import Foundation

// MARK: - PoloNotesEntry

/// A parsed entry from a Polo notes list file
public struct PoloNotesEntry: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        callsign: String,
        emoji: String? = nil,
        name: String? = nil,
        note: String? = nil
    ) {
        self.callsign = callsign.uppercased()
        self.emoji = emoji
        self.name = name
        self.note = note
    }

    // MARK: Public

    /// The callsign (always uppercase)
    public let callsign: String

    /// Leading emoji from the note text (e.g., "🌳")
    public let emoji: String?

    /// Operator name parsed from the note text
    public let name: String?

    /// Note text (everything after name, may contain markdown links)
    public let note: String?

    /// Parse a Polo notes entry from callsign and note text
    public static func fromNoteText(callsign: String, noteText: String) -> PoloNotesEntry {
        let (emoji, remainingText) = extractLeadingEmoji(from: noteText)

        let trimmedNote = remainingText.trimmingCharacters(in: .whitespaces)

        // Collect leading plain-text words as name; everything from the first
        // non-text emoji or "[" (markdown link) onward becomes the note.
        let splitIndex = findNameEnd(in: trimmedNote)

        let name: String?
        let note: String?

        if splitIndex == trimmedNote.startIndex {
            name = nil
            note = trimmedNote.isEmpty ? nil : trimmedNote
        } else if splitIndex == trimmedNote.endIndex {
            name = trimmedNote
            note = nil
        } else {
            let nameStr = String(trimmedNote[..<splitIndex]).trimmingCharacters(in: .whitespaces)
            let noteStr = String(trimmedNote[splitIndex...]).trimmingCharacters(in: .whitespaces)
            name = nameStr.isEmpty ? nil : nameStr
            note = noteStr.isEmpty ? nil : noteStr
        }

        return PoloNotesEntry(
            callsign: callsign,
            emoji: emoji,
            name: name,
            note: note
        )
    }

    // MARK: Private

    /// Index where the name portion ends — stops at any non-ASCII emoji or `[`
    private static func findNameEnd(in text: String) -> String.Index {
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if char == "[" {
                return index
            }
            if isNonTextEmoji(char) {
                return index
            }
            index = text.index(after: index)
        }
        return text.endIndex
    }

    /// True for visual emoji (📺🌊🏠), false for ASCII chars that happen
    /// to have `isEmoji` (digits, #, *)
    private static func isNonTextEmoji(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else {
            return false
        }
        guard scalar.value > 0x7F else {
            return false
        }
        return scalar.properties.isEmoji
    }

    /// Extract leading emoji from text
    private static func extractLeadingEmoji(from text: String) -> (
        emoji: String?, remaining: String
    ) {
        var emojiChars: [Character] = []
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]
            if char.unicodeScalars.first?.properties.isEmoji == true, char != " " {
                emojiChars.append(char)
                index = text.index(after: index)
            } else {
                break
            }
        }

        if emojiChars.isEmpty {
            return (nil, text)
        }

        let emoji = String(emojiChars)
        let remaining = String(text[index...])
        return (emoji, remaining)
    }
}
