import CarrierWaveCore
import XCTest
@testable import CarrierWaveData

final class CwStoreProviderTests: XCTestCase {
    func testInMemoryProviderOpensAndReuses() async throws {
        let provider = CwStoreProvider(opener: { try FieldStore.openInMemory(key: "test") })
        let first = try await provider.store()
        let second = try await provider.store()
        XCTAssertTrue(first === second, "provider must reuse one FieldStore instance")
        XCTAssertEqual(try first.qsoCount(), 0)
    }
}
