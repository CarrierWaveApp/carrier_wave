//
//  ADIFParser.swift
//  CarrierWaveCore
//

import Foundation

// MARK: - ADIFRecord

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
        rawADIF: String
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
        // Pattern: <fieldname:length>value or <fieldname:length:type>value
        let pattern = "<\(fieldName):(\\d+)(?::\\w)?>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        else {
            return nil
        }

        let nsString = adif as NSString
        guard
            let match = regex.firstMatch(
                in: adif,
                options: [],
                range: NSRange(location: 0, length: nsString.length)
            )
        else {
            return nil
        }

        guard match.numberOfRanges >= 2 else {
            return nil
        }

        let lengthRange = match.range(at: 1)
        guard lengthRange.location != NSNotFound,
              let length = Int(nsString.substring(with: lengthRange))
        else {
            return nil
        }

        let valueStart = match.range.location + match.range.length
        guard valueStart + length <= nsString.length else {
            return nil
        }

        let value = nsString.substring(with: NSRange(location: valueStart, length: length))
        return value.trimmingCharacters(in: .whitespaces)
    }

    /// Extract DXCC entity number from a raw ADIF string.
    /// - Parameter adif: The raw ADIF string to search
    /// - Returns: The DXCC entity number if found, nil otherwise
    public static func extractDXCC(from adif: String) -> Int? {
        guard let value = extractField("dxcc", from: adif) else {
            return nil
        }
        return Int(value)
    }

    public func parse(_ content: String) throws -> [ADIFRecord] {
        var records: [ADIFRecord] = []

        // Find header end if present
        let workingContent: String =
            if let headerEnd = content.range(of: "<eoh>", options: .caseInsensitive) {
                String(content[headerEnd.upperBound...])
            } else {
                content
            }

        // Split by <eor> (end of record)
        let rawRecords = workingContent.split(separator: "<eor>", omittingEmptySubsequences: true)
            .map { $0.split(separator: "<EOR>", omittingEmptySubsequences: true) }
            .flatMap { $0 }
            .map { String($0) }

        for rawRecord in rawRecords {
            let trimmed = rawRecord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            let fields = parseFields(from: trimmed)
            guard let callsign = fields["call"],
                  let band = fields["band"],
                  let mode = fields["mode"]
            else {
                continue // Skip records missing required fields
            }

            let record = ADIFRecord(
                callsign: callsign.uppercased(),
                band: band.lowercased(),
                mode: mode.uppercased(),
                frequency: fields["freq"].flatMap { Double($0) },
                qsoDate: fields["qso_date"],
                timeOn: fields["time_on"],
                rstSent: fields["rst_sent"],
                rstReceived: fields["rst_rcvd"],
                myCallsign: fields["station_callsign"] ?? fields["operator"],
                myGridsquare: fields["my_gridsquare"],
                gridsquare: fields["gridsquare"],
                sigInfo: fields["sig_info"] ?? fields["pota_ref"],
                mySigInfo: fields["my_sig_info"] ?? fields["my_pota_ref"],
                myWwffRef: fields["my_wwff_ref"],
                wwffRef: fields["wwff_ref"],
                comment: fields["comment"] ?? fields["notes"],
                dxcc: fields["dxcc"].flatMap { Int($0) },
                country: fields["country"],
                state: fields["state"],
                name: fields["name"],
                qth: fields["qth"],
                rawADIF: "<" + trimmed + "<eor>"
            )

            records.append(record)
        }

        return records
    }

    // MARK: Private

    private func parseFields(from record: String) -> [String: String] {
        var fields: [String: String] = [:]

        // Pattern: <fieldname:length>value or <fieldname:length:type>value
        let pattern = #"<(\w+):(\d+)(?::\w)?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        else {
            return fields
        }

        let nsString = record as NSString
        let matches = regex.matches(
            in: record, range: NSRange(location: 0, length: nsString.length)
        )

        for match in matches {
            guard match.numberOfRanges >= 3 else {
                continue
            }

            let fieldName = nsString.substring(with: match.range(at: 1)).lowercased()
            let lengthStr = nsString.substring(with: match.range(at: 2))
            guard let length = Int(lengthStr) else {
                continue
            }

            let valueStart = match.range.location + match.range.length
            guard valueStart + length <= nsString.length else {
                continue
            }

            let value = nsString.substring(with: NSRange(location: valueStart, length: length))
            fields[fieldName] = value.trimmingCharacters(in: .whitespaces)
        }

        return fields
    }
}
