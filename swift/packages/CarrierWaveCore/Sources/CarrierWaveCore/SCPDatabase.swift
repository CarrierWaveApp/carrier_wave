import CarrierWaveCwFfi
import Foundation

// MARK: - SCPDatabase

/// In-memory Super Check Partial database for fast callsign matching.
///
/// A thin Swift facade over the Rust `ScpDatabase` (`cw_domain::scp`) — the
/// dedup/sort/partial/near-match logic lives in Rust and is shared with the
/// Android app. Parity is covered by `SCPDatabaseTests` (Swift) and
/// `scp::tests` (Rust).
public struct SCPDatabase: Sendable {
    // MARK: Lifecycle

    /// Initialize from a collection of callsigns. Deduplicates and uppercases.
    public init(callsigns: some Collection<String>) {
        rust = ScpDatabase(callsigns: Array(callsigns))
    }

    private init(rust: ScpDatabase) {
        self.rust = rust
    }

    // MARK: Public

    /// Number of callsigns in the database.
    public var count: Int {
        Int(rust.count())
    }

    /// Whether the database has no callsigns loaded.
    public var isEmpty: Bool {
        rust.isEmpty()
    }

    /// Classic SCP: all callsigns containing the fragment (case-insensitive).
    /// Returns up to `limit` matches, prefix matches first then substring.
    /// Fragments shorter than 3 characters return empty results.
    public func partialMatch(_ fragment: String, limit: Int = 20) -> [String] {
        rust.partialMatch(fragment: fragment, limit: UInt32(max(0, limit)))
    }

    /// Is this exact callsign in the database? (Case-insensitive)
    public func contains(_ callsign: String) -> Bool {
        rust.contains(callsign: callsign)
    }

    /// Create a new database by merging additional callsigns into this one.
    /// Used to augment MASTER.SCP with the user's repeat contacts.
    public func merging(additionalCallsigns: some Collection<String>) -> SCPDatabase {
        SCPDatabase(rust: rust.merging(additional: Array(additionalCallsigns)))
    }

    /// Near-misses within edit distance. Only useful for complete callsigns
    /// (4+ chars). Skips exact matches (distance == 0).
    public func nearMatches(
        for callsign: String,
        maxDistance: Int = 1
    ) -> [(callsign: String, distance: Int)] {
        rust.nearMatches(callsign: callsign, maxDistance: UInt32(max(0, maxDistance)))
            .map { (callsign: $0.callsign, distance: Int($0.distance)) }
    }

    // MARK: Private

    private let rust: ScpDatabase
}
