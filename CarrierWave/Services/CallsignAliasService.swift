import Foundation

// MARK: - CallsignAliasService

/// Service to manage the user's current callsign and previous callsigns (aliases).
/// Used to properly match QSOs across services when the user has changed callsigns over time.
@MainActor
final class CallsignAliasService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = CallsignAliasService()

    /// Get the user's current callsign
    func getCurrentCallsign() -> String? {
        do {
            return try keychain.readString(for: KeychainHelper.Keys.currentCallsign)
        } catch {
            return nil
        }
    }

    /// Save the user's current callsign
    func saveCurrentCallsign(_ callsign: String) throws {
        let normalized = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else {
            throw CallsignAliasError.invalidCallsign
        }
        try keychain.save(normalized, for: KeychainHelper.Keys.currentCallsign)
    }

    /// Clear the current callsign
    func clearCurrentCallsign() throws {
        try keychain.delete(for: KeychainHelper.Keys.currentCallsign)
    }

    /// Get the list of previous callsigns
    func getPreviousCallsigns() -> [String] {
        do {
            let data = try keychain.read(for: KeychainHelper.Keys.previousCallsigns)
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            return []
        }
    }

    /// Save the list of previous callsigns
    func savePreviousCallsigns(_ callsigns: [String]) throws {
        let normalized =
            callsigns
                .map { $0.uppercased().trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        let data = try JSONEncoder().encode(normalized)
        try keychain.save(data, for: KeychainHelper.Keys.previousCallsigns)
    }

    /// Add a previous callsign to the list
    func addPreviousCallsign(_ callsign: String) throws {
        let normalized = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else {
            throw CallsignAliasError.invalidCallsign
        }

        var existing = getPreviousCallsigns()
        if !existing.contains(normalized) {
            existing.append(normalized)
            try savePreviousCallsigns(existing)
        }
    }

    /// Remove a previous callsign from the list
    func removePreviousCallsign(_ callsign: String) throws {
        let normalized = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        var existing = getPreviousCallsigns()
        existing.removeAll { $0 == normalized }
        try savePreviousCallsigns(existing)
    }

    /// Get all user callsigns (current + previous), uppercased
    func getAllUserCallsigns() -> Set<String> {
        var callsigns = Set<String>()
        if let current = getCurrentCallsign() {
            callsigns.insert(current)
        }
        for previous in getPreviousCallsigns() {
            callsigns.insert(previous)
        }
        return callsigns
    }

    /// Check if a given callsign belongs to the user
    /// Handles portable suffixes like /P, /M, /QRP by extracting the base callsign
    func isUserCallsign(_ callsign: String) -> Bool {
        let normalized = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        let userCallsigns = getAllUserCallsigns()

        // Direct match
        if userCallsigns.contains(normalized) {
            return true
        }

        // Check if base callsign (without suffix) matches any user callsign
        let baseCallsign = extractBaseCallsign(normalized)
        return userCallsigns.contains(baseCallsign)
    }

    /// Find callsigns in the given set that are not configured as user callsigns
    /// Handles portable suffixes like /P, /M, /QRP by extracting the base callsign
    /// Filters out invalid callsigns (must contain letters and numbers)
    func getUnconfiguredCallsigns(from allCallsigns: Set<String>) -> Set<String> {
        let userCallsigns = getAllUserCallsigns()
        let userBaseCallsigns = Set(userCallsigns.map { extractBaseCallsign($0) })

        return allCallsigns.filter { callsign in
            let upper = callsign.uppercased()

            // Filter out strings that aren't valid callsigns
            guard isValidCallsignFormat(upper) else {
                return false
            }

            // Check direct match
            if userCallsigns.contains(upper) {
                return false
            }
            // Check base callsign match
            let baseCallsign = extractBaseCallsign(upper)
            return !userBaseCallsigns.contains(baseCallsign)
        }
    }

    // MARK: Private

    private let keychain = KeychainHelper.shared

    /// Check if a string has valid callsign format (contains both letters and numbers)
    /// This filters out placeholder strings like "EVENT" that aren't real callsigns
    private func isValidCallsignFormat(_ callsign: String) -> Bool {
        // Extract base callsign (without /P, /M suffixes) for validation
        let base = extractBaseCallsign(callsign)

        // Must be at least 3 characters (shortest valid: A1A)
        guard base.count >= 3 else {
            return false
        }

        // Must contain at least one letter
        guard base.contains(where: \.isLetter) else {
            return false
        }

        // Must contain at least one number
        guard base.contains(where: \.isNumber) else {
            return false
        }

        return true
    }

    /// Extract the base callsign from a potentially prefixed/suffixed callsign
    /// e.g., "W6JSV/P" -> "W6JSV", "VE3/W6JSV" -> "W6JSV", "W6JSV/QRP" -> "W6JSV"
    private func extractBaseCallsign(_ callsign: String) -> String {
        let parts = callsign.split(separator: "/").map(String.init)

        guard parts.count > 1 else {
            return callsign
        }

        // Common suffixes that indicate the base callsign is before them
        let knownSuffixes = Set(["P", "M", "MM", "AM", "QRP", "R", "A", "B", "LH", "LGT"])

        // For 2 parts: check if second part is a known suffix or very short (1-2 chars)
        if parts.count == 2 {
            let first = parts[0]
            let second = parts[1]

            // If second is a known suffix, first is the base
            if knownSuffixes.contains(second.uppercased()) {
                return first
            }

            // If second is very short (1-2 chars), it's likely a suffix
            if second.count <= 2 {
                return first
            }

            // If first is very short (1-2 chars), it's likely a country prefix
            if first.count <= 2 {
                return second
            }

            // Otherwise, return the longer one (more likely to be the full callsign)
            return first.count >= second.count ? first : second
        }

        // For 3 parts (prefix/call/suffix): middle is the base
        if parts.count == 3 {
            return parts[1]
        }

        // Fallback: return the longest part
        return parts.max(by: { $0.count < $1.count }) ?? callsign
    }
}

// MARK: - CallsignAliasError

enum CallsignAliasError: LocalizedError {
    case invalidCallsign

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidCallsign:
            "Invalid callsign"
        }
    }
}
