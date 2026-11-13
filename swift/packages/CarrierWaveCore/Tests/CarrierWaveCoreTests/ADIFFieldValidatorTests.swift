import Testing
@testable import CarrierWaveCore

// MARK: - ADIFFieldValidatorModeTests

struct ADIFFieldValidatorModeTests {
    @Test("Valid ADIF modes pass validation")
    func validModes() {
        let validModes = [
            "SSB", "CW", "FT8", "AM", "FM", "RTTY", "MFSK", "PSK",
            "DIGITALVOICE", "DYNAMIC", "OFDM", "SSTV", "ATV",
        ]
        for mode in validModes {
            #expect(
                ADIFFieldValidator.validateMode(mode) == nil,
                "Expected \(mode) to be valid"
            )
        }
    }

    @Test("Invalid modes fail validation")
    func invalidModes() {
        let invalidModes = ["UNKNOWN", "PHONE", "DATA", "", "XYZ", "FONE"]
        for mode in invalidModes {
            #expect(
                ADIFFieldValidator.validateMode(mode) != nil,
                "Expected \(mode) to be invalid"
            )
        }
    }

    @Test("Mode validation is case-insensitive")
    func caseInsensitive() {
        #expect(ADIFFieldValidator.validateMode("ssb") == nil)
        #expect(ADIFFieldValidator.validateMode("Ft8") == nil)
        #expect(ADIFFieldValidator.validateMode("cw") == nil)
    }

    @Test("PHONE after normalizeForStrictADIF becomes valid SSB")
    func phoneNormalizesToSSB() {
        let result = ModeEquivalence.normalizeForStrictADIF("PHONE")
        #expect(result.mode == "SSB")
        #expect(ADIFFieldValidator.validateMode(result.mode) == nil)
    }

    @Test("DATA after normalizeForStrictADIF becomes valid RTTY")
    func dataNormalizesToRTTY() {
        let result = ModeEquivalence.normalizeForStrictADIF("DATA")
        #expect(result.mode == "RTTY")
        #expect(ADIFFieldValidator.validateMode(result.mode) == nil)
    }

    @Test("UNKNOWN after normalizeForStrictADIF remains invalid")
    func unknownRemainsInvalid() {
        let result = ModeEquivalence.normalizeForStrictADIF("UNKNOWN")
        #expect(result.mode == "UNKNOWN")
        #expect(ADIFFieldValidator.validateMode(result.mode) != nil)
    }
}

// MARK: - ADIFFieldValidatorSubmodeTests

struct ADIFFieldValidatorSubmodeTests {
    @Test("Valid submode with correct parent passes")
    func validSubmodes() {
        #expect(ADIFFieldValidator.validateSubmode("USB", parentMode: "SSB") == nil)
        #expect(ADIFFieldValidator.validateSubmode("LSB", parentMode: "SSB") == nil)
        #expect(ADIFFieldValidator.validateSubmode("FT4", parentMode: "MFSK") == nil)
        #expect(ADIFFieldValidator.validateSubmode("PSK31", parentMode: "PSK") == nil)
        #expect(ADIFFieldValidator.validateSubmode("DMR", parentMode: "DIGITALVOICE") == nil)
        #expect(ADIFFieldValidator.validateSubmode("PCW", parentMode: "CW") == nil)
    }

    @Test("Submode with wrong parent fails")
    func wrongParent() {
        let vio = ADIFFieldValidator.validateSubmode("USB", parentMode: "CW")
        #expect(vio != nil)
        #expect(vio?.field == .submode)
    }

    @Test("Unrecognized submode fails")
    func unrecognizedSubmode() {
        #expect(ADIFFieldValidator.validateSubmode("GARBAGE", parentMode: "SSB") != nil)
    }

    @Test("Empty submode is ignored")
    func emptySubmode() {
        #expect(ADIFFieldValidator.validateSubmode("", parentMode: "SSB") == nil)
    }
}

// MARK: - ADIFFieldValidatorBandTests

struct ADIFFieldValidatorBandTests {
    @Test("Valid ADIF bands pass validation")
    func validBands() {
        let validBands = ["20m", "40m", "2m", "70cm", "8m", "5m", "submm", "160m"]
        for band in validBands {
            #expect(
                ADIFFieldValidator.validateBand(band) == nil,
                "Expected \(band) to be valid"
            )
        }
    }

    @Test("Invalid bands fail validation")
    func invalidBands() {
        let invalidBands = ["Unknown", "", "HF", "PHONE", "xyz"]
        for band in invalidBands {
            #expect(
                ADIFFieldValidator.validateBand(band) != nil,
                "Expected \(band) to be invalid"
            )
        }
    }

    @Test("Band validation is case-insensitive")
    func caseInsensitive() {
        #expect(ADIFFieldValidator.validateBand("20M") == nil)
        #expect(ADIFFieldValidator.validateBand("70CM") == nil)
        #expect(ADIFFieldValidator.validateBand("SUBMM") == nil)
    }
}

// MARK: - ADIFFieldValidatorBandFreqTests

struct ADIFFieldValidatorBandFreqTests {
    @Test("Frequency within band range passes")
    func freqInRange() {
        #expect(
            ADIFFieldValidator.validateBandFreqConsistency(
                band: "20m", freqMHz: 14.025
            ) == nil
        )
        #expect(
            ADIFFieldValidator.validateBandFreqConsistency(
                band: "40m", freqMHz: 7.1
            ) == nil
        )
    }

    @Test("Frequency outside band range fails")
    func freqOutOfRange() {
        let vio = ADIFFieldValidator.validateBandFreqConsistency(
            band: "20m", freqMHz: 7.1
        )
        #expect(vio != nil)
        #expect(vio?.field == .freq)
    }

    @Test("Unknown band is silently skipped")
    func unknownBandSkipped() {
        #expect(
            ADIFFieldValidator.validateBandFreqConsistency(
                band: "unknown", freqMHz: 14.0
            ) == nil
        )
    }
}

// MARK: - ADIFFieldValidatorDateTests

struct ADIFFieldValidatorDateTests {
    @Test("Valid dates pass")
    func validDates() {
        #expect(ADIFFieldValidator.validateDate("20240115") == nil)
        #expect(ADIFFieldValidator.validateDate("19300101") == nil)
        #expect(ADIFFieldValidator.validateDate("20001231") == nil)
        #expect(ADIFFieldValidator.validateDate("20240229") == nil) // leap year
    }

    @Test("Invalid month fails")
    func invalidMonth() {
        let vio = ADIFFieldValidator.validateDate("20241301")
        #expect(vio != nil)
        #expect(vio?.field == .date)
    }

    @Test("Feb 30 fails")
    func feb30() {
        #expect(ADIFFieldValidator.validateDate("20240230") != nil)
    }

    @Test("Feb 29 on non-leap year fails")
    func feb29NonLeap() {
        #expect(ADIFFieldValidator.validateDate("20230229") != nil)
    }

    @Test("Year before 1930 fails")
    func yearTooOld() {
        #expect(ADIFFieldValidator.validateDate("19290101") != nil)
    }

    @Test("Wrong length fails")
    func wrongLength() {
        #expect(ADIFFieldValidator.validateDate("2024011") != nil)
        #expect(ADIFFieldValidator.validateDate("202401150") != nil)
    }

    @Test("Non-numeric fails")
    func nonNumeric() {
        #expect(ADIFFieldValidator.validateDate("2024AB15") != nil)
    }
}

// MARK: - ADIFFieldValidatorTimeTests

struct ADIFFieldValidatorTimeTests {
    @Test("Valid times pass")
    func validTimes() {
        #expect(ADIFFieldValidator.validateTime("1430") == nil)
        #expect(ADIFFieldValidator.validateTime("143022") == nil)
        #expect(ADIFFieldValidator.validateTime("0000") == nil)
        #expect(ADIFFieldValidator.validateTime("235959") == nil)
    }

    @Test("Hour 25 fails")
    func hourTooHigh() {
        #expect(ADIFFieldValidator.validateTime("2500") != nil)
    }

    @Test("Minute 60 fails")
    func minuteTooHigh() {
        #expect(ADIFFieldValidator.validateTime("1460") != nil)
    }

    @Test("Second 60 fails")
    func secondTooHigh() {
        #expect(ADIFFieldValidator.validateTime("143060") != nil)
    }

    @Test("Wrong length fails")
    func wrongLength() {
        #expect(ADIFFieldValidator.validateTime("143") != nil)
        #expect(ADIFFieldValidator.validateTime("14301") != nil)
    }
}

// MARK: - ADIFFieldValidatorGridTests

struct ADIFFieldValidatorGridTests {
    @Test("Valid grid squares pass")
    func validGrids() {
        #expect(ADIFFieldValidator.validateGridSquare("FN") == nil)
        #expect(ADIFFieldValidator.validateGridSquare("FN31") == nil)
        #expect(ADIFFieldValidator.validateGridSquare("FN31pr") == nil)
        #expect(ADIFFieldValidator.validateGridSquare("FN31pr42") == nil)
        #expect(ADIFFieldValidator.validateGridSquare("AA00") == nil)
        #expect(ADIFFieldValidator.validateGridSquare("RR99") == nil)
    }

    @Test("Odd-length grid fails")
    func oddLength() {
        #expect(ADIFFieldValidator.validateGridSquare("FN3") != nil)
        #expect(ADIFFieldValidator.validateGridSquare("FN31p") != nil)
    }

    @Test("Field character beyond R fails")
    func fieldCharTooHigh() {
        #expect(ADIFFieldValidator.validateGridSquare("ZZ99") != nil)
        #expect(ADIFFieldValidator.validateGridSquare("SA00") != nil)
    }

    @Test("Subsquare character beyond X fails")
    func subsquareCharTooHigh() {
        #expect(ADIFFieldValidator.validateGridSquare("FN31zz") != nil)
    }

    @Test("Empty grid is allowed")
    func emptyGrid() {
        #expect(ADIFFieldValidator.validateGridSquare("") == nil)
    }

    @Test("Grid is case-insensitive")
    func caseInsensitive() {
        #expect(ADIFFieldValidator.validateGridSquare("fn31PR") == nil)
        #expect(ADIFFieldValidator.validateGridSquare("fn31pr42") == nil)
    }
}

// MARK: - ADIFFieldValidatorCallsignTests

struct ADIFFieldValidatorCallsignTests {
    @Test("Non-empty callsigns pass")
    func validCallsigns() {
        #expect(ADIFFieldValidator.validateCallsign("W1AW") == nil)
        #expect(ADIFFieldValidator.validateCallsign("JA1XX") == nil)
    }

    @Test("Empty callsign fails")
    func emptyCallsign() {
        #expect(ADIFFieldValidator.validateCallsign("") != nil)
        #expect(ADIFFieldValidator.validateCallsign("   ") != nil)
    }
}

// MARK: - ADIFFieldValidatorCompositeTests

struct ADIFFieldValidatorCompositeTests {
    @Test("Valid QSO has no violations")
    func validQSO() {
        let violations = ADIFFieldValidator.validateForUpload(
            callsign: "W1AW", band: "20m", mode: "SSB",
            submode: "USB", freqMHz: 14.025,
            dateStr: "20240115", timeStr: "1430", grid: "FN31pr"
        )
        #expect(violations.isEmpty)
    }

    @Test("Multiple violations collected")
    func multipleViolations() {
        let violations = ADIFFieldValidator.validateForUpload(
            callsign: "", band: "Unknown", mode: "UNKNOWN"
        )
        #expect(violations.count == 3)
        let fields = Set(violations.map(\.field))
        #expect(fields.contains(.call))
        #expect(fields.contains(.band))
        #expect(fields.contains(.mode))
    }

    @Test("Optional fields skipped when nil")
    func optionalFieldsSkipped() {
        let violations = ADIFFieldValidator.validateForUpload(
            callsign: "W1AW", band: "20m", mode: "CW"
        )
        #expect(violations.isEmpty)
    }

    @Test("Band/freq mismatch caught in composite")
    func bandFreqMismatch() {
        let violations = ADIFFieldValidator.validateForUpload(
            callsign: "W1AW", band: "20m", mode: "CW", freqMHz: 7.1
        )
        #expect(violations.count == 1)
        #expect(violations.first?.field == .freq)
    }
}

// MARK: - ADIFFieldValidatorRoundTripTests

struct ADIFFieldValidatorRoundTripTests {
    @Test("Valid ADIF string has no violations")
    func validADIF() {
        let adif = """
        <ADIF_VER:5>3.1.7<EOH>
        <CALL:4>W1AW<BAND:3>20m<MODE:2>CW\
        <QSO_DATE:8>20240115<TIME_ON:4>1430<EOR>
        """
        let results = ADIFFieldValidator.validateADIFString(adif)
        #expect(results.isEmpty)
    }

    @Test("ADIF with invalid mode produces violation")
    func invalidModeInADIF() {
        let adif = """
        <ADIF_VER:5>3.1.7<EOH>
        <CALL:4>W1AW<BAND:3>20m<MODE:7>UNKNOWN\
        <QSO_DATE:8>20240115<TIME_ON:4>1430<EOR>
        """
        let results = ADIFFieldValidator.validateADIFString(adif)
        #expect(results.count == 1)
        #expect(results.first?.violations.first?.field == .mode)
    }

    @Test("ADIF with invalid band produces violation")
    func invalidBandInADIF() {
        let adif = """
        <ADIF_VER:5>3.1.7<EOH>
        <CALL:4>W1AW<BAND:7>Unknown<MODE:2>CW\
        <QSO_DATE:8>20240115<TIME_ON:4>1430<EOR>
        """
        let results = ADIFFieldValidator.validateADIFString(adif)
        #expect(results.count == 1)
        #expect(results.first?.violations.first?.field == .band)
    }
}

// MARK: - ADIFFieldValidatorIncidentTests

struct ADIFFieldValidatorIncidentTests {
    @Test("Full chain: PHONE mode gets normalized and passes")
    func phoneChainPasses() {
        let normalized = ModeEquivalence.normalizeForStrictADIF("PHONE")
        let violations = ADIFFieldValidator.validateForUpload(
            callsign: "W1AW", band: "20m",
            mode: normalized.mode, submode: normalized.submode
        )
        #expect(violations.isEmpty)
    }

    @Test("Full chain: DATA mode gets normalized and passes")
    func dataChainPasses() {
        let normalized = ModeEquivalence.normalizeForStrictADIF("DATA")
        let violations = ADIFFieldValidator.validateForUpload(
            callsign: "W1AW", band: "20m",
            mode: normalized.mode, submode: normalized.submode
        )
        #expect(violations.isEmpty)
    }

    @Test("Full chain: UNKNOWN mode remains invalid after normalization")
    func unknownChainFails() {
        let normalized = ModeEquivalence.normalizeForStrictADIF("UNKNOWN")
        let violations = ADIFFieldValidator.validateForUpload(
            callsign: "W1AW", band: "20m",
            mode: normalized.mode, submode: normalized.submode
        )
        #expect(violations.count == 1)
        #expect(violations.first?.field == .mode)
    }

    @Test("Full chain: USB normalizes to SSB+USB and passes")
    func usbChainPasses() {
        let normalized = ModeEquivalence.normalizeForStrictADIF("USB")
        #expect(normalized.mode == "SSB")
        #expect(normalized.submode == "USB")
        let violations = ADIFFieldValidator.validateForUpload(
            callsign: "W1AW", band: "20m",
            mode: normalized.mode, submode: normalized.submode
        )
        #expect(violations.isEmpty)
    }

    @Test("Full chain: FT4 normalizes to MFSK+FT4 and passes")
    func ft4ChainPasses() {
        let normalized = ModeEquivalence.normalizeForStrictADIF("FT4")
        #expect(normalized.mode == "MFSK")
        #expect(normalized.submode == "FT4")
        let violations = ADIFFieldValidator.validateForUpload(
            callsign: "W1AW", band: "20m",
            mode: normalized.mode, submode: normalized.submode
        )
        #expect(violations.isEmpty)
    }
}
