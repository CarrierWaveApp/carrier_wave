import Foundation

// MARK: - RawBytesAcceptanceStore

/// Persists per-spec-hash acceptance decisions for raw-bytes macros so
/// the safety gate can recognize an already-approved byte sequence on
/// subsequent runs. Keyed on `MacroSpecHash.canonical(spec)` so any
/// change to the transmitted bytes invalidates the acceptance.
///
/// The Updates tab invalidates the stored hash before applying a remote
/// update — guaranteeing the user re-confirms before raw-bytes go on
/// the air again.
public protocol RawBytesAcceptanceStore: Sendable {
    /// `true` if the user has previously approved this specific hash.
    func isAccepted(specId: UUID, hash: String) -> Bool
    /// Record approval for a specific hash. Keyed on (specId, hash) so an
    /// old hash for the same spec stays around as "previously approved"
    /// if the user reverts.
    func recordAcceptance(specId: UUID, hash: String)
    /// Discard the acceptance for a specific (specId, hash). Called by
    /// the Update review flow when applying a remote update whose new
    /// steps will produce a different hash; without this call the gate
    /// could mis-identify the new bytes as already-approved.
    func invalidate(specId: UUID, hash: String)
}

// MARK: - UserDefaultsRawBytesAcceptanceStore

public final class UserDefaultsRawBytesAcceptanceStore: RawBytesAcceptanceStore, @unchecked Sendable {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = .standard, key: String = "macros.rawBytes.acceptedHashes") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    public static let shared = UserDefaultsRawBytesAcceptanceStore()

    public func isAccepted(specId: UUID, hash: String) -> Bool {
        guard !hash.isEmpty else {
            return false
        }
        return loadMap()[mapKey(specId, hash)] ?? false
    }

    public func recordAcceptance(specId: UUID, hash: String) {
        guard !hash.isEmpty else {
            return
        }
        var map = loadMap()
        map[mapKey(specId, hash)] = true
        saveMap(map)
    }

    public func invalidate(specId: UUID, hash: String) {
        guard !hash.isEmpty else {
            return
        }
        var map = loadMap()
        map[mapKey(specId, hash)] = nil
        saveMap(map)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String

    private func mapKey(_ specId: UUID, _ hash: String) -> String {
        "\(specId.uuidString):\(hash)"
    }

    private func loadMap() -> [String: Bool] {
        defaults.dictionary(forKey: key) as? [String: Bool] ?? [:]
    }

    private func saveMap(_ map: [String: Bool]) {
        defaults.set(map, forKey: key)
    }
}
