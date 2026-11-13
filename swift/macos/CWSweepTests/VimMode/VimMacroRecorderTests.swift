import Testing
@testable import CWSweep

@MainActor
struct VimMacroRecorderTests {
    @Test func startAndStopRecording() {
        let recorder = VimMacroRecorder()
        #expect(!recorder.isRecording)
        #expect(recorder.activeRegister == nil)

        recorder.startRecording(register: "a")
        #expect(recorder.isRecording)
        #expect(recorder.activeRegister == "a")

        recorder.stopRecording()
        #expect(!recorder.isRecording)
        #expect(recorder.activeRegister == nil)
    }

    @Test func recordedKeysAreStored() {
        let recorder = VimMacroRecorder()
        recorder.startRecording(register: "b")
        recorder.recordKey("j")
        recorder.recordKey("k")
        recorder.recordKey("t")
        recorder.stopRecording()

        let keys = recorder.getMacro("b")
        #expect(keys == ["j", "k", "t"])
    }

    @Test func playbackReturnsKeys() {
        let recorder = VimMacroRecorder()
        recorder.startRecording(register: "c")
        recorder.recordKey("G")
        recorder.recordKey("g")
        recorder.recordKey("g")
        recorder.stopRecording()

        let keys = recorder.getMacro("c")
        #expect(keys?.count == 3)
        #expect(keys?[0] == "G")
        #expect(keys?[1] == "g")
        #expect(keys?[2] == "g")
    }

    @Test func differentRegistersAreIndependent() {
        let recorder = VimMacroRecorder()
        recorder.startRecording(register: "x")
        recorder.recordKey("j")
        recorder.stopRecording()

        recorder.startRecording(register: "y")
        recorder.recordKey("k")
        recorder.recordKey("k")
        recorder.stopRecording()

        #expect(recorder.getMacro("x") == ["j"])
        #expect(recorder.getMacro("y") == ["k", "k"])
    }

    @Test func onlyAToZAccepted() {
        let recorder = VimMacroRecorder()
        recorder.startRecording(register: "A")
        #expect(!recorder.isRecording)

        recorder.startRecording(register: "1")
        #expect(!recorder.isRecording)

        recorder.startRecording(register: "!")
        #expect(!recorder.isRecording)
    }

    @Test func getNonexistentMacroReturnsNil() {
        let recorder = VimMacroRecorder()
        #expect(recorder.getMacro("z") == nil)
    }

    @Test func recordKeyIgnoredWhenNotRecording() {
        let recorder = VimMacroRecorder()
        recorder.recordKey("j")
        recorder.startRecording(register: "a")
        recorder.stopRecording()
        #expect(recorder.getMacro("a")?.isEmpty == true)
    }

    @Test func overwriteExistingMacro() {
        let recorder = VimMacroRecorder()
        recorder.startRecording(register: "a")
        recorder.recordKey("j")
        recorder.stopRecording()

        recorder.startRecording(register: "a")
        recorder.recordKey("k")
        recorder.recordKey("k")
        recorder.stopRecording()

        #expect(recorder.getMacro("a") == ["k", "k"])
    }
}
