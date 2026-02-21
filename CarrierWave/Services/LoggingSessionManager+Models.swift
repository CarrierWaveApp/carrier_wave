import Foundation

// MARK: - SessionNoteEntry

/// A parsed note entry from session notes
struct SessionNoteEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let displayTime: String
    let text: String

    /// Parse a note line in format "[ISO8601|HH:mm] text" or legacy "[HH:mm] text"
    static func parse(_ line: String) -> SessionNoteEntry? {
        // Try new format first: [ISO8601|HH:mm] text
        if let bracketEnd = line.firstIndex(of: "]"),
           line.first == "["
        {
            let bracketContent = String(line[line.index(after: line.startIndex) ..< bracketEnd])
            let text = String(line[line.index(after: bracketEnd)...]).trimmingCharacters(
                in: .whitespaces
            )

            // Check for new format with pipe separator
            if let pipeIndex = bracketContent.firstIndex(of: "|") {
                let isoString = String(bracketContent[..<pipeIndex])
                let displayTime = String(bracketContent[bracketContent.index(after: pipeIndex)...])

                let isoFormatter = ISO8601DateFormatter()
                if let timestamp = isoFormatter.date(from: isoString) {
                    return SessionNoteEntry(
                        timestamp: timestamp,
                        displayTime: displayTime,
                        text: text
                    )
                }
            }

            // Legacy format: [HH:mm] text - use today's date with that time
            let displayTime = bracketContent
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            formatter.timeZone = TimeZone(identifier: "UTC")

            // For legacy notes, we can't determine the exact date, so use a very old date
            // This will sort them before any new-format notes from today
            if let timeComponents = formatter.date(from: displayTime) {
                let calendar = Calendar.current
                // Use the time components with a base date of 1970
                var components = calendar.dateComponents([.hour, .minute], from: timeComponents)
                components.year = 1_970
                components.month = 1
                components.day = 1
                if let legacyDate = calendar.date(from: components) {
                    return SessionNoteEntry(
                        timestamp: legacyDate,
                        displayTime: displayTime,
                        text: text
                    )
                }
            }
        }

        return nil
    }
}

// MARK: - SessionLogEntry

/// A unified entry in the session log (either a QSO or a note)
enum SessionLogEntry: Identifiable {
    case qso(QSO)
    case note(SessionNoteEntry)

    // MARK: Internal

    var id: String {
        switch self {
        case let .qso(qso):
            "qso-\(qso.id)"
        case let .note(note):
            "note-\(note.id)"
        }
    }

    var timestamp: Date {
        switch self {
        case let .qso(qso):
            qso.timestamp
        case let .note(note):
            note.timestamp
        }
    }

    /// Combine QSOs and notes into a sorted list
    static func combine(qsos: [QSO], notes: [SessionNoteEntry]) -> [SessionLogEntry] {
        var entries: [SessionLogEntry] = []

        entries.append(contentsOf: qsos.map { .qso($0) })
        entries.append(contentsOf: notes.map { .note($0) })

        // Sort by timestamp, most recent first
        return entries.sorted { $0.timestamp > $1.timestamp }
    }
}
