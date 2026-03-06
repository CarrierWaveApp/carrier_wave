import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - CallsignInfoSource

/// Source of callsign information
enum CallsignInfoSource: String, Codable, Sendable {
    /// From a Polo notes list (local, offline)
    case poloNotes
    /// From QRZ XML callbook API
    case qrz
    /// From HamDB.org API (free, US callsigns)
    case hamdb
}

// MARK: - CallsignInfo

/// Information about a callsign from lookup services
struct CallsignInfo: Codable, Identifiable, Equatable, Sendable {
    // MARK: Lifecycle

    nonisolated init(
        callsign: String,
        name: String? = nil,
        firstName: String? = nil,
        nickname: String? = nil,
        note: String? = nil,
        emoji: String? = nil,
        qth: String? = nil,
        state: String? = nil,
        country: String? = nil,
        grid: String? = nil,
        licenseClass: String? = nil,
        previousCallsign: String? = nil,
        source: CallsignInfoSource,
        lookupDate: Date = Date(),
        allEmojis: [String]? = nil,
        matchingSources: [String]? = nil,
        callsignChangeNote: String? = nil
    ) {
        self.callsign = callsign.uppercased()
        self.name = name
        self.firstName = firstName
        self.nickname = nickname
        self.note = note
        self.emoji = emoji
        self.qth = qth
        self.state = state
        self.country = country
        self.grid = grid
        self.licenseClass = licenseClass
        self.previousCallsign = previousCallsign
        self.source = source
        self.lookupDate = lookupDate
        self.allEmojis = allEmojis
        self.matchingSources = matchingSources
        self.callsignChangeNote = callsignChangeNote
    }

    // MARK: Internal

    /// The callsign (always uppercase)
    let callsign: String

    /// Operator full name (first + last) or just name from Polo notes
    let name: String?

    /// First name only (from QRZ)
    let firstName: String?

    /// Nickname (from QRZ)
    let nickname: String?

    /// Note from Polo notes list (e.g., "POTA activator")
    let note: String?

    /// Emoji from Polo notes list (e.g., "🌳")
    let emoji: String?

    /// City/QTH
    let qth: String?

    /// State/province
    let state: String?

    /// Country
    let country: String?

    /// Grid square
    let grid: String?

    /// License class (e.g., "Extra", "General")
    let licenseClass: String?

    /// Previous callsign (from QRZ `p_call` field)
    let previousCallsign: String?

    /// Where this information came from
    let source: CallsignInfoSource

    /// When this lookup was performed
    let lookupDate: Date

    /// All emojis from matching sources (for merged display)
    let allEmojis: [String]?

    /// Source titles that matched this callsign
    let matchingSources: [String]?

    /// Note when HamDB shows a different name than QRZ (callsign recently changed owners)
    let callsignChangeNote: String?

    /// Unique identifier (the callsign)
    nonisolated var id: String {
        callsign
    }

    /// Display name for the operator, prioritizing nickname > firstName > name.
    /// Normalizes casing to title case (e.g., "JOHN SMITH" → "John Smith").
    nonisolated var displayName: String? {
        if let nickname, !nickname.isEmpty {
            return nickname.capitalized
        }
        if let firstName, !firstName.isEmpty {
            return firstName.capitalized
        }
        if let name, !name.isEmpty {
            return name.capitalized
        }
        return nil
    }

    /// Full location string (city, state, country)
    nonisolated var fullLocation: String? {
        let parts = [qth, state, country].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Whether this info is from a local source (fast, offline)
    nonisolated var isLocal: Bool {
        source == .poloNotes
    }

    /// Age of this lookup in seconds
    nonisolated var age: TimeInterval {
        Date().timeIntervalSince(lookupDate)
    }

    /// Combined emoji string from all sources
    nonisolated var combinedEmoji: String? {
        if let emojis = allEmojis, !emojis.isEmpty {
            return emojis.joined()
        }
        return emoji
    }
}

// MARK: - CallsignInfo + Polo Notes

extension CallsignInfo {
    /// Create from a Polo notes entry
    /// - Parameters:
    ///   - callsign: The callsign
    ///   - noteText: The note text (may contain emoji and name)
    static func fromPoloNotes(callsign: String, noteText: String) -> CallsignInfo {
        let entry = PoloNotesEntry.fromNoteText(callsign: callsign, noteText: noteText)
        return CallsignInfo(
            callsign: entry.callsign,
            name: entry.name,
            note: entry.note,
            emoji: entry.emoji,
            source: .poloNotes
        )
    }
}

// MARK: - CallsignInfo + Note Markdown

extension CallsignInfo {
    /// Parse note text containing markdown links into an AttributedString.
    /// Uses manual link detection instead of AttributedString(markdown:) which
    /// clips brackets from links whose URLs contain special characters like @.
    static func parseNoteMarkdown(_ text: String) -> AttributedString {
        // swiftlint:disable:next force_try
        let pattern = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#)
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, range: nsRange)

        guard !matches.isEmpty else {
            return AttributedString(text)
        }

        var result = AttributedString()
        var cursor = text.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: text),
                  let linkTextRange = Range(match.range(at: 1), in: text),
                  let urlRange = Range(match.range(at: 2), in: text)
            else {
                continue
            }

            if cursor < matchRange.lowerBound {
                result.append(AttributedString(String(text[cursor ..< matchRange.lowerBound])))
            }

            var linkAttr = AttributedString(String(text[linkTextRange]))
            if let url = URL(string: String(text[urlRange])) {
                linkAttr.link = url
            }
            result.append(linkAttr)
            cursor = matchRange.upperBound
        }

        if cursor < text.endIndex {
            result.append(AttributedString(String(text[cursor...])))
        }

        return result
    }
}
