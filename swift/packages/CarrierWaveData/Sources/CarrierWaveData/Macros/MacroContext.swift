import Foundation

// MARK: - MacroContext

/// Live context fed into a macro at execution time. Placeholder tokens like
/// `{MYCALL}`, `{FREQ}`, `{PARK}` resolve against this struct via
/// `MacroTemplateEngine`. Values are optional because most macros only need a
/// subset; references to a missing key surface as a clear runtime error.
public struct MacroContext: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        myCall: String? = nil,
        myName: String? = nil,
        myGrid: String? = nil,
        contactCall: String? = nil,
        contactName: String? = nil,
        rstSent: String? = nil,
        rstReceived: String? = nil,
        serial: Int? = nil,
        exchange: String? = nil,
        currentFreqHz: UInt64? = nil,
        currentMode: String? = nil,
        park: String? = nil,
        sotaRef: String? = nil,
        wwffRef: String? = nil,
        time: Date = Date()
    ) {
        self.myCall = myCall
        self.myName = myName
        self.myGrid = myGrid
        self.contactCall = contactCall
        self.contactName = contactName
        self.rstSent = rstSent
        self.rstReceived = rstReceived
        self.serial = serial
        self.exchange = exchange
        self.currentFreqHz = currentFreqHz
        self.currentMode = currentMode
        self.park = park
        self.sotaRef = sotaRef
        self.wwffRef = wwffRef
        self.time = time
    }

    // MARK: Public

    /// Returns the canonical preview context used by editors and tests so
    /// users see realistic values when the live session has none.
    public static let preview = MacroContext(
        myCall: "W6JY",
        myName: "JAY",
        myGrid: "CM87",
        contactCall: "W1AW",
        contactName: "HIRAM",
        rstSent: "599",
        rstReceived: "579",
        serial: 1,
        exchange: "5NN",
        currentFreqHz: 7_032_000,
        currentMode: "CW",
        park: "K-4567",
        time: Date(timeIntervalSince1970: 1_726_790_400) // 2024-09-20 00:00:00 UTC
    )

    public var myCall: String?
    public var myName: String?
    public var myGrid: String?
    public var contactCall: String?
    public var contactName: String?
    public var rstSent: String?
    public var rstReceived: String?
    public var serial: Int?
    public var exchange: String?
    public var currentFreqHz: UInt64?
    public var currentMode: String?
    public var park: String?
    public var sotaRef: String?
    public var wwffRef: String?
    public var time: Date

    /// Returns the resolved value for the uppercase context token (without
    /// braces or format hints). Returns nil if no value is bound.
    public func value(forToken token: String) -> String? {
        profileValue(forToken: token)
            ?? contactValue(forToken: token)
            ?? radioValue(forToken: token)
            ?? activationValue(forToken: token)
            ?? timeValue(forToken: token)
    }

    // MARK: Private

    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private func profileValue(forToken token: String) -> String? {
        switch token {
        case "MYCALL": myCall
        case "MYNAME": myName
        case "MYGRID": myGrid
        default: nil
        }
    }

    private func contactValue(forToken token: String) -> String? {
        switch token {
        case "CALL": contactCall
        case "NAME": contactName
        case "RST": rstSent
        case "RSTR": rstReceived
        case "NR": serial.map { String(format: "%03d", $0) }
        case "EXCH": exchange
        default: nil
        }
    }

    private func radioValue(forToken token: String) -> String? {
        switch token {
        case "FREQ": currentFreqHz.map { String($0) }
        case "FREQ_KHZ": currentFreqHz.map { String($0 / 1_000) }
        case "FREQ_MHZ": currentFreqHz.map { String(format: "%.6f", Double($0) / 1_000_000) }
        case "MODE": currentMode
        default: nil
        }
    }

    private func activationValue(forToken token: String) -> String? {
        switch token {
        case "PARK": park
        case "SOTAREF": sotaRef
        case "WWFFREF": wwffRef
        default: nil
        }
    }

    private func timeValue(forToken token: String) -> String? {
        switch token {
        case "TIME": Self.utcFormatter.string(from: time)
        case "DATE": Self.dateFormatter.string(from: time)
        default: nil
        }
    }
}
