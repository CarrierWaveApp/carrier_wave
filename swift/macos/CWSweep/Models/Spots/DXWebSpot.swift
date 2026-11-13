import Foundation

// MARK: - DXSummitSpot

/// DX Summit API response element
struct DXSummitSpot: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case dxCall = "dx_call"
        case deCall = "de_call"
        case frequency
        case time
        case info
        case dxCountry = "dx_country"
        case dxLatitude = "dx_latitude"
        case dxLongitude = "dx_longitude"
        case deLatitude = "de_latitude"
        case deLongitude = "de_longitude"
    }

    let id: Int
    let dxCall: String
    let deCall: String
    let frequency: Double
    let time: Date
    let info: String?
    let dxCountry: String?
    let dxLatitude: Double?
    let dxLongitude: Double?
    let deLatitude: Double?
    let deLongitude: Double?
}

// MARK: - DXHeatSpot

/// DXHeat API response element
struct DXHeatSpot: Codable {
    enum CodingKeys: String, CodingKey {
        case nr = "Nr"
        case spotter = "Spotter"
        case frequency = "Frequency"
        case dxCall = "DXCall"
        case time = "Time"
        case date = "Date"
        case beacon = "Beacon"
        case mm = "MM"
        case am = "AM"
        case valid = "Valid"
        case dxHomecall = "DXHomecall"
        case comment = "Comment"
        case flag = "Flag"
        case band = "Band"
        case mode = "Mode"
        case continentDX = "Continent_dx"
        case continentSpotter = "Continent_spotter"
        case dxLocator = "DXLocator"
        case lotw = "LOTW"
        case lotwDate = "LOTW_Date"
        case eqsl = "EQSL"
    }

    let nr: Int
    let spotter: String
    let frequency: String
    let dxCall: String
    let time: String
    let date: String
    let beacon: Bool?
    let mm: Bool?
    let am: Bool?
    let valid: Bool?
    let dxHomecall: String?
    let comment: String?
    let flag: String?
    let band: Double?
    let mode: String?
    let continentDX: String?
    let continentSpotter: String?
    let dxLocator: String?
    let lotw: Bool?
    let lotwDate: String?
    let eqsl: Bool?

    /// Parse DXHeat's split date/time into a Date
    static func parseTimestamp(date: String, time: String) -> Date? {
        // Date: "20/03/26" (DD/MM/YY), Time: "14:19" (HH:MM)
        let combined = "\(date) \(time)"
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: combined)
    }

    /// Decode common HTML entities in DXHeat comments
    static func decodeHTMLEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}

// MARK: - DXWatchResponse

/// DXWatch API top-level response
struct DXWatchResponse {
    let spots: [DXWatchSpot]
    let callInfo: [String: DXWatchCallInfo]
}

// MARK: - DXWatchSpot

/// A single DXWatch spot decoded from the compact array format
struct DXWatchSpot {
    /// Band code mapping from DXWatch JS g_b table
    static let bandCodeMap: [Int: String] = [
        3: "160m",
        7: "80m",
        12: "40m",
        17: "30m",
        22: "20m",
        27: "17m",
        32: "15m",
        37: "12m",
        42: "10m",
        50: "6m",
        62: "2m",
    ]

    let id: String
    let spotter: String
    let frequency: Double
    let dxCall: String
    let comment: String?
    let timeString: String
    let bandCode: Int
    let flag: Int

    /// Parse "1409z 20 Mar" style timestamp
    var timestamp: Date? {
        // Extract HHMMz DD Mon from timeString
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmm'z' dd MMM"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Add current year since DXWatch doesn't include it
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        let withYear = "\(timeString) \(year)"

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "HHmm'z' dd MMM yyyy"
        yearFormatter.timeZone = TimeZone(identifier: "UTC")
        yearFormatter.locale = Locale(identifier: "en_US_POSIX")
        return yearFormatter.date(from: withYear)
    }

    /// Map band code to band name in meters
    var bandMeters: String? {
        Self.bandCodeMap[bandCode]
    }
}

// MARK: - DXWatchCallInfo

/// DXWatch callsign info decoded from the ci array
struct DXWatchCallInfo {
    let prefix: String?
    let entityName: String?
    let continent: String?
    let flagCode: String?
    let cqZone: Int?
    let ituZone: Int?
    let latitude: Double?
    let longitude: Double?
    let state: String?
    let grid: String?
    let dxccNumber: String?
    let iotaRef: String?
}

// MARK: - DXWatchResponseDecoder

/// Custom decoder for DXWatch's compact array-based JSON format
enum DXWatchResponseDecoder {
    // MARK: Internal

    static func decode(from data: Data) throws -> DXWatchResponse {
        // DXWatch response may have leading whitespace/newline — trim before parsing
        let trimmedData = data.drop(while: { $0 == 0x0A || $0 == 0x0D || $0 == 0x20 })
        guard let json = try JSONSerialization.jsonObject(
            with: Data(trimmedData)
        ) as? [String: Any] else {
            throw DXWatchDecodingError.invalidFormat
        }

        let spotsDict = json["s"] as? [String: [Any]] ?? [:]
        let ciDict = json["ci"] as? [String: [Any]] ?? [:]

        let spots = spotsDict.compactMap { key, value -> DXWatchSpot? in
            decodeSpot(id: key, values: value)
        }

        var callInfo: [String: DXWatchCallInfo] = [:]
        for (callsign, values) in ciDict {
            if let info = decodeCallInfo(values: values) {
                callInfo[callsign] = info
            }
        }

        return DXWatchResponse(spots: spots, callInfo: callInfo)
    }

    // MARK: Private

    private static func decodeSpot(id: String, values: [Any]) -> DXWatchSpot? {
        guard values.count >= 7 else {
            return nil
        }
        guard let spotter = values[0] as? String,
              let dxCall = values[2] as? String
        else {
            return nil
        }

        let frequency: Double
        if let freq = values[1] as? Double {
            frequency = freq
        } else if let freq = values[1] as? Int {
            frequency = Double(freq)
        } else {
            return nil
        }

        let comment = values[3] as? String
        let timeString = values[4] as? String ?? ""
        let bandCode: Int = if let bc = values[6] as? Int {
            bc
        } else {
            0
        }
        let flag = (values.count > 7) ? (values[7] as? Int ?? 0) : 0

        return DXWatchSpot(
            id: id,
            spotter: spotter,
            frequency: frequency,
            dxCall: dxCall,
            comment: comment?.isEmpty == true ? nil : comment,
            timeString: timeString,
            bandCode: bandCode,
            flag: flag
        )
    }

    private static func decodeCallInfo(values: [Any]) -> DXWatchCallInfo? {
        guard values.count >= 10 else {
            return nil
        }

        let prefix = values[0] as? String
        let entityName = values[1] as? String
        let continent = values[2] as? String
        let flagCode = values[3] as? String
        let cqZone = values[4] as? Int
        let ituZone = values[5] as? Int
        let latitude = values[6] as? Double
        let longitude = values[7] as? Double
        let state = values[8] as? String
        let grid = values[9] as? String

        let dxccNumber = values.count > 11 ? values[11] as? String : nil
        let iotaRef: String? = if values.count > 12, let ref = values[12] as? String, !ref.isEmpty {
            ref
        } else {
            nil
        }

        return DXWatchCallInfo(
            prefix: prefix,
            entityName: entityName,
            continent: continent,
            flagCode: flagCode,
            cqZone: cqZone,
            ituZone: ituZone,
            latitude: latitude,
            longitude: longitude,
            state: state?.isEmpty == true ? nil : state,
            grid: grid?.isEmpty == true ? nil : grid,
            dxccNumber: dxccNumber,
            iotaRef: iotaRef
        )
    }
}

// MARK: - DXWatchDecodingError

enum DXWatchDecodingError: Error, LocalizedError {
    case invalidFormat

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            "Invalid DXWatch response format"
        }
    }
}

// MARK: - SplitInfoParser

/// Parses split/listening frequency info from spot comments
enum SplitInfoParser {
    /// Parse split info from a comment string.
    /// Returns a human-readable split description or nil.
    static func parse(_ comment: String?) -> String? {
        guard let comment, !comment.isEmpty else {
            return nil
        }

        // QSX with explicit frequency: "QSX 14215" or "QSX 7025.00"
        if let match = comment.range(
            of: #"\bQSX\s+(\d{3,6}\.?\d*)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            return String(comment[match]).trimmingCharacters(in: .whitespaces)
        }

        // Up with range: "up1-4", "up 5-10"
        if let match = comment.range(
            of: #"\bup\s*(\d+\.?\d*)\s*-\s*(\d+\.?\d*)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            return "UP \(comment[match].dropFirst(2))".trimmingCharacters(in: .whitespaces)
        }

        // Up with value and optional plus: "up 5", "UP1+", "up4.4"
        if let match = comment.range(
            of: #"\bup\s*(\d+\.?\d*)\+?\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            return String(comment[match]).uppercased().trimmingCharacters(in: .whitespaces)
        }

        // Down with value: "down 2"
        if let match = comment.range(
            of: #"\bdown\s*(\d+\.?\d*)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            return String(comment[match]).uppercased().trimmingCharacters(in: .whitespaces)
        }

        // "listening up" or "listening down"
        if let match = comment.range(
            of: #"\blistening\s+(up|down)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            return String(comment[match]).uppercased().trimmingCharacters(in: .whitespaces)
        }

        // Simplex (various spellings)
        if comment.range(
            of: #"\bsimpl[ex]+\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return "SIMPLEX"
        }

        return nil
    }
}
