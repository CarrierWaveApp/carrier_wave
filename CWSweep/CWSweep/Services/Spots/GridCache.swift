import Foundation

// MARK: - GridCache

/// Shared cache for callsign grid lookups with time-based expiration
actor GridCache {
    // MARK: Internal

    static let shared = GridCache()

    /// Get a cached grid if it exists and hasn't expired
    func get(_ callsign: String) -> String?? {
        let key = callsign.uppercased()
        guard let entry = cache[key] else {
            return nil // Not in cache
        }
        if Date().timeIntervalSince(entry.timestamp) > expirationInterval {
            cache.removeValue(forKey: key)
            return nil // Expired
        }
        return entry.grid // Return cached value (may be nil if lookup found nothing)
    }

    /// Store a grid lookup result
    func set(_ callsign: String, grid: String?) {
        let key = callsign.uppercased()
        cache[key] = CacheEntry(grid: grid, timestamp: Date())

        if cache.count > 200 {
            pruneExpired()
        }
    }

    // MARK: Private

    private struct CacheEntry {
        let grid: String?
        let timestamp: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let expirationInterval: TimeInterval = 3_600

    private func pruneExpired() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.timestamp) <= expirationInterval }
    }
}

// MARK: - CallsignStateCache

/// Shared cache for callsign → US state lookups with time-based expiration
actor CallsignStateCache {
    // MARK: Internal

    static let shared = CallsignStateCache()

    /// Get a cached state if it exists and hasn't expired
    func get(_ callsign: String) -> String?? {
        let key = callsign.uppercased()
        guard let entry = cache[key] else {
            return nil
        }
        if Date().timeIntervalSince(entry.timestamp) > expirationInterval {
            cache.removeValue(forKey: key)
            return nil
        }
        return entry.state
    }

    /// Store a state lookup result
    func set(_ callsign: String, state: String?) {
        let key = callsign.uppercased()
        cache[key] = CacheEntry(state: state, timestamp: Date())

        if cache.count > 200 {
            pruneExpired()
        }
    }

    // MARK: Private

    private struct CacheEntry {
        let state: String?
        let timestamp: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let expirationInterval: TimeInterval = 3_600

    private func pruneExpired() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.timestamp) <= expirationInterval }
    }
}
