# FT8 Digital Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add full FT8 transmit and receive capability to Carrier Wave, integrated with the existing logging and sync pipeline.

**Architecture:** Vendor ft8_lib (C, MIT) as a C target in CarrierWaveCore SPM package. Swift overlay provides `FT8Decoder`/`FT8Encoder`/`FT8Message` types. App target adds `FT8AudioEngine` (actor for AVAudioEngine), `FT8SessionManager` (@MainActor @Observable QSO state machine), and SwiftUI views that conditionally replace the standard logger form when mode is FT8.

**Tech Stack:** ft8_lib (C), KISS FFT (bundled), AVAudioEngine, Swift Testing, SwiftUI, SwiftData

**Design doc:** `docs/plans/2026-02-25-ft8-design.md`

---

## Task 1: Vendor ft8_lib C Sources into CarrierWaveCore

**Files:**
- Create: `CarrierWaveCore/Sources/CFT8/include/module.modulemap`
- Create: `CarrierWaveCore/Sources/CFT8/ft8/*.c` and `CarrierWaveCore/Sources/CFT8/ft8/*.h` (7 pairs)
- Create: `CarrierWaveCore/Sources/CFT8/fft/*.c` and `CarrierWaveCore/Sources/CFT8/fft/*.h` (2 pairs + 1 internal header)
- Create: `CarrierWaveCore/Sources/CFT8/common/monitor.c`, `monitor.h`, `common.h`
- Modify: `CarrierWaveCore/Package.swift`

**Step 1: Clone ft8_lib and copy source files**

```bash
cd /tmp && git clone https://github.com/kgoba/ft8_lib.git
```

Copy the minimal file set into `CarrierWaveCore/Sources/CFT8/`:

```
CFT8/
├── include/
│   └── module.modulemap
├── ft8/
│   ├── constants.c, constants.h
│   ├── crc.c, crc.h
│   ├── debug.h
│   ├── decode.c, decode.h
│   ├── encode.c, encode.h
│   ├── ldpc.c, ldpc.h
│   ├── message.c, message.h
│   └── text.c, text.h
├── fft/
│   ├── _kiss_fft_guts.h
│   ├── kiss_fft.c, kiss_fft.h
│   └── kiss_fftr.c, kiss_fftr.h
└── common/
    ├── common.h
    ├── monitor.c
    └── monitor.h
```

Do NOT copy `common/wave.c`, `common/wave.h`, `common/audio.c`, `common/audio.h` — those are for file I/O and PortAudio, not needed.

**Step 2: Create the module map**

Write `CarrierWaveCore/Sources/CFT8/include/module.modulemap`:

```
module CFT8 {
    header "../ft8/constants.h"
    header "../ft8/crc.h"
    header "../ft8/decode.h"
    header "../ft8/encode.h"
    header "../ft8/ldpc.h"
    header "../ft8/message.h"
    header "../ft8/text.h"
    header "../common/monitor.h"
    header "../common/common.h"
    export *
}
```

**Step 3: Fix include paths for SPM compatibility**

ft8_lib uses root-relative includes like `#include "ft8/decode.h"` and `#include "fft/kiss_fft.h"`. Since SPM compiles from within the `CFT8/` directory, these paths work as-is because the `ft8/`, `fft/`, and `common/` subdirectories are direct children. Verify no includes reference paths outside `CFT8/`.

The `monitor.h` includes `fft/kiss_fftr.h` and `ft8/decode.h` — these should resolve correctly.

**Step 4: Update Package.swift**

Modify `CarrierWaveCore/Package.swift` to add the C target and make CarrierWaveCore depend on it:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CarrierWaveCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    products: [
        .library(name: "CarrierWaveCore", targets: ["CarrierWaveCore"]),
        .executable(name: "LoFiCLI", targets: ["LoFiCLI"]),
    ],
    targets: [
        .target(
            name: "CFT8",
            path: "Sources/CFT8",
            exclude: [],
            publicHeadersPath: "include",
            cSettings: [
                .define("HAVE_STPCPY"),
                .headerSearchPath("."),
            ]
        ),
        .target(
            name: "CarrierWaveCore",
            dependencies: ["CFT8"]
        ),
        .executableTarget(
            name: "LoFiCLI",
            dependencies: ["CarrierWaveCore"]
        ),
        .testTarget(
            name: "CarrierWaveCoreTests",
            dependencies: ["CarrierWaveCore"],
            resources: [
                .copy("Resources/ft8-samples"),
            ]
        ),
    ]
)
```

Key additions:
- `CFT8` C target with `publicHeadersPath: "include"` and `cSettings` for `HAVE_STPCPY` and header search path
- `CarrierWaveCore` now depends on `CFT8`
- Test target gets a `resources` declaration for WAV test samples

**Step 5: Copy test WAV samples into test resources**

```bash
mkdir -p CarrierWaveCore/Tests/CarrierWaveCoreTests/Resources/ft8-samples
cp docs/plans/ft8-samples/ft8_lib_test_vectors/*.wav \
   CarrierWaveCore/Tests/CarrierWaveCoreTests/Resources/ft8-samples/
cp docs/plans/ft8-samples/ft8_lib_test_vectors/*.txt \
   CarrierWaveCore/Tests/CarrierWaveCoreTests/Resources/ft8-samples/
cp docs/plans/ft8-samples/ft8_lib_test_vectors/20m_busy/*.wav \
   CarrierWaveCore/Tests/CarrierWaveCoreTests/Resources/ft8-samples/
cp docs/plans/ft8-samples/ft8_lib_test_vectors/20m_busy/*.txt \
   CarrierWaveCore/Tests/CarrierWaveCoreTests/Resources/ft8-samples/
cp docs/plans/ft8-samples/*.wav \
   CarrierWaveCore/Tests/CarrierWaveCoreTests/Resources/ft8-samples/
```

**Step 6: Verify the C target compiles**

Run: `cd CarrierWaveCore && swift build`

Expected: Build succeeds with no errors. There may be warnings from the C code (unused variables, etc.) — these are acceptable for vendored code.

**Step 7: Commit**

```bash
git add CarrierWaveCore/Sources/CFT8/ CarrierWaveCore/Package.swift \
        CarrierWaveCore/Tests/CarrierWaveCoreTests/Resources/
git commit -m "Vendor ft8_lib C sources as CFT8 target in CarrierWaveCore

MIT-licensed C library for FT8 encode/decode by Karlis Goba.
Includes KISS FFT (bundled), monitor for waterfall computation,
and full LDPC(174,91) codec. Test WAV samples with expected
decode outputs copied to test resources."
```

---

## Task 2: FT8 Constants and Message Types (Swift)

**Files:**
- Create: `CarrierWaveCore/Sources/CarrierWaveCore/FT8Constants.swift`
- Create: `CarrierWaveCore/Sources/CarrierWaveCore/FT8Message.swift`

**Step 1: Write failing test for FT8 constants**

Create `CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8ConstantsTests.swift`:

```swift
//
//  FT8ConstantsTests.swift
//  CarrierWaveCore
//

import Testing
@testable import CarrierWaveCore

@Suite("FT8 Constants Tests")
struct FT8ConstantsTests {
    @Test("Standard FT8 dial frequencies by band")
    func dialFrequencies() {
        #expect(FT8Constants.dialFrequency(forBand: "20m") == 14.074)
        #expect(FT8Constants.dialFrequency(forBand: "40m") == 7.074)
        #expect(FT8Constants.dialFrequency(forBand: "80m") == 3.573)
        #expect(FT8Constants.dialFrequency(forBand: "10m") == 28.074)
        #expect(FT8Constants.dialFrequency(forBand: "6m") == 50.313)
        #expect(FT8Constants.dialFrequency(forBand: "160m") == 1.840)
        #expect(FT8Constants.dialFrequency(forBand: "999m") == nil)
    }

    @Test("Band from FT8 dial frequency")
    func bandFromFrequency() {
        #expect(FT8Constants.band(forDialFrequency: 14.074) == "20m")
        #expect(FT8Constants.band(forDialFrequency: 7.074) == "40m")
        #expect(FT8Constants.band(forDialFrequency: 99.999) == nil)
    }

    @Test("Protocol timing constants")
    func timing() {
        #expect(FT8Constants.slotDuration == 15.0)
        #expect(FT8Constants.symbolPeriod == 0.160)
        #expect(FT8Constants.sampleRate == 12000)
        #expect(FT8Constants.toneSpacing == 6.25)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd CarrierWaveCore && swift test --filter FT8ConstantsTests`
Expected: FAIL — `FT8Constants` not defined

**Step 3: Implement FT8Constants**

Write `CarrierWaveCore/Sources/CarrierWaveCore/FT8Constants.swift`:

```swift
//
//  FT8Constants.swift
//  CarrierWaveCore
//

/// FT8 protocol constants and standard dial frequencies.
public enum FT8Constants: Sendable {
    // MARK: - Timing

    /// Duration of one TX/RX slot in seconds.
    public static let slotDuration: Double = 15.0

    /// Duration of one symbol in seconds (1/6.25 baud).
    public static let symbolPeriod: Double = 0.160

    /// Tone spacing in Hz.
    public static let toneSpacing: Double = 6.25

    /// Number of tones (8-FSK).
    public static let toneCount = 8

    /// Total symbols per transmission (58 data + 21 Costas sync).
    public static let totalSymbols = 79

    /// Transmission duration in seconds (79 * 0.160).
    public static let txDuration: Double = 12.64

    /// Required audio sample rate in Hz.
    public static let sampleRate = 12000

    /// Samples per 15-second slot.
    public static let samplesPerSlot = 180_000

    // MARK: - Dial Frequencies

    /// Standard FT8 dial frequencies (MHz) indexed by band name.
    private static let dialFrequencies: [String: Double] = [
        "160m": 1.840,
        "80m": 3.573,
        "60m": 5.357,
        "40m": 7.074,
        "30m": 10.136,
        "20m": 14.074,
        "17m": 18.100,
        "15m": 21.074,
        "12m": 24.915,
        "10m": 28.074,
        "6m": 50.313,
        "2m": 144.174,
        "70cm": 432.174,
    ]

    /// Returns the standard FT8 dial frequency for a band, or nil if unknown.
    public static func dialFrequency(forBand band: String) -> Double? {
        dialFrequencies[band]
    }

    /// Returns the band name for a given FT8 dial frequency, or nil if not a standard FT8 frequency.
    public static func band(forDialFrequency frequency: Double) -> String? {
        dialFrequencies.first { abs($0.value - frequency) < 0.001 }?.key
    }

    /// All supported bands in frequency order.
    public static let supportedBands: [String] = [
        "160m", "80m", "60m", "40m", "30m", "20m",
        "17m", "15m", "12m", "10m", "6m", "2m", "70cm",
    ]
}
```

**Step 4: Write failing test for FT8Message**

Add to a new file `CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8MessageTests.swift`:

```swift
//
//  FT8MessageTests.swift
//  CarrierWaveCore
//

import Testing
@testable import CarrierWaveCore

@Suite("FT8 Message Tests")
struct FT8MessageTests {
    @Test("CQ message properties")
    func cqMessage() {
        let msg = FT8Message.cq(call: "K1ABC", grid: "FN42", modifier: nil)
        #expect(msg.isCallable)
        #expect(msg.callerCallsign == "K1ABC")
        #expect(msg.grid == "FN42")
    }

    @Test("CQ POTA message properties")
    func cqPotaMessage() {
        let msg = FT8Message.cq(call: "K7ABC", grid: "CN87", modifier: "POTA")
        #expect(msg.isCallable)
        #expect(msg.callerCallsign == "K7ABC")
        #expect(msg.cqModifier == "POTA")
    }

    @Test("Signal report message")
    func signalReport() {
        let msg = FT8Message.signalReport(from: "W9XYZ", to: "K1ABC", dB: -11)
        #expect(!msg.isCallable)
        #expect(msg.isDirectedTo("K1ABC"))
        #expect(!msg.isDirectedTo("W9XYZ"))
    }

    @Test("RR73 message completes QSO")
    func rr73CompletesQSO() {
        let msg = FT8Message.rogerEnd(from: "K1ABC", to: "W9XYZ")
        #expect(msg.completesQSO)
    }

    @Test("Standard message does not complete QSO")
    func standardDoesNotComplete() {
        let msg = FT8Message.signalReport(from: "K1ABC", to: "W9XYZ", dB: -12)
        #expect(!msg.completesQSO)
    }

    @Test("Parse from raw text - CQ")
    func parseRawCQ() {
        let msg = FT8Message.parse("CQ K1ABC FN42")
        #expect(msg == .cq(call: "K1ABC", grid: "FN42", modifier: nil))
    }

    @Test("Parse from raw text - CQ POTA")
    func parseRawCQPOTA() {
        let msg = FT8Message.parse("CQ POTA K7ABC CN87")
        #expect(msg == .cq(call: "K7ABC", grid: "CN87", modifier: "POTA"))
    }

    @Test("Parse from raw text - signal report")
    func parseRawReport() {
        let msg = FT8Message.parse("W9XYZ K1ABC -11")
        #expect(msg == .signalReport(from: "K1ABC", to: "W9XYZ", dB: -11))
    }

    @Test("Parse from raw text - RR73")
    func parseRawRR73() {
        let msg = FT8Message.parse("W9XYZ K1ABC RR73")
        #expect(msg == .rogerEnd(from: "K1ABC", to: "W9XYZ"))
    }

    @Test("Parse from raw text - directed with grid")
    func parseRawDirectedGrid() {
        let msg = FT8Message.parse("K1ABC W9XYZ EN37")
        #expect(msg == .directed(from: "W9XYZ", to: "K1ABC", grid: "EN37"))
    }

    @Test("Parse from raw text - roger report")
    func parseRawRogerReport() {
        let msg = FT8Message.parse("K1ABC W9XYZ R-07")
        #expect(msg == .rogerReport(from: "W9XYZ", to: "K1ABC", dB: -7))
    }

    @Test("Parse from raw text - free text")
    func parseRawFreeText() {
        let msg = FT8Message.parse("TNX BOB 73 GL")
        #expect(msg == .freeText("TNX BOB 73 GL"))
    }
}
```

**Step 5: Run test to verify it fails**

Run: `cd CarrierWaveCore && swift test --filter FT8MessageTests`
Expected: FAIL — `FT8Message` not defined

**Step 6: Implement FT8Message**

Write `CarrierWaveCore/Sources/CarrierWaveCore/FT8Message.swift`:

```swift
//
//  FT8Message.swift
//  CarrierWaveCore
//

/// A parsed FT8 message with typed fields.
public enum FT8Message: Sendable, Equatable, Hashable {
    /// CQ call. modifier is optional (e.g., "POTA", "DX", "NA", "JA", or 3-digit numeric).
    case cq(call: String, grid: String, modifier: String?)
    /// Directed message with grid square (response to CQ).
    case directed(from: String, to: String, grid: String)
    /// Signal report (e.g., -12 dB).
    case signalReport(from: String, to: String, dB: Int)
    /// Roger + signal report (e.g., R-07).
    case rogerReport(from: String, to: String, dB: Int)
    /// Roger acknowledgment (RRR).
    case roger(from: String, to: String)
    /// Roger + 73 (RR73) — completes QSO.
    case rogerEnd(from: String, to: String)
    /// 73 farewell.
    case end(from: String, to: String)
    /// Free text (up to 13 characters).
    case freeText(String)

    // MARK: - Computed Properties

    /// Whether this message is a CQ that can be replied to.
    public var isCallable: Bool {
        if case .cq = self { return true }
        return false
    }

    /// Whether this message completes a QSO exchange.
    public var completesQSO: Bool {
        switch self {
        case .rogerEnd, .end: return true
        default: return false
        }
    }

    /// The callsign of the station that sent this message.
    public var callerCallsign: String? {
        switch self {
        case let .cq(call, _, _): return call
        case let .directed(from, _, _): return from
        case let .signalReport(from, _, _): return from
        case let .rogerReport(from, _, _): return from
        case let .roger(from, _): return from
        case let .rogerEnd(from, _): return from
        case let .end(from, _): return from
        case .freeText: return nil
        }
    }

    /// The grid square, if present.
    public var grid: String? {
        switch self {
        case let .cq(_, grid, _): return grid.isEmpty ? nil : grid
        case let .directed(_, _, grid): return grid.isEmpty ? nil : grid
        default: return nil
        }
    }

    /// The CQ modifier (POTA, DX, etc.), if this is a CQ message.
    public var cqModifier: String? {
        if case let .cq(_, _, modifier) = self { return modifier }
        return nil
    }

    /// Whether this message is directed to the given callsign.
    public func isDirectedTo(_ callsign: String) -> Bool {
        switch self {
        case let .directed(_, to, _): return to.uppercased() == callsign.uppercased()
        case let .signalReport(_, to, _): return to.uppercased() == callsign.uppercased()
        case let .rogerReport(_, to, _): return to.uppercased() == callsign.uppercased()
        case let .roger(_, to): return to.uppercased() == callsign.uppercased()
        case let .rogerEnd(_, to): return to.uppercased() == callsign.uppercased()
        case let .end(_, to): return to.uppercased() == callsign.uppercased()
        default: return false
        }
    }

    // MARK: - Parsing

    /// Parse a raw FT8 message string into a typed FT8Message.
    ///
    /// FT8 message formats:
    /// - `CQ [modifier] CALL GRID` — CQ call
    /// - `TOCALL FROMCALL GRID` — directed with grid
    /// - `TOCALL FROMCALL {+/-}NN` — signal report
    /// - `TOCALL FROMCALL R{+/-}NN` — roger + report
    /// - `TOCALL FROMCALL RRR` — roger
    /// - `TOCALL FROMCALL RR73` — roger + 73
    /// - `TOCALL FROMCALL 73` — farewell
    /// - Anything else — free text
    public static func parse(_ text: String) -> FT8Message {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ").map(String.init)

        guard parts.count >= 2 else {
            return .freeText(trimmed)
        }

        // CQ messages: "CQ [modifier] CALL [GRID]"
        if parts[0] == "CQ" {
            return parseCQ(parts: parts)
        }

        // 4+ tokens with no CQ prefix is likely free text
        guard parts.count >= 3, parts.count <= 3 else {
            if parts.count > 3 {
                return .freeText(trimmed)
            }
            return .freeText(trimmed)
        }

        // Three-part messages: "TOCALL FROMCALL EXTRA"
        let toCall = parts[0]
        let fromCall = parts[1]
        let extra = parts[2]

        // Grid square (4 chars, letter-digit-letter-digit pattern)
        if isGridSquare(extra) {
            return .directed(from: fromCall, to: toCall, grid: extra)
        }

        // RR73
        if extra == "RR73" {
            return .rogerEnd(from: fromCall, to: toCall)
        }

        // RRR
        if extra == "RRR" {
            return .roger(from: fromCall, to: toCall)
        }

        // 73
        if extra == "73" {
            return .end(from: fromCall, to: toCall)
        }

        // Roger + report: R{+/-}NN
        if extra.hasPrefix("R+") || extra.hasPrefix("R-"),
           let dB = Int(extra.dropFirst())
        {
            return .rogerReport(from: fromCall, to: toCall, dB: dB)
        }

        // Signal report: {+/-}NN
        if (extra.hasPrefix("+") || extra.hasPrefix("-")),
           let dB = Int(extra)
        {
            return .signalReport(from: fromCall, to: toCall, dB: dB)
        }

        return .freeText(trimmed)
    }

    private static func parseCQ(parts: [String]) -> FT8Message {
        switch parts.count {
        case 3:
            // "CQ CALL GRID" or "CQ MODIFIER CALL" (no grid)
            if isGridSquare(parts[2]) {
                return .cq(call: parts[1], grid: parts[2], modifier: nil)
            } else if isCallsign(parts[2]) {
                return .cq(call: parts[2], grid: "", modifier: parts[1])
            } else {
                return .cq(call: parts[1], grid: parts[2], modifier: nil)
            }
        case 4:
            // "CQ MODIFIER CALL GRID"
            return .cq(call: parts[2], grid: parts[3], modifier: parts[1])
        case 2:
            // "CQ CALL" (no grid)
            return .cq(call: parts[1], grid: "", modifier: nil)
        default:
            return .freeText(parts.joined(separator: " "))
        }
    }

    private static func isGridSquare(_ s: String) -> Bool {
        guard s.count == 4 else { return false }
        let chars = Array(s)
        return chars[0].isLetter && chars[1].isLetter
            && chars[2].isNumber && chars[3].isNumber
    }

    private static func isCallsign(_ s: String) -> Bool {
        // Simple heuristic: contains at least one digit and one letter, 3-10 chars
        s.count >= 3 && s.count <= 10
            && s.contains(where: \.isNumber)
            && s.contains(where: \.isLetter)
    }
}

/// A single decode result from the FT8 decoder.
public struct FT8DecodeResult: Sendable, Equatable {
    /// The parsed message.
    public let message: FT8Message
    /// Signal-to-noise ratio in dB (in 2500 Hz reference bandwidth).
    public let snr: Int
    /// Time offset from slot boundary in seconds.
    public let deltaTime: Double
    /// Audio frequency in Hz.
    public let frequency: Double
    /// Raw message text as decoded by ft8_lib.
    public let rawText: String

    public init(message: FT8Message, snr: Int, deltaTime: Double, frequency: Double, rawText: String) {
        self.message = message
        self.snr = snr
        self.deltaTime = deltaTime
        self.frequency = frequency
        self.rawText = rawText
    }
}
```

**Step 7: Run tests to verify they pass**

Run: `cd CarrierWaveCore && swift test --filter "FT8ConstantsTests|FT8MessageTests"`
Expected: All PASS

**Step 8: Commit**

```bash
git add CarrierWaveCore/Sources/CarrierWaveCore/FT8Constants.swift \
        CarrierWaveCore/Sources/CarrierWaveCore/FT8Message.swift \
        CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8ConstantsTests.swift \
        CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8MessageTests.swift
git commit -m "Add FT8Constants and FT8Message types with tests

FT8Constants provides timing values and standard dial frequencies.
FT8Message is a typed enum for all FT8 message formats with parsing
from raw text strings. FT8DecodeResult wraps a message with SNR,
frequency, and time offset metadata."
```

---

## Task 3: FT8 Decoder (Swift Wrapper over ft8_lib)

**Files:**
- Create: `CarrierWaveCore/Sources/CarrierWaveCore/FT8Decoder.swift`
- Create: `CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8DecoderTests.swift`

**Step 1: Write failing test for decoder using WAV test vectors**

Create `CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8DecoderTests.swift`:

```swift
//
//  FT8DecoderTests.swift
//  CarrierWaveCore
//

import Foundation
import Testing
@testable import CarrierWaveCore

@Suite("FT8 Decoder Tests")
struct FT8DecoderTests {
    /// Load a WAV file from test resources and return raw Float samples.
    private func loadWAV(named name: String) throws -> [Float] {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "ft8-samples")
        )
        return try FT8Decoder.loadWAV(url: url)
    }

    /// Load expected decode output from a .txt file.
    private func loadExpected(named name: String) throws -> [String] {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "ft8-samples")
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    @Test("Decode ft8_lib test vector 191111_110615")
    func decodeTestVector1() throws {
        let samples = try loadWAV(named: "191111_110615")
        #expect(samples.count == 180_000) // 15s at 12kHz

        let results = FT8Decoder.decode(samples: samples)
        #expect(results.count >= 10) // Should find many signals

        // Verify at least some known decodes from the expected output
        let expected = try loadExpected(named: "191111_110615")
        let decodedTexts = Set(results.map(\.rawText))

        // Check that several expected messages were found
        var matchCount = 0
        for line in expected {
            let msgText = extractMessageText(from: line)
            if decodedTexts.contains(msgText) {
                matchCount += 1
            }
        }
        #expect(matchCount >= expected.count / 2,
                "Should decode at least half of expected messages")
    }

    @Test("Decode ft8_lib test vector 191111_110630")
    func decodeTestVector2() throws {
        let samples = try loadWAV(named: "191111_110630")
        let results = FT8Decoder.decode(samples: samples)
        #expect(results.count >= 10)
    }

    @Test("Decode 20m busy band sample")
    func decodeBusyBand() throws {
        let samples = try loadWAV(named: "test_01")
        let results = FT8Decoder.decode(samples: samples)
        #expect(results.count >= 15, "Busy band should have many signals")
    }

    @Test("Decode WSJT-X official sample")
    func decodeWSJTXSample() throws {
        let samples = try loadWAV(named: "170709_135615")
        let results = FT8Decoder.decode(samples: samples)
        #expect(results.count > 0, "Should decode at least one signal from official sample")
    }

    @Test("Empty audio returns no decodes")
    func emptyAudio() {
        let silence = [Float](repeating: 0, count: 180_000)
        let results = FT8Decoder.decode(samples: silence)
        #expect(results.isEmpty)
    }

    @Test("Short audio returns no decodes without crash")
    func shortAudio() {
        let short = [Float](repeating: 0, count: 100)
        let results = FT8Decoder.decode(samples: short)
        #expect(results.isEmpty)
    }

    @Test("Decode results have valid SNR range")
    func snrRange() throws {
        let samples = try loadWAV(named: "191111_110615")
        let results = FT8Decoder.decode(samples: samples)
        for result in results {
            #expect(result.snr >= -30 && result.snr <= 30,
                    "SNR \(result.snr) out of expected range for \(result.rawText)")
        }
    }

    @Test("Decode results have valid frequency range")
    func frequencyRange() throws {
        let samples = try loadWAV(named: "191111_110615")
        let results = FT8Decoder.decode(samples: samples)
        for result in results {
            #expect(result.frequency >= 100 && result.frequency <= 4000,
                    "Frequency \(result.frequency) out of expected range")
        }
    }

    /// Extract message text from a test vector line like "110615  -2  1.0  431 ~  VK4BLE OH8JK R-17"
    private func extractMessageText(from line: String) -> String {
        guard let tildeRange = line.range(of: "~") else { return line }
        let afterTilde = line[tildeRange.upperBound...]
        // Remove trailing comments (after multiple spaces)
        let trimmed = afterTilde.trimmingCharacters(in: .whitespaces)
        if let doubleSpace = trimmed.range(of: "  ") {
            return String(trimmed[..<doubleSpace.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd CarrierWaveCore && swift test --filter FT8DecoderTests`
Expected: FAIL — `FT8Decoder` not defined

**Step 3: Implement FT8Decoder**

Write `CarrierWaveCore/Sources/CarrierWaveCore/FT8Decoder.swift`:

```swift
//
//  FT8Decoder.swift
//  CarrierWaveCore
//

import CFT8
import Foundation

/// Decodes FT8 signals from audio samples using ft8_lib.
public enum FT8Decoder: Sendable {
    /// Maximum number of candidate signals to search for.
    private static let maxCandidates: Int32 = 140

    /// Minimum sync score threshold for candidate detection.
    private static let minScore: Int32 = 10

    /// Maximum LDPC decoder iterations.
    private static let maxLDPCIterations: Int32 = 25

    /// Decode FT8 messages from a buffer of audio samples.
    ///
    /// - Parameters:
    ///   - samples: Audio samples at 12,000 Hz sample rate, mono, Float.
    ///   - minFrequency: Minimum audio frequency to search (Hz). Default 100.
    ///   - maxFrequency: Maximum audio frequency to search (Hz). Default 3000.
    /// - Returns: Array of decoded FT8 messages with metadata.
    public static func decode(
        samples: [Float],
        minFrequency: Float = 100,
        maxFrequency: Float = 3000
    ) -> [FT8DecodeResult] {
        guard samples.count >= FT8Constants.sampleRate else { return [] }

        // Configure the monitor
        var config = monitor_config_t(
            f_min: minFrequency,
            f_max: maxFrequency,
            sample_rate: Int32(FT8Constants.sampleRate),
            time_osr: 2,
            freq_osr: 2,
            protocol: FTX_PROTOCOL_FT8
        )

        var monitor = monitor_t()
        monitor_init(&monitor, &config)
        defer { monitor_free(&monitor) }

        // Feed audio samples to the monitor in block_size chunks
        let blockSize = Int(monitor.block_size)
        var offset = 0
        while offset + blockSize <= samples.count {
            samples.withUnsafeBufferPointer { buffer in
                monitor_process(&monitor, buffer.baseAddress! + offset)
            }
            offset += blockSize
        }

        // Find candidate signals
        var candidates = [ftx_candidate_t](repeating: ftx_candidate_t(), count: Int(maxCandidates))
        let numCandidates = ftx_find_candidates(
            &monitor.wf,
            maxCandidates,
            &candidates,
            minScore
        )

        // Set up callsign hash table for nonstandard callsign resolution
        var hashTable = CallsignHashTable()

        // Decode each candidate
        var results: [FT8DecodeResult] = []
        var seenMessages = Set<String>()

        for i in 0 ..< Int(numCandidates) {
            var message = ftx_message_t()
            var status = ftx_decode_status_t()

            let decoded = ftx_decode_candidate(
                &monitor.wf,
                &candidates[i],
                maxLDPCIterations,
                &message,
                &status
            )

            guard decoded else { continue }

            // Decode message to text
            var textBuffer = [CChar](repeating: 0, count: Int(FTX_MAX_MESSAGE_LENGTH) + 1)
            var offsets = ftx_message_offsets_t()

            var hashIF = hashTable.interface
            ftx_message_decode(&message, &hashIF, &textBuffer, &offsets)

            let messageText = String(cString: textBuffer)
            guard !messageText.isEmpty, !seenMessages.contains(messageText) else { continue }
            seenMessages.insert(messageText)

            // Compute SNR and frequency from candidate position
            let timeOffset = Double(candidates[i].time_offset) * Double(FT8Constants.symbolPeriod) / 2.0
            let freqOffset = Double(candidates[i].freq_offset) * Double(FT8Constants.toneSpacing) / 2.0
                + Double(minFrequency)

            let snr = Int(candidates[i].score) - 120 // Approximate SNR from score

            let parsed = FT8Message.parse(messageText)
            results.append(FT8DecodeResult(
                message: parsed,
                snr: snr,
                deltaTime: timeOffset,
                frequency: freqOffset,
                rawText: messageText
            ))
        }

        return results
    }

    // MARK: - WAV Loading

    /// Load a 12 kHz mono WAV file into Float samples.
    public static func loadWAV(url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count >= 44 else {
            throw FT8Error.invalidWAV("File too small for WAV header")
        }

        // Parse WAV header (minimal validation)
        let sampleRate = data.withUnsafeBytes { ptr -> UInt32 in
            ptr.load(fromByteOffset: 24, as: UInt32.self)
        }
        let bitsPerSample = data.withUnsafeBytes { ptr -> UInt16 in
            ptr.load(fromByteOffset: 34, as: UInt16.self)
        }
        let numChannels = data.withUnsafeBytes { ptr -> UInt16 in
            ptr.load(fromByteOffset: 22, as: UInt16.self)
        }

        guard sampleRate == 12000 else {
            throw FT8Error.invalidWAV("Expected 12000 Hz sample rate, got \(sampleRate)")
        }
        guard bitsPerSample == 16 else {
            throw FT8Error.invalidWAV("Expected 16-bit samples, got \(bitsPerSample)")
        }
        guard numChannels == 1 else {
            throw FT8Error.invalidWAV("Expected mono, got \(numChannels) channels")
        }

        // Find data chunk
        let audioData = data.dropFirst(44) // Standard WAV header size
        let sampleCount = audioData.count / 2 // 16-bit = 2 bytes per sample

        var samples = [Float](repeating: 0, count: sampleCount)
        audioData.withUnsafeBytes { ptr in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            for i in 0 ..< sampleCount {
                samples[i] = Float(int16Ptr[i]) / 32768.0
            }
        }

        return samples
    }
}

/// Errors from FT8 operations.
public enum FT8Error: Error, Sendable {
    case invalidWAV(String)
    case encodingFailed(String)
}

// MARK: - Callsign Hash Table

/// In-memory hash table for resolving nonstandard callsign hashes during decoding.
/// ft8_lib requires this callback interface for callsigns encoded as 12/22-bit hashes.
private final class CallsignHashTable {
    private var entries: [(callsign: String, hash: UInt32)] = []

    var interface: ftx_callsign_hash_interface_t {
        ftx_callsign_hash_interface_t(
            lookup_hash: { hashType, hash, callsignOut in
                // Simple lookup — in practice, this is called to resolve hashed callsigns
                // For decode-only use, returning false is acceptable (shows <...> placeholder)
                return false
            },
            save_hash: { callsign, n22 in
                // Called when a standard callsign is decoded — save its hash for future lookups
                // We don't persist across decode calls in this implementation
            }
        )
    }
}
```

Note: The SNR computation and frequency offset computation above are approximations. The exact conversion depends on how ft8_lib's `ftx_candidate_t` score maps to SNR. This will need to be tuned against the test vectors. The status struct returned by `ftx_decode_candidate` may provide better frequency/time info through `status.freq` and `status.time`.

**Step 4: Run tests to verify they pass**

Run: `cd CarrierWaveCore && swift test --filter FT8DecoderTests`
Expected: Most PASS. The SNR/frequency range tests may need tuning based on how ft8_lib maps scores. The hash table implementation is minimal — hashed callsigns will show as `<...>` in decoded output.

**Step 5: Iterate on SNR/frequency computation**

Examine `ftx_decode_status_t` fields (`status.freq` and `status.time`) — these provide the actual frequency and time offset. Update the decoder to use `status.freq` for frequency and `status.time` for deltaTime instead of computing from candidate offsets.

**Step 6: Commit**

```bash
git add CarrierWaveCore/Sources/CarrierWaveCore/FT8Decoder.swift \
        CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8DecoderTests.swift
git commit -m "Add FT8Decoder wrapping ft8_lib with WAV test vectors

Decodes FT8 signals from 12kHz Float audio samples using ft8_lib's
monitor → candidates → LDPC decode pipeline. Includes WAV loader
for test data. Validated against ft8_lib test vectors and WSJT-X
official recordings."
```

---

## Task 4: FT8 Encoder (Swift Wrapper)

**Files:**
- Create: `CarrierWaveCore/Sources/CarrierWaveCore/FT8Encoder.swift`
- Create: `CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8EncoderTests.swift`

**Step 1: Write failing test for encoder**

Create `CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8EncoderTests.swift`:

```swift
//
//  FT8EncoderTests.swift
//  CarrierWaveCore
//

import Testing
@testable import CarrierWaveCore

@Suite("FT8 Encoder Tests")
struct FT8EncoderTests {
    @Test("Encode CQ message produces correct sample count")
    func encodeCQSampleCount() throws {
        let samples = try FT8Encoder.encode(message: "CQ K1ABC FN42")
        // 79 symbols * 0.160s * 12000 Hz = 151,680 samples
        #expect(samples.count == 79 * 1920)
    }

    @Test("Encoded audio is not silence")
    func encodedNotSilence() throws {
        let samples = try FT8Encoder.encode(message: "CQ K1ABC FN42")
        let maxAmplitude = samples.map { abs($0) }.max() ?? 0
        #expect(maxAmplitude > 0.01, "Encoded audio should not be silence")
    }

    @Test("Encoded audio amplitude is normalized")
    func encodedAmplitudeNormalized() throws {
        let samples = try FT8Encoder.encode(message: "CQ K1ABC FN42")
        let maxAmplitude = samples.map { abs($0) }.max() ?? 0
        #expect(maxAmplitude <= 1.0, "Amplitude should not exceed 1.0")
        #expect(maxAmplitude > 0.5, "Amplitude should be reasonably loud")
    }

    @Test("Round-trip: encode then decode recovers message")
    func roundTrip() throws {
        let originalMessage = "CQ K1ABC FN42"
        let encoded = try FT8Encoder.encode(message: originalMessage, frequency: 1500)

        // Pad to 15 seconds (decoder expects a full slot)
        var padded = [Float](repeating: 0, count: FT8Constants.samplesPerSlot)
        for i in 0 ..< min(encoded.count, padded.count) {
            padded[i] = encoded[i]
        }

        let results = FT8Decoder.decode(samples: padded)
        let texts = results.map(\.rawText)
        #expect(texts.contains("CQ K1ABC FN42"),
                "Round-trip should recover the original message. Got: \(texts)")
    }

    @Test("Encode signal report message")
    func encodeSignalReport() throws {
        let samples = try FT8Encoder.encode(message: "W9XYZ K1ABC -11")
        #expect(samples.count == 79 * 1920)
    }

    @Test("Encode RR73 message")
    func encodeRR73() throws {
        let samples = try FT8Encoder.encode(message: "W9XYZ K1ABC RR73")
        #expect(samples.count == 79 * 1920)
    }

    @Test("Encode free text message")
    func encodeFreeText() throws {
        let samples = try FT8Encoder.encode(message: "TNX BOB 73 GL")
        #expect(samples.count == 79 * 1920)
    }

    @Test("Encode CQ POTA message")
    func encodeCQPOTA() throws {
        let samples = try FT8Encoder.encode(message: "CQ POTA K7ABC CN87")
        #expect(samples.count == 79 * 1920)
    }

    @Test("Invalid message returns error")
    func invalidMessage() {
        #expect(throws: FT8Error.self) {
            _ = try FT8Encoder.encode(message: "")
        }
    }

    @Test("Different frequencies produce different audio")
    func differentFrequencies() throws {
        let at1000 = try FT8Encoder.encode(message: "CQ K1ABC FN42", frequency: 1000)
        let at2000 = try FT8Encoder.encode(message: "CQ K1ABC FN42", frequency: 2000)
        // Same length but different content
        #expect(at1000.count == at2000.count)
        #expect(at1000 != at2000)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd CarrierWaveCore && swift test --filter FT8EncoderTests`
Expected: FAIL — `FT8Encoder` not defined

**Step 3: Implement FT8Encoder**

Write `CarrierWaveCore/Sources/CarrierWaveCore/FT8Encoder.swift`:

```swift
//
//  FT8Encoder.swift
//  CarrierWaveCore
//

import CFT8
import Foundation

/// Encodes FT8 messages into audio tone sequences.
public enum FT8Encoder: Sendable {
    /// Encode an FT8 message string into audio samples.
    ///
    /// - Parameters:
    ///   - message: The FT8 message text (e.g., "CQ K1ABC FN42").
    ///   - frequency: Audio frequency in Hz for the base tone. Default 1500.
    ///   - sampleRate: Output sample rate. Default 12000.
    /// - Returns: Array of Float audio samples representing the FT8 transmission.
    /// - Throws: `FT8Error.encodingFailed` if the message cannot be encoded.
    public static func encode(
        message: String,
        frequency: Double = 1500.0,
        sampleRate: Int = FT8Constants.sampleRate
    ) throws -> [Float] {
        guard !message.isEmpty else {
            throw FT8Error.encodingFailed("Empty message")
        }

        // Pack the message into 77-bit payload
        var ftxMessage = ftx_message_t()
        ftx_message_init(&ftxMessage)

        let rc = message.withCString { cStr in
            ftx_message_encode(&ftxMessage, nil, cStr)
        }

        guard rc == FTX_MESSAGE_RC_OK else {
            throw FT8Error.encodingFailed("ft8_lib encode failed with code \(rc.rawValue) for: \(message)")
        }

        // Generate tone sequence (79 symbols, each 0-7)
        var tones = [UInt8](repeating: 0, count: Int(FT8_NN))
        ft8_encode(&ftxMessage.payload.0, &tones)

        // Synthesize audio from tones using GFSK modulation
        return synthesizeTones(tones, frequency: frequency, sampleRate: sampleRate)
    }

    /// Generate audio samples from a tone sequence.
    ///
    /// Each symbol is 0.160 seconds = 1920 samples at 12 kHz.
    /// Tones are GFSK-modulated with 6.25 Hz spacing.
    private static func synthesizeTones(
        _ tones: [UInt8],
        frequency: Double,
        sampleRate: Int
    ) -> [Float] {
        let symbolSamples = Int(Double(sampleRate) * FT8Constants.symbolPeriod)
        let totalSamples = tones.count * symbolSamples
        var samples = [Float](repeating: 0, count: totalSamples)

        var phase: Double = 0
        let twoPi = 2.0 * Double.pi

        for (symbolIndex, tone) in tones.enumerated() {
            let toneFrequency = frequency + Double(tone) * FT8Constants.toneSpacing
            let phaseIncrement = twoPi * toneFrequency / Double(sampleRate)

            for j in 0 ..< symbolSamples {
                let sampleIndex = symbolIndex * symbolSamples + j
                samples[sampleIndex] = Float(sin(phase))
                phase += phaseIncrement
                if phase > twoPi { phase -= twoPi }
            }
        }

        return samples
    }
}
```

Note: The `ftxMessage.payload.0` syntax accesses the first element of the C tuple that Swift bridges from `uint8_t payload[10]`. This may need adjustment based on how Swift imports the C struct — it might need `withUnsafePointer(to: &ftxMessage.payload) { ... }` or similar to pass the payload array correctly to `ft8_encode`. Build and fix based on the actual Swift/C bridging behavior.

**Step 4: Run tests to verify they pass**

Run: `cd CarrierWaveCore && swift test --filter FT8EncoderTests`
Expected: PASS (the round-trip test is the most important validation)

**Step 5: Commit**

```bash
git add CarrierWaveCore/Sources/CarrierWaveCore/FT8Encoder.swift \
        CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8EncoderTests.swift
git commit -m "Add FT8Encoder with GFSK tone synthesis and round-trip tests

Encodes FT8 message strings into audio samples via ft8_lib message
packing and tone generation. Round-trip test validates encode → decode
recovers the original message."
```

---

## Task 5: FT8 Session State Machine

**Files:**
- Create: `CarrierWave/Services/FT8SessionState.swift`
- Create: `CarrierWaveCore/Sources/CarrierWaveCore/FT8QSOStateMachine.swift`
- Create: `CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8QSOStateMachineTests.swift`

The QSO state machine is pure logic — put it in CarrierWaveCore for testability.

**Step 1: Write failing test for the state machine**

Create `CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8QSOStateMachineTests.swift`:

```swift
//
//  FT8QSOStateMachineTests.swift
//  CarrierWaveCore
//

import Testing
@testable import CarrierWaveCore

@Suite("FT8 QSO State Machine Tests")
struct FT8QSOStateMachineTests {
    let myCall = "K1ABC"
    let myGrid = "FN42"

    // MARK: - Search & Pounce Flow

    @Test("S&P: idle → calling on CQ tap")
    func spCallingOnCQTap() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        #expect(sm.state == .idle)

        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        #expect(sm.state == .calling)
        #expect(sm.theirCallsign == "W9XYZ")
        #expect(sm.nextTXMessage == "\(myCall) W9XYZ EN37"
                || sm.nextTXMessage == "W9XYZ \(myCall) \(myGrid)")
    }

    @Test("S&P: calling → reportSent on signal report received")
    func spReportSent() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")

        sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
        #expect(sm.state == .reportSent)
        #expect(sm.theirReport == -12)
    }

    @Test("S&P: reportSent → complete on RR73 received")
    func spCompleteOnRR73() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
        // Our auto-sequencer would send R-XX, then we get RR73
        sm.processMessage(.rogerEnd(from: "W9XYZ", to: myCall))
        #expect(sm.state == .complete)
    }

    // MARK: - CQ (Run) Flow

    @Test("CQ: idle generates CQ message")
    func cqIdleGeneratesCQ() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.setCQMode(modifier: nil)
        #expect(sm.nextTXMessage == "CQ \(myCall) \(myGrid)")
    }

    @Test("CQ POTA: includes modifier")
    func cqPotaIncludesModifier() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.setCQMode(modifier: "POTA")
        #expect(sm.nextTXMessage == "CQ POTA \(myCall) \(myGrid)")
    }

    @Test("CQ: station responds → exchange starts")
    func cqStationResponds() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.setCQMode(modifier: nil)
        sm.processMessage(.directed(from: "W9XYZ", to: myCall, grid: "EN37"))
        #expect(sm.state == .reportSent)
        #expect(sm.theirCallsign == "W9XYZ")
    }

    // MARK: - Timeout

    @Test("Timeout after N cycles with no response")
    func timeoutAfterNCycles() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        #expect(sm.state == .calling)

        // Simulate 10 cycles with no response
        for _ in 0 ..< 10 {
            sm.advanceCycle()
        }
        #expect(sm.state == .idle, "Should timeout and return to idle")
    }

    // MARK: - Duplicate Prevention

    @Test("Won't initiate QSO with already-worked station")
    func duplicatePrevention() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.markWorked("W9XYZ")
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        #expect(sm.state == .idle, "Should not start QSO with worked station")
    }

    // MARK: - Completed QSO Data

    @Test("Completed QSO provides all fields")
    func completedQSOData() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
        sm.myReport = -7
        sm.processMessage(.rogerEnd(from: "W9XYZ", to: myCall))

        let qso = sm.completedQSO
        #expect(qso != nil)
        #expect(qso?.theirCallsign == "W9XYZ")
        #expect(qso?.theirGrid == "EN37")
        #expect(qso?.theirReport == -12)
        #expect(qso?.myReport == -7)
    }

    // MARK: - Irrelevant Messages

    @Test("Ignores messages not directed at us")
    func ignoresIrrelevant() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")

        // Message between other stations
        sm.processMessage(.signalReport(from: "AA1BB", to: "CC2DD", dB: -5))
        #expect(sm.state == .calling, "Should ignore messages not for us")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd CarrierWaveCore && swift test --filter FT8QSOStateMachineTests`
Expected: FAIL — `FT8QSOStateMachine` not defined

**Step 3: Implement FT8QSOStateMachine**

Write `CarrierWaveCore/Sources/CarrierWaveCore/FT8QSOStateMachine.swift`:

```swift
//
//  FT8QSOStateMachine.swift
//  CarrierWaveCore
//

/// Pure-logic state machine for FT8 QSO exchanges.
/// Drives the auto-sequencer: given the current state and incoming messages,
/// determines the next TX message and when a QSO is complete.
public struct FT8QSOStateMachine: Sendable {
    // MARK: - Types

    public enum State: Sendable, Equatable {
        case idle
        case calling       // Sent our grid/call, waiting for report
        case reportSent    // Sent signal report, waiting for R+report
        case reportReceived // Received R+report, sending RR73
        case complete      // QSO done
    }

    public struct CompletedQSO: Sendable {
        public let theirCallsign: String
        public let theirGrid: String?
        public let theirReport: Int?
        public let myReport: Int?
        public let startTime: Date
    }

    // MARK: - Properties

    public private(set) var state: State = .idle
    public let myCallsign: String
    public let myGrid: String

    public private(set) var theirCallsign: String?
    public private(set) var theirGrid: String?
    public private(set) var theirReport: Int?
    public var myReport: Int?

    private var cqModifier: String?
    private var isCQMode = false
    private var cyclesSinceLastResponse = 0
    private var maxCyclesBeforeTimeout = 8
    private var workedCallsigns = Set<String>()
    private var qsoStartTime: Date?

    // MARK: - Init

    public init(myCallsign: String, myGrid: String) {
        self.myCallsign = myCallsign
        self.myGrid = myGrid
    }

    // MARK: - CQ Mode

    public mutating func setCQMode(modifier: String?) {
        isCQMode = true
        cqModifier = modifier
        state = .idle
    }

    public mutating func setListenMode() {
        isCQMode = false
        state = .idle
        resetQSO()
    }

    // MARK: - Initiate Call (S&P)

    public mutating func initiateCall(to callsign: String, theirGrid: String?) {
        guard !workedCallsigns.contains(callsign.uppercased()) else { return }

        theirCallsign = callsign
        self.theirGrid = theirGrid
        state = .calling
        cyclesSinceLastResponse = 0
        qsoStartTime = Date()
    }

    // MARK: - Process Incoming Message

    public mutating func processMessage(_ message: FT8Message) {
        // Only process messages directed at us
        guard message.isDirectedTo(myCallsign) else {
            // In CQ mode, also check if someone is responding to our CQ
            if isCQMode, state == .idle,
               case let .directed(from, to, grid) = message,
               to.uppercased() == myCallsign.uppercased()
            {
                theirCallsign = from
                theirGrid = grid
                state = .reportSent
                cyclesSinceLastResponse = 0
                qsoStartTime = Date()
            }
            return
        }

        cyclesSinceLastResponse = 0

        switch (state, message) {
        case (.calling, .signalReport(_, _, let dB)):
            theirReport = dB
            state = .reportSent

        case (.reportSent, .rogerReport(_, _, let dB)):
            theirReport = dB
            state = .reportReceived

        case (.reportReceived, .rogerEnd):
            state = .complete
            if let call = theirCallsign {
                workedCallsigns.insert(call.uppercased())
            }

        case (.reportReceived, .end):
            state = .complete
            if let call = theirCallsign {
                workedCallsigns.insert(call.uppercased())
            }

        case (_, .rogerEnd(_, _)):
            // RR73 at any stage completes the QSO
            state = .complete
            if let call = theirCallsign {
                workedCallsigns.insert(call.uppercased())
            }

        default:
            break
        }
    }

    // MARK: - TX Message Generation

    public var nextTXMessage: String? {
        switch state {
        case .idle:
            if isCQMode {
                if let mod = cqModifier {
                    return "CQ \(mod) \(myCallsign) \(myGrid)"
                }
                return "CQ \(myCallsign) \(myGrid)"
            }
            return nil

        case .calling:
            guard let their = theirCallsign else { return nil }
            return "\(their) \(myCallsign) \(myGrid)"

        case .reportSent:
            guard let their = theirCallsign, let report = myReport else { return nil }
            let sign = report >= 0 ? "+" : ""
            return "\(their) \(myCallsign) \(sign)\(String(format: "%02d", abs(report)))"

        case .reportReceived:
            guard let their = theirCallsign else { return nil }
            return "\(their) \(myCallsign) RR73"

        case .complete:
            return nil
        }
    }

    // MARK: - Cycle Management

    public mutating func advanceCycle() {
        guard state != .idle, state != .complete else { return }
        cyclesSinceLastResponse += 1
        if cyclesSinceLastResponse >= maxCyclesBeforeTimeout {
            state = .idle
            resetQSO()
        }
    }

    // MARK: - Completed QSO

    public var completedQSO: CompletedQSO? {
        guard state == .complete, let call = theirCallsign else { return nil }
        return CompletedQSO(
            theirCallsign: call,
            theirGrid: theirGrid,
            theirReport: theirReport,
            myReport: myReport,
            startTime: qsoStartTime ?? Date()
        )
    }

    // MARK: - Worked Stations

    public mutating func markWorked(_ callsign: String) {
        workedCallsigns.insert(callsign.uppercased())
    }

    public func hasWorked(_ callsign: String) -> Bool {
        workedCallsigns.contains(callsign.uppercased())
    }

    // MARK: - Reset

    public mutating func resetForNextQSO() {
        state = .idle
        resetQSO()
    }

    private mutating func resetQSO() {
        theirCallsign = nil
        theirGrid = nil
        theirReport = nil
        myReport = nil
        cyclesSinceLastResponse = 0
        qsoStartTime = nil
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd CarrierWaveCore && swift test --filter FT8QSOStateMachineTests`
Expected: All PASS

**Step 5: Commit**

```bash
git add CarrierWaveCore/Sources/CarrierWaveCore/FT8QSOStateMachine.swift \
        CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8QSOStateMachineTests.swift
git commit -m "Add FT8QSOStateMachine with auto-sequencing and timeout

Pure-logic state machine in CarrierWaveCore for FT8 QSO exchanges.
Handles S&P and CQ (run) flows, timeout after N cycles, duplicate
prevention, and TX message generation for auto-sequencing."
```

---

## Task 6: FT8 Audio Engine

**Files:**
- Create: `CarrierWave/Services/FT8AudioEngine.swift`

This is the AVAudioEngine wrapper. It cannot be unit-tested without a real audio session (hardware dependency), so we test it indirectly through integration tests and manual testing.

**Step 1: Implement FT8AudioEngine**

Write `CarrierWave/Services/FT8AudioEngine.swift`:

```swift
//
//  FT8AudioEngine.swift
//  CarrierWave
//

import AVFoundation
import CarrierWaveCore

/// Manages AVAudioEngine for FT8 audio capture and playback.
/// Handles resampling from device sample rate to 12 kHz for the FT8 codec.
actor FT8AudioEngine {
    // MARK: - Properties

    private let engine = AVAudioEngine()
    private var playerNode: AVAudioPlayerNode?
    private var isRunning = false
    private var inputBuffer: [Float] = []
    private let targetSampleRate = Double(FT8Constants.sampleRate)

    // Callbacks
    private var onSlotReady: (([Float]) -> Void)?
    private var onAudioLevel: ((Float) -> Void)?

    // MARK: - Configuration

    func configure() throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(
            .playAndRecord,
            mode: .measurement, // Disables voice processing — critical for data modes
            options: [.allowBluetooth, .defaultToSpeaker]
        )

        try session.setPreferredSampleRate(48000) // Prefer 48kHz for clean 4:1 decimation
        try session.setPreferredIOBufferDuration(0.02) // 20ms buffers
        try session.setActive(true)

        setupInputTap()
        setupPlayerNode()
    }

    // MARK: - Start/Stop

    func start(onSlotReady: @escaping @Sendable ([Float]) -> Void) throws {
        self.onSlotReady = onSlotReady
        inputBuffer.removeAll()
        try engine.start()
        isRunning = true
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        playerNode?.stop()
        engine.stop()
        isRunning = false
        onSlotReady = nil
    }

    // MARK: - Transmit

    func playTones(_ samples: [Float]) {
        guard let player = playerNode else { return }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        )!

        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = buffer.floatChannelData![0]
        for i in 0 ..< samples.count {
            channelData[i] = samples[i]
        }

        player.scheduleBuffer(buffer)
        player.play()
    }

    // MARK: - Audio Level

    func setAudioLevelCallback(_ callback: @escaping @Sendable (Float) -> Void) {
        onAudioLevel = callback
    }

    // MARK: - Private

    private func setupInputTap() {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let deviceSampleRate = inputFormat.sampleRate

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self else { return }
            let samples = self.extractSamples(from: buffer)
            let resampled = self.decimate(
                samples,
                fromRate: deviceSampleRate,
                toRate: self.targetSampleRate
            )
            Task { await self.appendSamples(resampled) }
        }
    }

    private func setupPlayerNode() {
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
        playerNode = player
    }

    private func appendSamples(_ samples: [Float]) {
        inputBuffer.append(contentsOf: samples)

        // Report audio level
        if let levelCallback = onAudioLevel, !samples.isEmpty {
            let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
            levelCallback(rms)
        }

        // When we have a full 15-second slot, deliver it
        if inputBuffer.count >= FT8Constants.samplesPerSlot {
            let slot = Array(inputBuffer.prefix(FT8Constants.samplesPerSlot))
            inputBuffer.removeFirst(FT8Constants.samplesPerSlot)
            onSlotReady?(slot)
        }
    }

    private func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let count = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: count))
    }

    /// Decimate audio from device sample rate to target rate.
    /// For 48kHz → 12kHz, this is a simple 4:1 decimation.
    private nonisolated func decimate(
        _ samples: [Float],
        fromRate: Double,
        toRate: Double
    ) -> [Float] {
        let ratio = Int(fromRate / toRate)
        guard ratio > 1 else { return samples }

        // Simple decimation (for 4:1, take every 4th sample)
        // A proper anti-aliasing filter should be added for production use
        var result = [Float]()
        result.reserveCapacity(samples.count / ratio)
        for i in stride(from: 0, to: samples.count, by: ratio) {
            result.append(samples[i])
        }
        return result
    }
}
```

**Step 2: Build to verify compilation**

Run: `xc build`
Expected: Compiles without errors.

**Step 3: Commit**

```bash
git add CarrierWave/Services/FT8AudioEngine.swift
git commit -m "Add FT8AudioEngine actor for AVAudioEngine management

Manages audio capture with .measurement mode (no voice processing),
resamples 48kHz to 12kHz for FT8 codec, delivers 15-second audio
slots for decoding, and plays encoded FT8 tones for transmission."
```

---

## Task 7: FT8 Session Manager

**Files:**
- Create: `CarrierWave/Services/FT8SessionManager.swift`

This is the @MainActor @Observable brain that ties the audio engine, decoder, state machine, and UI together.

**Step 1: Implement FT8SessionManager**

Write `CarrierWave/Services/FT8SessionManager.swift`:

```swift
//
//  FT8SessionManager.swift
//  CarrierWave
//

import CarrierWaveCore
import Foundation
import SwiftData

/// Operating mode for FT8.
enum FT8OperatingMode: Sendable {
    case listen
    case callCQ(modifier: String?)
    case searchAndPounce
}

/// Manages an active FT8 session — decoding, auto-sequencing, and QSO logging.
@MainActor @Observable
final class FT8SessionManager {
    // MARK: - Published State

    private(set) var decodeResults: [FT8DecodeResult] = []
    private(set) var currentCycleDecodes: [FT8DecodeResult] = []
    private(set) var isTransmitting = false
    private(set) var isReceiving = false
    private(set) var cycleTimeRemaining: Double = 15.0
    private(set) var qsoStateMachine: FT8QSOStateMachine
    private(set) var operatingMode: FT8OperatingMode = .listen
    private(set) var qsoCount = 0
    private(set) var audioLevel: Float = 0

    var selectedBand: String = "20m" {
        didSet { selectedFrequency = FT8Constants.dialFrequency(forBand: selectedBand) ?? 14.074 }
    }
    var selectedFrequency: Double = 14.074

    // MARK: - Private

    private let audioEngine = FT8AudioEngine()
    private var slotTimer: Timer?
    private var cycleTimer: Timer?
    private var isEvenSlot = true
    private var transmitOnEven = true
    private let modelContext: ModelContext
    private let loggingSessionManager: LoggingSessionManager

    // MARK: - Init

    init(
        myCallsign: String,
        myGrid: String,
        modelContext: ModelContext,
        loggingSessionManager: LoggingSessionManager
    ) {
        self.qsoStateMachine = FT8QSOStateMachine(myCallsign: myCallsign, myGrid: myGrid)
        self.modelContext = modelContext
        self.loggingSessionManager = loggingSessionManager
    }

    // MARK: - Start/Stop

    func start() async throws {
        try await audioEngine.configure()
        try await audioEngine.start { [weak self] samples in
            Task { @MainActor in
                self?.handleDecodedSlot(samples)
            }
        }

        await audioEngine.setAudioLevelCallback { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
            }
        }

        startCycleTimer()
        isReceiving = true
    }

    func stop() async {
        slotTimer?.invalidate()
        cycleTimer?.invalidate()
        await audioEngine.stop()
        isReceiving = false
        isTransmitting = false
    }

    // MARK: - Mode Control

    func setMode(_ mode: FT8OperatingMode) {
        operatingMode = mode
        switch mode {
        case .listen:
            qsoStateMachine.setListenMode()
        case let .callCQ(modifier):
            qsoStateMachine.setCQMode(modifier: modifier)
        case .searchAndPounce:
            qsoStateMachine.setListenMode()
        }
    }

    func callStation(_ result: FT8DecodeResult) {
        guard case let .cq(call, grid, _) = result.message else { return }
        setMode(.searchAndPounce)
        qsoStateMachine.initiateCall(to: call, theirGrid: grid)
    }

    // MARK: - Private: Decoding

    private func handleDecodedSlot(_ samples: [Float]) {
        let results = FT8Decoder.decode(samples: samples)
        currentCycleDecodes = results
        decodeResults.append(contentsOf: results)

        // Trim old decodes (keep last ~4 minutes = 16 slots)
        if decodeResults.count > 500 {
            decodeResults.removeFirst(decodeResults.count - 500)
        }

        // Process each decode through the state machine
        for result in results {
            qsoStateMachine.processMessage(result.message)
        }

        // Check if QSO completed
        if qsoStateMachine.state == .complete, let completed = qsoStateMachine.completedQSO {
            logCompletedQSO(completed)
            qsoStateMachine.resetForNextQSO()
        }
    }

    // MARK: - Private: Transmitting

    private func transmitIfNeeded() {
        guard operatingMode != .listen else { return }
        guard let message = qsoStateMachine.nextTXMessage else { return }

        do {
            let samples = try FT8Encoder.encode(
                message: message,
                frequency: 1500 // Default audio offset
            )
            isTransmitting = true
            Task {
                await audioEngine.playTones(samples)
                await MainActor.run {
                    self.isTransmitting = false
                }
            }
        } catch {
            // Log encoding error
        }
    }

    // MARK: - Private: Timing

    private func startCycleTimer() {
        // Synchronize to UTC 15-second boundaries
        let now = Date()
        let seconds = now.timeIntervalSince1970
        let slotSeconds = seconds.truncatingRemainder(dividingBy: 15.0)
        let nextSlotStart = 15.0 - slotSeconds

        isEvenSlot = Int(seconds / 15.0) % 2 == 0

        // Fire at next slot boundary
        slotTimer = Timer.scheduledTimer(
            withTimeInterval: nextSlotStart,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onSlotBoundary()
                // Then fire every 15 seconds
                self?.slotTimer = Timer.scheduledTimer(
                    withTimeInterval: 15.0,
                    repeats: true
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.onSlotBoundary()
                    }
                }
            }
        }

        // Countdown timer (fires every second)
        cycleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCountdown()
            }
        }
    }

    private func onSlotBoundary() {
        isEvenSlot.toggle()
        cycleTimeRemaining = 15.0
        qsoStateMachine.advanceCycle()

        // Transmit on our designated slot (even or odd)
        if (isEvenSlot && transmitOnEven) || (!isEvenSlot && !transmitOnEven) {
            transmitIfNeeded()
        }
    }

    private func updateCountdown() {
        cycleTimeRemaining = max(0, cycleTimeRemaining - 1.0)
    }

    // MARK: - Private: QSO Logging

    private func logCompletedQSO(_ completed: FT8QSOStateMachine.CompletedQSO) {
        let rstSent: String
        if let report = completed.myReport {
            rstSent = report >= 0 ? "+\(String(format: "%02d", report))" : "\(report)"
        } else {
            rstSent = "0"
        }

        let rstReceived: String
        if let report = completed.theirReport {
            rstReceived = report >= 0 ? "+\(String(format: "%02d", report))" : "\(report)"
        } else {
            rstReceived = "0"
        }

        _ = loggingSessionManager.logQSO(
            callsign: completed.theirCallsign,
            rstSent: rstSent,
            rstReceived: rstReceived,
            theirGrid: completed.theirGrid
        )

        qsoCount += 1
    }
}
```

**Step 2: Build to verify compilation**

Run: `xc build`
Expected: Compiles. May need adjustments for `LoggingSessionManager.logQSO` parameter names — check the actual signature.

**Step 3: Commit**

```bash
git add CarrierWave/Services/FT8SessionManager.swift
git commit -m "Add FT8SessionManager for session orchestration

@MainActor @Observable class that ties together audio engine, decoder,
QSO state machine, and logging. Handles 15-second slot timing synced
to UTC, auto-sequencing TX messages, and auto-logging completed QSOs
through the existing LoggingSessionManager pipeline."
```

---

## Task 8: FT8 Waterfall View Data

**Files:**
- Create: `CarrierWave/Services/FT8WaterfallData.swift`

**Step 1: Implement waterfall data model**

Write `CarrierWave/Services/FT8WaterfallData.swift`:

```swift
//
//  FT8WaterfallData.swift
//  CarrierWave
//

import Accelerate
import CarrierWaveCore
import Foundation

/// Computes and stores FFT spectrogram data for the FT8 waterfall display.
@MainActor @Observable
final class FT8WaterfallData {
    /// 2D array of magnitude values [time][frequency], normalized 0-1.
    private(set) var magnitudes: [[Float]] = []

    /// Number of frequency bins.
    private(set) var frequencyBins: Int = 0

    /// Frequency range in Hz.
    let minFrequency: Float = 100
    let maxFrequency: Float = 3000

    /// Maximum number of time rows to keep (4 slots = ~60 seconds).
    private let maxRows = 240

    /// FFT size matching ft8_lib's resolution (6.25 Hz bins at 12 kHz).
    private let fftSize = 1920

    /// Process a chunk of audio samples and add a row to the waterfall.
    func processAudio(_ samples: [Float]) {
        guard samples.count >= fftSize else { return }

        // Process in fftSize chunks
        var offset = 0
        while offset + fftSize <= samples.count {
            let chunk = Array(samples[offset ..< offset + fftSize])
            let spectrum = computeSpectrum(chunk)
            magnitudes.append(spectrum)
            offset += fftSize
        }

        // Trim old rows
        if magnitudes.count > maxRows {
            magnitudes.removeFirst(magnitudes.count - maxRows)
        }

        if frequencyBins == 0, let first = magnitudes.first {
            frequencyBins = first.count
        }
    }

    func clear() {
        magnitudes.removeAll()
    }

    // MARK: - Private

    private func computeSpectrum(_ samples: [Float]) -> [Float] {
        let n = samples.count
        let halfN = n / 2

        // Apply Hann window
        var windowed = [Float](repeating: 0, count: n)
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(n))

        // FFT setup
        let log2n = vDSP_Length(log2(Float(n)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return []
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Split complex format
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)
        var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)

        // Convert to split complex
        windowed.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
            }
        }

        // Forward FFT
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

        // Compute magnitudes (dB)
        var magnitudes = [Float](repeating: 0, count: halfN)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))

        // Convert to dB and normalize
        var one: Float = 1e-10
        vDSP_vsadd(magnitudes, 1, &one, &magnitudes, 1, vDSP_Length(halfN))

        var logMagnitudes = [Float](repeating: 0, count: halfN)
        var count = Int32(halfN)
        vvlog10f(&logMagnitudes, magnitudes, &count)

        var scale: Float = 20.0
        vDSP_vsmul(logMagnitudes, 1, &scale, &logMagnitudes, 1, vDSP_Length(halfN))

        // Clip to useful range and normalize to 0-1
        let binSpacing = Float(FT8Constants.sampleRate) / Float(n) // 6.25 Hz
        let minBin = Int(minFrequency / binSpacing)
        let maxBin = min(Int(maxFrequency / binSpacing), halfN - 1)

        let usefulBins = Array(logMagnitudes[minBin ... maxBin])

        // Normalize: map [-80, 0] dB to [0, 1]
        var normalized = [Float](repeating: 0, count: usefulBins.count)
        var offset: Float = 80
        vDSP_vsadd(usefulBins, 1, &offset, &normalized, 1, vDSP_Length(usefulBins.count))
        var divisor: Float = 80
        vDSP_vsdiv(normalized, 1, &divisor, &normalized, 1, vDSP_Length(normalized.count))

        // Clamp to [0, 1]
        var low: Float = 0
        var high: Float = 1
        vDSP_vclip(normalized, 1, &low, &high, &normalized, 1, vDSP_Length(normalized.count))

        return normalized
    }
}
```

**Step 2: Build to verify compilation**

Run: `xc build`
Expected: Compiles without errors.

**Step 3: Commit**

```bash
git add CarrierWave/Services/FT8WaterfallData.swift
git commit -m "Add FT8WaterfallData for spectrogram computation

Uses Accelerate framework for FFT on audio chunks. Produces normalized
magnitude arrays for the waterfall display at 6.25 Hz frequency
resolution matching ft8_lib's bin spacing."
```

---

## Task 9: FT8 Session View (SwiftUI)

**Files:**
- Create: `CarrierWave/Views/Logger/FT8/FT8SessionView.swift`
- Create: `CarrierWave/Views/Logger/FT8/FT8DecodeListView.swift`
- Create: `CarrierWave/Views/Logger/FT8/FT8WaterfallView.swift`
- Create: `CarrierWave/Views/Logger/FT8/FT8CycleIndicatorView.swift`
- Create: `CarrierWave/Views/Logger/FT8/FT8ActiveQSOCard.swift`
- Create: `CarrierWave/Views/Logger/FT8/FT8ControlBar.swift`

This is the main FT8 UI. Each subview should be small (<100 lines). Refer to `docs/plans/2026-02-25-ft8-design.md` for the layout mockup.

**Step 1: Implement the subviews bottom-up**

Start with the smallest leaf views, then compose them.

`FT8CycleIndicatorView.swift` — the RX/TX timing bar:

```swift
//
//  FT8CycleIndicatorView.swift
//  CarrierWave
//

import SwiftUI

struct FT8CycleIndicatorView: View {
    let isTransmitting: Bool
    let timeRemaining: Double

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isTransmitting ? Color.orange : Color.blue)
                .frame(width: 8, height: 8)
            Text(isTransmitting ? "TX" : "RX")
                .font(.caption.bold())
                .foregroundStyle(isTransmitting ? .orange : .blue)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isTransmitting ? Color.orange : Color.blue)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 8)

            Text("\(Int(timeRemaining))s")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }

    private var progress: Double {
        max(0, min(1, (15.0 - timeRemaining) / 15.0))
    }
}
```

`FT8DecodeListView.swift` — scrolling decode results:

```swift
//
//  FT8DecodeListView.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

struct FT8DecodeListView: View {
    let decodes: [FT8DecodeResult]
    let currentCycleDecodes: [FT8DecodeResult]
    let myCallsign: String
    let onCallStation: (FT8DecodeResult) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(decodes.enumerated()), id: \.offset) { index, result in
                        decodeRow(result, isNew: currentCycleDecodes.contains(result))
                            .id(index)
                            .onTapGesture {
                                if result.message.isCallable {
                                    onCallStation(result)
                                }
                            }
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: decodes.count) {
                if let last = decodes.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func decodeRow(_ result: FT8DecodeResult, isNew: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(result.snr)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)

            Text(result.rawText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(textColor(for: result))
                .fontWeight(isNew ? .bold : .regular)

            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func textColor(for result: FT8DecodeResult) -> Color {
        if result.message.isCallable {
            return .green
        }
        if result.message.isDirectedTo(myCallsign) {
            return .red
        }
        return .primary
    }
}
```

`FT8ActiveQSOCard.swift` — shows current QSO progress:

```swift
//
//  FT8ActiveQSOCard.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

struct FT8ActiveQSOCard: View {
    let stateMachine: FT8QSOStateMachine

    var body: some View {
        if let call = stateMachine.theirCallsign, stateMachine.state != .idle {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Active QSO")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(stateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(call)
                        .font(.title3.bold())
                    if let grid = stateMachine.theirGrid {
                        Text(grid)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let report = stateMachine.theirReport {
                        Text("\(report) dB")
                            .font(.body.monospacedDigit())
                    }
                }

                ProgressView(value: stateProgress)
                    .tint(.orange)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    private var stateLabel: String {
        switch stateMachine.state {
        case .idle: "Idle"
        case .calling: "Calling..."
        case .reportSent: "Report Sent"
        case .reportReceived: "Confirming"
        case .complete: "Complete"
        }
    }

    private var stateProgress: Double {
        switch stateMachine.state {
        case .idle: 0
        case .calling: 0.2
        case .reportSent: 0.5
        case .reportReceived: 0.8
        case .complete: 1.0
        }
    }
}
```

`FT8ControlBar.swift` — mode controls and session stats:

```swift
//
//  FT8ControlBar.swift
//  CarrierWave
//

import SwiftUI

struct FT8ControlBar: View {
    @Binding var operatingMode: FT8OperatingMode
    let qsoCount: Int
    let parkReference: String?
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                modeButton("Listen", mode: .listen, systemImage: "headphones")
                modeButton("Call CQ", mode: .callCQ(modifier: nil), systemImage: "antenna.radiowaves.left.and.right")
                Button(action: onStop) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            HStack {
                Label("\(qsoCount) QSOs", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let park = parkReference {
                    Spacer()
                    Text(park)
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func modeButton(
        _ title: String,
        mode: FT8OperatingMode,
        systemImage: String
    ) -> some View {
        Button {
            operatingMode = mode
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .tint(isSelected(mode) ? .accentColor : .secondary)
    }

    private func isSelected(_ mode: FT8OperatingMode) -> Bool {
        switch (operatingMode, mode) {
        case (.listen, .listen): true
        case (.callCQ, .callCQ): true
        case (.searchAndPounce, .searchAndPounce): true
        default: false
        }
    }
}
```

`FT8SessionView.swift` — the main composed view:

```swift
//
//  FT8SessionView.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

struct FT8SessionView: View {
    @State var ft8Manager: FT8SessionManager
    @State private var waterfallData = FT8WaterfallData()
    let parkReference: String?

    var body: some View {
        VStack(spacing: 0) {
            bandSelector

            FT8WaterfallView(data: waterfallData)
                .frame(height: 80)

            FT8CycleIndicatorView(
                isTransmitting: ft8Manager.isTransmitting,
                timeRemaining: ft8Manager.cycleTimeRemaining
            )

            Divider()

            FT8DecodeListView(
                decodes: ft8Manager.decodeResults,
                currentCycleDecodes: ft8Manager.currentCycleDecodes,
                myCallsign: ft8Manager.qsoStateMachine.myCallsign,
                onCallStation: { ft8Manager.callStation($0) }
            )

            FT8ActiveQSOCard(stateMachine: ft8Manager.qsoStateMachine)

            Divider()

            FT8ControlBar(
                operatingMode: Binding(
                    get: { ft8Manager.operatingMode },
                    set: { ft8Manager.setMode($0) }
                ),
                qsoCount: ft8Manager.qsoCount,
                parkReference: parkReference,
                onStop: {
                    Task { await ft8Manager.stop() }
                }
            )
        }
        .task {
            try? await ft8Manager.start()
        }
    }

    private var bandSelector: some View {
        HStack {
            Picker("Band", selection: $ft8Manager.selectedBand) {
                ForEach(FT8Constants.supportedBands, id: \.self) { band in
                    Text(band).tag(band)
                }
            }
            .pickerStyle(.menu)

            Text("·")
                .foregroundStyle(.secondary)

            Text("\(ft8Manager.selectedFrequency, specifier: "%.3f") MHz")
                .font(.body.monospacedDigit())

            Text("·")
                .foregroundStyle(.secondary)

            Text("FT8")
                .font(.caption.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2))
                .clipShape(Capsule())

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}
```

`FT8WaterfallView.swift` — compact waterfall display using Canvas:

```swift
//
//  FT8WaterfallView.swift
//  CarrierWave
//

import SwiftUI

struct FT8WaterfallView: View {
    let data: FT8WaterfallData

    var body: some View {
        Canvas { context, size in
            let rows = data.magnitudes
            guard !rows.isEmpty, data.frequencyBins > 0 else { return }

            let rowHeight = size.height / CGFloat(min(rows.count, 60))
            let binWidth = size.width / CGFloat(data.frequencyBins)

            for (rowIdx, row) in rows.suffix(60).enumerated() {
                for (binIdx, magnitude) in row.enumerated() {
                    let rect = CGRect(
                        x: CGFloat(binIdx) * binWidth,
                        y: CGFloat(rowIdx) * rowHeight,
                        width: binWidth + 1,
                        height: rowHeight + 1
                    )
                    context.fill(
                        Path(rect),
                        with: .color(waterfallColor(magnitude))
                    )
                }
            }
        }
        .background(Color.black)
    }

    private func waterfallColor(_ magnitude: Float) -> Color {
        // Blue → Cyan → Green → Yellow → Red gradient
        let v = Double(magnitude)
        if v < 0.25 {
            return Color(red: 0, green: 0, blue: v * 4)
        } else if v < 0.5 {
            let t = (v - 0.25) * 4
            return Color(red: 0, green: t, blue: 1.0 - t)
        } else if v < 0.75 {
            let t = (v - 0.5) * 4
            return Color(red: t, green: 1.0, blue: 0)
        } else {
            let t = (v - 0.75) * 4
            return Color(red: 1.0, green: 1.0 - t, blue: 0)
        }
    }
}
```

**Step 2: Build to verify compilation**

Run: `xc build`
Expected: Compiles. Fix any SwiftUI API issues.

**Step 3: Commit**

```bash
git add CarrierWave/Views/Logger/FT8/
git commit -m "Add FT8 session UI views

Compact waterfall strip, scrolling decode list with color coding,
cycle timing indicator, active QSO progress card, and mode control
bar. Composed in FT8SessionView for the logger flow."
```

---

## Task 10: Logger Integration (Mode Conditional)

**Files:**
- Modify: `CarrierWave/Views/Logger/LoggerView+Layout.swift`

**Step 1: Add conditional FT8 view in the logger layout**

Read `LoggerView+Layout.swift` to find the `portraitLayout` and identify where to insert the mode-conditional branch. The FT8 view replaces the callsign input + form fields section when the session mode is "FT8" or "FT4".

Add a check in the `portraitLayout` body:

```swift
// Inside portraitLayout, where callsignInputSection + compactFieldsSection are:
if sessionManager?.activeSession?.mode == "FT8" {
    FT8SessionView(
        ft8Manager: ft8Manager,
        parkReference: sessionManager?.activeSession?.parkReference
    )
} else {
    callsignInputSection
    POTAStatusBanner(...)
    callsignLookupDisplay
    compactFieldsSection
}
```

The `ft8Manager` needs to be created when the session starts with mode FT8. Add a `@State private var ft8Manager: FT8SessionManager?` property to LoggerView and initialize it in `.onChange(of: sessionManager?.activeSession?.mode)`.

**Step 2: Build to verify compilation**

Run: `xc build`
Expected: Compiles.

**Step 3: Commit**

```bash
git add CarrierWave/Views/Logger/LoggerView+Layout.swift
git commit -m "Integrate FT8 session view into logger flow

When active session mode is FT8, the standard callsign input and
form fields are replaced with the FT8 session view (waterfall,
decode list, auto-sequencer). Session header and QSO list remain
shared between modes."
```

---

## Task 11: FT8 Setup Wizard

**Files:**
- Create: `CarrierWave/Views/Logger/FT8/FT8SetupWizardView.swift`

**Step 1: Implement the setup wizard**

This is a multi-step sheet shown when the user first enters FT8 mode. It guides them through audio connection, radio configuration, and audio level verification. Store completion state in `@AppStorage("ft8SetupComplete")`.

Write `FT8SetupWizardView.swift` with three steps:
1. Audio connection type selection (USB interface / TRRS cable / speaker-mic)
2. Radio configuration checklist (mode, frequency, power, VOX, AGC, filter)
3. Audio level check (start listening, verify decodes appear)

Each step uses a `TabView` with `.page` style for swipe navigation.

Save the user's selected connection type in `@AppStorage("ft8ConnectionType")` and selected band in `@AppStorage("ft8DefaultBand")`.

**Step 2: Show wizard on first FT8 session**

In the FT8 session initialization code, check `@AppStorage("ft8SetupComplete")`. If false, present the wizard as a `.sheet`. On completion, set the flag and start the session.

**Step 3: Build and test visually**

Run: `xc build && xc deploy`
Expected: Navigate to logger, start session with FT8 mode, wizard appears.

**Step 4: Commit**

```bash
git add CarrierWave/Views/Logger/FT8/FT8SetupWizardView.swift
git commit -m "Add FT8 setup wizard for first-time configuration

Three-step guide: audio connection type, radio configuration
checklist with band-specific dial frequency, and audio level
verification. Persists connection type and band preference."
```

---

## Task 12: Integration Testing

**Files:**
- Create: `CarrierWaveTests/FT8IntegrationTests.swift` (or equivalent test target)

**Step 1: Write integration tests**

Test the full flow from decoded messages to QSO creation:

```swift
@Test("FT8 QSO completion creates QSO with correct fields")
func ft8QSOCreation() async throws {
    // Set up in-memory SwiftData container
    // Create a LoggingSession with mode "FT8", frequency 14.074
    // Create FT8SessionManager
    // Simulate decode results for a complete S&P exchange
    // Verify QSO created with:
    //   - mode == "FT8"
    //   - band == "20m"
    //   - rstSent/rstReceived in dB format
    //   - theirGrid from FT8 exchange
    //   - parkReference from session (if POTA)
    //   - ServicePresence records created
}

@Test("FT8 dB signal reports stored correctly in RST fields")
func ft8SignalReportFormat() async throws {
    // Verify that negative dB values like "-12" are stored as strings
    // Verify ADIF export formats them correctly
}

@Test("POTA activation with FT8 auto-applies park reference")
func ft8POTAActivation() async throws {
    // Create POTA activation session with park K-1234
    // Complete an FT8 QSO
    // Verify QSO.parkReference == "K-1234"
    // Verify ServicePresence for POTA created
}
```

**Step 2: Run integration tests**

Run: `xc test-unit`
Expected: All PASS

**Step 3: Commit**

```bash
git add CarrierWaveTests/FT8IntegrationTests.swift
git commit -m "Add FT8 integration tests for QSO creation and sync

Validates end-to-end flow: decoded FT8 messages → QSO state machine
→ QSO model creation with dB signal reports → ServicePresence records.
Tests POTA activation context propagation."
```

---

## Task 13: Update FILE_INDEX.md and CHANGELOG.md

**Files:**
- Modify: `docs/FILE_INDEX.md`
- Modify: `CHANGELOG.md`

**Step 1: Add all new files to FILE_INDEX.md**

Add entries for:
- `CarrierWaveCore/Sources/CFT8/` — ft8_lib C library (vendored)
- `CarrierWaveCore/Sources/CarrierWaveCore/FT8Constants.swift`
- `CarrierWaveCore/Sources/CarrierWaveCore/FT8Message.swift`
- `CarrierWaveCore/Sources/CarrierWaveCore/FT8Decoder.swift`
- `CarrierWaveCore/Sources/CarrierWaveCore/FT8Encoder.swift`
- `CarrierWaveCore/Sources/CarrierWaveCore/FT8QSOStateMachine.swift`
- `CarrierWave/Services/FT8AudioEngine.swift`
- `CarrierWave/Services/FT8SessionManager.swift`
- `CarrierWave/Services/FT8WaterfallData.swift`
- `CarrierWave/Views/Logger/FT8/` — all FT8 UI views

**Step 2: Add CHANGELOG entry**

Under `[Unreleased]`:

```markdown
### Added
- FT8 digital mode support with full TX and RX capability
- FT8 decoder using ft8_lib C library (MIT license) in CarrierWaveCore
- FT8 encoder with GFSK tone synthesis for transmission
- FT8 session view with compact waterfall, decode list, and auto-sequencing
- QSO state machine with automatic message exchange (CQ and Search & Pounce modes)
- First-time setup wizard for audio connection and radio configuration
- Auto-logging of completed FT8 QSOs with dB signal reports
- Seamless integration with POTA/QRZ/LoFi sync pipeline
```

**Step 3: Commit**

```bash
git add docs/FILE_INDEX.md CHANGELOG.md
git commit -m "Update FILE_INDEX.md and CHANGELOG.md for FT8 feature"
```

---

## Summary

| Task | Description | New Files | Test Files |
|------|-------------|-----------|------------|
| 1 | Vendor ft8_lib C sources | ~20 C files + modulemap | (WAV samples) |
| 2 | FT8Constants + FT8Message | 2 Swift | 2 Swift |
| 3 | FT8Decoder (Swift wrapper) | 1 Swift | 1 Swift |
| 4 | FT8Encoder (Swift wrapper) | 1 Swift | 1 Swift |
| 5 | FT8QSOStateMachine | 1 Swift | 1 Swift |
| 6 | FT8AudioEngine | 1 Swift | — |
| 7 | FT8SessionManager | 1 Swift | — |
| 8 | FT8WaterfallData | 1 Swift | — |
| 9 | FT8 Session UI views | 6 Swift | — |
| 10 | Logger integration | 1 modified | — |
| 11 | Setup wizard | 1 Swift | — |
| 12 | Integration tests | — | 1 Swift |
| 13 | FILE_INDEX + CHANGELOG | 2 modified | — |

**Total: ~35 new files, 5 test files, 3 modified files, 13 commits.**
