import Testing
@testable import CWSweep

@MainActor
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
        // Should produce moveSelection(.down(3)) — verified in later tasks
    }

    @Test func gPrefixForPaneFocus() {
        let engine = VimEngine()
        engine.isEnabled = true
        engine.handleKey("g")
        engine.handleKey("1")
        // Should produce focusPane(.spots), not count 1 — verified in later tasks
    }

    @Test func ggJumpsToTop() {
        let engine = VimEngine()
        engine.isEnabled = true
        engine.handleKey("g")
        engine.handleKey("g")
        // Should produce moveSelection(.top) — verified in later tasks
    }

    @Test func pendingKeyBufferShowsPartialInput() {
        let engine = VimEngine()
        engine.isEnabled = true
        engine.handleKey("m")
        #expect(engine.pendingKeys == "m")
        #expect(engine.mode == .normal)
    }

    @Test func pendingKeyTimeoutClears() async {
        let engine = VimEngine()
        engine.isEnabled = true
        engine.handleKey("m")
        #expect(engine.pendingKeys == "m")
        try? await Task.sleep(for: .seconds(1.1))
        #expect(engine.pendingKeys.isEmpty)
    }
}
