//
//  ADIFParser.swift
//  CarrierWaveCore
//

import CarrierWaveCwFfi
import Foundation

// MARK: - ADIFRecord

/// A parsed ADIF QSO record.
///
/// The tokenizer and field extraction live in the shared Rust core
/// (`cw_domain::adif`); this is a value-type facade. Date handling
/// (``timestamp`` / ``ADIFParser/parseTimestamp(date:time:)``) stays in Swift.
public struct ADIFRecord: Sendable {
    // MARK: Lifecycle

    public init(
        callsign: String,
        band: String,
        mode: String,
        frequency: Double? = nil,
        qsoDate: String? = nil,
        timeOn: String? = nil,
        rstSent: String? = nil,
        rstReceived: String? = nil,
        myCallsign: String? = nil,
        myGridsquare: String? = nil,
        gridsquare: String? = nil,
        sigInfo: String? = nil,
        mySigInfo: String? = nil,
        myWwffRef: String? = nil,
        wwffRef: String? = nil,
        comment: String? = nil,
        dxcc: Int? = nil,
        country: String? = nil,
        state: String? = nil,
        name: String? = nil,
        qth: String? = nil,
        rawADIF: String,
        operatorCall: String? = nil,
        stationCallsign: String? = nil,
        satName: String? = nil,
        propMode: String? = nil
    ) {
        self.callsign = callsign
        self.band = band
        self.mode = mode
        self.frequency = frequency
        self.qsoDate = qsoDate
        self.timeOn = timeOn
        self.rstSent = rstSent
        self.rstReceived = rstReceived
        self.myCallsign = myCallsign
        self.myGridsquare = myGridsquare
        self.gridsquare = gridsquare
        self.sigInfo = sigInfo
        self.mySigInfo = mySigInfo
        self.myWwffRef = myWwffRef
        self.wwffRef = wwffRef
        self.comment = comment
        self.dxcc = dxcc
        self.country = country
        self.state = state
        self.name = name
        self.qth = qth
        self.rawADIF = rawADIF
        self.operatorCall = operatorCall
        self.stationCallsign = stationCallsign
        self.satName = satName
        self.propMode = propMode
    }

    /// Build a record from the Rust-parsed FFI value.
    init(ffi: FfiAdifRecord) {
        self.init(
            callsign: ffi.callsign,
            band: ffi.band,
            mode: ffi.mode,
            frequency: ffi.frequency,
            qsoDate: ffi.qsoDate,
            timeOn: ffi.timeOn,
            rstSent: ffi.rstSent,
            rstReceived: ffi.rstReceived,
            myCallsign: ffi.myCallsign,
            myGridsquare: ffi.myGridsquare,
            gridsquare: ffi.gridsquare,
            sigInfo: ffi.sigInfo,
            mySigInfo: ffi.mySigInfo,
            myWwffRef: ffi.myWwffRef,
            wwffRef: ffi.wwffRef,
            comment: ffi.comment,
            dxcc: ffi.dxcc.map(Int.init),
            country: ffi.country,
            state: ffi.state,
            name: ffi.name,
            qth: ffi.qth,
            rawADIF: ffi.rawAdif,
            operatorCall: ffi.operatorCall,
            stationCallsign: ffi.stationCallsign,
            satName: ffi.satName,
            propMode: ffi.propMode
        )
    }

    // MARK: Public

    public var callsign: String
    public var band: String
    public var mode: String
    public var frequency: Double?
    public var qsoDate: String? // YYYYMMDD
    public var timeOn: String? // HHMM or HHMMSS
    public var rstSent: String?
    public var rstReceived: String?
    public var myCallsign: String?
    public var myGridsquare: String?
    public var gridsquare: String? // Their grid
    public var sigInfo: String? // Their park reference (hunter contacts)
    public var mySigInfo: String? // My park reference (activations)
    public var myWwffRef: String? // My WWFF reference (ADIF 3.1.3+)
    public var wwffRef: String? // Their WWFF reference (ADIF 3.1.3+)
    public var comment: String?
    public var dxcc: Int? // DXCC entity number
    public var country: String? // Country name
    public var state: String? // US state abbreviation
    public var name: String? // Operator name
    public var qth: String? // Their QTH
    public var rawADIF: String
    public var operatorCall: String? // ADIF OPERATOR field
    public var stationCallsign: String? // ADIF STATION_CALLSIGN field
    public var satName: String? // ADIF SAT_NAME field
    public var propMode: String? // ADIF PROP_MODE field

    public var timestamp: Date? {
        guard let dateStr = qsoDate else {
            return nil
        }
        let timeStr = timeOn ?? "0000"

        let formatter = DateFormatter()
        formatter.dateFormat = timeStr.count == 6 ? "yyyyMMddHHmmss" : "yyyyMMddHHmm"
        formatter.timeZone = TimeZone(identifier: "UTC")

        return formatter.date(from: dateStr + timeStr)
    }
}

// MARK: - ADIFParser

/// Parses ADIF documents and extracts fields, delegating the tokenizer to the
/// shared Rust core (`cw_domain::adif`).
public struct ADIFParser: Sendable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// Extract a specific ADIF field value from a raw ADIF string.
    /// Handles case-insensitive field names and standard ADIF format.
    /// - Parameters:
    ///   - fieldName: The ADIF field name (e.g., "dxcc", "country")
    ///   - adif: The raw ADIF string to search
    /// - Returns: The field value if found, nil otherwise
    public static func extractField(_ fieldName: String, from adif: String) -> String? {
        adifExtractField(fieldName: fieldName, adifStr: adif)
    }

    /// Extract DXCC entity number from a raw ADIF string.
    /// - Parameter adif: The raw ADIF string to search
    /// - Returns: The DXCC entity number if found, nil otherwise
    public static func extractDXCC(from adif: String) -> Int? {
        adifExtractDxcc(adifStr: adif).map(Int.init)
    }

    /// Parse all ADIF fields from a raw record string into a dictionary.
    /// Field names are lowercased for uniform access.
    /// - Parameter record: A single ADIF record string (without `<eor>`)
    /// - Returns: Dictionary of field name -> value pairs
    public static func extractFields(_ record: String) -> [String: String] {
        adifExtractFields(record: record)
    }

    /// Parse ADIF date and time strings into a Date.
    /// - Parameters:
    ///   - date: Date string in YYYYMMDD format
    ///   - time: Time string in HHMM or HHMMSS format (optional)
    /// - Returns: Parsed UTC date, or nil if the date string is missing/invalid
    public static func parseTimestamp(date: String?, time: String?) -> Date? {
        guard let date else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")

        if let time, time.count >= 4 {
            formatter.dateFormat = "yyyyMMddHHmm"
            return formatter.date(from: date + String(time.prefix(4)))
        } else {
            formatter.dateFormat = "yyyyMMdd"
            return formatter.date(from: date)
        }
    }

    public func parse(_ content: String) throws -> [ADIFRecord] {
        adifParse(content: content).map(ADIFRecord.init(ffi:))
    }
}
