# CW Memory Keyer UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add CW memory keyer UI to the iOS session logger — keyer button row, message editor with template preview, and bridge sync.

**Architecture:** `CWKeyerService` (actor) owns slot CRUD and bridge communication. `CWKeyerRow` (SwiftUI) renders the scrollable button strip. `CWMessageEditorView` provides the detail editor with macro pills and live preview. The keyer row is injected into `LoggerKeyboardAccessory` conditionally on bridge connection + CW mode.

**Tech Stack:** SwiftUI, UserDefaults, BridgeProtocol (CWBP), @Observable RadioService

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `swift/ios/CarrierWave/Services/CWKeyerService.swift` | Create | Slot CRUD (UserDefaults), template preview expansion, bridge sync, QSO context building |
| `swift/ios/CarrierWave/Views/Logger/CWKeyerRow.swift` | Create | Scrollable orange capsule buttons, STOP, progress state, long-press sheet |
| `swift/ios/CarrierWave/Views/Settings/CWMessageListView.swift` | Create | Settings list: WPM stepper, slot rows with preview, + Add Message |
| `swift/ios/CarrierWave/Views/Settings/CWMessageEditorView.swift` | Create | Detail editor: label, template field, macro pills, live preview |
| `swift/ios/CarrierWave/Views/Logger/LoggerKeyboardAccessory.swift` | Modify | Insert `CWKeyerRow` above command row |
| `swift/ios/CarrierWave/Views/Settings/RadioSettingsView.swift` | Modify | Add NavigationLink to CW Messages |
| `swift/ios/CarrierWave/Services/Radio/RadioService.swift` | Modify | Add CW keyer state properties |
| `swift/ios/CarrierWave/Services/Radio/RadioService+Bridge.swift` | Modify | Handle CW bridge events, sync slots on handshake |

---

### Task 1: CWKeyerService — Slot Storage and Template Expansion

**Files:**
- Create: `swift/ios/CarrierWave/Services/CWKeyerService.swift`

This is the data layer — no UI yet. Stores slot labels and templates in UserDefaults, expands templates with sample values for preview, and builds context dictionaries from QSO state.

- [ ] **Step 1: Create CWKeyerService with slot model and CRUD**

```swift
// swift/ios/CarrierWave/Services/CWKeyerService.swift

import UIKit

// MARK: - CWSlot

struct CWSlot: Identifiable {
    let id: Int // 1-8
    var label: String
    var text: String

    var isEmpty: Bool { text.isEmpty }

    /// Auto-derive label from first word of template if label is empty.
    var displayLabel: String {
        if !label.isEmpty { return label }
        let firstWord = text.split(separator: " ").first.map(String.init) ?? ""
        // Strip macro braces for display
        if firstWord.hasPrefix("{"), firstWord.hasSuffix("}") {
            return String(firstWord.dropFirst().dropLast())
        }
        return String(firstWord.prefix(8))
    }
}

// MARK: - CWKeyerService

@MainActor
@Observable
final class CWKeyerService {
    // MARK: Lifecycle

    init() {
        loadSlots()
    }

    // MARK: Internal

    static let maxSlots = 8
    static let maxSlotLength = 120

    /// All 8 slots (some may be empty).
    private(set) var slots: [CWSlot] = []

    /// Programmed (non-empty) slots only.
    var programmedSlots: [CWSlot] {
        slots.filter { !$0.isEmpty }
    }

    /// Current WPM setting.
    var wpm: Int {
        get { UserDefaults.standard.integer(forKey: "cwKeyer.wpm").clamped(to: 5 ... 60) }
        set {
            UserDefaults.standard.set(newValue.clamped(to: 5 ... 60), forKey: "cwKeyer.wpm")
        }
    }

    func slot(for slotID: Int) -> CWSlot? {
        slots.first { $0.id == slotID }
    }

    func updateSlot(id: Int, label: String, text: String) {
        guard let idx = slots.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = String(text.prefix(Self.maxSlotLength))
        slots[idx].label = String(label.prefix(8))
        slots[idx].text = trimmed
        saveSlot(slots[idx])
    }

    /// Find the first empty slot ID, or nil if all 8 are full.
    func nextEmptySlotID() -> Int? {
        slots.first { $0.isEmpty }?.id
    }

    // MARK: - Template Expansion

    /// Available macro definitions for the editor UI.
    static let macroVariables: [(macro: String, description: String)] = [
        ("{MYCALL}", "Your callsign"),
        ("{CALL}", "Their callsign"),
        ("{NR}", "Serial number (001, 002...)"),
        ("{RST}", "RST sent"),
        ("{NAME}", "Their name"),
        ("{EXCH}", "Your exchange"),
    ]

    static let macroProsigns: [String] = [
        "{BT}", "{AR}", "{SK}", "{KN}", "{AS}",
    ]

    /// Expand a template with sample values for preview display.
    func expandForPreview(_ template: String, myCall: String, exchange: String) -> String {
        let sampleContext: [String: String] = [
            "{MYCALL}": myCall.isEmpty ? "W6JY" : myCall,
            "{CALL}": "W1AW",
            "{NR}": "001",
            "{RST}": "599",
            "{NAME}": "HIRAM",
            "{EXCH}": exchange.isEmpty ? "001" : exchange,
        ]
        var result = template
        for (macro, value) in sampleContext {
            result = result.replacingOccurrences(of: macro, with: value)
        }
        return result
    }

    /// Build the context dictionary for a live CW_SLOT_PLAY command.
    func buildContext(
        callsign: String,
        myCall: String,
        serial: Int,
        rstSent: String,
        name: String,
        exchange: String
    ) -> [String: String] {
        [
            "MYCALL": myCall,
            "CALL": callsign,
            "NR": String(format: "%03d", serial),
            "RST": rstSent.isEmpty ? "599" : rstSent,
            "NAME": name,
            "EXCH": exchange,
        ]
    }

    // MARK: Private

    private func loadSlots() {
        slots = (1 ... Self.maxSlots).map { idx in
            let label = UserDefaults.standard.string(forKey: "cwKeyer.slot.\(idx).label") ?? ""
            let text = UserDefaults.standard.string(forKey: "cwKeyer.slot.\(idx).text") ?? ""
            return CWSlot(id: idx, label: label, text: text)
        }
    }

    private func saveSlot(_ slot: CWSlot) {
        UserDefaults.standard.set(slot.label, forKey: "cwKeyer.slot.\(slot.id).label")
        UserDefaults.standard.set(slot.text, forKey: "cwKeyer.slot.\(slot.id).text")
    }
}

// MARK: - Comparable Clamping

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
```

- [ ] **Step 2: Run swiftformat and swiftlint**

```bash
swiftformat swift/ios/CarrierWave/Services/CWKeyerService.swift
swiftlint lint --strict --config .swiftlint.yml swift/ios/CarrierWave/Services/CWKeyerService.swift
```

Expected: 0 violations.

- [ ] **Step 3: Commit**

```bash
git add swift/ios/CarrierWave/Services/CWKeyerService.swift
git commit -m "feat(keyer): add CWKeyerService for slot storage and template expansion"
```

---

### Task 2: CWMessageEditorView — Detail Editor with Macro Pills

**Files:**
- Create: `swift/ios/CarrierWave/Views/Settings/CWMessageEditorView.swift`

The reusable detail editor: label field, monospaced template field, tappable macro pills, and live preview. Used from both settings (NavigationLink) and logger (sheet on long-press).

- [ ] **Step 1: Create CWMessageEditorView**

```swift
// swift/ios/CarrierWave/Views/Settings/CWMessageEditorView.swift

import SwiftUI

// MARK: - CWMessageEditorView

struct CWMessageEditorView: View {
    let slotID: Int
    @Bindable var keyerService: CWKeyerService

    @State private var label: String = ""
    @State private var text: String = ""
    @Environment(\.dismiss) private var dismiss
    @AppStorage("stationCallsign") private var myCall = ""
    @AppStorage("contestExchange") private var exchange = ""

    var body: some View {
        Form {
            Section("Label") {
                TextField("CQ, EXCH, TU...", text: $label)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .onChange(of: label) { _, new in
                        label = String(new.prefix(8))
                    }
            }

            Section("Message") {
                TextField("CQ CQ DE {MYCALL} K", text: $text, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .lineLimit(3 ... 5)
                    .onChange(of: text) { _, new in
                        text = String(new.prefix(CWKeyerService.maxSlotLength))
                    }
            }

            Section("Insert Macro") {
                macroPillsView
            }

            Section("Preview") {
                Text(keyerService.expandForPreview(text, myCall: myCall, exchange: exchange))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }
        .navigationTitle("Message \(slotID)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let slot = keyerService.slot(for: slotID) {
                label = slot.label
                text = slot.text
            }
        }
        .onDisappear {
            keyerService.updateSlot(id: slotID, label: label, text: text)
        }
    }

    // MARK: Private

    @ViewBuilder
    private var macroPillsView: some View {
        FlowLayout(spacing: 8) {
            ForEach(CWKeyerService.macroVariables, id: \.macro) { macro in
                Button {
                    text.append(macro.macro)
                } label: {
                    Text(macro.macro)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            ForEach(CWKeyerService.macroProsigns, id: \.self) { prosign in
                Button {
                    text.append(prosign)
                } label: {
                    Text(prosign)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.25))
                        .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.26))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - FlowLayout

/// Simple horizontal flow layout that wraps to the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (positions, CGSize(width: maxX, height: currentY + lineHeight))
    }
}
```

- [ ] **Step 2: Run swiftformat and swiftlint**

```bash
swiftformat swift/ios/CarrierWave/Views/Settings/CWMessageEditorView.swift
swiftlint lint --strict --config .swiftlint.yml swift/ios/CarrierWave/Views/Settings/CWMessageEditorView.swift
```

Fix any violations (likely function length on `arrange` — split if needed).

- [ ] **Step 3: Commit**

```bash
git add swift/ios/CarrierWave/Views/Settings/CWMessageEditorView.swift
git commit -m "feat(keyer): add CWMessageEditorView with macro pills and live preview"
```

---

### Task 3: CWMessageListView — Settings Page

**Files:**
- Create: `swift/ios/CarrierWave/Views/Settings/CWMessageListView.swift`
- Modify: `swift/ios/CarrierWave/Views/Settings/RadioSettingsView.swift`

The settings list with WPM stepper, slot rows, and navigation to the detail editor.

- [ ] **Step 1: Create CWMessageListView**

```swift
// swift/ios/CarrierWave/Views/Settings/CWMessageListView.swift

import SwiftUI

// MARK: - CWMessageListView

struct CWMessageListView: View {
    @State private var keyerService = CWKeyerService()
    @AppStorage("stationCallsign") private var myCall = ""
    @AppStorage("contestExchange") private var exchange = ""

    var body: some View {
        List {
            Section("CW Speed") {
                Stepper(
                    "WPM: \(keyerService.wpm)",
                    value: Binding(
                        get: { keyerService.wpm },
                        set: { keyerService.wpm = $0 }
                    ),
                    in: 5 ... 60
                )
            }

            Section("Messages") {
                ForEach(keyerService.slots) { slot in
                    NavigationLink {
                        CWMessageEditorView(
                            slotID: slot.id,
                            keyerService: keyerService
                        )
                    } label: {
                        slotRow(slot)
                    }
                }
            }
        }
        .navigationTitle("CW Messages")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    @ViewBuilder
    private func slotRow(_ slot: CWSlot) -> some View {
        HStack(spacing: 10) {
            Text("\(slot.id)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)
                .frame(width: 20, alignment: .trailing)

            if slot.isEmpty {
                Text("Empty")
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.displayLabel)
                        .font(.subheadline.weight(.medium))
                    Text(
                        keyerService.expandForPreview(
                            slot.text,
                            myCall: myCall,
                            exchange: exchange
                        )
                    )
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Add NavigationLink in RadioSettingsView**

In `swift/ios/CarrierWave/Views/Settings/RadioSettingsView.swift`, add a CW Messages section in the `body` after the transport-specific sections:

```swift
// Add after the transport/advanced sections, before the dataLog section:
Section {
    NavigationLink {
        CWMessageListView()
    } label: {
        Label("CW Messages", systemImage: "radiowaves.right")
    }
}
```

Find the insertion point in the `body` `List`:
```swift
if radioService.transportType != .flex {
    advancedSection
}
// INSERT HERE — new section for CW Messages
Section {
    NavigationLink {
        CWMessageListView()
    } label: {
        Label("CW Messages", systemImage: "radiowaves.right")
    }
}
if !radioService.dataLog.isEmpty {
    dataLogSection
}
```

- [ ] **Step 3: Run swiftformat, swiftlint**

```bash
swiftformat swift/ios/CarrierWave/Views/Settings/CWMessageListView.swift swift/ios/CarrierWave/Views/Settings/RadioSettingsView.swift
swiftlint lint --strict --config .swiftlint.yml swift/ios/CarrierWave/Views/Settings/CWMessageListView.swift swift/ios/CarrierWave/Views/Settings/RadioSettingsView.swift
```

- [ ] **Step 4: Commit**

```bash
git add swift/ios/CarrierWave/Views/Settings/CWMessageListView.swift swift/ios/CarrierWave/Views/Settings/RadioSettingsView.swift
git commit -m "feat(keyer): add CW Messages settings page with slot list and WPM stepper"
```

---

### Task 4: CWKeyerRow — Logger Button Strip

**Files:**
- Create: `swift/ios/CarrierWave/Views/Logger/CWKeyerRow.swift`

The scrollable orange capsule row with STOP button and progress dimming.

- [ ] **Step 1: Create CWKeyerRow**

```swift
// swift/ios/CarrierWave/Views/Logger/CWKeyerRow.swift

import SwiftUI

// MARK: - CWKeyerRow

struct CWKeyerRow: View {
    let keyerService: CWKeyerService
    let onPlay: (Int, [String: String]) -> Void
    let onStop: () -> Void
    let onEdit: (Int) -> Void
    let context: () -> [String: String]

    /// Slot currently transmitting (nil if idle).
    var sendingSlot: Int?

    var body: some View {
        VStack(spacing: 0) {
            // Status line
            statusLine

            Divider()

            // Keyer buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(keyerService.programmedSlots) { slot in
                        slotButton(slot)
                    }
                    stopButton
                }
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: Private

    private var statusLine: some View {
        HStack(spacing: 4) {
            let service = RadioService.shared
            if let freq = service.radioFrequencyMHz {
                Text(FrequencyFormatter.format(freq))
                    .font(.caption2.monospaced())
                Text("·")
            }
            if let mode = service.radioMode {
                Text(mode)
                    .font(.caption2.weight(.medium))
                Text("·")
            }
            Text("\(keyerService.wpm) WPM")
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }

    private func slotButton(_ slot: CWSlot) -> some View {
        let isSending = sendingSlot == slot.id

        return Button {
            onPlay(slot.id, context())
        } label: {
            Text(slot.displayLabel)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
                .opacity(isSending ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                onEdit(slot.id)
            }
        )
    }

    private var stopButton: some View {
        Button {
            onStop()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10))
                Text("STOP")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.15))
            .foregroundStyle(.red)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(sendingSlot == nil)
        .opacity(sendingSlot != nil ? 1.0 : 0.4)
    }
}
```

- [ ] **Step 2: Run swiftformat and swiftlint**

```bash
swiftformat swift/ios/CarrierWave/Views/Logger/CWKeyerRow.swift
swiftlint lint --strict --config .swiftlint.yml swift/ios/CarrierWave/Views/Logger/CWKeyerRow.swift
```

- [ ] **Step 3: Commit**

```bash
git add swift/ios/CarrierWave/Views/Logger/CWKeyerRow.swift
git commit -m "feat(keyer): add CWKeyerRow with scrollable slot buttons and STOP"
```

---

### Task 5: Wire Keyer Row into LoggerKeyboardAccessory

**Files:**
- Modify: `swift/ios/CarrierWave/Views/Logger/LoggerKeyboardAccessory.swift`
- Modify: `swift/ios/CarrierWave/Services/Radio/RadioService.swift`

Add keyer row above the command row, conditional on bridge + CW mode.

- [ ] **Step 1: Add CW keyer state to RadioService**

In `swift/ios/CarrierWave/Services/Radio/RadioService.swift`, add these properties after the existing bridge state properties (after `var bridgeIsFramed: Bool = false` around line 133):

```swift
// MARK: - CW Keyer State (CWBP)

/// Whether the bridge supports CW keyer commands.
var bridgeHasCWKeyer: Bool = false

/// Slot currently transmitting (nil if idle).
var cwSendingSlot: Int?

/// CW keyer service instance (shared).
let cwKeyer = CWKeyerService()
```

- [ ] **Step 2: Add keyer row to LoggerKeyboardAccessory**

In `swift/ios/CarrierWave/Views/Logger/LoggerKeyboardAccessory.swift`, add the keyer row above the command row section. The keyer row should appear when `RadioService.shared.bridgeHasCWKeyer` is true and the mode is CW.

Add a `@State private var editingSlotID: Int?` and a sheet binding. Insert the keyer row just before the command row Divider:

```swift
// After the number row section and before the command row section,
// add the keyer row:

// CW Keyer row (above command row, when bridge connected in CW mode)
if showKeyerRow {
    Divider()
    CWKeyerRow(
        keyerService: RadioService.shared.cwKeyer,
        onPlay: { slot, ctx in playCWSlot(slot, context: ctx) },
        onStop: { stopCW() },
        onEdit: { editingSlotID = $0 },
        context: { buildCWContext() },
        sendingSlot: RadioService.shared.cwSendingSlot
    )
}
```

Add these computed properties and methods to `LoggerKeyboardAccessory`:

```swift
private var showKeyerRow: Bool {
    let service = RadioService.shared
    let isCW = service.radioMode == "CW" || service.radioMode == "CW-R"
    return service.bridgeHasCWKeyer && isCW && !service.cwKeyer.programmedSlots.isEmpty
}

private func playCWSlot(_ slot: Int, context: [String: String]) {
    guard let bridge = RadioService.shared.bridgeProtocol else { return }
    Task {
        try? await bridge.playCWSlot(UInt8(slot), context: context)
    }
}

private func stopCW() {
    guard let bridge = RadioService.shared.bridgeProtocol else { return }
    Task {
        try? await bridge.stopCW()
    }
}

private func buildCWContext() -> [String: String] {
    // Build from parent binding — the onCommand closure pattern
    // gives us access to the current callsign via the text binding
    RadioService.shared.cwKeyer.buildContext(
        callsign: text,
        myCall: UserDefaults.standard.string(forKey: "stationCallsign") ?? "",
        serial: 1, // TODO: wire to session QSO count
        rstSent: "599",
        name: "",
        exchange: UserDefaults.standard.string(forKey: "contestExchange") ?? ""
    )
}
```

Add the sheet for long-press editing:

```swift
.sheet(item: $editingSlotID) { slotID in
    NavigationStack {
        CWMessageEditorView(
            slotID: slotID,
            keyerService: RadioService.shared.cwKeyer
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { editingSlotID = nil }
            }
        }
    }
}
```

Note: `editingSlotID` needs `Int` to conform to `Identifiable` for the sheet binding. Wrap it:

```swift
@State private var editingSlotID: Int?
```

And use `.sheet(item:)` with an `Identifiable` wrapper, or use `.sheet(isPresented:)` with a guard. The simplest approach:

```swift
.sheet(isPresented: Binding(
    get: { editingSlotID != nil },
    set: { if !$0 { editingSlotID = nil } }
)) {
    if let slotID = editingSlotID {
        NavigationStack {
            CWMessageEditorView(
                slotID: slotID,
                keyerService: RadioService.shared.cwKeyer
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { editingSlotID = nil }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Run swiftformat and swiftlint**

```bash
swiftformat swift/ios/CarrierWave/Views/Logger/LoggerKeyboardAccessory.swift swift/ios/CarrierWave/Services/Radio/RadioService.swift
swiftlint lint --strict --config .swiftlint.yml swift/ios/CarrierWave/Views/Logger/LoggerKeyboardAccessory.swift swift/ios/CarrierWave/Services/Radio/RadioService.swift
```

- [ ] **Step 4: Commit**

```bash
git add swift/ios/CarrierWave/Views/Logger/LoggerKeyboardAccessory.swift swift/ios/CarrierWave/Services/Radio/RadioService.swift
git commit -m "feat(keyer): wire CWKeyerRow into logger keyboard accessory"
```

---

### Task 6: Bridge Event Handling and Slot Sync

**Files:**
- Modify: `swift/ios/CarrierWave/Services/Radio/RadioService+Bridge.swift`
- Modify: `swift/ios/CarrierWave/Services/Radio/RadioService.swift`

Handle CW events from the bridge and sync slots on handshake.

- [ ] **Step 1: Add CW event cases to handleBridgeEvent**

In `swift/ios/CarrierWave/Services/Radio/RadioService+Bridge.swift`, add cases for the CW events in the `handleBridgeEvent` switch. Add after the `.setVerifyResult` case:

```swift
case let .cwAck(result, bufferDepth):
    switch result {
    case .okay, .queued:
        addLog(.info, "CW ack: \(result) (buf=\(bufferDepth))")
    case .fail, .unsupported, .badSlot, .emptySlot:
        addLog(.error, "CW ack: \(result)")
        cwSendingSlot = nil
    }

case let .cwProgress(bufferDepth, flags):
    if flags.contains(.complete) {
        addLog(.info, "CW send complete")
        cwSendingSlot = nil
    } else {
        addLog(.info, "CW progress: buf=\(bufferDepth) flags=\(flags)")
    }

case let .cwStatus(wpm, bufferDepth, flags, slotCount):
    addLog(.info, "CW status: \(wpm) WPM, buf=\(bufferDepth), slots=\(slotCount)")
    cwKeyer.wpm = Int(wpm)
    if !flags.contains(.txActive) {
        cwSendingSlot = nil
    }
```

- [ ] **Step 2: Add slot sync on handshake**

In the `.handshakeComplete` case of `handleBridgeEvent`, add CW keyer sync after setting `bridgeIsFramed`:

```swift
case let .handshakeComplete(fwVersion, capabilities):
    addLog(.info, "Bridge handshake OK (fw \(fwVersion))")
    bridgeFirmwareVersion = fwVersion
    bridgeIsFramed = true

    // Check CW keyer capability
    let caps = BridgeFrame.Capabilities(rawValue: capabilities)
    bridgeHasCWKeyer = caps.contains(.cwKeyer)

    // Sync CW slots to bridge if keyer is supported
    if bridgeHasCWKeyer {
        syncCWSlotsTobridge(bridge: bridge)
    }
```

Add the sync method to the extension:

```swift
/// Push all programmed CW slots and speed to the bridge.
func syncCWSlotsTobridge(bridge: BridgeProtocol) {
    Task {
        // Sync speed
        try? await bridge.setCWSpeed(wpm: UInt8(cwKeyer.wpm))

        // Sync programmed slots
        for slot in cwKeyer.programmedSlots {
            try? await bridge.setCWSlot(UInt8(slot.id), text: slot.text)
        }
        addLog(.info, "CW keyer synced (\(cwKeyer.programmedSlots.count) slots, \(cwKeyer.wpm) WPM)")
    }
}
```

- [ ] **Step 3: Reset CW state on disconnect**

In the `resetBridgeState()` method of `RadioService+Bridge.swift`, add:

```swift
bridgeHasCWKeyer = false
cwSendingSlot = nil
```

- [ ] **Step 4: Track sending slot on play**

The `cwSendingSlot` needs to be set when the user taps a keyer button. In `LoggerKeyboardAccessory.swift`, update the `playCWSlot` method:

```swift
private func playCWSlot(_ slot: Int, context: [String: String]) {
    guard let bridge = RadioService.shared.bridgeProtocol else { return }
    RadioService.shared.cwSendingSlot = slot
    Task {
        try? await bridge.playCWSlot(UInt8(slot), context: context)
    }
}
```

- [ ] **Step 5: Run swiftformat and swiftlint on all modified files**

```bash
swiftformat swift/ios/CarrierWave/Services/Radio/RadioService+Bridge.swift swift/ios/CarrierWave/Services/Radio/RadioService.swift swift/ios/CarrierWave/Views/Logger/LoggerKeyboardAccessory.swift
swiftlint lint --strict --config .swiftlint.yml swift/ios/CarrierWave/Services/Radio/RadioService+Bridge.swift swift/ios/CarrierWave/Services/Radio/RadioService.swift swift/ios/CarrierWave/Views/Logger/LoggerKeyboardAccessory.swift
```

- [ ] **Step 6: Commit**

```bash
git add swift/ios/CarrierWave/Services/Radio/RadioService+Bridge.swift swift/ios/CarrierWave/Services/Radio/RadioService.swift swift/ios/CarrierWave/Views/Logger/LoggerKeyboardAccessory.swift
git commit -m "feat(keyer): handle CW bridge events and sync slots on handshake"
```

---

### Task 7: Build Verification

**Files:** None (verification only)

- [ ] **Step 1: Build the iOS app**

```bash
xc build
```

Expected: BUILD SUCCEEDED. Fix any compilation errors — likely candidates are access control issues (`bridgeProtocol` is internal, `cwKeyer` needs to be accessible from extensions).

- [ ] **Step 2: Run swiftlint on all new files**

```bash
swiftlint lint --strict --config .swiftlint.yml \
  swift/ios/CarrierWave/Services/CWKeyerService.swift \
  swift/ios/CarrierWave/Views/Settings/CWMessageEditorView.swift \
  swift/ios/CarrierWave/Views/Settings/CWMessageListView.swift \
  swift/ios/CarrierWave/Views/Logger/CWKeyerRow.swift
```

Expected: 0 violations.

- [ ] **Step 3: Update FILE_INDEX.md**

Add the new files to `docs/FILE_INDEX.md` under the appropriate sections:

```markdown
| `ios/CarrierWave/Services/CWKeyerService.swift` | CW memory keyer slot CRUD, template expansion, bridge sync context |
| `ios/CarrierWave/Views/Logger/CWKeyerRow.swift` | CW keyer button row in logger keyboard accessory |
| `ios/CarrierWave/Views/Settings/CWMessageListView.swift` | CW message slot list with WPM stepper (Settings) |
| `ios/CarrierWave/Views/Settings/CWMessageEditorView.swift` | CW message detail editor with macro pills and live preview |
```

- [ ] **Step 4: Final commit**

```bash
git add docs/FILE_INDEX.md
git commit -m "docs: add CW keyer files to FILE_INDEX.md"
```
