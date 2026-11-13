import SwiftData
import XCTest
@testable import CarrierWave

final class AppSchemaTests: XCTestCase {
    /// A model listed twice in the container schema makes SwiftData register two
    /// dynamic subclasses for the same `@Model`; a later fetch crashes with
    /// "Failed to cast model X to X". Guard the schema against that.
    func testNoDuplicateModelTypes() {
        let ids = AppSchema.models.map { ObjectIdentifier($0) }
        let duplicates = Dictionary(grouping: ids, by: { $0 })
            .filter { $0.value.count > 1 }
        let names = AppSchema.models
            .filter { duplicates[ObjectIdentifier($0)] != nil }
            .map { String(reflecting: $0) }
        XCTAssertEqual(
            ids.count, Set(ids).count,
            "Duplicate model types in AppSchema.models: \(Set(names))"
        )
    }
}
