import Foundation

// MARK: - VimEngine Mark Commands

extension VimEngine {
    /// Returns true if the key was consumed as part of a pending mark sequence.
    func resolvePendingMarkKey(_ key: String) -> Bool {
        guard let ch = key.first, key.count == 1 else {
            return false
        }

        if pendingKeys == "q" {
            pendingKeyTimer?.cancel()
            pendingKeys = ""
            if ch >= "a", ch <= "z" {
                macroRecorder.startRecording(register: ch)
                isRecordingMacro = true
                recordingRegister = ch
                echo("Recording @\(ch)")
            }
            return true
        }

        if pendingKeys == "@" {
            pendingKeyTimer?.cancel()
            pendingKeys = ""
            if ch >= "a", ch <= "z" {
                if let keys = macroRecorder.getMacro(ch) {
                    for macroKey in keys {
                        handleKey(macroKey)
                    }
                    echo("Played @\(ch)")
                } else {
                    echo("No macro @\(ch)")
                }
            }
            return true
        }

        if pendingKeys == "m" {
            pendingKeyTimer?.cancel()
            pendingKeys = ""
            setMark(ch)
            return true
        }

        if pendingKeys == "'" {
            pendingKeyTimer?.cancel()
            pendingKeys = ""
            if ch == "'" {
                jumpToPreviousMark()
            } else {
                jumpToMark(ch)
            }
            return true
        }

        return false
    }

    // MARK: Private

    private func setMark(_ register: Character) {
        guard register >= "a", register <= "z" else {
            echo("Invalid mark register '\(register)'")
            return
        }
        let freq = executor?.radioManager.frequency ?? 0
        let mode = executor?.radioManager.mode ?? ""
        markStore.set(register, frequency: freq, mode: mode)
        echo("Mark '\(register)' set")
    }

    private func jumpToPreviousMark() {
        guard let prev = markStore.previousFrequency else {
            echo("No previous mark")
            return
        }
        savePreviousAndTune(to: prev)
        echo("Jump back")
    }

    private func jumpToMark(_ register: Character) {
        guard let mark = markStore.get(register) else {
            echo("No mark '\(register)'")
            return
        }
        savePreviousAndTune(to: mark)
        echo("Mark '\(register)'")
    }

    private func savePreviousAndTune(to mark: FrequencyMark) {
        let currentFreq = executor?.radioManager.frequency ?? 0
        let currentMode = executor?.radioManager.mode ?? ""
        markStore.updatePrevious(frequency: currentFreq, mode: currentMode)
        let radioManager = executor?.radioManager
        Task {
            await radioManager?.tuneToSpot(
                frequencyMHz: mark.frequencyMHz,
                mode: mark.mode,
                autoXITEnabled: false,
                autoXITOffsetHz: 0
            )
        }
    }
}
