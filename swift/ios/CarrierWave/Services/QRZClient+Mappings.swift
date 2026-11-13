import CarrierWaveData
import Foundation

// MARK: - QRZLogbookCallsignMismatch

/// The operator's current callsign has no connected QRZ logbook API key, so
/// QSOs logged under it are not uploaded to QRZ. Surfaced as a notice in the
/// QRZ settings and on the Logbook Services row.
struct QRZLogbookCallsignMismatch: Equatable {
    /// The callsign the operator is currently logging under.
    let currentCallsign: String
    /// The callsign the primary (or, failing that, first) QRZ key belongs to.
    let logbookCallsign: String
}

// MARK: - QRZClient Callsign Mapping Management

extension QRZClient {
    /// Get all callsign-to-API-key mappings, auto-migrating from legacy single-key storage.
    func getCallsignMappings() -> [QRZCallsignMapping] {
        if let data = try? keychain.read(for: KeychainHelper.Keys.qrzCallsignMappings),
           let mappings = try? JSONDecoder().decode([QRZCallsignMapping].self, from: data),
           !mappings.isEmpty
        {
            return mappings
        }

        // Auto-migrate from legacy single-key storage
        guard let legacyKey = try? keychain.readString(for: KeychainHelper.Keys.qrzApiKey),
              let legacyCallsign = getCallsign()
        else {
            return []
        }

        let bookId = getBookId(for: legacyCallsign)
        let mapping = QRZCallsignMapping(
            callsign: legacyCallsign.uppercased(),
            apiKey: legacyKey,
            bookId: bookId,
            isPrimary: true
        )
        try? saveCallsignMappings([mapping])
        return [mapping]
    }

    /// Save the full list of callsign mappings.
    func saveCallsignMappings(_ mappings: [QRZCallsignMapping]) throws {
        let data = try JSONEncoder().encode(mappings)
        try keychain.save(data, for: KeychainHelper.Keys.qrzCallsignMappings)

        // Keep legacy keys in sync for CW Sweep / widget compat
        if let primary = mappings.first(where: \.isPrimary) {
            try keychain.save(primary.apiKey, for: KeychainHelper.Keys.qrzApiKey)
            try keychain.save(primary.callsign, for: KeychainHelper.Keys.qrzCallsign)
            if let bookId = primary.bookId {
                try saveBookId(bookId, for: primary.callsign)
            }
        } else {
            // No primary left: clear legacy keys, otherwise getCallsignMappings()
            // auto-migrates them back and a removed key reappears
            try? keychain.delete(for: KeychainHelper.Keys.qrzApiKey)
            try? keychain.delete(for: KeychainHelper.Keys.qrzCallsign)
        }
    }

    /// Add or update a mapping for a callsign. Rejects duplicate API keys.
    func addCallsignMapping(_ mapping: QRZCallsignMapping) throws {
        var existing = getCallsignMappings()

        // Reject if this API key is already used by another callsign
        if let conflict = existing.first(where: {
            $0.apiKey == mapping.apiKey && $0.callsign != mapping.callsign
        }) {
            throw QRZError.invalidApiKey(
                "This API key is already associated with \(conflict.callsign)"
            )
        }

        // Replace existing mapping for this callsign, or append
        if let idx = existing.firstIndex(where: { $0.callsign == mapping.callsign }) {
            existing[idx] = mapping
        } else {
            existing.append(mapping)
        }

        try saveCallsignMappings(existing)
    }

    /// Remove the mapping for a callsign. If the primary is removed, the first
    /// remaining mapping is promoted so QRZ sync (and the legacy keys CW Sweep
    /// and the widgets read) never end up with accounts but no primary.
    func removeCallsignMapping(for callsign: String) throws {
        var existing = getCallsignMappings()
        existing.removeAll { $0.callsign == callsign.uppercased() }
        if !existing.isEmpty, !existing.contains(where: \.isPrimary) {
            existing[0].isPrimary = true
        }
        try saveCallsignMappings(existing)

        var bookIds = getBookIdMap()
        if bookIds.removeValue(forKey: callsign.uppercased()) != nil {
            try saveBookIdMap(bookIds)
        }
    }

    /// Look up the API key for a specific callsign.
    func getApiKey(for callsign: String) -> String? {
        getCallsignMappings().first { $0.callsign == callsign.uppercased() }?.apiKey
    }

    /// Get the primary callsign mapping (the current QRZ account).
    func getPrimaryMapping() -> QRZCallsignMapping? {
        getCallsignMappings().first(where: \.isPrimary)
    }

    /// Make `callsign` the primary mapping, demoting the current primary.
    /// `saveCallsignMappings` re-syncs the legacy single-key Keychain entries,
    /// and the next QRZ sync propagates the callsign to the user profile via
    /// `syncCallsignFromQRZ` — the same semantics as adding this key first.
    func setPrimaryMapping(for callsign: String) throws {
        let upper = callsign.uppercased()
        var mappings = getCallsignMappings()
        guard mappings.contains(where: { $0.callsign == upper }) else {
            return
        }
        for idx in mappings.indices {
            mappings[idx].isPrimary = mappings[idx].callsign == upper
        }
        try saveCallsignMappings(mappings)
    }

    /// Validate an API key and build a mapping from the QRZ STATUS response.
    func validateAndCreateMapping(
        _ apiKey: String, isPrimary: Bool = false
    ) async throws -> QRZCallsignMapping {
        let status = try await validateApiKey(apiKey)
        return QRZCallsignMapping(
            callsign: status.callsign.uppercased(),
            apiKey: apiKey,
            bookId: status.bookId,
            isPrimary: isPrimary
        )
    }

    /// Update the primary mapping's callsign when QRZ detects a change.
    func updatePrimaryCallsign(
        _ newCallsign: String, bookId: String?
    ) throws {
        var mappings = getCallsignMappings()
        guard let idx = mappings.firstIndex(where: \.isPrimary) else {
            return
        }
        mappings[idx] = QRZCallsignMapping(
            callsign: newCallsign.uppercased(),
            apiKey: mappings[idx].apiKey,
            bookId: bookId ?? mappings[idx].bookId,
            isPrimary: true
        )
        try saveCallsignMappings(mappings)
    }

    /// Find the mapping that matches a QSO's myCallsign (handles portable suffixes).
    func findMapping(for myCallsign: String) -> QRZCallsignMapping? {
        Self.mapping(for: myCallsign, in: getCallsignMappings())
    }

    /// Find the mapping in `mappings` for a callsign: direct match first, then
    /// the base callsign (strips /P, /M, etc.).
    nonisolated static func mapping(
        for myCallsign: String, in mappings: [QRZCallsignMapping]
    ) -> QRZCallsignMapping? {
        let upper = myCallsign.uppercased()

        if let direct = mappings.first(where: { $0.callsign == upper }) {
            return direct
        }

        let base = CallsignAliasService.extractBaseCallsign(upper)
        return mappings.first { $0.callsign == base }
    }

    /// The operator's current callsign has no connected QRZ logbook key.
    /// Nil when there is no current callsign, no QRZ keys at all, or a key
    /// (direct or base-callsign match) already covers the current callsign.
    func logbookMismatch() -> QRZLogbookCallsignMismatch? {
        Self.logbookMismatch(
            currentCallsign: CallsignAliasService.shared.getCurrentCallsign(),
            mappings: getCallsignMappings()
        )
    }

    /// Pure form of `logbookMismatch()` for the given callsign and mappings.
    nonisolated static func logbookMismatch(
        currentCallsign: String?, mappings: [QRZCallsignMapping]
    ) -> QRZLogbookCallsignMismatch? {
        guard let current = currentCallsign?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
            !current.isEmpty,
            !mappings.isEmpty,
            case .none = mapping(for: current, in: mappings)
        else {
            return nil
        }
        let logbook = mappings.first(where: \.isPrimary) ?? mappings[0]
        return QRZLogbookCallsignMismatch(
            currentCallsign: current,
            logbookCallsign: logbook.callsign
        )
    }

    /// Clear all callsign mappings (used during logout).
    func clearCallsignMappings() {
        try? keychain.delete(for: KeychainHelper.Keys.qrzCallsignMappings)
    }
}
