import Foundation
import SwiftData

// MARK: - CallsignContactCache

/// Background cache of how many times each callsign has been contacted.
/// Pre-computed at session start for O(1) lookups during logging.
actor CallsignContactCache {
    // MARK: Internal

    /// Pre-computed contact counts: [normalized_callsign: count]
    private var counts: [String: Int] = [:]

    /// Whether the cache has been loaded
    private var isLoaded = false

    /// Modes that represent activation metadata, not actual QSOs
    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    /// Build the cache from all visible QSOs.
    /// Must be called from a background context (not main thread).
    func load(container: ModelContainer) async {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let predicate = #Predicate<QSO> { qso in
            !qso.isHidden
        }

        var descriptor = FetchDescriptor<QSO>(predicate: predicate)
        // Fetch in batches to avoid memory spikes
        descriptor.fetchLimit = 10_000

        var newCounts: [String: Int] = [:]
        var offset = 0

        do {
            while true {
                descriptor.fetchOffset = offset
                let batch = try context.fetch(descriptor)

                if batch.isEmpty {
                    break
                }

                for qso in batch {
                    // Skip metadata pseudo-modes
                    guard !Self.metadataModes.contains(qso.mode.uppercased()) else {
                        continue
                    }
                    let key = normalizeCallsign(qso.callsign)
                    newCounts[key, default: 0] += 1
                }

                offset += batch.count

                // Yield periodically to avoid blocking
                if offset % 10_000 == 0 {
                    await Task.yield()
                }
            }
        } catch {
            // Silently fail - cache is a nice-to-have
        }

        counts = newCounts
        isLoaded = true
    }

    /// Get the contact count for a callsign. Returns nil if cache isn't loaded yet.
    func count(for callsign: String) -> Int? {
        guard isLoaded else {
            return nil
        }
        let key = normalizeCallsign(callsign)
        return counts[key] ?? 0
    }

    /// Increment the count after logging a new QSO (avoids full reload)
    func increment(callsign: String) {
        let key = normalizeCallsign(callsign)
        counts[key, default: 0] += 1
    }

    /// Clear the cache
    func clear() {
        counts = [:]
        isLoaded = false
    }

    // MARK: Private

    /// Normalize callsign for consistent lookup (uppercase, strip portable suffixes)
    private func normalizeCallsign(_ callsign: String) -> String {
        let upper = callsign.uppercased()
        if let slashIndex = upper.firstIndex(of: "/") {
            let before = String(upper[..<slashIndex])
            let after = String(upper[upper.index(after: slashIndex)...])
            // If suffix is short (1-3 chars), it's a portable indicator - use base
            // If prefix is short (1-2 chars), it's a country prefix - use rest
            if after.count <= 3 {
                return before
            } else if before.count <= 2 {
                return after
            }
            return before.count >= after.count ? before : after
        }
        return upper
    }
}
