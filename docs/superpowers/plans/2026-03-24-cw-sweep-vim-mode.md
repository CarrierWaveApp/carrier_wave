# CW Sweep Vim Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a vim-inspired modal keyboard interface to CW Sweep that replaces scattered shortcuts with a composable command language — four modes (Normal, Entry, Command, Search) with operators, motions, marks, macros, and undo.

**Architecture:** A new `VimEngine` observable manages modal state, key buffering, marks, macros, and undo history. An `NSEvent.addLocalMonitor(for: .keyDown)` in the app delegate intercepts all key events and routes them through VimEngine before SwiftUI's responder chain. VimEngine dispatches actions to existing services (RadioManager, WinKeyerManager, SelectionState) via a `VimActionExecutor`. The entry text field becomes mode-aware — unfocused in Normal mode, focused in Entry mode.

**Tech Stack:** SwiftUI (macOS), AppKit (NSEvent monitoring), SwiftData, CarrierWaveCore, CarrierWaveData

**Spec:** `docs/plans/cw-sweep-vim-mode.py` (PDF generator containing full design spec)

---

## Phased Delivery

This is a large feature. Each phase produces a working, testable increment. Phases are independent enough to ship separately.

| Phase | Scope | Tasks |
|-------|-------|-------|
| 1 | Core modal infrastructure (mode state, key interception, status bar badge) | 1–4 |
| 2 | Normal mode basics (j/k navigation, t tune, i enter, Tab focus, pane focus indicators) | 5–8 |
| 3 | Entry mode (mode-aware text field, Return logs, Escape exits, spot pre-fill) | 9–11 |
| 4 | Search mode (/ filter, filter language parser, live filtering) | 12–14 |
| 5 | Command mode (: command line, command parser, tab completion) | 15–17 |
| 6 | Marks, undo, dot-repeat, WPM control, F-key CW memories, Ctrl+C abort | 18–23 |
| 7 | Help overlay, discoverability, settings toggle | 24–26 |

---

## File Map

### New Files

| File | Responsibility |
|------|---------------|
| `CWSweep/CWSweep/Services/VimMode/VimEngine.swift` | Core modal state machine: current mode, pending key buffer, mode transitions, key dispatch |
| `CWSweep/CWSweep/Services/VimMode/VimKeyInterceptor.swift` | NSEvent.addLocalMonitor wrapper — intercepts keyDown events, routes to VimEngine |
| `CWSweep/CWSweep/Services/VimMode/VimActionExecutor.swift` | Translates VimEngine commands into app actions (tune, log, spot, lookup, etc.) |
| `CWSweep/CWSweep/Services/VimMode/VimMotion.swift` | Motion enum and parsing — j/k/gg/G/n/N/J/K/Tab/g1-g4 |
| `CWSweep/CWSweep/Services/VimMode/VimOperator.swift` | Operator enum — t/i/a/?/x/s/u/S/f/+/-/./F1-F6/Ctrl+C |
| `CWSweep/CWSweep/Services/VimMode/VimCommandParser.swift` | Parser for : command mode input (connect, set, role, park, summit, split, etc.) |
| `CWSweep/CWSweep/Services/VimMode/VimFilterParser.swift` | Parser for / search mode input (mode:, band:, src:, call:, new, dupe, need:) |
| `CWSweep/CWSweep/Services/VimMode/VimMarkStore.swift` | Frequency mark storage (a-z registers) with previous-frequency tracking ('') |
| `CWSweep/CWSweep/Services/VimMode/VimMacroRecorder.swift` | Macro recording and playback (qa-qz registers, @ replay) |
| `CWSweep/CWSweep/Services/VimMode/VimUndoStack.swift` | Undo history for reversible actions (log, dismiss, tune) |
| `CWSweep/CWSweep/Views/VimMode/VimStatusBadge.swift` | Mode badge view for status bar (NORMAL/ENTRY/COMMAND/SEARCH with colors) |
| `CWSweep/CWSweep/Views/VimMode/VimCommandLine.swift` | Command/Search input bar at bottom of workspace (appears in Command/Search modes) |
| `CWSweep/CWSweep/Views/VimMode/VimHelpOverlay.swift` | Translucent help overlay showing available commands for current mode |
| `CWSweep/CWSweep/Views/VimMode/VimPaneFocusIndicator.swift` | Focus border modifier for panes (accent when focused, dim when not) |
| `CWSweep/CWSweepTests/VimMode/VimEngineTests.swift` | Unit tests for modal state machine |
| `CWSweep/CWSweepTests/VimMode/VimFilterParserTests.swift` | Unit tests for filter language parsing |
| `CWSweep/CWSweepTests/VimMode/VimCommandParserTests.swift` | Unit tests for command parsing |
| `CWSweep/CWSweepTests/VimMode/VimMarkStoreTests.swift` | Unit tests for mark storage |
| `CWSweep/CWSweepTests/VimMode/VimMacroRecorderTests.swift` | Unit tests for macro recording/playback |
| `CWSweep/CWSweepTests/VimMode/VimUndoStackTests.swift` | Unit tests for undo stack |

### Modified Files

| File | Change |
|------|--------|
| `CWSweep/CWSweepApp.swift` | Initialize VimKeyInterceptor when vim mode enabled; pass VimEngine to environment |
| `CWSweep/CWSweep/Views/Workspace/WorkspaceView.swift` | Inject VimEngine into environment; add VimCommandLine overlay; add pane focus tracking |
| `CWSweep/CWSweep/Views/Workspace/StatusBarView.swift` | Add VimStatusBadge; show pending keys; show last command echo |
| `CWSweep/CWSweep/Views/Logger/ParsedEntryView.swift` | Make mode-aware: unfocus text field in Normal mode; suppress key handlers when not in Entry mode |
| `CWSweep/CWSweep/Views/Spots/SpotListView.swift` | Accept vim-driven selection changes; expose selection for VimEngine navigation |
| `CWSweep/CWSweep/Views/Spots/BandMapView.swift` | Accept vim-driven selection; j/k navigation when focused |
| `CWSweep/CWSweep/Models/SelectionState.swift` | Add focusedPane enum, vim-driven selection properties |
| `CWSweep/CWSweep/Views/Settings/SettingsView.swift` | Add vim mode toggle |
| `CWSweep/CWSweep/Models/LayoutConfiguration.swift` | Add pane numbering for g1-g4 focus |

---

## Phase 1: Core Modal Infrastructure

### Task 1: VimEngine — Modal State Machine

**Files:**
- Create: `CWSweep/CWSweep/Services/VimMode/VimEngine.swift`
- Create: `CWSweep/CWSweepTests/VimMode/VimEngineTests.swift`

- [ ] **Step 1: Write failing tests for mode transitions**

```swift
import Testing

@Suite("VimEngine Mode Transitions")
struct VimEngineTests {
    @Test func startsInNormalMode() {
        let engine = VimEngine()
        #expect(engine.mode == .normal)
    }

    @Test func escapeFromAnyModeReturnsToNormal() {
        let engine = VimEngine()
        engine.mode = .entry
        engine.handleEscape()
        #expect(engine.mode == .normal)

        engine.mode = .command
        engine.handleEscape()
        #expect(engine.mode == .normal)

        engine.mode = .search
        engine.handleEscape()
        #expect(engine.mode == .normal)
    }

    @Test func iEntersEntryMode() {
        let engine = VimEngine()
        engine.isEnabled = true
        engine.handleKey("i")
        #expect(engine.mode == .entry)
    }

    @Test func colonEntersCommandMode() {
        let engine = VimEngine()
        engine.isEnabled = true
        engine.handleKey(":")
        #expect(engine.mode == .command)
    }

    @Test func slashEntersSearchMode() {
        let engine = VimEngine()
        engine.isEnabled = true
        engine.handleKey("/")
        #expect(engine.mode == .search)
    }

    @Test func countPrefixWithMotion() {
        let engine = VimEngine()
        engine.isEnabled = true
        engine.handleKey("3")
        engine.handleKey("j")
        // Should produce moveSelection(.down(3))
    }

    @Test func gPrefixForPaneFocus() {
        let engine = VimEngine()
        engine.isEnabled = true
        engine.handleKey("g")
        engine.handleKey("1")
        // Should produce focusPane(.spots), not count 1
    }

    @Test func ggJumpsToTop() {
        let engine = VimEngine()
        engine.isEnabled = true
        engine.handleKey("g")
        engine.handleKey("g")
        // Should produce moveSelection(.top)
    }

    @Test func pendingKeyBufferShowsPartialInput() {
        let engine = VimEngine()
        engine.isEnabled = true
        engine.handleKey("m")
        #expect(engine.pendingKeys == "m")
        #expect(engine.mode == .normal) // still normal, waiting for register
    }

    @Test func pendingKeyTimeoutClears() async {
        let engine = VimEngine()
        engine.isEnabled = true
        engine.handleKey("m")
        #expect(engine.pendingKeys == "m")
        try? await Task.sleep(for: .seconds(1.1))
        #expect(engine.pendingKeys == "")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xc test-unit` or `swift test --filter VimEngineTests`
Expected: FAIL — VimEngine does not exist

- [ ] **Step 3: Implement VimEngine**

```swift
// CWSweep/CWSweep/Services/VimMode/VimEngine.swift
import SwiftUI

enum VimMode: String, Sendable {
    case normal = "NORMAL"
    case entry = "ENTRY"
    case command = "COMMAND"
    case search = "SEARCH"
}

@MainActor @Observable
final class VimEngine {
    var mode: VimMode = .normal
    var pendingKeys: String = ""
    var lastCommandEcho: String = ""
    var isEnabled: Bool = false
    var isPaletteActive: Bool = false // when true, interceptor passes all events through
    var commandLineText: String = ""
    var searchText: String = ""
    var isRecordingMacro: Bool = false
    var recordingRegister: Character?

    private var pendingKeyTimer: Task<Void, Never>?
    private var countBuffer: String = ""

    // MARK: - Mode transitions

    func handleEscape() {
        pendingKeys = ""
        countBuffer = ""
        pendingKeyTimer?.cancel()
        switch mode {
        case .entry:
            mode = .normal
        case .command:
            commandLineText = ""
            mode = .normal
        case .search:
            searchText = ""
            mode = .normal
        case .normal:
            break // already normal — clear any pending state
        }
    }

    func handleKey(_ key: String) {
        guard isEnabled else { return }

        switch mode {
        case .normal:
            handleNormalKey(key)
        case .entry:
            break // keys go to text field
        case .command:
            handleCommandKey(key)
        case .search:
            handleSearchKey(key)
        }
    }

    // MARK: - Normal mode

    private func handleNormalKey(_ key: String) {
        // Check for mode transitions first
        switch key {
        case "i":
            mode = .entry
            return
        case ":":
            mode = .command
            return
        case "/":
            mode = .search
            return
        default:
            break
        }

        // Accumulate pending keys for multi-key sequences
        pendingKeys += key
        pendingKeyTimer?.cancel()
        pendingKeyTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            guard !Task.isCancelled else { return }
            pendingKeys = ""
        }
    }

    private func handleCommandKey(_ key: String) {
        commandLineText += key
    }

    private func handleSearchKey(_ key: String) {
        searchText += key
    }

    func echo(_ message: String) {
        lastCommandEcho = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.0))
            if lastCommandEcho == message {
                lastCommandEcho = ""
            }
        }
    }

    // MARK: - Stub methods (implemented in later tasks, needed for VimKeyInterceptor to compile)
    func handleControlC() {}
    func handleEntryReturn() {}
    func handleLineReturn() {}
    func handleTab() {}
    func handleBackspace() {}
    func handleFKey(_ number: Int) {}
}
```

> **File splitting:** VimEngine will exceed the 300-line type body limit as features are added. Plan to split into extensions from the start: `VimEngine+NormalMode.swift`, `VimEngine+CommandMode.swift`, `VimEngine+SearchMode.swift`. Properties must be `internal` (not `private`) to allow extension access across files.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xc test-unit` or `swift test --filter VimEngineTests`
Expected: PASS

- [ ] **Step 5: Commit**

```
git add CWSweep/CWSweep/Services/VimMode/VimEngine.swift CWSweep/CWSweepTests/VimMode/VimEngineTests.swift
git commit -m "feat(cw-sweep): add VimEngine modal state machine"
```

---

### Task 2: VimKeyInterceptor — NSEvent Monitoring

**Files:**
- Create: `CWSweep/CWSweep/Services/VimMode/VimKeyInterceptor.swift`

- [ ] **Step 1: Implement key interceptor**

```swift
// CWSweep/CWSweep/Services/VimMode/VimKeyInterceptor.swift
import AppKit

@MainActor
final class VimKeyInterceptor {
    private var monitor: Any?
    private weak var engine: VimEngine?

    func install(engine: VimEngine) {
        self.engine = engine
        monitor = NSEvent.addLocalMonitor(forEventsMatching: .keyDown) { [weak self] event in
            guard let self, let engine = self.engine,
              engine.isEnabled, !engine.isPaletteActive else {
                return event
            }
            return self.handleKeyEvent(event, engine: engine)
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handleKeyEvent(_ event: NSEvent, engine: VimEngine) -> NSEvent? {
        // Cmd+key shortcuts always pass through (menu items)
        if event.modifierFlags.contains(.command) {
            return event
        }

        // Ctrl+C = abort CW (all modes)
        if event.modifierFlags.contains(.control),
           event.charactersIgnoringModifiers == "c"
        {
            engine.handleControlC()
            return nil // consumed
        }

        // Escape always returns to Normal
        if event.keyCode == 53 { // Escape
            engine.handleEscape()
            return nil
        }

        // In Entry mode, most keys pass through to the text field
        if engine.mode == .entry {
            // Return in Entry mode triggers log
            if event.keyCode == 36 { // Return
                engine.handleEntryReturn()
                return nil
            }
            // F1-F6 work in Entry mode too (CW memories)
            if let fKey = fKeyNumber(event), fKey >= 1, fKey <= 6 {
                engine.handleFKey(fKey)
                return nil
            }
            return event // all other keys go to text field
        }

        // In Command/Search mode, Return executes/locks
        if engine.mode == .command || engine.mode == .search {
            if event.keyCode == 36 { // Return
                engine.handleLineReturn()
                return nil
            }
            if event.keyCode == 48 { // Tab (completion)
                engine.handleTab()
                return nil
            }
            // Backspace
            if event.keyCode == 51 {
                engine.handleBackspace()
                return nil
            }
            // Regular characters go to command/search line
            if let chars = event.characters, !chars.isEmpty {
                engine.handleKey(chars)
                return nil
            }
            return event
        }

        // Normal mode — consume everything
        if let chars = event.characters, !chars.isEmpty {
            // F-keys
            if let fKey = fKeyNumber(event), fKey >= 1, fKey <= 6 {
                engine.handleFKey(fKey)
                return nil
            }
            engine.handleKey(chars)
            return nil
        }

        return event
    }

    private func fKeyNumber(_ event: NSEvent) -> Int? {
        switch event.keyCode {
        case 122: return 1 // F1
        case 120: return 2 // F2
        case 99: return 3  // F3
        case 118: return 4 // F4
        case 96: return 5  // F5
        case 97: return 6  // F6
        default: return nil
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xc build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```
git add CWSweep/CWSweep/Services/VimMode/VimKeyInterceptor.swift
git commit -m "feat(cw-sweep): add VimKeyInterceptor NSEvent monitor"
```

---

### Task 3: VimStatusBadge — Mode Indicator in Status Bar

**Files:**
- Create: `CWSweep/CWSweep/Views/VimMode/VimStatusBadge.swift`
- Modify: `CWSweep/CWSweep/Views/Workspace/StatusBarView.swift`

- [ ] **Step 1: Create VimStatusBadge view**

```swift
// CWSweep/CWSweep/Views/VimMode/VimStatusBadge.swift
import SwiftUI

struct VimStatusBadge: View {
    let mode: VimMode
    let pendingKeys: String
    let lastEcho: String

    var body: some View {
        HStack(spacing: 6) {
            Text(mode.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(modeColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(modeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))

            if !pendingKeys.isEmpty {
                Text(pendingKeys + "_")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if !lastEcho.isEmpty {
                Text(lastEcho)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var modeColor: Color {
        switch mode {
        case .normal: .green
        case .entry: .yellow
        case .command: .blue
        case .search: .purple
        }
    }
}
```

- [ ] **Step 2: Add badge to StatusBarView**

Insert at the start of StatusBarView's HStack, before the QSO count, conditionally on vim mode being enabled:

```swift
if vimEngine.isEnabled {
    VimStatusBadge(
        mode: vimEngine.mode,
        pendingKeys: vimEngine.pendingKeys,
        lastEcho: vimEngine.lastCommandEcho
    )
    Divider()
}
```

Add `@Environment(VimEngine.self) private var vimEngine` to StatusBarView.

- [ ] **Step 3: Build to verify compilation**

Run: `xc build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```
git add CWSweep/CWSweep/Views/VimMode/VimStatusBadge.swift CWSweep/CWSweep/Views/Workspace/StatusBarView.swift
git commit -m "feat(cw-sweep): add vim mode badge to status bar"
```

---

### Task 4: Wire VimEngine into App Lifecycle

**Files:**
- Modify: `CWSweep/CWSweepApp.swift`
- Modify: `CWSweep/CWSweep/Views/Workspace/WorkspaceView.swift`

- [ ] **Step 1: Create VimEngine in CWSweepApp and inject into environment**

In `CWSweepApp`, add `@State private var vimEngine = VimEngine()` and `@State private var vimInterceptor = VimKeyInterceptor()`.

In the `WindowGroup` body, add `.environment(vimEngine)`.

In `.onAppear` or `init`, call `vimInterceptor.install(engine: vimEngine)`.

Read `vimEngine.isEnabled` from UserDefaults (key: `"vimModeEnabled"`).

- [ ] **Step 2: Add VimEngine environment to WorkspaceView**

Add `@Environment(VimEngine.self) private var vimEngine` to WorkspaceView.

Set `vimEngine.isPaletteActive = true` when CommandPaletteView or RadioPaletteView is presented (observe their `isPresented` bindings). Set back to `false` on dismiss. This ensures palette key handling is not swallowed by the vim interceptor.

- [ ] **Step 3: Build and manually test**

Run: `xc build`
Expected: BUILD SUCCEEDED. App launches. Status bar shows no vim badge (disabled by default).

- [ ] **Step 4: Commit**

```
git add CWSweep/CWSweepApp.swift CWSweep/CWSweep/Views/Workspace/WorkspaceView.swift
git commit -m "feat(cw-sweep): wire VimEngine into app lifecycle"
```

---

## Phase 2: Normal Mode Basics

### Task 5: Pane Focus Model

**Files:**
- Modify: `CWSweep/CWSweep/Models/SelectionState.swift`
- Create: `CWSweep/CWSweep/Views/VimMode/VimPaneFocusIndicator.swift`

- [ ] **Step 1: Add FocusedPane enum to SelectionState**

```swift
enum FocusedPane: Int, CaseIterable, Sendable {
    case spots = 1
    case log = 2
    case bandMap = 3
    case cluster = 4
}

// In SelectionState:
var focusedPane: FocusedPane = .spots
```

- [ ] **Step 2: Create VimPaneFocusIndicator modifier**

A ViewModifier that draws an accent border when this pane is focused, dim border when not, and shows the pane number badge in the header. Only visible when vim mode is enabled.

- [ ] **Step 3: Apply modifier to SpotListView, QSOLogTableView, BandMapView, ClusterView in their parent layouts**

- [ ] **Step 4: Build and verify**

Run: `xc build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```
git commit -m "feat(cw-sweep): add pane focus model for vim mode"
```

---

### Task 6: VimMotion — Navigation Commands

**Files:**
- Create: `CWSweep/CWSweep/Services/VimMode/VimMotion.swift`

- [ ] **Step 1: Define VimMotion enum**

```swift
enum VimMotion: Sendable {
    case down(Int)           // j with count
    case up(Int)             // k with count
    case bandDown             // J
    case bandUp               // K
    case top                  // gg
    case bottom               // G
    case nextResult           // n
    case prevResult           // N
    case cycleFocus            // Tab
    case focusPane(FocusedPane) // g1-g4
}
```

- [ ] **Step 2: Add motion parsing to VimEngine.handleNormalKey**

Parse count prefix + motion key into VimMotion. Handle the `g` prefix for `gg` and `g1-g4`. Handle `G` (shift+g).

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```
git commit -m "feat(cw-sweep): add VimMotion parsing"
```

---

### Task 7: VimActionExecutor — Bridge to App Services

**Files:**
- Create: `CWSweep/CWSweep/Services/VimMode/VimActionExecutor.swift`

- [ ] **Step 1: Define VimAction enum**

```swift
enum VimAction: Sendable {
    case moveSelection(VimMotion)
    case tune
    case enterEntryMode
    case appendNotes
    case lookup
    case dismiss
    case spot
    case undo
    case toggleSplit
    case adjustWPM(Int)        // +/- without split active
    case adjustTXOffset(Int)   // +/- with split active (Hz steps)
    case directFrequency(String)
    case dotRepeat
    case sendCWMemory(Int)     // F1-F6
    case abortCW
    case jumpToAlert
    case setMark(Character)
    case jumpToMark(Character)
    case jumpToPrevious
    case startMacro(Character)
    case stopMacro
    case playMacro(Character)
    case executeCommand(String)
    case applyFilter(String)
    case clearFilter
}
```

- [ ] **Step 2: Implement VimActionExecutor**

```swift
@MainActor
final class VimActionExecutor {
    private let selectionState: SelectionState
    private let radioManager: RadioManager
    private let winKeyer: WinKeyerManager
    // ... other services

    func execute(_ action: VimAction) async { ... }
}
```

> **File splitting:** VimActionExecutor's `execute` method handles 25+ action cases. Split into extensions by category: `VimActionExecutor+Navigation.swift`, `VimActionExecutor+Radio.swift`, `VimActionExecutor+CW.swift`, `VimActionExecutor+Session.swift` to stay under the 50-line function body limit.
```

Each action case calls the appropriate service. For `moveSelection(.down(n))`: update `selectionState.focusedPane`'s selection index. For `tune`: call `radioManager.tuneToSpot(...)`. Etc.

- [ ] **Step 3: Wire VimEngine → VimActionExecutor**

VimEngine's `handleNormalKey` resolves a complete key sequence into a `VimAction` and calls `executor.execute(action)`.

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```
git commit -m "feat(cw-sweep): add VimActionExecutor bridging vim commands to app services"
```

---

### Task 8: j/k/t/Tab in Normal Mode — End-to-End

**Files:**
- Modify: `CWSweep/CWSweep/Views/Spots/SpotListView.swift`
- Modify: `CWSweep/CWSweep/Services/VimMode/VimEngine.swift`
- Modify: `CWSweep/CWSweep/Services/VimMode/VimActionExecutor.swift`

> **Note:** SpotListView is already at ~457 lines. Extract vim-related selection logic into `SpotListView+VimMode.swift` to avoid exceeding the 500-line limit.

- [ ] **Step 1: Make SpotListView selection driven by SelectionState when vim mode is active**

Add an `@Environment(VimEngine.self)` check. When vim mode is enabled, the Table selection binding is driven by `selectionState` rather than local `@State`. VimActionExecutor's `moveSelection(.down)` increments the selected index in the spot array.

- [ ] **Step 2: Wire `t` to tuneAndLog**

VimActionExecutor's `.tune` reads `selectionState.selectedSpot` and calls the existing `tuneToSpot` flow through RadioManager.

- [ ] **Step 3: Wire Tab to cycle `selectionState.focusedPane`**

- [ ] **Step 4: Manual test — launch app, enable vim mode, verify j/k moves spot selection, t tunes radio, Tab cycles pane focus border**

- [ ] **Step 5: Commit**

```
git commit -m "feat(cw-sweep): wire j/k/t/Tab in Normal mode end-to-end"
```

---

## Phase 3: Entry Mode

### Task 9: Mode-Aware ParsedEntryView

**Files:**
- Modify: `CWSweep/CWSweep/Views/Logger/ParsedEntryView.swift`

- [ ] **Step 1: Add vim mode awareness to ParsedEntryView**

When vim mode is enabled and mode is `.normal`, the text field's `@FocusState` is forced to `false` — the field is visible but not focused. This prevents Normal mode keys from being typed into the entry field.

When VimEngine transitions to `.entry` mode, set `isEntryFocused = true`. Pre-fill from `selectionState.pendingSpotEntry` if a spot was selected.

- [ ] **Step 2: Handle Return in Entry mode**

VimKeyInterceptor already catches Return in Entry mode and calls `engine.handleEntryReturn()`. This should trigger the existing `logQSO()` flow in ParsedEntryView and transition back to Normal mode.

Bridge: VimEngine publishes a `shouldLogEntry` flag; ParsedEntryView observes it and calls `logQSO()`.

- [ ] **Step 3: Handle Escape in Entry mode**

Already handled by VimKeyInterceptor → `engine.handleEscape()`. ParsedEntryView observes the mode change back to `.normal` and calls `clearEntry()` + unfocuses the text field.

- [ ] **Step 4: Build and manual test**

Verify: `i` focuses entry field, typing works, Return logs and returns to Normal, Escape clears and returns to Normal.

- [ ] **Step 5: Commit**

```
git commit -m "feat(cw-sweep): make ParsedEntryView vim-mode-aware"
```

---

### Task 10: Spot Pre-fill on `i` and on `t` then `i`

**Files:**
- Modify: `CWSweep/CWSweep/Services/VimMode/VimActionExecutor.swift`

- [ ] **Step 1: When `i` is pressed with a spot selected, populate entry field**

VimActionExecutor's `.enterEntryMode` checks `selectionState.selectedSpot`. If present, sets `selectionState.pendingSpotEntry` with the spot's callsign/freq/mode (same format as existing `tuneAndLog`). Then transitions to Entry mode.

- [ ] **Step 2: When `t` then `i`, spot is already pre-filled from tune**

The existing flow already sets `pendingSpotEntry` during tune. Just verify this works.

- [ ] **Step 3: Commit**

```
git commit -m "feat(cw-sweep): pre-fill entry from selected spot on i"
```

---

### Task 11: Entry History Navigation

**Files:**
- Modify: `CWSweep/CWSweep/Views/Logger/ParsedEntryView.swift`

- [ ] **Step 1: Verify Up/Down arrow history works in Entry mode**

VimKeyInterceptor passes Up/Down through to the text field in Entry mode (they're not consumed). ParsedEntryView's existing `.onKeyPress(.upArrow)` and `.onKeyPress(.downArrow)` handlers should still work. Verify this.

If they don't work because NSEvent monitor consumes them first, add explicit passthrough for arrow keys in Entry mode in VimKeyInterceptor.

- [ ] **Step 2: Commit if changes needed**

---

## Phase 4: Search Mode

### Task 12: VimFilterParser

**Files:**
- Create: `CWSweep/CWSweep/Services/VimMode/VimFilterParser.swift`
- Create: `CWSweep/CWSweepTests/VimMode/VimFilterParserTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
@Suite("VimFilterParser")
struct VimFilterParserTests {
    @Test func parseModeFilter() {
        let result = VimFilterParser.parse("cw")
        #expect(result.modeFilter == "CW")
    }

    @Test func parseBandFilter() {
        let result = VimFilterParser.parse("20m")
        #expect(result.bandFilter == "20m")
    }

    @Test func parseSourceFilter() {
        let result = VimFilterParser.parse("pota")
        #expect(result.sourceFilter == .pota)
    }

    @Test func parseNeededFilter() {
        let result = VimFilterParser.parse("new")
        #expect(result.neededOnly == true)
    }

    @Test func parseCombined() {
        let result = VimFilterParser.parse("cw 20m new")
        #expect(result.modeFilter == "CW")
        #expect(result.bandFilter == "20m")
        #expect(result.neededOnly == true)
    }

    @Test func parseCallsignPrefix() {
        let result = VimFilterParser.parse("ja")
        #expect(result.callsignPrefix == "JA")
    }

    @Test func disambiguateWithPrefix() {
        let result = VimFilterParser.parse("call:cw")
        #expect(result.callsignPrefix == "CW")
        #expect(result.modeFilter == nil)
    }

    @Test func parseBandNeedFilter() {
        let result = VimFilterParser.parse("need:40m")
        #expect(result.neededOnBand == "40m")
    }
}
```

- [ ] **Step 2: Run tests — verify failure**

- [ ] **Step 3: Implement VimFilterParser**

A struct that tokenizes the input on spaces, matches each token against known keywords (mode names, band names, source names, `new`, `dupe`), and falls through to callsign prefix for unrecognized tokens. Supports `mode:`, `band:`, `src:`, `call:`, `need:` prefixes for disambiguation.

- [ ] **Step 4: Run tests — verify pass**

- [ ] **Step 5: Commit**

```
git commit -m "feat(cw-sweep): add VimFilterParser for search mode"
```

---

### Task 13: VimCommandLine View

**Files:**
- Create: `CWSweep/CWSweep/Views/VimMode/VimCommandLine.swift`
- Modify: `CWSweep/CWSweep/Views/Workspace/WorkspaceView.swift`

- [ ] **Step 1: Create VimCommandLine view**

A bottom-of-window bar that appears in Command and Search modes. Shows `:` or `/` prefix. Uses a real `TextField` with `@FocusState` — this gives native text editing affordances (cursor movement, word-delete, selection) for free. The VimKeyInterceptor passes character keys through to the TextField when in Command/Search mode. `onSubmit` triggers execution; Escape observation triggers cancel.

- [ ] **Step 2: Add to WorkspaceView as an overlay at the bottom**

Show conditionally when `vimEngine.mode == .command || vimEngine.mode == .search`.

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```
git commit -m "feat(cw-sweep): add VimCommandLine overlay view"
```

---

### Task 14: Live Search Filtering

**Files:**
- Modify: `CWSweep/CWSweep/Views/Spots/SpotListView.swift`
- Modify: `CWSweep/CWSweep/Services/VimMode/VimEngine.swift`

- [ ] **Step 1: Connect VimEngine.searchText to SpotListView filtering**

SpotListView already has filter state (band, mode, source, text search). When vim mode is active and `searchText` changes, apply `VimFilterParser.parse(searchText)` results to the existing filter properties.

- [ ] **Step 2: Handle Return in Search mode — lock filter**

VimEngine's `handleLineReturn()` in Search mode: parse the current searchText, store as active filter, transition to Normal mode. The filter persists until Escape clears it.

- [ ] **Step 3: Handle Escape in Search mode — clear filter**

Already handled — `handleEscape()` clears `searchText` and returns to Normal. SpotListView observes the cleared text and removes the vim-applied filters.

- [ ] **Step 4: Manual test**

Type `/cw 20m`, verify spots filter live. Press Return, verify filter sticks. Press Escape, verify filter clears.

- [ ] **Step 5: Commit**

```
git commit -m "feat(cw-sweep): wire search mode to live spot filtering"
```

---

## Phase 5: Command Mode

### Task 15: VimCommandParser

**Files:**
- Create: `CWSweep/CWSweep/Services/VimMode/VimCommandParser.swift`
- Create: `CWSweep/CWSweepTests/VimMode/VimCommandParserTests.swift`

- [ ] **Step 1: Write failing tests**

Test parsing for all command types:

**Radio/Config:** `connect w3lpl`, `disconnect`, `set wpm 25`, `set power 100`, `role hunter`, `role activator`, `park K-1234`, `summit W4C/CM-001`, `split up 2`, `split dn 1`, `split off`, `export adif`, `import adif`

**CW Sending:** `cq`, `send 1`–`send 6`, `send TU 73` (freeform), `wpm 22`, `agn`, `tu`

**Cluster:** `dx`, `wwv`, `skimmer`, `raw SH/DX`

**Activation:** `spot`, `spot CQ 40m SSB`, `respot`, `rove K-5678`, `end`, `upload`

**Alerts:** `alert add P5`, `alert add 3Y cw 40m`, `alert list`, `alert clear`

**Other:** `help`, `notes`

- [ ] **Step 2: Implement VimCommandParser**

Returns a `VimCommand` enum with associated values. Tokenizes on spaces. First token is the command name, rest are arguments.

- [ ] **Step 3: Run tests — verify pass**

- [ ] **Step 4: Commit**

```
git commit -m "feat(cw-sweep): add VimCommandParser for command mode"
```

---

### Task 16: Command Execution

**Files:**
- Modify: `CWSweep/CWSweep/Services/VimMode/VimActionExecutor.swift`

- [ ] **Step 1: Add executeCommand to VimActionExecutor**

Map each `VimCommand` case to the appropriate service call:
- `connect` → `clusterManager.connect(node:)`
- `set wpm` → `winKeyer.setSpeed()`
- `role` → update `activeRole` in WorkspaceView
- `park`/`summit` → update session state
- `split up/dn/off` → RadioManager XIT calls
- `spot` → POTASpotService or cluster spot
- `alert` → alert configuration storage (UserDefaults)
- `help` → toggle help overlay

- [ ] **Step 2: Wire Return in Command mode to parse + execute**

VimEngine's `handleLineReturn()` in Command mode: parse `commandLineText` with VimCommandParser, dispatch to VimActionExecutor, clear command line, transition to Normal.

- [ ] **Step 3: Commit**

```
git commit -m "feat(cw-sweep): wire command mode execution"
```

---

### Task 17: Command Tab Completion

**Files:**
- Modify: `CWSweep/CWSweep/Services/VimMode/VimEngine.swift`

- [ ] **Step 1: Add tab completion to command mode**

Maintain a list of known command prefixes. On Tab in command mode, find the longest common completion for the current input. If unique match, complete it. If multiple matches, show options in the echo area.

- [ ] **Step 2: Commit**

```
git commit -m "feat(cw-sweep): add tab completion for command mode"
```

---

## Phase 6: Advanced Normal Mode Features

### Task 18: VimMarkStore — Frequency Bookmarks

**Files:**
- Create: `CWSweep/CWSweep/Services/VimMode/VimMarkStore.swift`
- Create: `CWSweep/CWSweepTests/VimMode/VimMarkStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Test: set mark, retrieve mark, previous frequency tracking, '' jump-back.

- [ ] **Step 2: Implement VimMarkStore**

Stores 26 named marks (a-z) as `(frequencyMHz: Double, mode: String)` tuples. Tracks previous frequency for `''`. Updated on every tune action.

- [ ] **Step 3: Wire into VimEngine**

`m` + letter → `markStore.set(register, frequency, mode)`. `'` + letter → `executor.execute(.tune(markStore.get(register)))`. `''` → `executor.execute(.tune(markStore.previous))`.

- [ ] **Step 4: Run tests, build, commit**

```
git commit -m "feat(cw-sweep): add frequency marks (m/'/'')"
```

---

### Task 19: VimUndoStack

**Files:**
- Create: `CWSweep/CWSweep/Services/VimMode/VimUndoStack.swift`
- Create: `CWSweep/CWSweepTests/VimMode/VimUndoStackTests.swift`

- [ ] **Step 1: Write failing tests**

Test: push action, undo pops and returns inverse action, multiple undos work in order.

- [ ] **Step 2: Implement VimUndoStack**

Each reversible action (log QSO, dismiss spot, tune) pushes an undo entry. `u` pops and executes the inverse (delete QSO, un-dismiss, tune to previous frequency).

- [ ] **Step 3: Wire into VimActionExecutor**

Before executing a reversible action, push the inverse onto the undo stack.

- [ ] **Step 4: Run tests, build, commit**

```
git commit -m "feat(cw-sweep): add undo stack (u)"
```

---

### Task 20: Dot-Repeat

**Files:**
- Modify: `CWSweep/CWSweep/Services/VimMode/VimEngine.swift`

- [ ] **Step 1: Track last compound action**

When a compound action completes (e.g., `i` → type → Return), record it as the "last action." `.` replays it.

For logging: replay enters Entry mode with the same defaults (RST, mode) but blank callsign.
For dismiss: dismiss the currently selected spot.
For tune: re-tune to the same frequency (less useful, but consistent).

- [ ] **Step 2: Commit**

```
git commit -m "feat(cw-sweep): add dot-repeat (.)"
```

---

### Task 21: WPM Speed / TX Offset Control (+/-)

**Files:**
- Modify: `CWSweep/CWSweep/Services/VimMode/VimActionExecutor.swift`

- [ ] **Step 1: Wire +/- with dual behavior based on split state**

**Without split active:** Read current speed from `winKeyer.speed`. Apply delta (+/- 2 * count). Clamp to 5–60 WPM. Call `winKeyer.setSpeed(newSpeed)`. Echo "WPM: {newSpeed}".

**With split active:** Adjust TX frequency offset. Step size: 1000 Hz for SSB modes, 500 Hz for CW. Apply count multiplier. Call `radioManager.setXITOffset(newOffset)`. Echo "TX: +{offset} Hz".

- [ ] **Step 2: Commit**

```
git commit -m "feat(cw-sweep): add +/- WPM speed control in Normal mode"
```

---

### Task 22: F1–F6 CW Memories

**Files:**
- Modify: `CWSweep/CWSweep/Services/VimMode/VimActionExecutor.swift`

- [ ] **Step 1: Wire F-keys to WinKeyerManager.sendText via MacroEngine**

VimActionExecutor's `.sendCWMemory(n)` reads macro text from MacroEngine for slot n, calls `winKeyer.sendText(macroText)`. If no macro is configured, echo "No macro in F{n}".

Note: MacroEngine → WinKeyerManager wiring does not currently exist. This task creates it.

- [ ] **Step 2: Commit**

```
git commit -m "feat(cw-sweep): add F1-F6 CW memory sending"
```

---

### Task 23: Ctrl+C CW Abort

**Files:**
- Modify: `CWSweep/CWSweep/Services/VimMode/VimEngine.swift`
- Modify: `CWSweep/CWSweep/Services/VimMode/VimActionExecutor.swift`

- [ ] **Step 1: Add handleControlC to VimEngine**

Dispatches `.abortCW` action. Does NOT change mode.

- [ ] **Step 2: Wire to WinKeyerManager.cancelSending and RadioManager abort**

VimActionExecutor's `.abortCW` calls `winKeyer.cancelSending()`. If using radio-internal CW (Elecraft/Flex), also sends the protocol-level abort command. Echo "CW aborted".

- [ ] **Step 3: Commit**

```
git commit -m "feat(cw-sweep): add Ctrl+C CW abort"
```

---

## Phase 7: Discoverability and Settings

### Task 24: VimHelpOverlay

**Files:**
- Create: `CWSweep/CWSweep/Views/VimMode/VimHelpOverlay.swift`

- [ ] **Step 1: Create help overlay view**

A translucent overlay showing available commands for the current mode. Organized in columns: motions, operators, marks/macros. Mode-specific — shows different content for Normal vs. Command vs. Search.

Triggered by Ctrl+F1 or `:help`. Dismisses on any keypress (consumed).

- [ ] **Step 2: Add to WorkspaceView as a fullscreen overlay**

- [ ] **Step 3: Commit**

```
git commit -m "feat(cw-sweep): add vim help overlay (Ctrl+F1)"
```

---

### Task 25: VimMacroRecorder

**Files:**
- Create: `CWSweep/CWSweep/Services/VimMode/VimMacroRecorder.swift`
- Create: `CWSweep/CWSweepTests/VimMode/VimMacroRecorderTests.swift`

- [ ] **Step 1: Write failing tests**

Test: start recording, keys are captured, stop recording, replay emits same keys.

- [ ] **Step 2: Implement VimMacroRecorder**

26 registers (a-z). `startRecording(register:)` captures all VimActions dispatched while recording. `stopRecording()` saves the sequence. `play(register:)` replays the sequence through VimEngine.

- [ ] **Step 3: Wire q/@ into VimEngine**

`q` state machine: not recording → wait for register letter → start recording. Recording → stop on bare `q`. `@` + letter → play macro.

- [ ] **Step 4: Run tests, build, commit**

```
git commit -m "feat(cw-sweep): add macro recording and playback (q/@)"
```

---

### Task 26: Settings Toggle and Persistence

**Files:**
- Modify: `CWSweep/CWSweep/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Add Vim Mode section to Settings**

Toggle: "Enable Vim Mode" backed by `@AppStorage("vimModeEnabled")`. Description text explaining what it does and linking to the help overlay.

- [ ] **Step 2: Wire AppStorage to VimEngine.isEnabled**

VimEngine reads from UserDefaults. When disabled, VimKeyInterceptor passes all events through unchanged.

- [ ] **Step 3: Commit**

```
git commit -m "feat(cw-sweep): add vim mode settings toggle"
```

---

## Phase 8: Deferred Features

These features are specified in the design doc but deferred to future iterations:

| Feature | Design Spec Section | Notes |
|---------|-------------------|-------|
| ESM (Enter Sends Message) | Contest-Style Rapid Logging | Context-aware Return in Entry mode for contests. Needs detailed QSO state machine design. |
| P2P/S2S inline syntax | Notes and Free-Text Logging | `P:K-5678` and `S:W4C/CM-001` in Entry mode. Requires QuickEntryParser changes in CarrierWaveCore. |
| Voice keyer commands | SSB Voice Keyer | `:voice 1`–`:voice 6`, `:voice record 1`. Requires audio recording/playback infrastructure. |
| Dupe checking indicators | DXCC and Need Status | Visual flagging of worked callsigns in spot list, DUPE warning in Entry mode. |
| `ga` jump to alert | Alerts | Jump to most recent alert spot. Requires alert storage and notification system. |
| Command history (Up/Down) | Command Mode key reference | Navigate previous commands with arrow keys in Command mode. |
| DXCC band/mode matrix in `?` lookup | DXCC and Need Status | Full band x mode grid showing Confirmed/Worked/Needed per entity. |
| Digital modes integration | Digital Modes (v2+) | WSJT-X UDP integration, modified operators for FT8. |
| SO2R (second radio) | Review Findings | Radio context switching for dual-radio operation. |
| Net frequency presets | Review Findings | `:net add` / `:net join` for casual operators. |
| Mark/macro persistence | — | Save marks and macros to UserDefaults so they survive app restarts. |

---

## Testing Strategy

- **Unit tests** for all parsers (VimFilterParser, VimCommandParser), state machines (VimEngine), and data structures (VimMarkStore, VimUndoStack, VimMacroRecorder).
- **Integration testing** is manual — keyboard interception, focus management, and radio control require a running app with connected hardware.
- **Each phase is independently shippable** — Phase 1-3 gives a usable basic vim mode. Phases 4-7 add power features incrementally.
