import Foundation

@MainActor
final class VimMacroRecorder {
    // MARK: Internal

    private(set) var isRecording = false
    private(set) var activeRegister: Character?

    func startRecording(register: Character) {
        guard register >= "a", register <= "z" else {
            return
        }
        isRecording = true
        activeRegister = register
        currentRecording = []
    }

    func stopRecording() {
        guard isRecording, let register = activeRegister else {
            return
        }
        macros[register] = currentRecording
        isRecording = false
        activeRegister = nil
        currentRecording = []
    }

    func recordKey(_ key: String) {
        guard isRecording else {
            return
        }
        currentRecording.append(key)
    }

    func getMacro(_ register: Character) -> [String]? {
        macros[register]
    }

    // MARK: Private

    private var macros: [Character: [String]] = [:]
    private var currentRecording: [String] = []
}
