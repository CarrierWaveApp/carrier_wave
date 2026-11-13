import Testing
@testable import CWSweep

@MainActor
struct VimUndoStackTests {
    @Test func emptyStackCannotUndo() {
        let stack = VimUndoStack()
        #expect(!stack.canUndo)
    }

    @Test func emptyPopReturnsNil() {
        let stack = VimUndoStack()
        let result = stack.pop()
        #expect(result == nil as VimUndoEntry?)
    }

    @Test func pushMakesUndoAvailable() {
        let stack = VimUndoStack()
        stack.push(.tunedFrom(frequencyMHz: 14.225, mode: "USB"))
        #expect(stack.canUndo)
    }

    @Test func lifoOrder() {
        let stack = VimUndoStack()
        stack.push(.tunedFrom(frequencyMHz: 14.225, mode: "USB"))
        stack.push(.tunedFrom(frequencyMHz: 7.074, mode: "FT8"))
        if case let .tunedFrom(freq, mode) = stack.pop() {
            #expect(freq == 7.074)
            #expect(mode == "FT8")
        } else {
            Issue.record("Expected tunedFrom entry")
        }
        if case let .tunedFrom(freq, _) = stack.pop() {
            #expect(freq == 14.225)
        } else {
            Issue.record("Expected tunedFrom entry")
        }
        #expect(!stack.canUndo)
    }

    @Test func maxEntriesLimit() {
        let stack = VimUndoStack()
        for index in 0 ..< 60 {
            stack.push(.tunedFrom(frequencyMHz: Double(index), mode: "USB"))
        }
        // Stack should hold at most 50 entries; oldest should have been dropped
        var count = 0
        var lastFreq: Double?
        while stack.canUndo {
            if case let .tunedFrom(freq, _) = stack.pop() {
                lastFreq = freq
            }
            count += 1
        }
        #expect(count == 50)
        // Oldest remaining entry should be index 10 (pushed after first 10 were dropped)
        #expect(lastFreq == 10.0)
    }

    @Test func clearEmptiesStack() {
        let stack = VimUndoStack()
        stack.push(.tunedFrom(frequencyMHz: 14.225, mode: "USB"))
        stack.push(.dismissed(spotID: "abc123"))
        stack.clear()
        #expect(!stack.canUndo)
        #expect(stack.pop() == nil)
    }

    @Test func dismissedEntryRoundtrips() {
        let stack = VimUndoStack()
        stack.push(.dismissed(spotID: "W1AW-14"))
        if case let .dismissed(spotID) = stack.pop() {
            #expect(spotID == "W1AW-14")
        } else {
            Issue.record("Expected dismissed entry")
        }
    }
}
