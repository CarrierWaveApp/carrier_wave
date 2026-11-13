import Testing
@testable import CWSweep

@MainActor
struct VimMarkStoreTests {
    @Test func setAndGetMark() {
        let store = VimMarkStore()
        store.set("a", frequency: 14.225, mode: "USB")
        let mark = store.get("a")
        #expect(mark == FrequencyMark(frequencyMHz: 14.225, mode: "USB"))
    }

    @Test func getNonexistentMarkReturnsNil() {
        let store = VimMarkStore()
        #expect(store.get("z") == nil)
    }

    @Test func previousFrequencyTracking() {
        let store = VimMarkStore()
        #expect(store.previousFrequency == nil)
        store.updatePrevious(frequency: 7.074, mode: "FT8")
        #expect(store.previousFrequency == FrequencyMark(frequencyMHz: 7.074, mode: "FT8"))
        store.updatePrevious(frequency: 14.074, mode: "FT8")
        #expect(store.previousFrequency == FrequencyMark(frequencyMHz: 14.074, mode: "FT8"))
    }

    @Test func onlyAToZAccepted() {
        let store = VimMarkStore()
        store.set("A", frequency: 14.225, mode: "USB")
        store.set("1", frequency: 14.225, mode: "USB")
        store.set("!", frequency: 14.225, mode: "USB")
        #expect(store.get("A") == nil)
        #expect(store.get("1") == nil)
        #expect(store.get("!") == nil)
    }

    @Test func allLowercaseLettersAccepted() {
        let store = VimMarkStore()
        store.set("a", frequency: 1.0, mode: "AM")
        store.set("z", frequency: 2.0, mode: "FM")
        #expect(store.get("a") != nil)
        #expect(store.get("z") != nil)
    }

    @Test func overwriteExistingMark() {
        let store = VimMarkStore()
        store.set("b", frequency: 7.0, mode: "CW")
        store.set("b", frequency: 14.0, mode: "USB")
        #expect(store.get("b") == FrequencyMark(frequencyMHz: 14.0, mode: "USB"))
    }
}
