import CarrierWaveCwFfi
import Foundation

// MARK: - ADIFFieldValidator

/// Validates ADIF fields against the ADIF 3.1.7 specification.
///
/// Every per-field check and the composite upload validator delegate to the
/// shared Rust core (`cw_domain::adif_validator`); this is a value-type facade.
public enum ADIFFieldValidator {
    /// A single validation violation for one field.
    public struct Violation: Sendable, Equatable {
        // MARK: Lifecycle

        public init(field: Field, value: String, reason: String) {
            self.field = field
            self.value = value
            self.reason = reason
        }

        init(ffi: FfiViolation) {
            self.init(field: Field(ffi: ffi.field), value: ffi.value, reason: ffi.reason)
        }

        // MARK: Public

        public let field: Field
        public let value: String
        public let reason: String
    }

    /// Fields that can be validated.
    public enum Field: String, Sendable, Equatable {
        case call
        case band
        case mode
        case submode
        case freq
        case date
        case time
        case grid

        // MARK: Lifecycle

        init(ffi: FfiAdifField) {
            switch ffi {
            case .call: self = .call
            case .band: self = .band
            case .mode: self = .mode
            case .submode: self = .submode
            case .freq: self = .freq
            case .date: self = .date
            case .time: self = .time
            case .grid: self = .grid
            }
        }
    }

    /// Violations for a single QSO record in a parsed ADIF string.
    public struct RecordViolation: Sendable {
        public let recordIndex: Int
        public let callsign: String?
        public let violations: [Violation]
    }
}

// MARK: - Per-Field Validators

public extension ADIFFieldValidator {
    /// Callsign must be non-empty after trimming.
    static func validateCallsign(_ call: String) -> Violation? {
        adifValidateCallsign(call: call).map(Violation.init(ffi:))
    }

    /// Band must be a recognized ADIF 3.1.7 band code.
    static func validateBand(_ band: String) -> Violation? {
        adifValidateBand(band: band).map(Violation.init(ffi:))
    }

    /// Mode must be a recognized ADIF 3.1.7 mode code.
    static func validateMode(_ mode: String) -> Violation? {
        adifValidateMode(mode: mode).map(Violation.init(ffi:))
    }

    /// If submode is present, it must be a known submode of the given parent mode.
    static func validateSubmode(
        _ submode: String, parentMode: String
    ) -> Violation? {
        adifValidateSubmode(submode: submode, parentMode: parentMode).map(Violation.init(ffi:))
    }

    /// If both band and frequency are present, freq must fall within band range.
    static func validateBandFreqConsistency(
        band: String, freqMHz: Double
    ) -> Violation? {
        adifValidateBandFreqConsistency(band: band, freqMhz: freqMHz).map(Violation.init(ffi:))
    }

    /// Date must be YYYYMMDD with year >= 1930 and valid month/day.
    static func validateDate(_ dateStr: String) -> Violation? {
        adifValidateDate(dateStr: dateStr).map(Violation.init(ffi:))
    }

    /// Time must be HHMM or HHMMSS with valid ranges.
    static func validateTime(_ timeStr: String) -> Violation? {
        adifValidateTime(timeStr: timeStr).map(Violation.init(ffi:))
    }

    /// Grid square must be 2/4/6/8 chars with valid Maidenhead characters.
    static func validateGridSquare(_ grid: String) -> Violation? {
        adifValidateGridSquare(grid: grid).map(Violation.init(ffi:))
    }
}

// MARK: - Composite Validators

public extension ADIFFieldValidator {
    /// Validate all available fields for a QSO before upload.
    /// Mode should already be normalized (e.g., via normalizeForStrictADIF).
    static func validateForUpload(
        callsign: String,
        band: String,
        mode: String,
        submode: String? = nil,
        freqMHz: Double? = nil,
        dateStr: String? = nil,
        timeStr: String? = nil,
        grid: String? = nil
    ) -> [Violation] {
        adifValidateForUpload(
            callsign: callsign,
            band: band,
            mode: mode,
            submode: submode,
            freqMhz: freqMHz,
            dateStr: dateStr,
            timeStr: timeStr,
            grid: grid
        ).map(Violation.init(ffi:))
    }

    /// Parse an ADIF string and validate each record against the spec.
    static func validateADIFString(_ adif: String) -> [RecordViolation] {
        let parser = ADIFParser()
        guard let records = try? parser.parse(adif) else {
            return []
        }
        var results: [RecordViolation] = []
        for (idx, record) in records.enumerated() {
            let modeSubmode = ModeEquivalence.adifModeSubmode(record.mode)
            let violations = validateForUpload(
                callsign: record.callsign ?? "",
                band: record.band ?? "",
                mode: modeSubmode.mode,
                submode: modeSubmode.submode,
                freqMHz: record.frequency,
                dateStr: record.qsoDate,
                timeStr: record.timeOn
            )
            if !violations.isEmpty {
                results.append(RecordViolation(
                    recordIndex: idx,
                    callsign: record.callsign,
                    violations: violations
                ))
            }
        }
        return results
    }
}
