import Foundation

// MARK: - RadioMacroCapabilities

/// Declared capability set for a `RadioMacroSpec`. The verifier checks
/// that the declared set dominates the set inferred from steps + opcode
/// tables; mismatches surface as errors during `MacroVerifier.verify`.
public struct RadioMacroCapabilities: Codable, Sendable, Hashable {
    // MARK: Lifecycle

    public init(
        transmits: Bool = false,
        changesFrequency: Bool = false,
        changesMode: Bool = false,
        changesPower: Bool = false,
        usesRawBytes: Bool = false,
        regions: [String]? = nil
    ) {
        self.transmits = transmits
        self.changesFrequency = changesFrequency
        self.changesMode = changesMode
        self.changesPower = changesPower
        self.usesRawBytes = usesRawBytes
        self.regions = regions
    }

    // MARK: Public

    public var transmits: Bool
    public var changesFrequency: Bool
    public var changesMode: Bool
    public var changesPower: Bool
    public var usesRawBytes: Bool
    public var regions: [String]?

    /// Bitwise OR (used when combining inferred and declared sets).
    public func union(_ other: RadioMacroCapabilities) -> RadioMacroCapabilities {
        RadioMacroCapabilities(
            transmits: transmits || other.transmits,
            changesFrequency: changesFrequency || other.changesFrequency,
            changesMode: changesMode || other.changesMode,
            changesPower: changesPower || other.changesPower,
            usesRawBytes: usesRawBytes || other.usesRawBytes,
            regions: Self.unionRegions(regions, other.regions)
        )
    }

    /// Returns true if every bit set in `other` is also set in self.
    public func dominates(_ other: RadioMacroCapabilities) -> Bool {
        (!other.transmits || transmits) &&
            (!other.changesFrequency || changesFrequency) &&
            (!other.changesMode || changesMode) &&
            (!other.changesPower || changesPower) &&
            (!other.usesRawBytes || usesRawBytes)
    }

    // MARK: Private

    private static func unionRegions(_ lhs: [String]?, _ rhs: [String]?) -> [String]? {
        switch (lhs, rhs) {
        case (nil, nil): nil
        case let (lhs?, nil): lhs
        case let (nil, rhs?): rhs
        case let (lhs?, rhs?): Array(Set(lhs).union(rhs)).sorted()
        }
    }
}
