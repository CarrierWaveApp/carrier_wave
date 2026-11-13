import Foundation

// MARK: - StoreCountParity

/// Compares a SwiftData (authoritative) row count against the Rust mirror's count
/// for a single entity. The per-entity read cutover starts by proving this
/// total-count invariant before richer field/order parity (the pattern QSO
/// established). Generic so each entity's read source reuses one comparison type.
public struct StoreCountParity: Sendable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public struct Result: Sendable, Equatable {
        // MARK: Lifecycle

        public init(entity: String, swiftData: Int, rust: Int) {
            self.entity = entity
            self.swiftData = swiftData
            self.rust = rust
        }

        // MARK: Public

        public let entity: String
        public let swiftData: Int
        public let rust: Int

        public var matches: Bool {
            swiftData == rust
        }
    }

    public func compare(entity: String, swiftData: Int, rust: Int) -> Result {
        Result(entity: entity, swiftData: swiftData, rust: rust)
    }
}
