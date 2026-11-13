import CarrierWaveData
import Foundation
import Testing

@Suite(.serialized)
struct RawBytesAcceptanceStoreTests {
    // MARK: Internal

    @Test func recordedHashesArePersistedAndRecognized() {
        let store = makeStore()
        let id = UUID()
        #expect(store.isAccepted(specId: id, hash: "abc") == false)
        store.recordAcceptance(specId: id, hash: "abc")
        #expect(store.isAccepted(specId: id, hash: "abc") == true)
    }

    @Test func invalidateOnlyClearsTheMatchingHash() {
        let store = makeStore()
        let id = UUID()
        store.recordAcceptance(specId: id, hash: "old")
        store.recordAcceptance(specId: id, hash: "new")
        store.invalidate(specId: id, hash: "old")
        #expect(store.isAccepted(specId: id, hash: "old") == false)
        #expect(store.isAccepted(specId: id, hash: "new") == true)
    }

    @Test func emptyHashIsNeverAccepted() {
        let store = makeStore()
        let id = UUID()
        store.recordAcceptance(specId: id, hash: "")
        #expect(store.isAccepted(specId: id, hash: "") == false)
    }

    // MARK: Private

    private func makeStore() -> UserDefaultsRawBytesAcceptanceStore {
        // Per-test suite name keeps state isolated and survives clean tests.
        let defaults = UserDefaults(suiteName: "RawBytesAcceptanceStoreTests.\(UUID().uuidString)")!
        return UserDefaultsRawBytesAcceptanceStore(defaults: defaults)
    }
}
