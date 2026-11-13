import SwiftUI

// MARK: - VimMode

enum VimMode: String {
    case normal = "NORMAL"
    case entry = "ENTRY"
    case command = "COMMAND"
    case search = "SEARCH"
}

// MARK: - VimEngine

@MainActor @Observable
final class VimEngine {
    var mode: VimMode = .normal
    var pendingKeys: String = ""
    var lastCommandEcho: String = ""
    var isEnabled: Bool = false
    var isPaletteActive: Bool = false
    var commandLineText: String = ""
    var searchText: String = ""
    var isRecordingMacro: Bool = false
    var recordingRegister: Character?
    var shouldLogEntry: Bool = false
    var shouldShowHelp: Bool = false

    var pendingKeyTimer: Task<Void, Never>?
    var countBuffer: String = ""
    var executor: VimActionExecutor?
    var markStore = VimMarkStore()
    var undoStack = VimUndoStack()
    var macroRecorder = VimMacroRecorder()
    var lastAction: VimAction?

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
            break
        }
    }

    func handleKey(_ key: String) {
        guard isEnabled else {
            return
        }
        switch mode {
        case .normal:
            handleNormalKey(key)
        case .entry,
             .command,
             .search:
            break
        }
    }

    func echo(_ message: String) {
        lastCommandEcho = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.0))
            if self.lastCommandEcho == message {
                self.lastCommandEcho = ""
            }
        }
    }

    func dispatchMotion(_ motion: VimMotion) {
        if let message = executor?.execute(.moveSelection(motion)) {
            echo(message)
        }
    }

    func handleOperatorKey(_ key: String) {
        // Resolve pending mark sequences before dispatching new operator keys
        if resolvePendingMarkKey(key) {
            return
        }

        switch key {
        case ".":
            handleDotRepeat()
        case "t":
            handleTuneOperator()
        case "+":
            handleWPMAdjust(direction: .up)
        case "-":
            handleWPMAdjust(direction: .down)
        case "u":
            handleUndoOperator()
        case "q":
            handleMacroToggle()
        case "x",
             "o",
             "s",
             "?":
            dispatchSimpleOperator(key)
        case "@",
             "m",
             "'":
            pendingKeys = String(key)
            startPendingKeyTimer()
        default:
            pendingKeys += key
            startPendingKeyTimer()
        }
    }

    func startPendingKeyTimer() {
        pendingKeyTimer?.cancel()
        pendingKeyTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            guard !Task.isCancelled else {
                return
            }
            self.pendingKeys = ""
            self.countBuffer = ""
        }
    }

    func handleControlC() {
        Task { await executor?.winKeyer.cancelSending() }
        echo("CW aborted")
    }

    func handleEntryReturn() {
        shouldLogEntry = true
        mode = .normal
    }

    func handleLineReturn() {
        switch mode {
        case .command:
            let command = VimCommandParser.parse(commandLineText)
            if command == .help {
                shouldShowHelp = true
                commandLineText = ""
                mode = .normal
                return
            }
            if let message = executor?.execute(.executeCommand(command)) {
                echo(message)
            }
            commandLineText = ""
            mode = .normal
        case .search:
            mode = .normal
        default:
            break
        }
    }

    func handleFKey(_ number: Int) {
        guard mode == .normal || mode == .entry else {
            return
        }
        let defaultTexts = [
            1: "CQ CQ CQ",
            2: "5NN",
            3: "TU",
            4: "DE",
            5: "",
            6: "AGN",
        ]
        if let text = defaultTexts[number], !text.isEmpty {
            Task { await executor?.winKeyer.sendText(text) }
            echo("F\(number)")
        }
    }
}

// MARK: - Operator helpers

extension VimEngine {
    private func handleTuneOperator() {
        pendingKeys = ""
        pendingKeyTimer?.cancel()
        if let radio = executor?.radioManager, radio.frequency > 0 {
            undoStack.push(.tunedFrom(frequencyMHz: radio.frequency, mode: radio.mode))
        }
        lastAction = .tune
        if let message = executor?.execute(.tune) {
            echo(message)
        }
    }

    enum WPMDirection { case up, down }

    private func handleWPMAdjust(direction: WPMDirection) {
        // Split TX offset adjustment is not yet implemented; always adjusts WPM.
        pendingKeys = ""
        pendingKeyTimer?.cancel()
        let count = Int(countBuffer) ?? 1
        countBuffer = ""
        let delta = 2 * count
        Task {
            let current = Int(self.executor?.winKeyer.speed ?? 25)
            let newSpeed: Int = switch direction {
            case .up: min(60, current + delta)
            case .down: max(5, current - delta)
            }
            await self.executor?.winKeyer.setSpeed(UInt8(newSpeed))
            self.echo("WPM: \(newSpeed)")
        }
    }

    private func handleDotRepeat() {
        pendingKeys = ""
        pendingKeyTimer?.cancel()
        if let action = lastAction, let message = executor?.execute(action) {
            echo(message)
        } else {
            echo("No action to repeat")
        }
    }

    private func handleMacroToggle() {
        if macroRecorder.isRecording {
            macroRecorder.stopRecording()
            isRecordingMacro = false
            recordingRegister = nil
            echo("Recorded")
            pendingKeys = ""
        } else {
            pendingKeys = "q"
            startPendingKeyTimer()
        }
    }

    private func dispatchSimpleOperator(_ key: String) {
        pendingKeys = ""
        pendingKeyTimer?.cancel()
        let action: VimAction? = switch key {
        case "x": .dismiss
        case "o": .openInspector
        case "s": .spot
        case "?": .lookup
        default: nil
        }
        guard let action else {
            return
        }
        if let message = executor?.execute(action) {
            echo(message)
        }
    }

    private func handleUndoOperator() {
        pendingKeys = ""
        pendingKeyTimer?.cancel()
        if let entry = undoStack.pop() {
            switch entry {
            case let .tunedFrom(freq, undoMode):
                Task {
                    await executor?.radioManager.tuneToSpot(
                        frequencyMHz: freq,
                        mode: undoMode,
                        autoXITEnabled: false,
                        autoXITOffsetHz: 0
                    )
                }
                echo("Undo tune")
            case .dismissed:
                echo("Undo dismiss")
            }
        } else {
            echo("Nothing to undo")
        }
    }
}
