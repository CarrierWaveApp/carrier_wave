# Quick Entry Parser Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow users to enter a complete QSO as a single space-separated string (e.g., `AJ7CM 579 WA US-0189`) with inline preview and auto-population of form fields.

**Architecture:** Create a pure `QuickEntryParser` service that tokenizes input and identifies field types by pattern. Add a `QuickEntryPreview` SwiftUI component for inline feedback. Integrate into `LoggerView` by detecting quick entry mode (space after valid callsign) and parsing on submit.

**Tech Stack:** Swift, SwiftUI, XCTest

---

## Task 1: Create QuickEntryParser with Callsign Detection

**Files:**
- Create: `CarrierWave/Services/QuickEntryParser.swift`
- Create: `CarrierWaveTests/QuickEntryParserTests.swift`

**Step 1: Write the failing test for callsign detection**

Create `CarrierWaveTests/QuickEntryParserTests.swift`:

```swift
//
//  QuickEntryParserTests.swift
//  CarrierWaveTests
//

import XCTest
@testable import CarrierWave

final class QuickEntryParserTests: XCTestCase {

    // MARK: - Callsign Detection

    func testSingleCallsignReturnsNil() {
        // Single callsign without additional tokens is not quick entry
        let result = QuickEntryParser.parse("W1AW")
        XCTAssertNil(result)
    }

    func testCallsignWithSpaceButNoTokensReturnsNil() {
        let result = QuickEntryParser.parse("W1AW ")
        XCTAssertNil(result)
    }

    func testValidCallsignPatterns() {
        // Various valid callsign formats should be recognized
        XCTAssertTrue(QuickEntryParser.isCallsign("W1AW"))
        XCTAssertTrue(QuickEntryParser.isCallsign("K3LR"))
        XCTAssertTrue(QuickEntryParser.isCallsign("VE3ABC"))
        XCTAssertTrue(QuickEntryParser.isCallsign("JA1ABC"))
        XCTAssertTrue(QuickEntryParser.isCallsign("G4ABC"))
        XCTAssertTrue(QuickEntryParser.isCallsign("DL1ABC"))
        XCTAssertTrue(QuickEntryParser.isCallsign("9A1A"))
        XCTAssertTrue(QuickEntryParser.isCallsign("3DA0ABC"))
    }

    func testCallsignWithModifiers() {
        XCTAssertTrue(QuickEntryParser.isCallsign("W1AW/P"))
        XCTAssertTrue(QuickEntryParser.isCallsign("W1AW/M"))
        XCTAssertTrue(QuickEntryParser.isCallsign("I/W1AW"))
        XCTAssertTrue(QuickEntryParser.isCallsign("VE3/K1ABC"))
        XCTAssertTrue(QuickEntryParser.isCallsign("W1AW/MM"))
    }

    func testInvalidCallsignPatterns() {
        XCTAssertFalse(QuickEntryParser.isCallsign("599"))
        XCTAssertFalse(QuickEntryParser.isCallsign("WA"))
        XCTAssertFalse(QuickEntryParser.isCallsign("FREQ"))
        XCTAssertFalse(QuickEntryParser.isCallsign("US-0189"))
        XCTAssertFalse(QuickEntryParser.isCallsign("CN87"))
    }

    func testCommandAsFirstTokenReturnsNil() {
        // Commands should not trigger quick entry
        XCTAssertNil(QuickEntryParser.parse("FREQ 14.060"))
        XCTAssertNil(QuickEntryParser.parse("MODE CW"))
        XCTAssertNil(QuickEntryParser.parse("SPOT"))
    }
}
```

**Step 2: Run test to verify it fails**

Ask user to run: `make test` or run tests in Xcode
Expected: FAIL - QuickEntryParser not defined

**Step 3: Write minimal implementation for callsign detection**

Create `CarrierWave/Services/QuickEntryParser.swift`:

```swift
//
//  QuickEntryParser.swift
//  CarrierWave
//

import Foundation

// MARK: - QuickEntryResult

/// Result of parsing a quick entry string
struct QuickEntryResult: Equatable {
    let callsign: String
    var rstSent: String?
    var rstReceived: String?
    var state: String?
    var theirPark: String?
    var theirGrid: String?
    var notes: String?
}

// MARK: - QuickEntryParser

/// Parses quick entry strings like "AJ7CM 579 WA US-0189" into structured data
enum QuickEntryParser {

    // MARK: - Public API

    /// Parse a quick entry string into structured result
    /// Returns nil if input is not valid quick entry (single callsign or command)
    static func parse(_ input: String) -> QuickEntryResult? {
        let tokens = input.uppercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        // Need at least 2 tokens for quick entry
        guard tokens.count >= 2 else {
            return nil
        }

        // First token must be a callsign
        guard isCallsign(tokens[0]) else {
            return nil
        }

        // Don't trigger quick entry if first token looks like a command
        if LoggerCommand.parse(tokens[0]) != nil {
            return nil
        }

        return QuickEntryResult(callsign: tokens[0])
    }

    /// Check if a string looks like a valid amateur radio callsign
    static func isCallsign(_ string: String) -> Bool {
        let upper = string.uppercased()

        // Handle callsigns with modifiers (prefix/suffix)
        let parts = upper.split(separator: "/").map(String.init)
        let primaryPart = parts.count == 1 ? upper : extractPrimaryCallsign(parts)

        return isBasicCallsign(primaryPart)
    }

    // MARK: - Private Helpers

    /// Check if string matches basic callsign pattern (no modifiers)
    /// Pattern: optional digit/letters prefix + digit + 1-4 letter suffix
    private static func isBasicCallsign(_ string: String) -> Bool {
        // Callsign regex: optional prefix (1-2 chars or digit+letter), required digit, 1-4 letter suffix
        // Examples: W1AW, K3LR, VE3ABC, JA1ABC, G4ABC, DL1ABC, 9A1A, 3DA0ABC
        let pattern = #"^[A-Z0-9]{1,3}[0-9][A-Z]{1,4}$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }

        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }

    /// Extract the primary callsign from parts split by "/"
    private static func extractPrimaryCallsign(_ parts: [String]) -> String {
        let knownSuffixes: Set<String> = ["P", "M", "MM", "AM", "QRP", "R", "A", "B"]

        if parts.count == 2 {
            let first = parts[0]
            let second = parts[1]

            // If second is a known suffix or very short, first is primary
            if knownSuffixes.contains(second) || second.count <= 2 {
                return first
            }
            // If first is very short, it's likely a country prefix
            if first.count <= 2 {
                return second
            }
            // Return the longer one
            return first.count >= second.count ? first : second
        }

        // For 3 parts (prefix/call/suffix): middle is primary
        if parts.count == 3 {
            return parts[1]
        }

        // Fallback: return the longest part
        return parts.max(by: { $0.count < $1.count }) ?? parts[0]
    }
}
```

**Step 4: Run test to verify it passes**

Ask user to run: `make test`
Expected: PASS

**Step 5: Commit**

```bash
git add CarrierWave/Services/QuickEntryParser.swift CarrierWaveTests/QuickEntryParserTests.swift
git commit -m "feat(logger): add QuickEntryParser with callsign detection"
```

---

## Task 2: Add RST Token Detection

**Files:**
- Modify: `CarrierWave/Services/QuickEntryParser.swift`
- Modify: `CarrierWaveTests/QuickEntryParserTests.swift`

**Step 1: Write the failing tests for RST detection**

Add to `QuickEntryParserTests.swift`:

```swift
    // MARK: - RST Detection

    func testSingleRSTAppliedToReceived() {
        let result = QuickEntryParser.parse("W1AW 579")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "W1AW")
        XCTAssertNil(result?.rstSent)
        XCTAssertEqual(result?.rstReceived, "579")
    }

    func testTwoRSTsAppliedToSentAndReceived() {
        let result = QuickEntryParser.parse("W1AW 559 579")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.rstSent, "559")
        XCTAssertEqual(result?.rstReceived, "579")
    }

    func testPhoneRST() {
        let result = QuickEntryParser.parse("W1AW 57")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.rstReceived, "57")
    }

    func testValidRSTPatterns() {
        XCTAssertTrue(QuickEntryParser.isRST("599"))
        XCTAssertTrue(QuickEntryParser.isRST("579"))
        XCTAssertTrue(QuickEntryParser.isRST("339"))
        XCTAssertTrue(QuickEntryParser.isRST("59"))
        XCTAssertTrue(QuickEntryParser.isRST("57"))
        XCTAssertTrue(QuickEntryParser.isRST("44"))
        XCTAssertTrue(QuickEntryParser.isRST("11"))
    }

    func testInvalidRSTPatterns() {
        XCTAssertFalse(QuickEntryParser.isRST("999"))  // R can't be 9
        XCTAssertFalse(QuickEntryParser.isRST("69"))   // R can't be 6
        XCTAssertFalse(QuickEntryParser.isRST("50"))   // S can't be 0
        XCTAssertFalse(QuickEntryParser.isRST("5"))    // Too short
        XCTAssertFalse(QuickEntryParser.isRST("5999")) // Too long
        XCTAssertFalse(QuickEntryParser.isRST("WA"))   // Not a number
    }
```

**Step 2: Run test to verify it fails**

Ask user to run: `make test`
Expected: FAIL - isRST not defined, RST not being parsed

**Step 3: Add RST detection to parser**

Update `QuickEntryParser.swift` - add `isRST` method and update `parse`:

```swift
    // Add to public API section:

    /// Check if a string is a valid RST report
    /// Phone: [1-5][1-9], CW/Digital: [1-5][1-9][1-9]
    static func isRST(_ string: String) -> Bool {
        let upper = string.uppercased()

        // Must be 2 or 3 digits
        guard upper.count == 2 || upper.count == 3,
              upper.allSatisfy({ $0.isNumber })
        else {
            return false
        }

        let digits = upper.map { Int(String($0))! }

        // R (readability): 1-5
        guard digits[0] >= 1, digits[0] <= 5 else {
            return false
        }

        // S (strength): 1-9
        guard digits[1] >= 1, digits[1] <= 9 else {
            return false
        }

        // T (tone) for CW: 1-9 (if present)
        if digits.count == 3 {
            guard digits[2] >= 1, digits[2] <= 9 else {
                return false
            }
        }

        return true
    }
```

Update the `parse` function to process RST tokens:

```swift
    static func parse(_ input: String) -> QuickEntryResult? {
        let tokens = input.uppercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        // Need at least 2 tokens for quick entry
        guard tokens.count >= 2 else {
            return nil
        }

        // First token must be a callsign
        guard isCallsign(tokens[0]) else {
            return nil
        }

        // Don't trigger quick entry if first token looks like a command
        if LoggerCommand.parse(tokens[0]) != nil {
            return nil
        }

        var result = QuickEntryResult(callsign: tokens[0])
        var unrecognized: [String] = []

        // Process remaining tokens
        for token in tokens.dropFirst() {
            if isRST(token) {
                if result.rstReceived == nil {
                    result.rstReceived = token
                } else if result.rstSent == nil {
                    // Shift: first RST was actually sent, this one is received
                    result.rstSent = result.rstReceived
                    result.rstReceived = token
                } else {
                    // Already have both RSTs, treat as notes
                    unrecognized.append(token)
                }
            } else {
                unrecognized.append(token)
            }
        }

        // Unrecognized tokens become notes
        if !unrecognized.isEmpty {
            result.notes = unrecognized.joined(separator: " ")
        }

        return result
    }
```

**Step 4: Run test to verify it passes**

Ask user to run: `make test`
Expected: PASS

**Step 5: Commit**

```bash
git add CarrierWave/Services/QuickEntryParser.swift CarrierWaveTests/QuickEntryParserTests.swift
git commit -m "feat(logger): add RST detection to QuickEntryParser"
```

---

## Task 3: Add Park Reference Detection

**Files:**
- Modify: `CarrierWave/Services/QuickEntryParser.swift`
- Modify: `CarrierWaveTests/QuickEntryParserTests.swift`

**Step 1: Write the failing tests for park reference detection**

Add to `QuickEntryParserTests.swift`:

```swift
    // MARK: - Park Reference Detection

    func testParkReferenceDetection() {
        let result = QuickEntryParser.parse("W1AW US-0189")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.theirPark, "US-0189")
    }

    func testParkReferenceWithOtherTokens() {
        let result = QuickEntryParser.parse("W1AW 579 US-0189")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.rstReceived, "579")
        XCTAssertEqual(result?.theirPark, "US-0189")
    }

    func testValidParkPatterns() {
        XCTAssertTrue(QuickEntryParser.isParkReference("US-0189"))
        XCTAssertTrue(QuickEntryParser.isParkReference("K-1234"))
        XCTAssertTrue(QuickEntryParser.isParkReference("VE-0001"))
        XCTAssertTrue(QuickEntryParser.isParkReference("G-0001"))
        XCTAssertTrue(QuickEntryParser.isParkReference("DL-0001"))
        XCTAssertTrue(QuickEntryParser.isParkReference("JA-12345"))
    }

    func testInvalidParkPatterns() {
        XCTAssertFalse(QuickEntryParser.isParkReference("US0189"))   // Missing dash
        XCTAssertFalse(QuickEntryParser.isParkReference("US-01"))    // Too short
        XCTAssertFalse(QuickEntryParser.isParkReference("USA-0189")) // Prefix too long
        XCTAssertFalse(QuickEntryParser.isParkReference("W1AW"))     // Callsign
        XCTAssertFalse(QuickEntryParser.isParkReference("579"))      // RST
    }
```

**Step 2: Run test to verify it fails**

Ask user to run: `make test`
Expected: FAIL - isParkReference not defined

**Step 3: Add park reference detection to parser**

Add to `QuickEntryParser.swift`:

```swift
    // Add to public API section:

    /// Check if a string is a valid POTA/WWFF park reference
    /// Pattern: 1-2 letter country code, dash, 4-5 digits
    static func isParkReference(_ string: String) -> Bool {
        let upper = string.uppercased()

        // Pattern: XX-#### or XX-#####
        let pattern = #"^[A-Z]{1,2}-[0-9]{4,5}$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }

        let range = NSRange(upper.startIndex..., in: upper)
        return regex.firstMatch(in: upper, options: [], range: range) != nil
    }
```

Update the token processing loop in `parse`:

```swift
        // Process remaining tokens
        for token in tokens.dropFirst() {
            if isRST(token) {
                if result.rstReceived == nil {
                    result.rstReceived = token
                } else if result.rstSent == nil {
                    result.rstSent = result.rstReceived
                    result.rstReceived = token
                } else {
                    unrecognized.append(token)
                }
            } else if isParkReference(token) {
                result.theirPark = token
            } else {
                unrecognized.append(token)
            }
        }
```

**Step 4: Run test to verify it passes**

Ask user to run: `make test`
Expected: PASS

**Step 5: Commit**

```bash
git add CarrierWave/Services/QuickEntryParser.swift CarrierWaveTests/QuickEntryParserTests.swift
git commit -m "feat(logger): add park reference detection to QuickEntryParser"
```

---

## Task 4: Add Grid Square Detection

**Files:**
- Modify: `CarrierWave/Services/QuickEntryParser.swift`
- Modify: `CarrierWaveTests/QuickEntryParserTests.swift`

**Step 1: Write the failing tests for grid square detection**

Add to `QuickEntryParserTests.swift`:

```swift
    // MARK: - Grid Square Detection

    func testGridSquareDetection() {
        let result = QuickEntryParser.parse("W1AW CN87")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.theirGrid, "CN87")
    }

    func testSixCharGridSquare() {
        let result = QuickEntryParser.parse("W1AW FN31pr")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.theirGrid, "FN31PR")
    }

    func testValidGridPatterns() {
        XCTAssertTrue(QuickEntryParser.isGridSquare("CN87"))
        XCTAssertTrue(QuickEntryParser.isGridSquare("FN31"))
        XCTAssertTrue(QuickEntryParser.isGridSquare("JO22"))
        XCTAssertTrue(QuickEntryParser.isGridSquare("AA00"))
        XCTAssertTrue(QuickEntryParser.isGridSquare("RR99"))
        XCTAssertTrue(QuickEntryParser.isGridSquare("FN31pr"))
        XCTAssertTrue(QuickEntryParser.isGridSquare("CN87wk"))
    }

    func testInvalidGridPatterns() {
        XCTAssertFalse(QuickEntryParser.isGridSquare("CN8"))    // Too short
        XCTAssertFalse(QuickEntryParser.isGridSquare("CN877"))  // 5 chars invalid
        XCTAssertFalse(QuickEntryParser.isGridSquare("SN87"))   // S > R
        XCTAssertFalse(QuickEntryParser.isGridSquare("1N87"))   // Starts with number
        XCTAssertFalse(QuickEntryParser.isGridSquare("W1AW"))   // Callsign
        XCTAssertFalse(QuickEntryParser.isGridSquare("WA"))     // State code
    }
```

**Step 2: Run test to verify it fails**

Ask user to run: `make test`
Expected: FAIL - isGridSquare not defined

**Step 3: Add grid square detection to parser**

Add to `QuickEntryParser.swift`:

```swift
    // Add to public API section:

    /// Check if a string is a valid Maidenhead grid square
    /// 4-char: [A-R][A-R][0-9][0-9], 6-char: adds [a-x][a-x]
    static func isGridSquare(_ string: String) -> Bool {
        let upper = string.uppercased()

        // Must be 4 or 6 characters
        guard upper.count == 4 || upper.count == 6 else {
            return false
        }

        let chars = Array(upper)

        // First two: A-R (field)
        guard chars[0] >= "A", chars[0] <= "R",
              chars[1] >= "A", chars[1] <= "R"
        else {
            return false
        }

        // Next two: 0-9 (square)
        guard chars[2].isNumber, chars[3].isNumber else {
            return false
        }

        // If 6 chars, last two: A-X (subsquare)
        if upper.count == 6 {
            guard chars[4] >= "A", chars[4] <= "X",
                  chars[5] >= "A", chars[5] <= "X"
            else {
                return false
            }
        }

        return true
    }
```

Update the token processing loop in `parse`:

```swift
            } else if isParkReference(token) {
                result.theirPark = token
            } else if isGridSquare(token) {
                result.theirGrid = token
            } else {
```

**Step 4: Run test to verify it passes**

Ask user to run: `make test`
Expected: PASS

**Step 5: Commit**

```bash
git add CarrierWave/Services/QuickEntryParser.swift CarrierWaveTests/QuickEntryParserTests.swift
git commit -m "feat(logger): add grid square detection to QuickEntryParser"
```

---

## Task 5: Add State/Region Detection

**Files:**
- Modify: `CarrierWave/Services/QuickEntryParser.swift`
- Modify: `CarrierWaveTests/QuickEntryParserTests.swift`

**Step 1: Write the failing tests for state/region detection**

Add to `QuickEntryParserTests.swift`:

```swift
    // MARK: - State/Region Detection

    func testUSStateDetection() {
        let result = QuickEntryParser.parse("W1AW WA")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.state, "WA")
    }

    func testCanadianProvinceDetection() {
        let result = QuickEntryParser.parse("VE3ABC ON")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.state, "ON")
    }

    func testDXRegionDetection() {
        let result = QuickEntryParser.parse("DL1ABC DL")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.state, "DL")
    }

    func testValidStatePatterns() {
        // US States
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("WA"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("CA"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("TX"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("NY"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("DC"))

        // Canadian Provinces
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("ON"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("BC"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("QC"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("AB"))

        // DX Regions
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("DL"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("EA"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("JA"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("VK"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("ZL"))
    }

    func testInvalidStatePatterns() {
        XCTAssertFalse(QuickEntryParser.isStateOrRegion("XX"))  // Not a real code
        XCTAssertFalse(QuickEntryParser.isStateOrRegion("W1"))  // Callsign prefix
        XCTAssertFalse(QuickEntryParser.isStateOrRegion("599")) // RST
        XCTAssertFalse(QuickEntryParser.isStateOrRegion("USA")) // Too long
    }
```

**Step 2: Run test to verify it fails**

Ask user to run: `make test`
Expected: FAIL - isStateOrRegion not defined

**Step 3: Add state/region detection to parser**

Add to `QuickEntryParser.swift`:

```swift
    // Add to public API section:

    /// Check if a string is a valid US state, Canadian province, or DX region code
    static func isStateOrRegion(_ string: String) -> Bool {
        let upper = string.uppercased()
        return knownRegions.contains(upper)
    }

    // Add as private static property:

    /// Known state/province/region codes
    private static let knownRegions: Set<String> = {
        // US States + DC
        let usStates: Set<String> = [
            "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
            "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
            "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
            "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
            "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
            "DC",
        ]

        // Canadian Provinces/Territories
        let canada: Set<String> = [
            "AB", "BC", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT",
        ]

        // Common DX Region codes (country prefixes used as region identifiers)
        let dxRegions: Set<String> = [
            "DL", // Germany
            "EA", // Spain
            "EI", // Ireland
            "CT", // Portugal (note: also Connecticut - context matters)
            "HA", // Hungary
            "HB", // Switzerland
            "LU", // Argentina
            "LZ", // Bulgaria
            "OE", // Austria
            "OH", // Finland (note: also Ohio - context matters)
            "OK", // Czech Republic (note: also Oklahoma - US takes precedence)
            "OM", // Slovakia
            "OZ", // Denmark
            "PA", // Netherlands (note: also Pennsylvania - US takes precedence)
            "SM", // Sweden
            "SP", // Poland
            "UA", // Russia
            "UR", // Ukraine
            "VK", // Australia
            "ZL", // New Zealand
            "ZS", // South Africa
            "JA", // Japan
            "HL", // South Korea
            "BV", // Taiwan
            "BY", // China
            "YB", // Indonesia
            "HS", // Thailand
            "VU", // India
            "UK", // Uzbekistan
        ]

        return usStates.union(canada).union(dxRegions)
    }()
```

Update the token processing loop in `parse`:

```swift
            } else if isGridSquare(token) {
                result.theirGrid = token
            } else if isStateOrRegion(token) {
                result.state = token
            } else {
```

**Step 4: Run test to verify it passes**

Ask user to run: `make test`
Expected: PASS

**Step 5: Commit**

```bash
git add CarrierWave/Services/QuickEntryParser.swift CarrierWaveTests/QuickEntryParserTests.swift
git commit -m "feat(logger): add state/region detection to QuickEntryParser"
```

---

## Task 6: Add Notes Detection and Integration Tests

**Files:**
- Modify: `CarrierWave/Services/QuickEntryParser.swift`
- Modify: `CarrierWaveTests/QuickEntryParserTests.swift`

**Step 1: Write integration tests for full parsing**

Add to `QuickEntryParserTests.swift`:

```swift
    // MARK: - Notes Detection

    func testUnrecognizedTokensBecomeNotes() {
        let result = QuickEntryParser.parse("W1AW 579 good signal")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.rstReceived, "579")
        XCTAssertEqual(result?.notes, "GOOD SIGNAL")
    }

    func testNotesAtEnd() {
        let result = QuickEntryParser.parse("W1AW 579 WA nice QSO today")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.rstReceived, "579")
        XCTAssertEqual(result?.state, "WA")
        XCTAssertEqual(result?.notes, "NICE QSO TODAY")
    }

    // MARK: - Integration Tests

    func testFullQuickEntry() {
        let result = QuickEntryParser.parse("AJ7CM 579 WA US-0189")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "AJ7CM")
        XCTAssertEqual(result?.rstReceived, "579")
        XCTAssertEqual(result?.state, "WA")
        XCTAssertEqual(result?.theirPark, "US-0189")
        XCTAssertNil(result?.rstSent)
        XCTAssertNil(result?.theirGrid)
        XCTAssertNil(result?.notes)
    }

    func testQuickEntryWithAllFields() {
        let result = QuickEntryParser.parse("W1AW 559 579 FN31 MA US-1234 good op")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "W1AW")
        XCTAssertEqual(result?.rstSent, "559")
        XCTAssertEqual(result?.rstReceived, "579")
        XCTAssertEqual(result?.theirGrid, "FN31")
        XCTAssertEqual(result?.state, "MA")
        XCTAssertEqual(result?.theirPark, "US-1234")
        XCTAssertEqual(result?.notes, "GOOD OP")
    }

    func testQuickEntryTokenOrderIndependent() {
        // Tokens after callsign can be in any order
        let result1 = QuickEntryParser.parse("W1AW WA 579 US-0189")
        let result2 = QuickEntryParser.parse("W1AW US-0189 579 WA")

        XCTAssertEqual(result1?.callsign, result2?.callsign)
        XCTAssertEqual(result1?.rstReceived, result2?.rstReceived)
        XCTAssertEqual(result1?.state, result2?.state)
        XCTAssertEqual(result1?.theirPark, result2?.theirPark)
    }

    func testQuickEntryWithCallsignModifiers() {
        let result = QuickEntryParser.parse("W1AW/P 579 WA")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "W1AW/P")
        XCTAssertEqual(result?.rstReceived, "579")
        XCTAssertEqual(result?.state, "WA")
    }

    func testQuickEntryLowercaseNormalization() {
        let result = QuickEntryParser.parse("w1aw 579 wa us-0189")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "W1AW")
        XCTAssertEqual(result?.state, "WA")
        XCTAssertEqual(result?.theirPark, "US-0189")
    }
```

**Step 2: Run test to verify it passes**

Ask user to run: `make test`
Expected: PASS (notes handling already implemented)

**Step 3: Commit**

```bash
git add CarrierWaveTests/QuickEntryParserTests.swift
git commit -m "test(logger): add integration tests for QuickEntryParser"
```

---

## Task 7: Add Parsed Token Model for Preview

**Files:**
- Modify: `CarrierWave/Services/QuickEntryParser.swift`

**Step 1: Write the failing test for parsed tokens**

Add to `QuickEntryParserTests.swift`:

```swift
    // MARK: - Parsed Tokens for Preview

    func testParsedTokensReturnsColorCodingInfo() {
        let tokens = QuickEntryParser.parseTokens("W1AW 579 WA US-0189")
        XCTAssertEqual(tokens.count, 4)

        XCTAssertEqual(tokens[0].text, "W1AW")
        XCTAssertEqual(tokens[0].type, .callsign)

        XCTAssertEqual(tokens[1].text, "579")
        XCTAssertEqual(tokens[1].type, .rstReceived)

        XCTAssertEqual(tokens[2].text, "WA")
        XCTAssertEqual(tokens[2].type, .state)

        XCTAssertEqual(tokens[3].text, "US-0189")
        XCTAssertEqual(tokens[3].type, .park)
    }

    func testParsedTokensWithNotes() {
        let tokens = QuickEntryParser.parseTokens("W1AW 579 nice signal")
        XCTAssertEqual(tokens.count, 4)

        XCTAssertEqual(tokens[2].text, "NICE")
        XCTAssertEqual(tokens[2].type, .notes)

        XCTAssertEqual(tokens[3].text, "SIGNAL")
        XCTAssertEqual(tokens[3].type, .notes)
    }

    func testParsedTokensWithDualRST() {
        let tokens = QuickEntryParser.parseTokens("W1AW 559 579")
        XCTAssertEqual(tokens.count, 3)

        XCTAssertEqual(tokens[1].text, "559")
        XCTAssertEqual(tokens[1].type, .rstSent)

        XCTAssertEqual(tokens[2].text, "579")
        XCTAssertEqual(tokens[2].type, .rstReceived)
    }
```

**Step 2: Run test to verify it fails**

Ask user to run: `make test`
Expected: FAIL - ParsedToken and parseTokens not defined

**Step 3: Add ParsedToken type and parseTokens method**

Add to `QuickEntryParser.swift`:

```swift
// MARK: - ParsedToken

/// A token with its detected type for UI preview
struct ParsedToken: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let type: TokenType

    enum TokenType: Equatable {
        case callsign
        case rstSent
        case rstReceived
        case state
        case park
        case grid
        case notes
    }

    // Identifiable conformance with stable ID based on content
    static func == (lhs: ParsedToken, rhs: ParsedToken) -> Bool {
        lhs.text == rhs.text && lhs.type == rhs.type
    }
}
```

Add to `QuickEntryParser`:

```swift
    /// Parse input into tokens with type information for preview display
    /// Returns empty array if not valid quick entry
    static func parseTokens(_ input: String) -> [ParsedToken] {
        let tokens = input.uppercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        guard tokens.count >= 2, isCallsign(tokens[0]) else {
            return []
        }

        // Don't parse if first token is a command
        if LoggerCommand.parse(tokens[0]) != nil {
            return []
        }

        var result: [ParsedToken] = []
        var rstCount = 0

        // First token is always callsign
        result.append(ParsedToken(text: tokens[0], type: .callsign))

        // First pass: identify all tokens
        var tokenTypes: [(String, ParsedToken.TokenType?)] = tokens.dropFirst().map { token in
            if isRST(token) {
                return (token, nil) // RST type determined in second pass
            } else if isParkReference(token) {
                return (token, .park)
            } else if isGridSquare(token) {
                return (token, .grid)
            } else if isStateOrRegion(token) {
                return (token, .state)
            } else {
                return (token, .notes)
            }
        }

        // Count RSTs to determine sent/received
        let rstIndices = tokenTypes.enumerated().compactMap { index, pair in
            isRST(pair.0) ? index : nil
        }

        // Assign RST types based on count
        for (i, index) in rstIndices.enumerated() {
            if rstIndices.count == 1 {
                tokenTypes[index].1 = .rstReceived
            } else if i == 0 {
                tokenTypes[index].1 = .rstSent
            } else if i == 1 {
                tokenTypes[index].1 = .rstReceived
            } else {
                tokenTypes[index].1 = .notes // Extra RSTs become notes
            }
        }

        // Build result
        for (text, type) in tokenTypes {
            result.append(ParsedToken(text: text, type: type ?? .notes))
        }

        return result
    }
```

**Step 4: Run test to verify it passes**

Ask user to run: `make test`
Expected: PASS

**Step 5: Commit**

```bash
git add CarrierWave/Services/QuickEntryParser.swift CarrierWaveTests/QuickEntryParserTests.swift
git commit -m "feat(logger): add ParsedToken type for quick entry preview"
```

---

## Task 8: Create QuickEntryPreview Component

**Files:**
- Create: `CarrierWave/Views/Logger/QuickEntryPreview.swift`

**Step 1: Create the preview component**

Create `CarrierWave/Views/Logger/QuickEntryPreview.swift`:

```swift
//
//  QuickEntryPreview.swift
//  CarrierWave
//

import SwiftUI

// MARK: - QuickEntryPreview

/// Displays parsed quick entry tokens with color coding
struct QuickEntryPreview: View {
    let tokens: [ParsedToken]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tokens) { token in
                TokenBadge(token: token)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - TokenBadge

private struct TokenBadge: View {
    let token: ParsedToken

    var body: some View {
        VStack(spacing: 2) {
            Text(token.text)
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(token.type.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(token.type.color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(token.type.label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - TokenType Styling

extension ParsedToken.TokenType {
    var color: Color {
        switch self {
        case .callsign: .green
        case .rstSent: .blue
        case .rstReceived: .blue
        case .state: .orange
        case .park: .green
        case .grid: .purple
        case .notes: .secondary
        }
    }

    var label: String {
        switch self {
        case .callsign: "call"
        case .rstSent: "sent"
        case .rstReceived: "rcvd"
        case .state: "state"
        case .park: "park"
        case .grid: "grid"
        case .notes: "note"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        QuickEntryPreview(tokens: [
            ParsedToken(text: "AJ7CM", type: .callsign),
            ParsedToken(text: "579", type: .rstReceived),
            ParsedToken(text: "WA", type: .state),
            ParsedToken(text: "US-0189", type: .park),
        ])

        QuickEntryPreview(tokens: [
            ParsedToken(text: "W1AW", type: .callsign),
            ParsedToken(text: "559", type: .rstSent),
            ParsedToken(text: "579", type: .rstReceived),
            ParsedToken(text: "FN31", type: .grid),
            ParsedToken(text: "NICE", type: .notes),
            ParsedToken(text: "QSO", type: .notes),
        ])
    }
    .padding()
}
```

**Step 2: Verify the preview builds**

Ask user to build in Xcode and check the Preview canvas.

**Step 3: Commit**

```bash
git add CarrierWave/Views/Logger/QuickEntryPreview.swift
git commit -m "feat(logger): add QuickEntryPreview component"
```

---

## Task 9: Integrate Quick Entry into LoggerView

**Files:**
- Modify: `CarrierWave/Views/Logger/LoggerView.swift`

**Step 1: Add quick entry state and detection**

Add new state variable in LoggerView (around line 225, near other @State properties):

```swift
    /// Parsed quick entry result (when in quick entry mode)
    @State private var quickEntryResult: QuickEntryResult?

    /// Parsed tokens for preview display
    @State private var quickEntryTokens: [ParsedToken] = []
```

**Step 2: Add quick entry preview to callsignInputSection**

Update the `callsignInputSection` computed property. After the command description badge and before the cancel spot button, add the quick entry preview:

Find this section (around line 640):

```swift
            // Command description badge
            if let command = detectedCommand {
                // ... existing code ...
            }
```

Add after it:

```swift
            // Quick entry preview
            if !quickEntryTokens.isEmpty, detectedCommand == nil {
                QuickEntryPreview(tokens: quickEntryTokens)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
```

**Step 3: Update onCallsignChanged to detect quick entry**

In the `onCallsignChanged` function, add quick entry detection after the command check. Find this code (around line 1185):

```swift
        // Don't lookup if too short or looks like a command
        guard trimmed.count >= 3,
              LoggerCommand.parse(trimmed) == nil
        else {
            lookupResult = nil
            lookupError = nil
            return
        }
```

Replace the whole function with:

```swift
    private func onCallsignChanged(_ callsign: String) {
        lookupTask?.cancel()

        // Update cached POTA duplicate status
        cachedPotaDuplicateStatus = computePotaDuplicateStatus()

        let trimmed = callsign.trimmingCharacters(in: .whitespaces).uppercased()

        // Check for quick entry mode (space + additional tokens)
        if trimmed.contains(" ") {
            quickEntryTokens = QuickEntryParser.parseTokens(trimmed)
            quickEntryResult = QuickEntryParser.parse(trimmed)
        } else {
            quickEntryTokens = []
            quickEntryResult = nil
        }

        // Don't lookup if too short or looks like a command
        guard trimmed.count >= 3,
              LoggerCommand.parse(trimmed) == nil
        else {
            lookupResult = nil
            lookupError = nil
            return
        }

        // In quick entry mode, lookup the parsed callsign
        let callsignToLookup: String
        if let result = quickEntryResult {
            callsignToLookup = extractPrimaryCallsign(result.callsign)
        } else {
            callsignToLookup = extractPrimaryCallsign(trimmed)
        }

        // Don't lookup if primary is too short
        guard callsignToLookup.count >= 3 else {
            lookupResult = nil
            lookupError = nil
            return
        }

        let service = CallsignLookupService(modelContext: modelContext)
        lookupTask = Task {
            try? await Task.sleep(for: .milliseconds(300))

            guard !Task.isCancelled else {
                return
            }

            let result = await service.lookupWithResult(callsignToLookup)

            await MainActor.run {
                lookupResult = result.info
                if result.error == .notFound {
                    lookupError = nil
                } else {
                    lookupError = result.error
                }
            }
        }
    }
```

**Step 4: Update handleInputSubmit to use quick entry result**

Update the `handleInputSubmit` function (around line 1030):

```swift
    private func handleInputSubmit() {
        // Check if it's a command
        if let command = LoggerCommand.parse(callsignInput) {
            executeCommand(command)
            callsignInput = ""
            return
        }

        // Check for quick entry mode
        if let quickEntry = quickEntryResult {
            logQuickEntry(quickEntry)
            return
        }

        // Otherwise try to log normally
        if canLog {
            logQSO()
        }
    }
```

**Step 5: Add logQuickEntry function**

Add a new function after `logQSO()` (around line 1300):

```swift
    /// Log a QSO from quick entry parsed result
    private func logQuickEntry(_ entry: QuickEntryResult) {
        guard sessionManager?.hasActiveSession == true else {
            return
        }

        // Use quick entry values, falling back to lookup data
        let gridToUse = entry.theirGrid ?? lookupResult?.grid
        let stateToUse = entry.state ?? lookupResult?.state

        _ = sessionManager?.logQSO(
            callsign: entry.callsign,
            rstSent: entry.rstSent ?? defaultRST,
            rstReceived: entry.rstReceived ?? defaultRST,
            theirGrid: gridToUse,
            theirParkReference: entry.theirPark,
            notes: entry.notes,
            name: lookupResult?.name,
            operatorName: lookupResult?.displayName,
            state: stateToUse,
            country: lookupResult?.country,
            qth: lookupResult?.qth,
            theirLicenseClass: lookupResult?.licenseClass
        )

        // Refresh the QSO list
        refreshSessionQSOs()

        // Restore session frequency if tuned for a spot
        if let freq = preSpotFrequency {
            _ = sessionManager?.updateFrequency(freq)
            preSpotFrequency = nil
        }

        // Reset form
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            callsignInput = ""
            lookupResult = nil
            lookupError = nil
            cachedPotaDuplicateStatus = nil
            quickEntryResult = nil
            quickEntryTokens = []
            theirGrid = ""
            theirState = ""
            theirPark = ""
            notes = ""
            operatorName = ""
            rstSent = ""
            rstReceived = ""
        }

        callsignFieldFocused = true
    }
```

**Step 6: Update canLog to work with quick entry**

Update the `canLog` computed property to also check quick entry:

```swift
    private var canLog: Bool {
        // Quick entry mode - check the parsed callsign
        if let entry = quickEntryResult {
            guard entry.callsign.count >= 3 else {
                return false
            }

            let myCallsign = sessionManager?.activeSession?.myCallsign.uppercased() ?? ""
            if !myCallsign.isEmpty, entry.callsign.uppercased() == myCallsign {
                return false
            }

            return sessionManager?.hasActiveSession == true
        }

        // Normal mode
        guard sessionManager?.hasActiveSession == true,
              !callsignInput.isEmpty,
              callsignInput.count >= 3
        else {
            return false
        }

        let myCallsign = sessionManager?.activeSession?.myCallsign.uppercased() ?? ""
        if !myCallsign.isEmpty, callsignInput.uppercased() == myCallsign {
            return false
        }

        if case .duplicateBand = potaDuplicateStatus {
            return false
        }

        return true
    }
```

**Step 7: Verify changes compile**

Ask user to build in Xcode.

**Step 8: Commit**

```bash
git add CarrierWave/Views/Logger/LoggerView.swift
git commit -m "feat(logger): integrate quick entry parsing into LoggerView"
```

---

## Task 10: Add Tour Page for Quick Entry

**Files:**
- Modify: `CarrierWave/Views/Tour/MiniTourContent.swift`

**Step 1: Add the tour page**

In `MiniTourContent.swift`, add a new page to the `logger` array (after the "Logger Commands" page, around line 45):

```swift
        TourPage(
            icon: "text.line.first.and.arrowtriangle.forward",
            title: "Quick Entry",
            body: """
            Type everything in one line: callsign, RST, state, park reference, and notes. \
            Example: "AJ7CM 579 WA US-0189" fills the form automatically.
            """
        ),
```

**Step 2: Verify changes compile**

Ask user to build in Xcode.

**Step 3: Commit**

```bash
git add CarrierWave/Views/Tour/MiniTourContent.swift
git commit -m "docs(tour): add quick entry explanation to logger tour"
```

---

## Task 11: Update File Index and Changelog

**Files:**
- Modify: `docs/FILE_INDEX.md`
- Modify: `CHANGELOG.md`

**Step 1: Update FILE_INDEX.md**

Add to the Services section:

```markdown
| `QuickEntryParser.swift` | Parse quick entry strings (callsign RST state park) into structured data |
```

Add to the Views - Logger section:

```markdown
| `QuickEntryPreview.swift` | Inline token preview for quick entry mode |
```

**Step 2: Update CHANGELOG.md**

Add under `## [Unreleased]` → `### Added`:

```markdown
- Quick entry mode in logger: type "AJ7CM 579 WA US-0189" to auto-fill callsign, RST, state, and park reference
```

**Step 3: Commit**

```bash
git add docs/FILE_INDEX.md CHANGELOG.md
git commit -m "docs: update file index and changelog for quick entry feature"
```

---

## Task 12: Final Verification

**Step 1: Run all tests**

Ask user to run: `make test`
Expected: All tests pass

**Step 2: Manual testing checklist**

Ask user to test in the iOS Simulator:

1. Start a logging session
2. Type `W1AW 579` - should show preview with callsign (green) and RST (blue)
3. Type `W1AW 559 579 WA` - should show sent RST, received RST, and state
4. Type `W1AW 579 US-0189` - should show park reference
5. Type `W1AW FN31` - should show grid square
6. Type `W1AW 579 nice signal` - should show notes in gray
7. Press Return on any of the above - should log QSO with fields populated
8. Verify the logger tour includes the new Quick Entry page

**Step 3: Final commit (if any fixes needed)**

```bash
git add -A
git commit -m "fix(logger): address quick entry review feedback"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Callsign detection | QuickEntryParser.swift, QuickEntryParserTests.swift |
| 2 | RST detection | QuickEntryParser.swift |
| 3 | Park reference detection | QuickEntryParser.swift |
| 4 | Grid square detection | QuickEntryParser.swift |
| 5 | State/region detection | QuickEntryParser.swift |
| 6 | Notes + integration tests | QuickEntryParserTests.swift |
| 7 | ParsedToken for preview | QuickEntryParser.swift |
| 8 | QuickEntryPreview component | QuickEntryPreview.swift |
| 9 | LoggerView integration | LoggerView.swift |
| 10 | Tour page | MiniTourContent.swift |
| 11 | Documentation | FILE_INDEX.md, CHANGELOG.md |
| 12 | Final verification | - |
