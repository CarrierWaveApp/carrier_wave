//
//  CallsignDetectorTests.swift
//  CarrierWaveCoreTests
//

import Testing
@testable import CarrierWaveCore

@Suite("Callsign Detector Tests")
struct CallsignDetectorTests {
    // MARK: - Extract Callsigns

    @Test("Extract single callsign")
    func extractSingleCallsign() {
        let callsigns = CallsignDetector.extractCallsigns(from: "CQ CQ DE W1AW K")
        #expect(callsigns.contains("W1AW"))
    }

    @Test("Extract multiple callsigns")
    func extractMultipleCallsigns() {
        let callsigns = CallsignDetector.extractCallsigns(from: "W1AW DE K2ABC K")
        #expect(callsigns.contains("W1AW"))
        #expect(callsigns.contains("K2ABC"))
    }

    @Test("Extract international callsigns")
    func extractInternationalCallsigns() {
        let callsigns = CallsignDetector.extractCallsigns(from: "VK2ABC JA1XYZ 9A2AA")
        #expect(callsigns.contains("VK2ABC"))
        #expect(callsigns.contains("JA1XYZ"))
        #expect(callsigns.contains("9A2AA"))
    }

    @Test("Filter out false positives")
    func filterFalsePositives() {
        let callsigns = CallsignDetector.extractCallsigns(from: "73 88 1ST 2ND")
        #expect(!callsigns.contains("73"))
        #expect(!callsigns.contains("1ST"))
        #expect(!callsigns.contains("2ND"))
    }

    @Test("Case insensitive extraction")
    func caseInsensitive() {
        let callsigns = CallsignDetector.extractCallsigns(from: "w1aw k2abc")
        #expect(callsigns.contains("W1AW"))
        #expect(callsigns.contains("K2ABC"))
    }

    @Test("No duplicates returned")
    func noDuplicates() {
        let callsigns = CallsignDetector.extractCallsigns(from: "W1AW W1AW W1AW")
        #expect(callsigns.count == 1)
        #expect(callsigns.first == "W1AW")
    }

    // MARK: - Detect Primary Callsign

    @Test("Detect callsign after DE")
    func detectAfterDE() {
        let result = CallsignDetector.detectPrimaryCallsign(from: "W1XYZ DE K2ABC K")
        #expect(result?.callsign == "K2ABC")
        #expect(result?.context == .deIdentifier)
    }

    @Test("Detect callsign from CQ call")
    func detectFromCQ() {
        // When DE is present, it takes priority over CQ context
        let result = CallsignDetector.detectPrimaryCallsign(from: "CQ CQ DE W1AW W1AW K")
        #expect(result?.callsign == "W1AW")
        // DE identifier takes priority over CQ call
        #expect(result?.context == .deIdentifier)
    }

    @Test("Detect response callsign")
    func detectResponse() {
        let result = CallsignDetector.detectPrimaryCallsign(from: "W1AW DE K2ABC")
        // K2ABC is after DE, so it's the identifier
        #expect(result?.callsign == "K2ABC")
    }

    @Test("No callsigns returns nil")
    func noCallsigns() {
        let result = CallsignDetector.detectPrimaryCallsign(from: "CQ CQ CQ DE K")
        #expect(result == nil)
    }

    // MARK: - Parse Elements

    @Test("Parse prosigns")
    func parseProsigns() {
        let elements = CallsignDetector.parseElements(from: "CQ DE K")
        let prosigns = elements.compactMap { element -> String? in
            if case let .prosign(str) = element {
                return str
            }
            return nil
        }
        #expect(prosigns.contains("CQ"))
        #expect(prosigns.contains("DE"))
        #expect(prosigns.contains("K"))
    }

    @Test("Parse callsign elements")
    func parseCallsignElements() {
        let elements = CallsignDetector.parseElements(from: "CQ DE W1AW K")
        let callsigns = elements.compactMap { element -> String? in
            if case let .callsign(str, _) = element {
                return str
            }
            return nil
        }
        #expect(callsigns.contains("W1AW"))
    }

    @Test("Parse signal report")
    func parseSignalReport() {
        let elements = CallsignDetector.parseElements(from: "UR RST 599")
        let reports = elements.compactMap { element -> String? in
            if case let .signalReport(str) = element {
                return str
            }
            return nil
        }
        #expect(reports.contains("599"))
    }

    @Test("Parse grid square")
    func parseGridSquare() {
        let elements = CallsignDetector.parseElements(from: "QTH EM74")
        let grids = elements.compactMap { element -> String? in
            if case let .grid(str) = element {
                return str
            }
            return nil
        }
        #expect(grids.contains("EM74"))
    }

    @Test("Parse power level")
    func parsePowerLevel() {
        // Power level is parsed when it appears with other content
        // "100W" alone matches callsign pattern, so use a more realistic context
        let elements = CallsignDetector.parseElements(from: "PWR 5W QTH")
        let powers = elements.compactMap { element -> String? in
            if case let .power(str) = element {
                return str
            }
            return nil
        }
        #expect(powers.contains("5W"))
    }

    @Test("Parse name after keyword")
    func parseNameAfterKeyword() {
        let elements = CallsignDetector.parseElements(from: "NAME JOHN")
        let names = elements.compactMap { element -> String? in
            if case let .name(str) = element {
                return str
            }
            return nil
        }
        #expect(names.contains("JOHN"))
    }

    // MARK: - Callsign Role Detection

    @Test("Caller role after CQ")
    func callerRoleAfterCQ() {
        let elements = CallsignDetector.parseElements(from: "CQ CQ W1AW")
        let callsignElements = elements.compactMap {
            element -> (String, CWTextElement.CallsignRole)? in
            if case let .callsign(str, role) = element {
                return (str, role)
            }
            return nil
        }
        let w1aw = callsignElements.first { $0.0 == "W1AW" }
        #expect(w1aw?.1 == .caller)
    }

    @Test("Callee role after DE")
    func calleeRoleAfterDE() {
        let elements = CallsignDetector.parseElements(from: "W1XYZ DE K2ABC")
        let callsignElements = elements.compactMap {
            element -> (String, CWTextElement.CallsignRole)? in
            if case let .callsign(str, role) = element {
                return (str, role)
            }
            return nil
        }
        let k2abc = callsignElements.first { $0.0 == "K2ABC" }
        #expect(k2abc?.1 == .callee)
    }
}
