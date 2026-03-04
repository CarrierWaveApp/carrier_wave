import CarrierWaveData
import CoreLocation
import Foundation

// MARK: - MemberLocationCache

/// Caches HamDB callsign → coordinate lookups to avoid repeated API calls.
/// Entries expire after 30 days. Stored as JSON in the Caches directory.
actor MemberLocationCache {
    // MARK: Lifecycle

    init() {
        let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
        // Version suffix invalidates cache when lookup strategy changes
        fileURL = caches.appendingPathComponent(
            "member-locations-cache-v2.json"
        )
        entries = Self.load(from: fileURL)
    }

    // MARK: Internal

    enum CacheLookup {
        case miss
        case noLocation
        case found(CLLocationCoordinate2D)
    }

    static let shared = MemberLocationCache()

    func lookup(callsign: String) -> CacheLookup {
        let key = callsign.uppercased()
        guard let entry = entries[key] else {
            return .miss
        }

        if Date().timeIntervalSince(entry.cachedAt) > maxAge {
            entries.removeValue(forKey: key)
            return .miss
        }

        if let lat = entry.latitude, let lon = entry.longitude {
            return .found(CLLocationCoordinate2D(
                latitude: lat,
                longitude: lon
            ))
        }
        return .noLocation
    }

    func store(
        callsign: String,
        coordinate: CLLocationCoordinate2D?
    ) {
        let key = callsign.uppercased()
        entries[key] = CachedEntry(
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            cachedAt: Date()
        )
    }

    func persist() {
        Self.save(entries, to: fileURL)
    }

    // MARK: Private

    private struct CachedEntry: Codable {
        let latitude: Double?
        let longitude: Double?
        let cachedAt: Date
    }

    /// 30 days in seconds.
    private let maxAge: TimeInterval = 30 * 24 * 60 * 60
    private let fileURL: URL
    private var entries: [String: CachedEntry]

    private static func load(
        from url: URL
    ) -> [String: CachedEntry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(
                  [String: CachedEntry].self,
                  from: data
              )
        else {
            return [:]
        }
        return decoded
    }

    private static func save(
        _ entries: [String: CachedEntry],
        to url: URL
    ) {
        guard let data = try? JSONEncoder().encode(entries)
        else {
            return
        }
        try? data.write(to: url)
    }
}
