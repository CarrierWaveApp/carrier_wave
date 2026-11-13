// CTY.dat Parser
//
// Parses the AD1C CTY.dat country file format into a lookup table mapping
// callsign prefixes to DXCC entities with zone and continent metadata.
// See: https://www.country-files.com/cty-dat-format/
//
// Thin Swift facade over the Rust core (`cw_domain::cty`) — the parse,
// alias-stripping, and longest-prefix / portable lookup logic lives in Rust
// (held as the `CtyDatabase` FFI object) and is shared with the Android app.
// Parity is covered by `CTYParserTests` (Swift) and `cty::tests` (Rust).

import CarrierWaveCwFfi
import Foundation

// MARK: - DXCCEntity

/// A DXCC entity from CTY.dat with zone and location metadata.
public struct DXCCEntity: Sendable, Equatable, Hashable {
    // MARK: Lifecycle

    public init(
        name: String,
        cqZone: Int,
        ituZone: Int,
        continent: String,
        latitude: Double,
        longitude: Double,
        timeOffset: Double,
        primaryPrefix: String
    ) {
        self.name = name
        self.cqZone = cqZone
        self.ituZone = ituZone
        self.continent = continent
        self.latitude = latitude
        self.longitude = longitude
        self.timeOffset = timeOffset
        self.primaryPrefix = primaryPrefix
    }

    /// Build from the Rust-decoded FFI record.
    init(ffi: FfiDxccEntity) {
        self.init(
            name: ffi.name,
            cqZone: Int(ffi.cqZone),
            ituZone: Int(ffi.ituZone),
            continent: ffi.continent,
            latitude: ffi.latitude,
            longitude: ffi.longitude,
            timeOffset: ffi.timeOffset,
            primaryPrefix: ffi.primaryPrefix
        )
    }

    // MARK: Public

    public let name: String
    public let cqZone: Int
    public let ituZone: Int
    public let continent: String
    public let latitude: Double
    public let longitude: Double
    public let timeOffset: Double
    public let primaryPrefix: String
}

// MARK: - CTYParser

/// Parses CTY.dat format into a prefix-to-entity lookup table.
public enum CTYParser {
    /// Parse CTY.dat content into a `CTYDatabase` backed by the Rust core.
    public static func parse(_ content: String) -> CTYDatabase {
        CTYDatabase(rust: CtyDatabase.parse(content: content))
    }
}

// MARK: - CTYDatabase

/// In-memory DXCC entity lookup database built from CTY.dat.
///
/// Backed by the Rust `CtyDatabase` FFI object so the parsed table lives once
/// in Rust and is shared with the Android app.
public struct CTYDatabase: Sendable {
    // MARK: Lifecycle

    init(rust: CtyDatabase) {
        self.rust = rust
        entities = rust.entities().map(DXCCEntity.init(ffi:))
    }

    // MARK: Public

    /// All parsed entities, in source order.
    public let entities: [DXCCEntity]

    /// The full prefix → entity map (every alias prefix, uppercased keys).
    public var prefixMap: [String: DXCCEntity] {
        rust.prefixMap().mapValues(DXCCEntity.init(ffi:))
    }

    /// Look up the DXCC entity for a callsign using longest-prefix matching.
    /// Handles portable indicators (e.g., W1ABC/VP9 → VP9, VP9/W1ABC → VP9).
    public func lookup(_ callsign: String) -> DXCCEntity? {
        rust.lookup(callsign: callsign).map(DXCCEntity.init(ffi:))
    }

    // MARK: Private

    private let rust: CtyDatabase
}
