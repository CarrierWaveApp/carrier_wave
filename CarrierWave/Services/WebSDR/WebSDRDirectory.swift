import CoreLocation
import Foundation

// MARK: - KiwiSDRReceiver

/// A KiwiSDR receiver from the public directory
struct KiwiSDRReceiver: Identifiable, Sendable {
    let id: String // host:port
    let name: String
    let host: String
    let port: Int
    let latitude: Double
    let longitude: Double
    let bands: String // e.g., "0-30 MHz"
    let users: Int
    let maxUsers: Int
    let location: String // e.g., "Portland, OR, USA"
    let antenna: String

    /// Distance from a reference point in km
    var distanceKm: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isAvailable: Bool {
        users < maxUsers
    }

    var formattedDistance: String? {
        guard let km = distanceKm else { return nil }
        if km < 1 {
            return "<1 km"
        }
        let miles = km * 0.621371
        return String(format: "%.0f km (%.0f mi)", km, miles)
    }
}

// MARK: - WebSDRDirectory

/// Fetches and caches the KiwiSDR public directory for finding nearby receivers.
/// Caches locally and refreshes daily.
actor WebSDRDirectory {
    // MARK: Internal

    /// Shared singleton
    static let shared = WebSDRDirectory()

    /// Find nearby KiwiSDR receivers sorted by distance
    func findNearby(
        grid: String?,
        latitude: Double? = nil,
        longitude: Double? = nil,
        limit: Int = 10
    ) async -> [KiwiSDRReceiver] {
        // Determine reference coordinate
        let refCoord: CLLocationCoordinate2D?
        if let lat = latitude, let lon = longitude {
            refCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else if let grid, let coord = MaidenheadConverter.coordinate(from: grid) {
            refCoord = coord
        } else {
            refCoord = nil
        }

        // Load directory if needed
        if receivers.isEmpty {
            await loadDirectory()
        }

        var results = receivers

        // Calculate distances if we have a reference point
        if let ref = refCoord {
            let refLocation = CLLocation(latitude: ref.latitude, longitude: ref.longitude)
            results = results.map { receiver in
                var r = receiver
                let loc = CLLocation(
                    latitude: receiver.latitude,
                    longitude: receiver.longitude
                )
                r.distanceKm = refLocation.distance(from: loc) / 1_000
                return r
            }
            results.sort { ($0.distanceKm ?? .infinity) < ($1.distanceKm ?? .infinity) }
        }

        return Array(results.prefix(limit))
    }

    /// Force refresh the directory
    func refresh() async {
        await fetchDirectory()
    }

    /// Number of cached receivers
    var receiverCount: Int { receivers.count }

    // MARK: Private

    private var receivers: [KiwiSDRReceiver] = []
    private var lastFetched: Date?
    private let cacheFile = "kiwisdr_directory.json"
    private let refreshInterval: TimeInterval = 24 * 60 * 60 // 24 hours

    private func loadDirectory() async {
        // Try loading from cache first
        if let cached = loadFromCache() {
            receivers = cached.receivers
            lastFetched = cached.fetchedAt

            // Refresh in background if stale
            if let fetched = lastFetched,
               Date().timeIntervalSince(fetched) > refreshInterval
            {
                await fetchDirectory()
            }
            return
        }

        // No cache, fetch from network
        await fetchDirectory()
    }

    private func fetchDirectory() async {
        do {
            let parsed = try await fetchKiwiSDRList()
            receivers = parsed
            lastFetched = Date()
            saveToCache(receivers: parsed, fetchedAt: Date())
        } catch {
            print("[WebSDR] Directory fetch failed: \(error.localizedDescription)")
        }
    }

    /// Fetch the KiwiSDR public receiver list
    private func fetchKiwiSDRList() async throws -> [KiwiSDRReceiver] {
        // KiwiSDR publishes a JSON status endpoint
        guard let url = URL(string: "http://kiwisdr.com/public/") else {
            return []
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            return []
        }

        return parseKiwiSDRHTML(html)
    }

    /// Parse the KiwiSDR public directory HTML for receiver data.
    /// The page contains a JavaScript array with receiver metadata.
    private func parseKiwiSDRHTML(_ html: String) -> [KiwiSDRReceiver] {
        // The KiwiSDR public page embeds receiver data in a JS variable.
        // We parse the key fields from the HTML table rows as a fallback.
        var results: [KiwiSDRReceiver] = []

        // Look for table rows with receiver data
        // Each row has: name, band, users, location, antenna, coordinates
        let lines = html.components(separatedBy: "\n")

        for line in lines {
            guard line.contains("class=\"cl-") else { continue }
            if let receiver = parseReceiverRow(line) {
                results.append(receiver)
            }
        }

        return results
    }

    /// Parse a single receiver row from the HTML
    private func parseReceiverRow(_ html: String) -> KiwiSDRReceiver? {
        // Extract hostname from href
        guard let hostMatch = extractBetween(html, prefix: "href=\"http://", suffix: "\""),
              let name = extractBetween(html, prefix: "class=\"cl-name\">", suffix: "<")
        else {
            return nil
        }

        // Parse host:port
        let hostParts = hostMatch.components(separatedBy: ":")
        let host = hostParts[0]
        let port = hostParts.count > 1 ? Int(hostParts[1]) ?? 8073 : 8073

        // Extract location, bands, users, coordinates
        let location = extractBetween(html, prefix: "class=\"cl-loc\">", suffix: "<") ?? ""
        let bands = extractBetween(html, prefix: "class=\"cl-band\">", suffix: "<") ?? "0-30 MHz"
        let antenna = extractBetween(html, prefix: "class=\"cl-ant\">", suffix: "<") ?? ""
        let usersStr = extractBetween(html, prefix: "class=\"cl-users\">", suffix: "<") ?? "0/4"
        let gpsStr = extractBetween(html, prefix: "class=\"cl-gps\">", suffix: "<") ?? ""

        // Parse users "N/M"
        let userParts = usersStr.components(separatedBy: "/")
        let users = Int(userParts.first ?? "0") ?? 0
        let maxUsers = Int(userParts.last ?? "4") ?? 4

        // Parse GPS coordinates
        let coords = parseCoordinates(gpsStr)

        return KiwiSDRReceiver(
            id: "\(host):\(port)",
            name: name,
            host: host,
            port: port,
            latitude: coords?.latitude ?? 0,
            longitude: coords?.longitude ?? 0,
            bands: bands,
            users: users,
            maxUsers: maxUsers,
            location: location,
            antenna: antenna
        )
    }

    private func extractBetween(_ str: String, prefix: String, suffix: String) -> String? {
        guard let prefixRange = str.range(of: prefix) else { return nil }
        let after = str[prefixRange.upperBound...]
        guard let suffixRange = after.range(of: suffix) else { return nil }
        return String(after[..<suffixRange.lowerBound])
    }

    private func parseCoordinates(_ str: String) -> CLLocationCoordinate2D? {
        // Format: "(lat, lon)" or "lat, lon"
        let cleaned = str.replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespaces)
        let parts = cleaned.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1])
        else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: - Cache

    private struct CachedDirectory: Codable {
        let receivers: [CodableReceiver]
        let fetchedAt: Date
    }

    private struct CodableReceiver: Codable {
        let name: String
        let host: String
        let port: Int
        let latitude: Double
        let longitude: Double
        let bands: String
        let maxUsers: Int
        let location: String
        let antenna: String
    }

    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(cacheFile)
    }

    private func loadFromCache() -> (receivers: [KiwiSDRReceiver], fetchedAt: Date)? {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedDirectory.self, from: data)
        else { return nil }

        let receivers = cached.receivers.map { r in
            KiwiSDRReceiver(
                id: "\(r.host):\(r.port)",
                name: r.name, host: r.host, port: r.port,
                latitude: r.latitude, longitude: r.longitude,
                bands: r.bands, users: 0, maxUsers: r.maxUsers,
                location: r.location, antenna: r.antenna
            )
        }
        return (receivers, cached.fetchedAt)
    }

    private func saveToCache(receivers: [KiwiSDRReceiver], fetchedAt: Date) {
        guard let url = cacheURL else { return }
        let codable = CachedDirectory(
            receivers: receivers.map { r in
                CodableReceiver(
                    name: r.name, host: r.host, port: r.port,
                    latitude: r.latitude, longitude: r.longitude,
                    bands: r.bands, maxUsers: r.maxUsers,
                    location: r.location, antenna: r.antenna
                )
            },
            fetchedAt: fetchedAt
        )
        let data = try? JSONEncoder().encode(codable)
        try? data?.write(to: url)
    }
}
