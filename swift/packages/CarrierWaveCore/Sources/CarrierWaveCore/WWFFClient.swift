import CarrierWaveCwFfi
import Foundation

// MARK: - WWFFError

public enum WWFFError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)
    case parseError(String)

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from WWFF Spotline"
        case let .httpError(code):
            "WWFF Spotline returned HTTP \(code)"
        case let .parseError(message):
            "WWFF parse error: \(message)"
        }
    }
}

// MARK: - WWFFClient

/// Client for the WWFF Spotline site (spots.wwff.co).
/// Fetches active spots and scheduled agendas by scraping HTML tables
/// (the old JSON API was removed when the site was redesigned).
/// Spot HTML parsing is delegated to the shared Rust core (`cw_net::wwff`);
/// agenda HTML parsing remains in Swift.
public actor WWFFClient {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// Fetch all recent WWFF spots (includes DX cluster and RBN autospots).
    public func fetchSpots() async throws -> [WWFFSpot] {
        let html = try await fetchHTML("\(baseURL)/spots")
        return WWFFSpot.decodeResponse(html)
    }

    /// Fetch spots for a specific activator callsign (client-side filter).
    public func fetchSpots(for callsign: String) async throws -> [WWFFSpot] {
        let allSpots = try await fetchSpots()
        let upper = callsign.uppercased()
        return allSpots.filter { $0.activator.uppercased() == upper }
    }

    /// Fetch the WWFF agenda (scheduled upcoming activations).
    public func fetchAgenda() async throws -> [WWFFAgendaItem] {
        let html = try await fetchHTML("\(baseURL)/agenda")
        return Self.parseAgendaHTML(html)
    }

    /// Fetch agenda items for a specific activator callsign (client-side filter).
    public func fetchAgenda(for callsign: String) async throws -> [WWFFAgendaItem] {
        let allItems = try await fetchAgenda()
        let upper = callsign.uppercased()
        return allItems.filter { $0.activator.uppercased() == upper }
    }

    // MARK: Internal

    // MARK: - Agenda HTML Parsing

    /// Parse agenda items from the WWFF Spotline agenda HTML table.
    /// Each row has: Status, Start, End, Callsign, Reference, Reference Name,
    /// Band, Mode, Comments, Actions.
    static func parseAgendaHTML(_ html: String) -> [WWFFAgendaItem] {
        let rows = extractTableRows(from: html)
        var items: [WWFFAgendaItem] = []

        for (index, row) in rows.enumerated() {
            let cells = extractCells(from: row)

            guard let activator = cells["Callsign"], !activator.isEmpty,
                  let reference = cells["Reference"], !reference.isEmpty,
                  let startTime = cells["Start"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !startTime.isEmpty
            else {
                continue
            }

            let item = WWFFAgendaItem(
                id: index,
                activator: activator,
                reference: reference,
                referenceInfo: cells["Reference Name"],
                startTime: startTime,
                endTime: cells["End"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                frequencies: cells["Band"],
                modes: cells["Mode"],
                comments: cells["Comments"]
            )
            items.append(item)
        }

        return items
    }

    // MARK: Private

    private let baseURL = "https://spots.wwff.co"

    /// Extract table rows from the first <tbody> in the HTML.
    private static func extractTableRows(from html: String) -> [String] {
        guard let tbodyStart = html.range(of: "<tbody>"),
              let tbodyEnd = html.range(of: "</tbody>", range: tbodyStart.upperBound ..< html.endIndex)
        else {
            return []
        }

        let tbody = String(html[tbodyStart.upperBound ..< tbodyEnd.lowerBound])

        var rows: [String] = []
        var searchStart = tbody.startIndex
        while let trStart = tbody.range(of: "<tr", range: searchStart ..< tbody.endIndex),
              let trEnd = tbody.range(of: "</tr>", range: trStart.upperBound ..< tbody.endIndex)
        {
            rows.append(String(tbody[trStart.lowerBound ..< trEnd.upperBound]))
            searchStart = trEnd.upperBound
        }

        return rows
    }

    /// Extract cell values keyed by data-label from a table row.
    private static func extractCells(from row: String) -> [String: String] {
        var cells: [String: String] = [:]

        var searchStart = row.startIndex
        while let labelStart = row.range(of: "data-label=\"", range: searchStart ..< row.endIndex) {
            let afterQuote = labelStart.upperBound
            guard let labelEnd = row.range(of: "\"", range: afterQuote ..< row.endIndex) else {
                break
            }
            let label = String(row[afterQuote ..< labelEnd.lowerBound])

            guard let tagClose = row.range(of: ">", range: labelEnd.upperBound ..< row.endIndex) else {
                break
            }

            guard let tdEnd = row.range(of: "</td>", range: tagClose.upperBound ..< row.endIndex) else {
                break
            }

            let rawContent = String(row[tagClose.upperBound ..< tdEnd.lowerBound])
            let cleaned = Self.stripHTML(rawContent)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            cells[label] = cleaned
            searchStart = tdEnd.upperBound
        }

        return cells
    }

    /// Strip HTML tags from a string.
    private static func stripHTML(_ html: String) -> String {
        var result = html
        while let tagStart = result.range(of: "<"),
              let tagEnd = result.range(of: ">", range: tagStart.upperBound ..< result.endIndex)
        {
            result.removeSubrange(tagStart.lowerBound ... tagEnd.lowerBound)
        }
        result = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        return result
    }

    private func fetchHTML(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw WWFFError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw WWFFError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw WWFFError.httpError(http.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw WWFFError.parseError("Could not decode HTML")
        }
        return html
    }
}
