import Foundation

// MARK: - Ham365Error

public enum Ham365Error: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from Ham365"
        case let .httpError(code):
            "Ham365 returned HTTP \(code)"
        }
    }
}

// MARK: - Ham365Client

/// Client for Ham365.net DXpedition calendar.
/// Fetches and parses the HTML calendar to produce structured DXpedition data.
public actor Ham365Client {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// Fetch DXpeditions for a given month/year.
    /// - Parameters:
    ///   - month: Calendar month (1-12)
    ///   - year: Calendar year
    /// - Returns: Parsed DXpedition entries for the month.
    public func fetchDXpeditions(month: Int, year: Int) async throws -> [Ham365DXpedition] {
        guard let url = URL(string: baseURL) else {
            throw Ham365Error.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.timeoutInterval = 15
        request.httpBody = Data("month=\(month)&year=\(year)&options=V*".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw Ham365Error.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw Ham365Error.httpError(http.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw Ham365Error.invalidResponse
        }

        return Ham365Parser.parse(html: html, month: month, year: year)
    }

    // MARK: Private

    private let baseURL = "https://www.ham365.net/DxPeditionsPlan/DxPeditionsPartialView"
}
