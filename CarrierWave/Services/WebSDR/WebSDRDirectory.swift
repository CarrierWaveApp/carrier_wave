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
        guard let km = distanceKm else {
            return nil
        }
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

    /// Number of cached receivers
    var receiverCount: Int {
        receivers.count
    }

    /// Find nearby KiwiSDR receivers sorted by distance
    func findNearby(
        grid: String?,
        latitude: Double? = nil,
        longitude: Double? = nil,
        limit: Int = 10
    ) async -> [KiwiSDRReceiver] {
        // Determine reference coordinate
        let refCoord: CLLocationCoordinate2D? = if let lat = latitude, let lon = longitude {
            CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else if let grid, let coord = MaidenheadConverter.coordinate(from: grid) {
            coord
        } else {
            nil
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
                var updated = receiver
                let loc = CLLocation(
                    latitude: receiver.latitude,
                    longitude: receiver.longitude
                )
                updated.distanceKm = refLocation.distance(from: loc) / 1_000
                return updated
            }
            results.sort { ($0.distanceKm ?? .infinity) < ($1.distanceKm ?? .infinity) }
        }

        return Array(results.prefix(limit))
    }

    /// Force refresh the directory
    func refresh() async {
        await fetchDirectory()
    }

    // MARK: Private

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

    private var receivers: [KiwiSDRReceiver] = []
    private var lastFetched: Date?
    private let cacheFile = "kiwisdr_directory.json"
    private let refreshInterval: TimeInterval = 24 * 60 * 60 // 24 hours

    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(cacheFile)
    }

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
        guard let url = URL(string: "http://kiwisdr.com/.public/") else {
            return []
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            return []
        }

        return parseKiwiSDRHTML(html)
    }

    /// Parse the KiwiSDR public directory HTML for receiver data.
    /// Receiver metadata is embedded in HTML comments within cl-entry blocks.
    private func parseKiwiSDRHTML(_ html: String) -> [KiwiSDRReceiver] {
        let blocks = html.components(separatedBy: "<div class='cl-entry")
        // First element is everything before the first entry — skip it
        guard blocks.count > 1 else {
            return []
        }

        var results: [KiwiSDRReceiver] = []
        let commentPattern = try? NSRegularExpression(
            pattern: "<!--\\s*(\\w+)=(.+?)\\s*-->",
            options: []
        )

        for block in blocks.dropFirst() {
            if let receiver = parseEntryBlock(block, commentPattern: commentPattern) {
                results.append(receiver)
            }
        }

        return results
    }

    /// Parse a single cl-entry block from the directory HTML
    private func parseEntryBlock(
        _ block: String,
        commentPattern: NSRegularExpression?
    ) -> KiwiSDRReceiver? {
        guard let commentPattern else {
            return nil
        }

        // Extract comment fields into a dictionary
        let nsBlock = block as NSString
        let matches = commentPattern.matches(
            in: block,
            range: NSRange(location: 0, length: nsBlock.length)
        )
        var fields: [String: String] = [:]
        for match in matches {
            let key = nsBlock.substring(with: match.range(at: 1))
            let value = nsBlock.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }

        // Only include active receivers
        guard fields["status"] == "active" else {
            return nil
        }

        // Extract host from the link: <a href='http://host:port' ...>
        let host: String
        let port: Int
        if let linkRange = block.range(of: "href='http://"),
           let endRange = block[linkRange.upperBound...].range(of: "'")
        {
            let hostPort = String(block[linkRange.upperBound ..< endRange.lowerBound])
            let parts = hostPort.components(separatedBy: ":")
            host = parts[0]
            port = parts.count > 1 ? Int(parts[1]) ?? 8_073 : 8_073
        } else {
            return nil
        }

        let name = fields["name"] ?? host
        let coords = parseCoordinates(fields["gps"] ?? "")
        let users = Int(fields["users"] ?? "0") ?? 0
        let maxUsers = Int(fields["users_max"] ?? "4") ?? 4
        let location = fields["loc"] ?? ""
        let antenna = fields["antenna"] ?? ""
        let bands = formatBands(fields["bands"] ?? "0-30000000")

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

    /// Convert raw band range (Hz) to human-readable format
    private func formatBands(_ raw: String) -> String {
        let parts = raw.components(separatedBy: ",")
        guard let firstRange = parts.first else {
            return raw
        }
        let bounds = firstRange.components(separatedBy: "-")
        guard bounds.count == 2,
              let low = Double(bounds[0]),
              let high = Double(bounds[1])
        else {
            return raw
        }
        let lowMHz = low / 1_000_000
        let highMHz = high / 1_000_000
        return String(format: "%.0f-%.0f MHz", lowMHz, highMHz)
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
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func loadFromCache() -> (receivers: [KiwiSDRReceiver], fetchedAt: Date)? {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedDirectory.self, from: data)
        else {
            return nil
        }

        let receivers = cached.receivers.map { cached in
            KiwiSDRReceiver(
                id: "\(cached.host):\(cached.port)",
                name: cached.name, host: cached.host, port: cached.port,
                latitude: cached.latitude, longitude: cached.longitude,
                bands: cached.bands, users: 0, maxUsers: cached.maxUsers,
                location: cached.location, antenna: cached.antenna
            )
        }
        return (receivers, cached.fetchedAt)
    }

    private func saveToCache(receivers: [KiwiSDRReceiver], fetchedAt: Date) {
        guard let url = cacheURL else {
            return
        }
        let codable = CachedDirectory(
            receivers: receivers.map { receiver in
                CodableReceiver(
                    name: receiver.name, host: receiver.host, port: receiver.port,
                    latitude: receiver.latitude, longitude: receiver.longitude,
                    bands: receiver.bands, maxUsers: receiver.maxUsers,
                    location: receiver.location, antenna: receiver.antenna
                )
            },
            fetchedAt: fetchedAt
        )
        let data = try? JSONEncoder().encode(codable)
        try? data?.write(to: url)
    }
}
