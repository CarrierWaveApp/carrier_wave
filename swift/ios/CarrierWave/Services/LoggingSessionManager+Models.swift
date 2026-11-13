import CarrierWaveCore
import CarrierWaveData
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

// MARK: - SessionBoundaryMarker

/// A visual separator inserted into the session log at UTC day or shift boundaries.
struct SessionBoundaryMarker: Identifiable {
    enum Kind {
        case utcDayChange(dateLabel: String)
        case shiftStart(shift: POTAShift, window: ShiftWindow)
        case shiftEnd(shift: POTAShift, window: ShiftWindow)
    }

    let id = UUID()
    let timestamp: Date
    let kind: Kind
}

// MARK: - SessionLogEntry

/// A unified entry in the session log (QSO, note, or boundary marker)
enum SessionLogEntry: Identifiable {
    case qso(QSO)
    case note(SessionNoteEntry)
    case boundary(SessionBoundaryMarker)

    // MARK: Internal

    var id: String {
        switch self {
        case let .qso(qso):
            "qso-\(qso.id)"
        case let .note(note):
            "note-\(note.id)"
        case let .boundary(marker):
            "boundary-\(marker.id)"
        }
    }

    var timestamp: Date {
        switch self {
        case let .qso(qso):
            qso.timestamp
        case let .note(note):
            note.timestamp
        case let .boundary(marker):
            marker.timestamp
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

    /// Combine QSOs, notes, and boundary markers into a sorted list.
    /// Inserts UTC day change markers and POTA shift markers based on park longitude.
    static func combineWithBoundaries(
        qsos: [QSO],
        notes: [SessionNoteEntry],
        parkLongitude: Double?
    ) -> [SessionLogEntry] {
        var entries = combine(qsos: qsos, notes: notes)
        let markers = buildBoundaryMarkers(entries: entries, parkLongitude: parkLongitude)
        entries.append(contentsOf: markers.map { .boundary($0) })
        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: Private

    /// Build boundary markers for UTC day changes and shift transitions.
    private static func buildBoundaryMarkers(
        entries: [SessionLogEntry],
        parkLongitude: Double?
    ) -> [SessionBoundaryMarker] {
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else {
            return []
        }

        let dayKeyFmt = DateFormatter()
        dayKeyFmt.dateFormat = "yyyy-MM-dd"
        dayKeyFmt.timeZone = TimeZone(identifier: "UTC")

        var markers = buildUTCDayMarkers(sorted: sorted, dayKeyFmt: dayKeyFmt)

        if let longitude = parkLongitude {
            markers += buildShiftMarkers(sorted: sorted, longitude: longitude, dayKeyFmt: dayKeyFmt)
        }

        return markers
    }

    private static func buildUTCDayMarkers(
        sorted: [SessionLogEntry],
        dayKeyFmt: DateFormatter
    ) -> [SessionBoundaryMarker] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let displayFmt = DateFormatter()
        displayFmt.dateFormat = "MMM d, yyyy"
        displayFmt.timeZone = TimeZone(identifier: "UTC")

        var markers: [SessionBoundaryMarker] = []
        var seenDays: Set<String> = []
        if let first = sorted.first {
            seenDays.insert(dayKeyFmt.string(from: first.timestamp))
        }

        for idx in 1 ..< sorted.count {
            let currDay = dayKeyFmt.string(from: sorted[idx].timestamp)
            let prevDay = dayKeyFmt.string(from: sorted[idx - 1].timestamp)
            guard prevDay != currDay, !seenDays.contains(currDay) else {
                continue
            }
            seenDays.insert(currDay)
            markers.append(SessionBoundaryMarker(
                timestamp: cal.startOfDay(for: sorted[idx].timestamp),
                kind: .utcDayChange(dateLabel: displayFmt.string(from: sorted[idx].timestamp))
            ))
        }
        return markers
    }

    private static func buildShiftMarkers(
        sorted: [SessionLogEntry],
        longitude: Double,
        dayKeyFmt: DateFormatter
    ) -> [SessionBoundaryMarker] {
        var markers: [SessionBoundaryMarker] = []
        var seenStarts = Set<String>()
        var seenEnds = Set<String>()

        for idx in 1 ..< sorted.count {
            let prev = sorted[idx - 1]
            let curr = sorted[idx]

            for shift in POTAShift.allCases {
                let prevWin = shift.window(for: prev.timestamp, longitude: longitude)
                let currWin = shift.window(for: curr.timestamp, longitude: longitude)

                let startKey = "\(shift.rawValue)-\(dayKeyFmt.string(from: currWin.start))"
                if !seenStarts.contains(startKey),
                   !prevWin.contains(prev.timestamp),
                   currWin.contains(curr.timestamp)
                {
                    seenStarts.insert(startKey)
                    markers.append(SessionBoundaryMarker(
                        timestamp: currWin.start,
                        kind: .shiftStart(shift: shift, window: currWin)
                    ))
                }

                let endKey = "\(shift.rawValue)-\(dayKeyFmt.string(from: prevWin.start))"
                if !seenEnds.contains(endKey),
                   prevWin.contains(prev.timestamp),
                   !currWin.contains(curr.timestamp),
                   curr.timestamp >= prevWin.end
                {
                    seenEnds.insert(endKey)
                    markers.append(SessionBoundaryMarker(
                        timestamp: prevWin.end,
                        kind: .shiftEnd(shift: shift, window: prevWin)
                    ))
                }
            }
        }
        return markers
    }
}
