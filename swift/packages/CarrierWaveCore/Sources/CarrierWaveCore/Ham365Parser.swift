import Foundation

// MARK: - Ham365Parser

/// Parses Ham365.net DXpedition calendar HTML into structured data.
///
/// The HTML table has this structure:
/// - Row 0: Entity names in `<td class="rotate">` cells with `<div>` text
/// - Row 1: Callsigns in plain `<td>` cells
/// - Row 2: Color indicator row (skip)
/// - Row 3: "DAY" header row (skip)
/// - Rows 4+: Day rows — first cell is day number, remaining cells are colored if active
///
/// Header cells may contain `onair.gif` indicating the station is currently on air.
public enum Ham365Parser {
    // MARK: Public

    /// Parse DXpedition calendar HTML for the given month/year.
    public static func parse(html: String, month: Int, year: Int) -> [Ham365DXpedition] {
        let rows = extractRows(from: html)
        guard rows.count >= 5 else {
            return []
        }

        let entities = extractEntities(from: rows[0])
        let callsigns = extractCallsigns(from: rows[1])
        let onAirFlags = extractOnAirFlags(from: rows[0])

        let expeditionCount = min(entities.count, callsigns.count)
        guard expeditionCount > 0 else {
            return []
        }

        // Build per-expedition active days from day rows (rows 4+)
        var activeDaysByIndex: [Int: Set<Int>] = [:]
        for rowIndex in 4 ..< rows.count {
            let cells = extractCells(from: rows[rowIndex])
            guard let dayNumber = extractDayNumber(from: cells) else {
                continue
            }
            // Data cells start at index 1 (after the day number cell)
            for cellIndex in 1 ..< cells.count {
                let expIndex = cellIndex - 1
                guard expIndex < expeditionCount else {
                    break
                }
                if isCellActive(cells[cellIndex]) {
                    activeDaysByIndex[expIndex, default: []].insert(dayNumber)
                }
            }
        }

        var results: [Ham365DXpedition] = []
        for idx in 0 ..< expeditionCount {
            let callsign = callsigns[idx]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !callsign.isEmpty else {
                continue
            }

            let entity = entities[idx]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isOnAir = idx < onAirFlags.count && onAirFlags[idx]

            results.append(Ham365DXpedition(
                callsign: callsign,
                entity: entity,
                activeDays: activeDaysByIndex[idx] ?? [],
                isOnAir: isOnAir,
                month: month,
                year: year
            ))
        }

        return results
    }

    // MARK: Internal

    // MARK: - Private Helpers

    /// Split HTML into table rows by `<tr` tags.
    static func extractRows(from html: String) -> [String] {
        html.components(separatedBy: "<tr")
            .dropFirst() // before first <tr
            .map { row in
                // Take content up to </tr>
                if let end = row.range(of: "</tr>") {
                    return String(row[row.startIndex ..< end.lowerBound])
                }
                return row
            }
    }

    /// Extract entity names from the first row's rotated `<div>` elements.
    /// Skips leading non-rotate cells (e.g. the "Dx-peditions" rowspan header).
    static func extractEntities(from row: String) -> [String] {
        let cells = extractCells(from: row)
        return cells.compactMap { cell in
            // Only include cells with class="rotate" — skip header/label cells
            guard cell.contains("rotate") else {
                return nil
            }
            let inner = cellText(cell)
            return inner.isEmpty ? nil : inner
        }
    }

    /// Extract callsigns from the second row.
    /// Skips leading non-rotate cells (covered by the rowspan header).
    static func extractCallsigns(from row: String) -> [String] {
        let cells = extractCells(from: row)
        return cells.compactMap { cell in
            guard cell.contains("rotate") else {
                return nil
            }
            let text = cellText(cell)
            return text.isEmpty ? nil : text
        }
    }

    /// Check which header cells contain onair.gif.
    /// Only considers rotate cells to stay aligned with entity/callsign arrays.
    static func extractOnAirFlags(from row: String) -> [Bool] {
        let cells = extractCells(from: row)
        return cells.compactMap { cell in
            guard cell.contains("rotate") else {
                return nil
            }
            return cell.contains("onair.gif")
        }
    }

    /// Split a row into `<td` cells.
    /// Each cell includes the tag attributes (for bgcolor checks) and inner content.
    static func extractCells(from row: String) -> [String] {
        row.components(separatedBy: "<td")
            .dropFirst()
            .map { cell in
                if let end = cell.range(of: "</td>") {
                    return String(cell[cell.startIndex ..< end.lowerBound])
                }
                return cell
            }
    }

    /// Extract the text content from a cell, skipping past the `<td ...>` closing bracket.
    static func cellText(_ cell: String) -> String {
        let content: Substring = if let tagClose = cell.range(of: ">") {
            cell[tagClose.upperBound...]
        } else {
            cell[...]
        }
        return stripHTML(String(content))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract the day number from the first cell of a day row.
    static func extractDayNumber(from cells: [String]) -> Int? {
        guard let firstCell = cells.first else {
            return nil
        }
        return Int(cellText(firstCell))
    }

    /// Check if a cell has a background color indicating activity.
    /// Active cells have `bgcolor=` or `background-color:` with a non-white color.
    static func isCellActive(_ cell: String) -> Bool {
        // Active cells have bgcolor attribute or style background-color
        if cell.contains("bgcolor=") || cell.contains("background-color") {
            // White/empty backgrounds are not active
            let lowered = cell.lowercased()
            if lowered.contains("#ffffff") || lowered.contains("white") {
                return false
            }
            return true
        }
        return false
    }

    /// Strip HTML tags from a string.
    static func stripHTML(_ input: String) -> String {
        var result = input
        // Remove HTML tags
        while let tagStart = result.range(of: "<"),
              let tagEnd = result[tagStart.upperBound...].range(of: ">")
        {
            result.removeSubrange(tagStart.lowerBound ... tagEnd.lowerBound)
        }
        // Decode common HTML entities
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        return result
    }
}
