# FT8 Comms Interface Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the FT8 comms interface so operators can hold complete QSOs, with a conversation-centered UI that's significantly better than iFTX and WSJT-X on mobile.

**Architecture:** TDD on the state machine (CarrierWaveCore), then build UI components bottom-up (transcript row → conversation card → session view). The state machine fixes are the foundation — every UI component depends on correct role tracking and completion logic.

**Tech Stack:** Swift, SwiftUI, Swift Testing, CarrierWaveCore SPM package, SwiftData

**Design doc:** `docs/plans/2026-03-04-ft8-comms-interface-design.md`

**Build/test commands:** Use `xc` skill for all builds. `xc test-core` for CarrierWaveCore unit tests. `xc build` for full app build. `xc format` before commits.

---

### Task 1: State Machine — Role Tracking and R-Prefix Fix

The root cause of broken QSOs. The state machine doesn't know if we're the CQ originator or S&P responder, so it generates wrong TX messages.

**Files:**
- Modify: `CarrierWaveCore/Sources/CarrierWaveCore/FT8QSOStateMachine.swift`
- Modify: `CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8QSOStateMachineTests.swift`

**Step 1: Write failing tests for role tracking and R-prefix**

Add these tests to `FT8QSOStateMachineTests.swift`:

```swift
// MARK: - Role Tracking

@Test("S&P: role is searchAndPounce after initiateCall")
func spRoleTracking() {
    var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
    sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
    #expect(sm.role == .searchAndPounce)
}

@Test("CQ: role is cqOriginator when station responds to our CQ")
func cqRoleTracking() {
    var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
    sm.setCQMode(modifier: nil)
    sm.processMessage(.directed(from: "W9XYZ", to: myCall, grid: "EN37"))
    #expect(sm.role == .cqOriginator)
}

@Test("S&P: reportSent TX message has R-prefix")
func spReportSentHasRPrefix() {
    var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
    sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
    sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
    sm.myReport = -7
    #expect(sm.nextTXMessage == "W9XYZ \(myCall) R-07")
}

@Test("S&P: reportSent TX message has R-prefix for positive dB")
func spReportSentRPrefixPositive() {
    var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
    sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
    sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
    sm.myReport = 5
    #expect(sm.nextTXMessage == "W9XYZ \(myCall) R+05")
}

@Test("CQ: reportSent TX message has NO R-prefix")
func cqReportSentNoRPrefix() {
    var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
    sm.setCQMode(modifier: nil)
    sm.processMessage(.directed(from: "W9XYZ", to: myCall, grid: "EN37"))
    sm.myReport = -3
    #expect(sm.nextTXMessage == "W9XYZ \(myCall) -03")
}

@Test("Role resets to nil on resetForNextQSO")
func roleResetsOnReset() {
    var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
    sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
    #expect(sm.role == .searchAndPounce)
    sm.resetForNextQSO()
    #expect(sm.role == nil)
}
```

**Step 2: Run tests to verify they fail**

Run: `xc test-core`
Expected: 6 new tests FAIL — `role` property doesn't exist, R-prefix not generated.

**Step 3: Implement role tracking and R-prefix in state machine**

In `FT8QSOStateMachine.swift`:

1. Add `QSORole` enum and `role` property:
```swift
public enum QSORole: Sendable, Equatable {
    case cqOriginator
    case searchAndPounce
}

public private(set) var role: QSORole?
```

2. Set `role = .searchAndPounce` in `initiateCall(to:theirGrid:)`

3. Set `role = .cqOriginator` in `handleCQResponse(_:)`

4. Reset `role = nil` in `resetQSO()`

5. Fix `nextTXMessage` for `reportSent` state to check role:
```swift
case .reportSent:
    guard let their = theirCallsign, let report = myReport else {
        return nil
    }
    let sign = report >= 0 ? "+" : "-"
    let formatted = "\(sign)\(String(format: "%02d", abs(report)))"
    if role == .searchAndPounce {
        return "\(their) \(myCallsign) R\(formatted)"
    }
    return "\(their) \(myCallsign) \(formatted)"
```

**Step 4: Update existing tests that check reportSent TX message format**

The existing tests `reportSentNegativeDB` and `reportSentPositiveDB` use `initiateCall` (S&P), so their expected messages need the `R` prefix:
- `"W9XYZ K1ABC -07"` → `"W9XYZ K1ABC R-07"`
- `"W9XYZ K1ABC +05"` → `"W9XYZ K1ABC R+05"`

**Step 5: Run tests to verify all pass**

Run: `xc test-core`
Expected: ALL PASS

**Step 6: Commit**

```
feat: add role tracking and R-prefix to FT8 state machine

S&P responder now correctly sends R+NN (roger + report) instead of
plain +NN. CQ originator sends plain report. Role tracked via
QSORole enum, reset on QSO completion.

Fixes: S&P QSOs were sending wrong message format.
```

---

### Task 2: State Machine — Completing State and CQ Completion

CQ originator QSOs never complete because the state machine waits for their 73 after we send RR73. Add a `completing` state that logs the QSO immediately, with a grace cycle for final 73.

**Files:**
- Modify: `CarrierWaveCore/Sources/CarrierWaveCore/FT8QSOStateMachine.swift`
- Modify: `CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8QSOStateMachineTests.swift`

**Step 1: Write failing tests**

```swift
// MARK: - Completing State

@Test("CQ: QSO completes immediately when entering reportReceived (we will send RR73)")
func cqCompletesOnReportReceived() {
    var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
    sm.setCQMode(modifier: nil)
    sm.processMessage(.directed(from: "W9XYZ", to: myCall, grid: "EN37"))
    sm.myReport = -3
    sm.processMessage(.rogerReport(from: "W9XYZ", to: myCall, dB: 2))
    #expect(sm.state == .completing)
    #expect(sm.completedQSO != nil)
}

@Test("S&P: QSO completes when receiving RR73 (enters completing)")
func spCompletesOnRR73() {
    var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
    sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
    sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
    sm.myReport = -7
    sm.processMessage(.rogerEnd(from: "W9XYZ", to: myCall))
    #expect(sm.state == .completing)
    #expect(sm.completedQSO != nil)
}

@Test("Completing state returns to idle after one advanceCycle")
func completingReturnsToIdle() {
    var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
    sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
    sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
    sm.processMessage(.rogerEnd(from: "W9XYZ", to: myCall))
    #expect(sm.state == .completing)
    sm.advanceCycle()
    #expect(sm.state == .idle)
}

@Test("CQ: reportReceived TX message is RR73 for CQ originator")
func cqReportReceivedSendsRR73() {
    var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
    sm.setCQMode(modifier: nil)
    sm.processMessage(.directed(from: "W9XYZ", to: myCall, grid: "EN37"))
    sm.myReport = -3
    sm.processMessage(.rogerReport(from: "W9XYZ", to: myCall, dB: 2))
    #expect(sm.nextTXMessage == "W9XYZ \(myCall) RR73")
}

@Test("S&P: completing TX message is 73")
func spCompletingSends73() {
    var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
    sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
    sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
    sm.processMessage(.rogerEnd(from: "W9XYZ", to: myCall))
    #expect(sm.nextTXMessage == "W9XYZ \(myCall) 73")
}

@Test("S&P timeout reduced to 4 cycles")
func spTimeoutReducedTo4Cycles() {
    var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
    sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
    for _ in 0 ..< 4 {
        sm.advanceCycle()
    }
    #expect(sm.state == .idle, "S&P should timeout after 4 cycles")
}
```

**Step 2: Run tests to verify they fail**

Run: `xc test-core`
Expected: FAIL — no `completing` state exists.

**Step 3: Implement completing state**

1. Add `.completing` to the `State` enum.

2. Update `completedQSO` to also return data when `state == .completing`.

3. Update `nextTXMessage` for new states:
   - `.reportReceived` when CQ originator: return `"THEM MYCALL RR73"`
   - `.completing`: return `"THEM MYCALL 73"` (grace farewell)

4. Update `processMessage` transitions:
   - CQ originator in `.reportSent` receiving `.rogerReport`: go to `.completing` (not `.reportReceived`), mark complete
   - S&P in `.reportSent` receiving `.rogerEnd`: go to `.completing`, mark complete
   - Keep existing `.reportReceived` → complete transitions as fallback

5. Update `advanceCycle()`: if state is `.completing`, go to `.idle` and reset.

6. Set `maxCyclesBeforeTimeout` based on role: 4 for S&P, 8 for CQ.

**Step 4: Update existing tests**

The test `spCompleteOnRR73` currently expects `.complete` — update to expect `.completing`. The `completedQSOData` test checks `.complete` state — update to check `.completing`.

**Step 5: Run tests to verify all pass**

Run: `xc test-core`
Expected: ALL PASS

**Step 6: Commit**

```
feat: add completing state and fix CQ QSO completion

CQ originator now logs QSO immediately when receiving R+report
(entering completing state), sends RR73 as grace message.
S&P timeout reduced to 4 cycles (60s). Completing state auto-
resets to idle after one cycle.

Fixes: CQ QSOs never completed (waited for 73 that never came).
```

---

### Task 3: State Machine — Compound Callsign Matching

**Files:**
- Modify: `CarrierWaveCore/Sources/CarrierWaveCore/FT8QSOStateMachine.swift`
- Modify: `CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8QSOStateMachineTests.swift`

**Step 1: Write failing test**

```swift
@Test("Compound callsign matches base callsign in QSO")
func compoundCallsignMatches() {
    var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
    sm.initiateCall(to: "W9XYZ/P", theirGrid: "EN37")
    // They reply with base callsign (FT8 protocol may strip suffix)
    sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
    #expect(sm.state == .reportSent, "Should match W9XYZ to W9XYZ/P")
}
```

**Step 2: Run test, verify fail**

**Step 3: Implement base callsign extraction**

Add private helper:
```swift
private static func baseCallsign(_ call: String) -> String {
    let upper = call.uppercased()
    // Strip portable/mobile/QRP suffixes
    if let slashIndex = upper.lastIndex(of: "/") {
        let suffix = upper[upper.index(after: slashIndex)...]
        if ["P", "M", "QRP", "MM", "AM"].contains(String(suffix)) {
            return String(upper[..<slashIndex])
        }
        // Strip prefix modifiers (e.g., "VP2E/KD9ABC" → "KD9ABC")
        let prefix = upper[..<slashIndex]
        let base = upper[upper.index(after: slashIndex)...]
        // Longer part is likely the base callsign
        return String(base.count >= prefix.count ? base : prefix)
    }
    return upper
}
```

Update `processMessage` to compare `Self.baseCallsign(sender) == Self.baseCallsign(theirCallsign)` instead of exact match. Also update `workedCallsigns` to store base callsigns.

**Step 4: Run tests, verify pass**

**Step 5: Commit**

```
feat: handle compound callsigns in FT8 state machine

Base callsign extraction strips /P, /M, /QRP suffixes and
handles prefix modifiers (VP2E/KD9ABC). State machine matches
on base callsign so protocol variations don't break QSOs.
```

---

### Task 4: Session Manager — TX Frequency, TX Events, Halt/Resume, Parity Fix

**Files:**
- Modify: `CarrierWave/Services/FT8SessionManager.swift`

**Step 1: Add FT8TXEvent and FT8TXState types**

Add above `FT8SessionManager`:
```swift
struct FT8TXEvent: Identifiable, Sendable {
    let id = UUID()
    let message: String
    let timestamp: Date
    let audioFrequency: Double
}

enum FT8TXState: Sendable, Equatable {
    case idle
    case armed(callsign: String)
    case transmitting(message: String)
    case halted(callsign: String)
}
```

**Step 2: Add new properties to FT8SessionManager**

```swift
private(set) var rxAudioFrequency: Double = 1500
private(set) var txAudioFrequency: Double = 1500
private(set) var txEvents: [FT8TXEvent] = []
private(set) var txState: FT8TXState = .idle
private(set) var isTXHalted = false
var isFocusMode = false
```

**Step 3: Fix callStation — TX frequency and slot parity**

```swift
func callStation(_ result: FT8DecodeResult) {
    guard case let .cq(call, grid, _) = result.message else {
        Self.log.debug("callStation called with non-CQ message")
        return
    }
    setMode(.searchAndPounce)
    txAudioFrequency = result.frequency
    // TX on OPPOSITE parity from when we heard them
    transmitOnEven = !isEvenSlot
    qsoStateMachine.initiateCall(to: call, theirGrid: grid.isEmpty ? nil : grid)
    txState = .armed(callsign: call)
}
```

**Step 4: Fix transmitIfNeeded — use txAudioFrequency, record TX events**

```swift
private func transmitIfNeeded() {
    guard !isTXHalted else { return }
    if case .listen = operatingMode { return }
    guard let message = qsoStateMachine.nextTXMessage else { return }

    do {
        let samples = try FT8Encoder.encode(
            message: message,
            frequency: txAudioFrequency
        )
        isTransmitting = true
        txState = .transmitting(message: message)
        txEvents.append(FT8TXEvent(
            message: message,
            timestamp: Date(),
            audioFrequency: txAudioFrequency
        ))
        Task { @MainActor [weak self] in
            await self?.audioEngine.playTones(samples)
            self?.isTransmitting = false
            if let call = self?.qsoStateMachine.theirCallsign {
                self?.txState = .armed(callsign: call)
            } else {
                self?.txState = .idle
            }
        }
    } catch {
        Self.log.error("FT8 encode failed: \(error)")
    }
}
```

**Step 5: Add halt/resume methods**

```swift
func haltTX() {
    isTXHalted = true
    if let call = qsoStateMachine.theirCallsign {
        txState = .halted(callsign: call)
    }
}

func resumeTX() {
    isTXHalted = false
    if let call = qsoStateMachine.theirCallsign {
        txState = .armed(callsign: call)
    }
}
```

**Step 6: Update handleDecodedSlot — auto-set TX freq for CQ responses**

In the CQ response handling within `handleDecodedSlot`, after `qsoStateMachine.processMessage`, if we just entered a QSO from CQ mode (state went from idle to reportSent), set `txAudioFrequency = result.frequency`.

**Step 7: Update setMode to reset txState**

In `setMode(.listen)`: set `txState = .idle`.

**Step 8: Build and verify**

Run: `xc build`
Expected: BUILD SUCCEEDED

**Step 9: Commit**

```
feat: add TX frequency tracking, TX events, halt/resume to FT8 session

- TX frequency auto-set from decoded station's audio offset
- Fix slot parity: TX on opposite slot from when CQ was heard
- TX event log for conversation card transcript
- FT8TXState enum for control bar status display
- Halt/resume TX without aborting QSO
```

---

### Task 5: Decode Enricher — Cycle Age Tracking

**Files:**
- Modify: `CarrierWaveCore/Sources/CarrierWaveCore/FT8EnrichedDecode.swift`
- Modify: `CarrierWave/Services/FT8DecodeEnricher.swift`
- Modify: `CarrierWave/Services/FT8SessionManager.swift`

**Step 1: Add cycleAge to FT8EnrichedDecode**

In `FT8EnrichedDecode.swift`, add property:
```swift
/// Number of decode cycles since this was last heard. 0 = current cycle.
public var cycleAge: Int = 0
```

Add to init parameter list with default `cycleAge: Int = 0`.

**Step 2: Add cycle tracking to FT8DecodeEnricher**

```swift
private var currentCycleIndex = 0

func advanceCycle() {
    currentCycleIndex += 1
}

func enrich(_ decodes: [FT8DecodeResult]) -> [FT8EnrichedDecode] {
    decodes.map { decode in
        var enriched = enrichSingle(decode)
        enriched.cycleAge = 0
        return enriched
    }
}
```

**Step 3: Update FT8SessionManager to age enriched decodes**

In `onSlotBoundary()`, before calling `handleDecodedSlot`:
```swift
// Age existing enriched decodes
for i in enrichedDecodes.indices {
    enrichedDecodes[i].cycleAge += 1
}
decodeEnricher.advanceCycle()
```

**Step 4: Build and verify**

Run: `xc build`

**Step 5: Commit**

```
feat: add cycle age tracking to FT8 enriched decodes

Each enriched decode now tracks how many cycles old it is.
Used for freshness-based opacity and stale decode removal
in the decode list.
```

---

### Task 6: New View — FT8TranscriptRow and FT8NextTXRow

**Files:**
- Create: `CarrierWave/Views/Logger/FT8/FT8TranscriptRow.swift`
- Create: `CarrierWave/Views/Logger/FT8/FT8NextTXRow.swift`

**Step 1: Create FT8TranscriptRow**

```swift
//
//  FT8TranscriptRow.swift
//  CarrierWave
//

import SwiftUI

struct FT8TranscriptRow: View {
    let message: String
    let timestamp: Date
    let isTX: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(timestamp, format: .dateTime.hour().minute().second())
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)

            Image(systemName: isTX ? "arrow.right" : "arrow.left")
                .font(.system(size: 8))
                .foregroundStyle(isTX ? .blue : .secondary)

            Text(message)
                .font(.caption.monospaced())
                .lineLimit(1)

            Spacer()

            Text(isTX ? "TX" : "RX")
                .font(.caption2)
                .foregroundStyle(isTX ? .blue : .secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(isTX ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
    }
}
```

**Step 2: Create FT8NextTXRow**

```swift
//
//  FT8NextTXRow.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI

struct FT8NextTXRow: View {
    let nextMessage: String?
    let stepIndex: Int
    let totalSteps: Int
    let isOverrideActive: Bool
    let allMessages: [MessageOption]
    let onOverride: (String) -> Void

    @State private var isExpanded = false

    struct MessageOption: Identifiable {
        let id = UUID()
        let message: String
        let label: String
        let isAutoSelected: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            collapsedRow
            if isExpanded {
                overrideList
            }
        }
        .background(
            isOverrideActive
                ? Color.orange.opacity(0.1)
                : Color(.tertiarySystemGroupedBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            isOverrideActive
                ? RoundedRectangle(cornerRadius: 8)
                    .inset(by: 0.5)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                : nil
        )
    }

    private var collapsedRow: some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.0)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                if let msg = nextMessage {
                    Text(msg)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                } else {
                    Text("--")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text("auto \u{00B7} \(stepIndex)/\(totalSteps)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var overrideList: some View {
        VStack(spacing: 0) {
            Divider()
            ForEach(allMessages) { option in
                Button {
                    onOverride(option.message)
                    withAnimation { isExpanded = false }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: option.isAutoSelected ? "largecircle.fill.circle" : "circle")
                            .font(.caption)
                            .foregroundStyle(option.isAutoSelected ? .accent : .secondary)

                        Text(option.message)
                            .font(.caption.monospaced())
                            .lineLimit(1)

                        Spacer()

                        Text(option.label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

**Step 3: Build**

Run: `xc build`

**Step 4: Commit**

```
feat: add FT8TranscriptRow and FT8NextTXRow view components

TranscriptRow displays a single TX/RX message with timestamp,
direction arrow, and accent/gray background. NextTXRow shows
auto-selected next message with expandable override picker.
```

---

### Task 7: New View — FT8ConversationCard

**Files:**
- Create: `CarrierWave/Views/Logger/FT8/FT8ConversationCard.swift`
- Delete: `CarrierWave/Views/Logger/FT8/FT8ActiveQSOCard.swift`

**Step 1: Create FT8ConversationCard**

This replaces `FT8ActiveQSOCard`. Build it using `FT8TranscriptRow` and `FT8NextTXRow` from Task 6.

```swift
//
//  FT8ConversationCard.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI

struct FT8ConversationCard: View {
    let stateMachine: FT8QSOStateMachine
    let txEvents: [FT8TXEvent]
    let rxMessages: [FT8DecodeResult]
    let distanceMiles: Int?
    let dxccEntity: String?
    let txAudioFrequency: Double
    let isTXHalted: Bool
    let onHaltResume: () -> Void
    let onAbort: () -> Void
    let onOverride: (String) -> Void

    var body: some View {
        if let call = stateMachine.theirCallsign,
           stateMachine.state != .idle
        {
            VStack(alignment: .leading, spacing: 8) {
                headerSection(call)
                transcriptSection
                nextTXSection
                controlsSection
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Header

    private func headerSection(_ call: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(call)
                    .font(.headline.monospaced())

                if let grid = stateMachine.theirGrid {
                    Text(grid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                if let entity = dxccEntity {
                    Text("\u{00B7}")
                        .foregroundStyle(.tertiary)
                    Text(entity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let miles = distanceMiles {
                    Text("\u{00B7}")
                        .foregroundStyle(.tertiary)
                    Text("\(miles.formatted()) mi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 6) {
                if let report = stateMachine.theirReport {
                    Text("\(report) dB")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("\(Int(txAudioFrequency)) Hz")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        let entries = buildTranscript()
        return VStack(spacing: 0) {
            ForEach(entries.suffix(4)) { entry in
                FT8TranscriptRow(
                    message: entry.message,
                    timestamp: entry.timestamp,
                    isTX: entry.isTX
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Next TX

    private var nextTXSection: some View {
        let options = buildOverrideOptions()
        return FT8NextTXRow(
            nextMessage: stateMachine.nextTXMessage,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            isOverrideActive: false,
            allMessages: options,
            onOverride: onOverride
        )
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack {
            Spacer()
            Button(isTXHalted ? "Resume TX" : "Halt TX", action: onHaltResume)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Abort QSO", action: onAbort)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Helpers

    private var stepIndex: Int {
        switch stateMachine.state {
        case .idle: 0
        case .calling: 1
        case .reportSent: 2
        case .reportReceived: 3
        case .completing, .complete: 4
        }
    }

    private var totalSteps: Int { 4 }

    private struct TranscriptEntry: Identifiable {
        let id = UUID()
        let message: String
        let timestamp: Date
        let isTX: Bool
    }

    private func buildTranscript() -> [TranscriptEntry] {
        var entries: [TranscriptEntry] = []

        // Interleave TX events and RX messages by timestamp
        for tx in txEvents {
            entries.append(TranscriptEntry(message: tx.message, timestamp: tx.timestamp, isTX: true))
        }
        for rx in rxMessages {
            entries.append(TranscriptEntry(message: rx.rawText, timestamp: Date(), isTX: false))
        }

        return entries.sorted { $0.timestamp < $1.timestamp }
    }

    private func buildOverrideOptions() -> [FT8NextTXRow.MessageOption] {
        guard let their = stateMachine.theirCallsign else { return [] }
        let my = stateMachine.myCallsign
        let grid = stateMachine.myGrid
        let autoMsg = stateMachine.nextTXMessage

        var options: [FT8NextTXRow.MessageOption] = []

        // Current auto-selected message
        if let msg = autoMsg {
            options.append(.init(message: msg, label: "auto", isAutoSelected: true))
        }

        // Grid re-send
        let gridMsg = "\(their) \(my) \(grid)"
        if gridMsg != autoMsg {
            options.append(.init(message: gridMsg, label: "grid", isAutoSelected: false))
        }

        // RR73
        let rr73Msg = "\(their) \(my) RR73"
        if rr73Msg != autoMsg {
            options.append(.init(message: rr73Msg, label: "end", isAutoSelected: false))
        }

        // 73
        let endMsg = "\(their) \(my) 73"
        if endMsg != autoMsg {
            options.append(.init(message: endMsg, label: "bye", isAutoSelected: false))
        }

        return options
    }
}
```

**Step 2: Delete FT8ActiveQSOCard.swift**

Remove the file entirely.

**Step 3: Update FT8SessionView to use FT8ConversationCard**

Replace the `activeQSOCard` computed property in `FT8SessionView.swift`. Wire in the new properties from `ft8Manager` (txEvents, txAudioFrequency, isTXHalted). Also pass `onOverride` (initially a no-op, wired up in a later task).

**Step 4: Build**

Run: `xc build`
Fix any compilation issues.

**Step 5: Commit**

```
feat: replace FT8ActiveQSOCard with FT8ConversationCard

New conversation card shows real-time TX/RX transcript,
inline message override picker, and halt/abort controls.
Deletes the old 3-step indicator card.
```

---

### Task 8: FT8ControlBar — CQ Modifier Menu and TX Status Line

**Files:**
- Create: `CarrierWave/Views/Logger/FT8/FT8TXStatusLine.swift`
- Modify: `CarrierWave/Views/Logger/FT8/FT8ControlBar.swift`

**Step 1: Create FT8TXStatusLine**

```swift
//
//  FT8TXStatusLine.swift
//  CarrierWave
//

import SwiftUI

struct FT8TXStatusLine: View {
    let txState: FT8TXState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            statusDot
            statusText
        }
        .font(.caption)
    }

    @ViewBuilder
    private var statusDot: some View {
        switch txState {
        case .idle:
            EmptyView()
        case .armed:
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
        case .transmitting:
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
                .opacity(reduceMotion ? 1.0 : 1.0)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: txState
                )
        case .halted:
            Circle()
                .strokeBorder(Color.orange, lineWidth: 1.5)
                .frame(width: 8, height: 8)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch txState {
        case .idle:
            EmptyView()
        case let .armed(callsign):
            Text("TX armed \u{00B7} \(callsign)")
                .foregroundStyle(.secondary)
        case let .transmitting(message):
            Text("TX \u{00B7} \(message)")
                .font(.caption.monospaced())
                .foregroundStyle(.orange)
                .lineLimit(1)
        case let .halted(callsign):
            Text("TX halted \u{00B7} \(callsign)")
                .foregroundStyle(.secondary)
        }
    }
}
```

**Step 2: Add CQ modifier menu and TX status to FT8ControlBar**

Modify `FT8ControlBar.swift`:

1. Add new parameters:
```swift
let txState: FT8TXState
let parkReference: String?
```

2. Replace the "Call CQ" button with a `Menu`:
```swift
Menu {
    Button("CQ") { operatingMode = .callCQ(modifier: nil) }
    Button("CQ POTA") { operatingMode = .callCQ(modifier: "POTA") }
    Button("CQ DX") { operatingMode = .callCQ(modifier: "DX") }
    Button("CQ SOTA") { operatingMode = .callCQ(modifier: "SOTA") }
} label: {
    Label(cqLabel, systemImage: "antenna.radiowaves.left.and.right")
        .font(.caption.bold())
}
.buttonStyle(.bordered)
.tint(isCQSelected ? .accentColor : .secondary)
.disabled(!isReceiving)
```

Where `cqLabel` extracts the current modifier: `"CQ POTA"` if `.callCQ(modifier: "POTA")`, else `"Call CQ"`.

3. Replace the bottom counter row with conditional TX status:
```swift
HStack {
    if txState != .idle {
        FT8TXStatusLine(txState: txState)
    } else if parkReference != nil {
        potaCounter
    } else {
        Label("\(qsoCount) QSOs", systemImage: "list.bullet")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    Spacer()
}
```

**Step 3: Update FT8SessionView to pass new parameters to FT8ControlBar**

Wire `txState: ft8Manager.txState` and adjust the binding.

**Step 4: Build**

Run: `xc build`

**Step 5: Commit**

```
feat: add CQ modifier menu and TX status line to FT8 control bar

CQ button now opens a menu with POTA/DX/SOTA modifiers.
Auto-selects CQ POTA when park reference is active. TX status
line shows armed/transmitting/halted state with pulsing dot.
```

---

### Task 9: Decode List — Freshness, Inline Confirm, Priority Sort

**Files:**
- Modify: `CarrierWave/Views/Logger/FT8/FT8DecodeListView.swift`
- Modify: `CarrierWave/Views/Logger/FT8/FT8EnrichedDecodeRow.swift`
- Modify: `CarrierWave/Views/Logger/FT8/FT8CompactDecodeRow.swift`

**Step 1: Add freshness opacity to decode rows**

In `FT8EnrichedDecodeRow.swift`, update the opacity calculation:
```swift
.opacity(enriched.isDupe ? 0.5 : freshnessOpacity)

private var freshnessOpacity: Double {
    switch enriched.cycleAge {
    case 0...1: 1.0
    case 2...3: 0.6
    default: 0.4
    }
}
```

Add blue left border for current cycle:
```swift
HStack(spacing: 0) {
    if enriched.cycleAge == 0 {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.blue)
            .frame(width: 3)
    }
    // existing VStack content
}
```

Add audio frequency to essentials line:
```swift
Text("\(Int(enriched.decode.frequency)) Hz")
    .font(.caption.monospacedDigit())
    .foregroundStyle(.tertiary)
```

Do the same for `FT8CompactDecodeRow`.

**Step 2: Add inline call confirmation to FT8DecodeListView**

Add state:
```swift
@State private var confirmingCallID: UUID?
```

Replace the `onTapGesture` on CQ rows with:
```swift
.onTapGesture {
    if confirmingCallID == enriched.id {
        // Double-tap confirm
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onCallStation(enriched.decode)
        confirmingCallID = nil
    } else {
        confirmingCallID = enriched.id
    }
}
```

Below each CQ row, show confirm bar when selected:
```swift
if confirmingCallID == enriched.id, let call = enriched.decode.message.callerCallsign {
    HStack {
        Button("Call \(call)") {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onCallStation(enriched.decode)
            confirmingCallID = nil
        }
        .font(.caption.bold())
        .buttonStyle(.bordered)
        .tint(.accentColor)

        Spacer()

        Button("Cancel") { confirmingCallID = nil }
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .transition(.move(edge: .top).combined(with: .opacity))
}
```

**Step 3: Add freshness filtering to CQ section**

Filter stale decodes from CQ section:
```swift
private var cqDecodes: [FT8EnrichedDecode] {
    enrichedDecodes
        .filter { $0.section == .callingCQ && $0.cycleAge < 4 }
        .sorted { lhs, rhs in
            if lhs.sortPriority != rhs.sortPriority {
                return lhs.sortPriority < rhs.sortPriority
            }
            return lhs.decode.snr > rhs.decode.snr
        }
}
```

**Step 4: Add focus mode support**

Add parameter `isFocusMode: Bool`. When true:
- Hide all-activity section
- Filter dupes from CQ section: `.filter { !$0.isDupe }`

**Step 5: Build**

Run: `xc build`

**Step 6: Commit**

```
feat: add freshness aging, inline confirm, and focus mode to decode list

CQ decode rows now show freshness via opacity and blue border for
current cycle. Stale decodes (4+ cycles) removed from CQ section.
Tap-to-call shows inline confirmation bar with double-tap shortcut.
Focus mode hides all-activity and dupes.
```

---

### Task 10: Waterfall — RX/TX Frequency Markers

**Files:**
- Modify: `CarrierWave/Views/Logger/FT8/FT8WaterfallView.swift`

**Step 1: Add RX/TX frequency marker parameters**

```swift
var rxFrequency: Double = 1500
var txFrequency: Double = 1500
```

**Step 2: Draw RX/TX markers in Canvas**

Add a `drawFrequencyMarkers` method called after `drawChannelMarkers`:

```swift
private func drawFrequencyMarkers(
    context: GraphicsContext,
    size: CGSize,
    rxHz: Double,
    txHz: Double,
    minHz: Float,
    maxHz: Float
) {
    let range = CGFloat(maxHz - minHz)
    guard range > 0 else { return }

    // RX marker — green
    let rxFraction = CGFloat(Float(rxHz) - minHz) / range
    let rxX = rxFraction * size.width
    let rxLine = CGRect(x: rxX - 1, y: 0, width: 2, height: size.height)
    context.fill(Path(rxLine), with: .color(.green.opacity(0.8)))

    // TX marker — red
    let txFraction = CGFloat(Float(txHz) - minHz) / range
    let txX = txFraction * size.width
    let txLine = CGRect(x: txX - 1, y: 0, width: 2, height: size.height)
    context.fill(Path(txLine), with: .color(.red.opacity(0.8)))
}
```

**Step 3: Update FT8SessionView to pass frequencies**

Pass `rxFrequency: ft8Manager.rxAudioFrequency` and `txFrequency: ft8Manager.txAudioFrequency` to `FT8WaterfallView`.

**Step 4: Build**

Run: `xc build`

**Step 5: Commit**

```
feat: add RX/TX frequency markers to FT8 waterfall

Green line shows RX frequency, red line shows TX frequency.
Markers update when calling a station or changing mode.
```

---

### Task 11: Session View — Layout Modes and Focus Toggle

**Files:**
- Modify: `CarrierWave/Views/Logger/FT8/FT8SessionView.swift`

**Step 1: Add focus mode toggle to bandAndStatusRow**

Add a 🎯 button before the status pill:
```swift
Button {
    withAnimation(.spring(duration: 0.3, bounce: 0.0)) {
        ft8Manager.isFocusMode.toggle()
    }
} label: {
    Image(systemName: ft8Manager.isFocusMode ? "scope" : "target")
        .font(.caption)
        .foregroundStyle(ft8Manager.isFocusMode ? .orange : .secondary)
}
.buttonStyle(.plain)
```

When focus mode is active, add a thin orange top border:
```swift
.overlay(alignment: .top) {
    if ft8Manager.isFocusMode {
        Rectangle()
            .fill(Color.orange)
            .frame(height: 2)
    }
}
```

**Step 2: Update portrait layout to use conversation card**

Replace `activeQSOCard` with the new `FT8ConversationCard`, passing all required properties from `ft8Manager`.

**Step 3: Update landscape layout**

Left pane: waterfall + conversation card + controls.
Right pane: cycle indicator + decode list.

Wire the same conversation card component.

**Step 4: Pass focus mode to decode list**

```swift
FT8DecodeListView(
    enrichedDecodes: ft8Manager.enrichedDecodes,
    currentCycleIDs: Set(ft8Manager.currentCycleEnriched.map(\.id)),
    isFocusMode: ft8Manager.isFocusMode,
    onCallStation: { ft8Manager.callStation($0) }
)
```

**Step 5: Build**

Run: `xc build`

**Step 6: Format and lint**

Run: `xc format` then `xc lint`
Fix any violations (line length, function body length — split if needed).

**Step 7: Commit**

```
feat: add focus mode toggle and wire conversation card to session view

Focus mode (🎯) filters decode list to directed + CQ only,
hides dupes and all-activity. Orange top border indicates active.
Conversation card replaces old active QSO card in both portrait
and landscape layouts.
```

---

### Task 12: Integration Testing and Final Polish

**Files:**
- Modify: `CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8IntegrationTests.swift`
- Update: `docs/FILE_INDEX.md`
- Update: `CHANGELOG.md`

**Step 1: Add end-to-end state machine tests**

```swift
@Test("Full S&P QSO: CQ → call → report → R+report → RR73 → 73")
func fullSPQSO() {
    var sm = FT8QSOStateMachine(myCallsign: "W6JSV", myGrid: "DM13")
    sm.initiateCall(to: "W1ABC", theirGrid: "FN42")
    #expect(sm.role == .searchAndPounce)
    #expect(sm.state == .calling)
    #expect(sm.nextTXMessage == "W1ABC W6JSV DM13")

    sm.processMessage(.signalReport(from: "W1ABC", to: "W6JSV", dB: -7))
    #expect(sm.state == .reportSent)
    sm.myReport = -12
    #expect(sm.nextTXMessage == "W1ABC W6JSV R-12")

    sm.processMessage(.rogerEnd(from: "W1ABC", to: "W6JSV"))
    #expect(sm.state == .completing)
    #expect(sm.completedQSO != nil)
    #expect(sm.nextTXMessage == "W1ABC W6JSV 73")
}

@Test("Full CQ QSO: CQ → response → report → R+report → RR73")
func fullCQQSO() {
    var sm = FT8QSOStateMachine(myCallsign: "W6JSV", myGrid: "DM13")
    sm.setCQMode(modifier: "POTA")
    #expect(sm.nextTXMessage == "CQ POTA W6JSV DM13")

    sm.processMessage(.directed(from: "K5KHK", to: "W6JSV", grid: "FN13"))
    #expect(sm.role == .cqOriginator)
    #expect(sm.state == .reportSent)
    sm.myReport = -3
    #expect(sm.nextTXMessage == "K5KHK W6JSV -03")

    sm.processMessage(.rogerReport(from: "K5KHK", to: "W6JSV", dB: 2))
    #expect(sm.state == .completing)
    #expect(sm.completedQSO != nil)
    #expect(sm.completedQSO?.theirCallsign == "K5KHK")
    #expect(sm.nextTXMessage == "K5KHK W6JSV RR73")
}
```

**Step 2: Run all tests**

Run: `xc test-core`
Expected: ALL PASS

**Step 3: Full app build**

Run: `xc build`
Expected: BUILD SUCCEEDED

**Step 4: Update FILE_INDEX.md**

Add new files:
```
| `FT8ConversationCard.swift` | Active QSO conversation card with TX/RX transcript and message override |
| `FT8TranscriptRow.swift` | Single TX/RX message row for conversation transcript |
| `FT8NextTXRow.swift` | Next TX message display with expandable override picker |
| `FT8TXStatusLine.swift` | TX state indicator (armed/transmitting/halted) for control bar |
```

Remove deleted file:
```
| `FT8ActiveQSOCard.swift` | ...
```

**Step 5: Update CHANGELOG.md**

Under `[Unreleased]`:
```markdown
### Changed
- Redesign FT8 comms interface with conversation-centered layout
- Replace active QSO step indicator with full TX/RX conversation transcript
- Add inline message override picker for manual sequence control
- Add CQ modifier menu (POTA, DX, SOTA) to control bar

### Fixed
- Fix S&P mode sending wrong TX message (missing R-prefix on roger+report)
- Fix CQ QSOs never completing (now logs when RR73 sent, not waiting for 73)
- Fix TX slot parity (transmit on opposite slot from decoded station)
- Fix TX frequency hardcoded to 1500 Hz (now auto-set from decoded station)

### Added
- TX status line showing armed/transmitting/halted state
- Focus mode (🎯) filtering decode list to directed + CQ only
- Freshness aging on decode rows (opacity fade, stale removal)
- Cycle age tracking on enriched decodes
- RX/TX frequency markers on waterfall
- Tap-to-call inline confirmation with double-tap shortcut
- Halt/resume TX without aborting active QSO
- Compound callsign matching in state machine
```

**Step 6: Format and final build**

Run: `xc format && xc build`

**Step 7: Commit**

```
feat: complete FT8 comms interface redesign

Full redesign enabling QSO completion with conversation-centered
UI, role-aware state machine, TX frequency tracking, message
override, focus mode, and freshness-based decode list.

See docs/plans/2026-03-04-ft8-comms-interface-design.md
```

---

## Task Dependency Graph

```
Task 1 (role + R-prefix)
  └→ Task 2 (completing state)
       └→ Task 3 (compound calls)
            └→ Task 4 (session mgr: TX freq, events, halt)
                 ├→ Task 5 (enricher: cycle age)
                 ├→ Task 6 (transcript + next TX rows)
                 │    └→ Task 7 (conversation card)
                 ├→ Task 8 (control bar + TX status)
                 ├→ Task 9 (decode list enhancements)
                 └→ Task 10 (waterfall markers)
                      └→ Task 11 (session view: layout + focus)
                           └→ Task 12 (integration tests + polish)
```

Tasks 5–10 can be parallelized after Task 4 completes.
