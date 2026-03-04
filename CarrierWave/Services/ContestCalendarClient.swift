import CarrierWaveData
import Foundation

// MARK: - ContestCalendarError

nonisolated enum ContestCalendarError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case notModified
    case rateLimited
    case invalidResponse(String)
    case parsingError(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid contest calendar URL"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case .notModified:
            "Content not modified (304)"
        case .rateLimited:
            "Contest calendar rate limit exceeded"
        case let .invalidResponse(message):
            "Invalid response: \(message)"
        case let .parsingError(message):
            "Parsing error: \(message)"
        }
    }
}

// MARK: - ContestCalendarClient

/// Fetches and parses the WA7BNM Contest Calendar RSS feed with
/// conditional GET, rate-limit awareness, and Cache-Control support.
actor ContestCalendarClient {
    // MARK: Lifecycle

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: Internal

    /// Fetch contests from the RSS feed. Returns cached data when
    /// a 304 Not Modified is received or Cache-Control hasn't expired.
    func fetchContests() async throws -> [Contest] {
        // Return cached data if Cache-Control max-age hasn't expired
        if let nextAllowed = nextFetchAllowed,
           Date() < nextAllowed,
           let cached = cachedContests
        {
            return cached
        }

        let (data, httpResponse) = try await performRequest()

        // Store conditional GET headers for next request
        storeConditionalHeaders(httpResponse)

        if httpResponse.statusCode == 304 {
            if let cached = cachedContests {
                return cached
            }
            throw ContestCalendarError.notModified
        }

        if httpResponse.statusCode == 429 {
            throw ContestCalendarError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw ContestCalendarError.invalidResponse(
                "HTTP \(httpResponse.statusCode)"
            )
        }

        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw ContestCalendarError.parsingError("Unable to decode response as UTF-8")
        }

        let referenceYear = parseReferenceYear(from: xmlString)
        let contests = parseItems(from: xmlString, referenceYear: referenceYear)
        cachedContests = contests
        return contests
    }

    // MARK: Private

    private let feedURL = "https://www.contestcalendar.com/calendar.rss"
    private let session: URLSession

    // Conditional GET state
    private var cachedETag: String?
    private var cachedLastModified: String?
    private var cachedContests: [Contest]?

    /// Cache-Control state
    private var nextFetchAllowed: Date?

    // Rate limit state
    private var rateLimitRemaining: Int = 100
    private var rateLimitReset: Date?

    // MARK: - Request Helpers

    private func performRequest() async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: feedURL) else {
            throw ContestCalendarError.invalidURL
        }

        if rateLimitRemaining <= 0,
           let reset = rateLimitReset,
           Date() < reset
        {
            throw ContestCalendarError.rateLimited
        }

        var request = URLRequest(url: url)
        request.setValue("CarrierWave/1.0", forHTTPHeaderField: "User-Agent")

        if let etag = cachedETag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = cachedLastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ContestCalendarError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ContestCalendarError.invalidResponse("Not an HTTP response")
        }

        checkRateLimitHeaders(httpResponse)
        parseCacheControlHeaders(httpResponse)

        return (data, httpResponse)
    }

    private func storeConditionalHeaders(_ response: HTTPURLResponse) {
        if let etag = response.value(forHTTPHeaderField: "ETag") {
            cachedETag = etag
        }
        if let lastModified = response.value(forHTTPHeaderField: "Last-Modified") {
            cachedLastModified = lastModified
        }
    }

    // MARK: - Header Parsing

    private func checkRateLimitHeaders(_ response: HTTPURLResponse) {
        if let remaining = response.value(
            forHTTPHeaderField: "X-RateLimit-Remaining"
        ),
            let remainingInt = Int(remaining)
        {
            rateLimitRemaining = remainingInt
        }

        if let reset = response.value(
            forHTTPHeaderField: "X-RateLimit-Reset"
        ),
            let resetTimestamp = Double(reset)
        {
            rateLimitReset = Date(timeIntervalSince1970: resetTimestamp)
        }
    }

    private func parseCacheControlHeaders(_ response: HTTPURLResponse) {
        guard let cacheControl = response.value(
            forHTTPHeaderField: "Cache-Control"
        ) else {
            return
        }

        // Parse max-age=N from Cache-Control header
        let parts = cacheControl.components(separatedBy: ",")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("max-age="),
               let seconds = Int(trimmed.dropFirst("max-age=".count))
            {
                nextFetchAllowed = Date().addingTimeInterval(Double(seconds))
                return
            }
        }
    }

    // MARK: - XML Parsing

    /// Extract the reference year from the feed's <lastBuildDate> element.
    private func parseReferenceYear(from xml: String) -> Int {
        // Look for <lastBuildDate>Sat, 01 Mar 2026 06:00:00 GMT</lastBuildDate>
        if let match = xml.range(
            of: "<lastBuildDate>([^<]+)</lastBuildDate>",
            options: .regularExpression
        ) {
            let dateStr = String(xml[match])
                .replacingOccurrences(of: "<lastBuildDate>", with: "")
                .replacingOccurrences(of: "</lastBuildDate>", with: "")

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: dateStr) {
                return Calendar.current.component(.year, from: date)
            }
        }

        return Calendar.current.component(.year, from: Date())
    }

    /// Parse all <item> blocks from the RSS XML.
    private func parseItems(from xml: String, referenceYear: Int) -> [Contest] {
        var contests: [Contest] = []

        // Find each <item>...</item> block
        var searchStart = xml.startIndex
        while let itemStart = xml.range(
            of: "<item>", range: searchStart ..< xml.endIndex
        ),
            let itemEnd = xml.range(
                of: "</item>", range: itemStart.upperBound ..< xml.endIndex
            )
        {
            let itemXML = String(xml[itemStart.lowerBound ..< itemEnd.upperBound])

            if let contest = parseItem(itemXML, referenceYear: referenceYear) {
                contests.append(contest)
            }

            searchStart = itemEnd.upperBound
        }

        return contests
    }

    /// Parse a single <item> block into a Contest.
    private func parseItem(_ item: String, referenceYear: Int) -> Contest? {
        guard let title = extractTag("title", from: item),
              let guid = extractTag("guid", from: item),
              let description = extractTag("description", from: item)
        else {
            return nil
        }

        let link = extractTag("link", from: item).flatMap { URL(string: $0) }

        guard let dates = ContestDateParser.parse(
            description, referenceYear: referenceYear
        ) else {
            return nil
        }

        return Contest(
            id: guid,
            title: title,
            link: link,
            startDate: dates.start,
            endDate: dates.end
        )
    }

    /// Extract the text content of an XML tag, handling CDATA.
    private func extractTag(_ tag: String, from xml: String) -> String? {
        let pattern = "<\(tag)[^>]*>(.+?)</\(tag)>"
        guard let match = xml.range(of: pattern, options: .regularExpression) else {
            return nil
        }

        var content = String(xml[match])
        // Strip opening and closing tags
        if let openEnd = content.range(of: ">") {
            content = String(content[openEnd.upperBound...])
        }
        if let closeStart = content.range(of: "</\(tag)>") {
            content = String(content[..<closeStart.lowerBound])
        }

        // Strip CDATA wrapper if present
        content = content
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return content.isEmpty ? nil : content
    }
}
