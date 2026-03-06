import Foundation

// MARK: - QSYAction

/// Parsed action from a `qsy://` URI per the QSY URI Scheme specification.
/// See: https://github.com/jsvana/qsy-uri
public enum QSYAction: Equatable, Sendable {
    /// Pre-fill a logging form from spot data (requires callsign + freq)
    case spot(QSYSpotParams)

    /// Tune radio to frequency/mode via CAT control (requires freq)
    case tune(QSYTuneParams)

    /// Open callsign lookup view (requires callsign)
    case lookup(callsign: String)

    /// Import QSO records from ADIF source (requires url)
    case importLog(url: URL, format: String)

    /// Record a completed QSO (requires callsign + freq + mode)
    case log(QSYLogParams)
}

// MARK: - QSYSpotParams

/// Parameters for the `spot` action.
public struct QSYSpotParams: Equatable, Sendable {
    public let callsign: String
    public let frequencyHz: Int
    public let mode: String?
    public let submode: String?
    public let band: String?
    public let grid: String?
    public let ref: [String]?
    public let refType: [String]?
    public let txPower: Double?
    public let source: String?
    public let comment: String?

    /// Frequency in MHz (the standard internal unit).
    public var frequencyMHz: Double {
        Double(frequencyHz) / 1_000_000.0
    }
}

// MARK: - QSYTuneParams

/// Parameters for the `tune` action.
public struct QSYTuneParams: Equatable, Sendable {
    public let frequencyHz: Int
    public let mode: String?

    /// Frequency in MHz.
    public var frequencyMHz: Double {
        Double(frequencyHz) / 1_000_000.0
    }
}

// MARK: - QSYLogParams

/// Parameters for the `log` action.
public struct QSYLogParams: Equatable, Sendable {
    public let callsign: String
    public let frequencyHz: Int
    public let mode: String
    public let submode: String?
    public let band: String?
    public let rstSent: String?
    public let rstReceived: String?
    public let grid: String?
    public let myGrid: String?
    public let ref: [String]?
    public let refType: [String]?
    public let myRef: [String]?
    public let myRefType: [String]?
    public let txPower: Double?
    public let time: Date?
    public let op: String?
    public let station: String?
    public let contest: String?
    public let srx: String?
    public let stx: String?
    public let source: String?
    public let comment: String?

    /// Frequency in MHz.
    public var frequencyMHz: Double {
        Double(frequencyHz) / 1_000_000.0
    }
}

// MARK: - QSYURIParser

/// Parses `qsy://` URIs into typed actions per the QSY URI specification.
public enum QSYURIParser {
    // MARK: Public

    /// Parse a URL into a QSYAction. Returns nil if the URL is not a valid qsy:// URI.
    public static func parse(_ url: URL) -> QSYAction? {
        guard url.scheme?.lowercased() == "qsy" else {
            return nil
        }

        guard let action = url.host?.lowercased() else {
            return nil
        }

        let params = queryParameters(from: url)

        switch action {
        case "spot":
            return parseSpot(params)
        case "tune":
            return parseTune(params)
        case "lookup":
            return parseLookup(params)
        case "import":
            return parseImport(params)
        case "log":
            return parseLog(params)
        default:
            // Unknown actions: spec says "open default view"
            return nil
        }
    }

    // MARK: Private

    // MARK: - Action Parsers

    private static func parseSpot(_ params: [String: String]) -> QSYAction? {
        guard let callsign = params["callsign"],
              let freqStr = params["freq"],
              let freqHz = Int(freqStr)
        else {
            return nil
        }

        let spotParams = QSYSpotParams(
            callsign: callsign.uppercased(),
            frequencyHz: freqHz,
            mode: params["mode"]?.uppercased(),
            submode: params["submode"]?.uppercased(),
            band: params["band"],
            grid: params["grid"]?.uppercased(),
            ref: parseCSV(params["ref"]),
            refType: parseCSV(params["ref_type"]),
            txPower: params["tx_power"].flatMap(Double.init),
            source: params["source"],
            comment: params["comment"]
        )
        return .spot(spotParams)
    }

    private static func parseTune(_ params: [String: String]) -> QSYAction? {
        guard let freqStr = params["freq"],
              let freqHz = Int(freqStr)
        else {
            return nil
        }

        let tuneParams = QSYTuneParams(
            frequencyHz: freqHz,
            mode: params["mode"]?.uppercased()
        )
        return .tune(tuneParams)
    }

    private static func parseLookup(_ params: [String: String]) -> QSYAction? {
        guard let callsign = params["callsign"] else {
            return nil
        }
        return .lookup(callsign: callsign.uppercased())
    }

    private static func parseImport(_ params: [String: String]) -> QSYAction? {
        guard let urlString = params["url"],
              let url = URL(string: urlString)
        else {
            return nil
        }
        let format = params["format"] ?? "adif"
        return .importLog(url: url, format: format)
    }

    private static func parseLog(_ params: [String: String]) -> QSYAction? {
        guard let callsign = params["callsign"],
              let freqStr = params["freq"],
              let freqHz = Int(freqStr),
              let mode = params["mode"]
        else {
            return nil
        }

        let logParams = QSYLogParams(
            callsign: callsign.uppercased(),
            frequencyHz: freqHz,
            mode: mode.uppercased(),
            submode: params["submode"]?.uppercased(),
            band: params["band"],
            rstSent: params["rst_sent"],
            rstReceived: params["rst_rcvd"],
            grid: params["grid"]?.uppercased(),
            myGrid: params["my_grid"]?.uppercased(),
            ref: parseCSV(params["ref"]),
            refType: parseCSV(params["ref_type"]),
            myRef: parseCSV(params["my_ref"]),
            myRefType: parseCSV(params["my_ref_type"]),
            txPower: params["tx_power"].flatMap(Double.init),
            time: params["time"].flatMap(parseISO8601Compact),
            op: params["op"]?.uppercased(),
            station: params["station"]?.uppercased(),
            contest: params["contest"],
            srx: params["srx"],
            stx: params["stx"],
            source: params["source"],
            comment: params["comment"]
        )
        return .log(logParams)
    }

    // MARK: - Helpers

    /// Extract query parameters from URL, handling percent-encoding.
    private static func queryParameters(from url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems
        else {
            return [:]
        }

        var params: [String: String] = [:]
        for item in queryItems {
            if let value = item.value {
                params[item.name] = value
            }
        }
        return params
    }

    /// Parse comma-separated values into an array. Returns nil if input is nil.
    private static func parseCSV(_ value: String?) -> [String]? {
        guard let value, !value.isEmpty else {
            return nil
        }
        let components = value.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        return components.isEmpty ? nil : components
    }

    /// Parse compact ISO 8601 UTC timestamp: YYYYMMDDTHHmmZ or YYYYMMDDTHHmmSSZ
    private static func parseISO8601Compact(_ string: String) -> Date? {
        let clean = string.trimmingCharacters(in: .whitespaces)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")

        // Try with seconds first: YYYYMMDDTHHmmSSZ (16 chars)
        if clean.count == 16 {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            if let date = formatter.date(from: clean) {
                return date
            }
        }

        // Try without seconds: YYYYMMDDTHHmmZ (14 chars)
        if clean.count == 14 {
            formatter.dateFormat = "yyyyMMdd'T'HHmm'Z'"
            if let date = formatter.date(from: clean) {
                return date
            }
        }

        return nil
    }
}
