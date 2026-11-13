import Foundation

// MARK: - VimEngine Normal Mode

extension VimEngine {
    func handleNormalKey(_ key: String) {
        // Record key if macro is active (before any processing, but not 'q' that stops recording)
        if macroRecorder.isRecording, !(key == "q" && pendingKeys.isEmpty) {
            macroRecorder.recordKey(key)
        }

        // Mode transitions — always highest priority
        if handleModeTransition(key) {
            return
        }

        // Accumulate count prefix digits (but not when 'g' prefix is pending)
        if pendingKeys != "g", let firstChar = key.first, firstChar.isNumber {
            countBuffer += key
            return
        }

        // Start 'g' prefix sequence
        if key == "g", pendingKeys.isEmpty {
            pendingKeys = "g"
            startPendingKeyTimer()
            return
        }

        // Resolve 'g' + second key
        if pendingKeys == "g" {
            pendingKeyTimer?.cancel()
            pendingKeys = ""
            resolveGPrefix(key)
            countBuffer = ""
            return
        }

        dispatchMotionKey(key)
    }

    // MARK: Private helpers

    /// Returns true if the key caused a mode transition.
    private func handleModeTransition(_ key: String) -> Bool {
        switch key {
        case "i":
            if executor?.selectionState.focusedPane == .qsoLog {
                if executor?.selectionState.activatorEditMode == true {
                    // In activator log pane, i edits selected QSO in entry field
                    if let message = executor?.execute(.editQSO) {
                        echo(message)
                    }
                    mode = .entry
                } else {
                    // In other log panes, i opens inspector
                    if let message = executor?.execute(.openInspector) {
                        echo(message)
                    }
                }
            } else {
                // In spots pane, i enters Entry mode with spot pre-fill
                if let message = executor?.execute(.enterEntryMode) {
                    echo(message)
                }
                mode = .entry
            }
            return true
        case "I":
            // Enter Entry mode with blank field (no spot pre-fill)
            if let message = executor?.execute(.enterBlankEntry) {
                echo(message)
            }
            mode = .entry
            return true
        case ":":
            mode = .command
            return true
        case "/":
            mode = .search
            return true
        default:
            return false
        }
    }

    private func dispatchMotionKey(_ key: String) {
        let count = Int(countBuffer) ?? 1
        countBuffer = ""
        pendingKeys = ""
        pendingKeyTimer?.cancel()

        switch key {
        case "j": dispatchMotion(.down(count))
        case "k": dispatchMotion(.up(count))
        case "J": dispatchMotion(.bandDown)
        case "K": dispatchMotion(.bandUp)
        case "G": dispatchMotion(.bottom)
        case "n": dispatchMotion(.nextResult)
        case "N": dispatchMotion(.prevResult)
        default:
            // Not a recognised motion — treat as operator/pending sequence
            handleOperatorKey(key)
        }
    }

    func handleTab() {
        switch mode {
        case .normal:
            dispatchMotion(.cycleFocus)
        case .command:
            completeCommand()
        default:
            break
        }
    }

    private func resolveGPrefix(_ key: String) {
        if key == "g" {
            dispatchMotion(.top)
            return
        }
        // g1–g9: focus Nth pane in the current layout's panel order
        if let digit = Int(key), digit >= 1, digit <= 9 {
            dispatchMotion(.focusPaneByIndex(digit))
            return
        }
        // unknown g-sequence — silently ignore
    }
}
