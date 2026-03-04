// POTA Parks Cache
//
// Downloads and caches park reference data from pota.app for
// displaying human-readable park names throughout the app.
// Supports full-text search and nearby parks lookup.

import CarrierWaveData
import Foundation

// MARK: - POTAPark

/// Full park metadata from POTA CSV
struct POTAPark: Sendable {
    let reference: String // "US-1234"
    let name: String // "Yellowstone National Park"
    let locationDesc: String // "US-WY" (state/region)
    let latitude: Double?
    let longitude: Double?
    let grid: String?
    let entityId: Int // DXCC entity (291 = USA)
    let isActive: Bool

    /// Extract country prefix from reference (e.g., "US" from "US-1234")
    var countryPrefix: String {
        let parts = reference.split(separator: "-")
        guard let first = parts.first else {
            return ""
        }
        return String(first)
    }

    /// Extract numeric part from reference (e.g., "1234" from "US-1234")
    var numericPart: String {
        let parts = reference.split(separator: "-")
        guard parts.count >= 2 else {
            return ""
        }
        return String(parts[1])
    }

    /// Extract state from locationDesc (e.g., "WY" from "US-WY")
    var state: String? {
        let parts = locationDesc.split(separator: "-")
        guard parts.count >= 2 else {
            return nil
        }
        return String(parts[1])
    }
}

// MARK: - POTAParksCacheMetadata

struct POTAParksCacheMetadata {
    /// Manual Codable implementation to avoid @MainActor inference
    enum CodingKeys: String, CodingKey {
        case downloadedAt
        case recordCount
    }

    let downloadedAt: Date
    let recordCount: Int
}

// MARK: Codable, Sendable

extension POTAParksCacheMetadata: Codable, Sendable {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        downloadedAt = try container.decode(Date.self, forKey: .downloadedAt)
        recordCount = try container.decode(Int.self, forKey: .recordCount)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(downloadedAt, forKey: .downloadedAt)
        try container.encode(recordCount, forKey: .recordCount)
    }
}

// MARK: - POTAParksCacheStatus

enum POTAParksCacheStatus: Sendable {
    case notLoaded
    case loading
    case loaded(parkCount: Int, downloadedAt: Date?)
    case downloading
    case failed(String)
}

// MARK: - POTAParksCache

actor POTAParksCache {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = POTAParksCache()

    /// Current status of the cache (for UI display)
    private(set) var status: POTAParksCacheStatus = .notLoaded

    /// Number of parks in cache (for display/debugging)
    var parkCount: Int {
        parks.count
    }

    /// Get park name for a reference (e.g., "K-1234" -> "Yellowstone National Park")
    /// Returns nil if park not found or cache not loaded
    func name(for reference: String) -> String? {
        parks[reference.uppercased()]?.name
    }

    /// Get full park data for a reference
    func park(for reference: String) -> POTAPark? {
        parks[reference.uppercased()]
    }

    /// Ensure cache is loaded, downloading if necessary
    func ensureLoaded() async {
        guard !isLoaded else {
            return
        }

        status = .loading

        // Try to load from disk first
        if loadFromDisk() {
            isLoaded = true
            status = .loaded(parkCount: parks.count, downloadedAt: loadMetadata()?.downloadedAt)
            // Check if refresh needed in background
            Task {
                await refreshIfNeeded()
            }
            return
        }

        // No cache on disk, download
        do {
            status = .downloading
            try await downloadAndCache()
            isLoaded = true
            status = .loaded(parkCount: parks.count, downloadedAt: loadMetadata()?.downloadedAt)
        } catch {
            print("POTAParksCache: Failed to download parks: \(error)")
            status = .failed(error.localizedDescription)
            isLoaded = true // Mark loaded to avoid repeated attempts
        }
    }

    /// Check if cache is stale and refresh if needed (non-blocking)
    func refreshIfNeeded() async {
        guard let metadata = loadMetadata() else {
            // No metadata, need to download
            status = .downloading
            do {
                try await downloadAndCache()
                status = .loaded(parkCount: parks.count, downloadedAt: loadMetadata()?.downloadedAt)
            } catch {
                status = .failed(error.localizedDescription)
            }
            return
        }

        let twoWeeksAgo = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        if metadata.downloadedAt < twoWeeksAgo {
            status = .downloading
            do {
                try await downloadAndCache()
                status = .loaded(parkCount: parks.count, downloadedAt: loadMetadata()?.downloadedAt)
            } catch {
                // Keep old data, just update status to show we tried
                status = .loaded(parkCount: parks.count, downloadedAt: metadata.downloadedAt)
            }
        }
    }

    /// Force refresh the cache, throwing on failure
    func forceRefresh() async throws {
        status = .downloading
        do {
            try await downloadAndCache()
            status = .loaded(parkCount: parks.count, downloadedAt: loadMetadata()?.downloadedAt)
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Last download date (for display/debugging)
    func lastDownloadDate() -> Date? {
        loadMetadata()?.downloadedAt
    }

    /// Get current status snapshot for UI
    func getStatus() -> POTAParksCacheStatus {
        status
    }

    /// Synchronous park name lookup for UI use (nonisolated for MainActor access)
    /// Returns nil if park not found or cache not yet loaded
    nonisolated func nameSync(for reference: String) -> String? {
        parks[reference.uppercased()]?.name
    }

    /// Synchronous full park lookup for UI use (nonisolated for MainActor access)
    /// Returns nil if park not found or cache not yet loaded
    nonisolated func parkSync(for reference: String) -> POTAPark? {
        parks[reference.uppercased()]
    }

    /// Search parks by name (full-text search on words)
    /// Returns parks whose names contain all query words
    nonisolated func searchByName(_ query: String, limit: Int = 20) -> [POTAPark] {
        let queryWords = query.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard !queryWords.isEmpty else {
            return []
        }

        // Find references that match ALL query words
        var matchingRefs: Set<String>?

        for word in queryWords {
            var wordMatches = Set<String>()
            // Find all index entries that start with this word (prefix match)
            for (indexWord, refs) in nameIndex where indexWord.hasPrefix(word) {
                wordMatches.formUnion(refs)
            }

            if let existing = matchingRefs {
                matchingRefs = existing.intersection(wordMatches)
            } else {
                matchingRefs = wordMatches
            }

            // Early exit if no matches
            if matchingRefs?.isEmpty == true {
                return []
            }
        }

        guard let refs = matchingRefs else {
            return []
        }

        // Convert refs to parks and sort by relevance (shorter names first, then alphabetical)
        var results = refs.compactMap { parks[$0] }
        results.sort { lhs, rhs in
            if lhs.name.count != rhs.name.count {
                return lhs.name.count < rhs.name.count
            }
            return lhs.name < rhs.name
        }

        return Array(results.prefix(limit))
    }

    /// Find parks near a location
    /// Returns parks sorted by distance, closest first
    nonisolated func nearbyParks(
        latitude: Double,
        longitude: Double,
        limit: Int = 20,
        maxDistanceKm: Double = 100
    ) -> [(park: POTAPark, distanceKm: Double)] {
        var results: [(park: POTAPark, distanceKm: Double)] = []

        for park in parks.values {
            guard let parkLat = park.latitude, let parkLon = park.longitude else {
                continue
            }

            let distance = haversineDistance(
                lat1: latitude, lon1: longitude,
                lat2: parkLat, lon2: parkLon
            )

            if distance <= maxDistanceKm {
                results.append((park: park, distanceKm: distance))
            }
        }

        // Sort by distance
        results.sort { $0.distanceKm < $1.distanceKm }

        return Array(results.prefix(limit))
    }

    /// Lookup a park by reference, supporting shorthand notation
    /// - "1234" -> looks up with defaultCountry prefix (e.g., "US-1234")
    /// - "K-1234" -> direct lookup
    /// - "US-1234" -> direct lookup
    nonisolated func lookupPark(_ query: String, defaultCountry: String = "US") -> POTAPark? {
        let trimmed = query.trimmingCharacters(in: .whitespaces).uppercased()

        // Direct lookup first
        if let park = parks[trimmed] {
            return park
        }

        // Try with default country prefix if query looks like just a number
        if trimmed.allSatisfy(\.isNumber) {
            let withPrefix = "\(defaultCountry.uppercased())-\(trimmed)"
            return parks[withPrefix]
        }

        // Try common prefixes if not found (K- is an alias for US-)
        if trimmed.hasPrefix("K-") {
            let usRef = "US-" + trimmed.dropFirst(2)
            return parks[String(usRef)]
        }

        return nil
    }

    // MARK: Private

    private static let csvURL = URL(string: "https://pota.app/all_parks_ext.csv")!
    private static let cacheFileName = "pota_parks.csv"
    private static let metadataFileName = "pota_parks_metadata.json"

    /// Thread-safe parks lookup using nonisolated(unsafe) for synchronous access
    /// Safe because: writes only happen during ensureLoaded() which completes before reads
    nonisolated(unsafe) private var parks: [String: POTAPark] = [:] // reference -> park
    nonisolated(unsafe) private var nameIndex: [String: [String]] = [:] // lowercase word -> [references]
    private var isLoaded = false

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private var cacheFileURL: URL {
        cacheDirectory.appendingPathComponent(Self.cacheFileName)
    }

    private var metadataFileURL: URL {
        cacheDirectory.appendingPathComponent(Self.metadataFileName)
    }

    private func loadFromDisk() -> Bool {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            return false
        }

        do {
            let csvData = try String(contentsOf: cacheFileURL, encoding: .utf8)
            parks = parseCSV(csvData)
            buildNameIndex()
            return !parks.isEmpty
        } catch {
            print("POTAParksCache: Failed to load from disk: \(error)")
            return false
        }
    }

    private func loadMetadata() -> POTAParksCacheMetadata? {
        guard let data = try? Data(contentsOf: metadataFileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(POTAParksCacheMetadata.self, from: data)
    }

    private func saveMetadata(recordCount: Int) {
        let metadata = POTAParksCacheMetadata(
            downloadedAt: Date(),
            recordCount: recordCount
        )
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: metadataFileURL)
        }
    }

    private func downloadAndCache() async throws {
        let (data, response) = try await URLSession.shared.data(from: Self.csvURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw URLError(.badServerResponse)
        }

        guard let csvString = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        // Parse and store in memory
        let parsed = parseCSV(csvString)
        parks = parsed
        buildNameIndex()

        // Save to disk
        try csvString.write(to: cacheFileURL, atomically: true, encoding: .utf8)
        saveMetadata(recordCount: parsed.count)

        print("POTAParksCache: Downloaded \(parsed.count) parks")
    }

    /// Parse the POTA CSV into full park objects
    /// CSV columns: reference, name, active, entityId, locationDesc, latitude, longitude, grid
    private func parseCSV(_ csv: String) -> [String: POTAPark] {
        var result: [String: POTAPark] = [:]
        for line in csv.components(separatedBy: .newlines).dropFirst() {
            guard !line.isEmpty else {
                continue
            }
            let fields = parseCSVLine(line)
            guard fields.count >= 8 else {
                continue
            }
            let reference = fields[0].uppercased()
            let name = fields[1]
            guard !reference.isEmpty, !name.isEmpty else {
                continue
            }
            let park = POTAPark(
                reference: reference,
                name: name,
                locationDesc: fields[4],
                latitude: Double(fields[5]),
                longitude: Double(fields[6]),
                grid: fields[7].isEmpty ? nil : fields[7],
                entityId: Int(fields[3]) ?? 0,
                isActive: fields[2].lowercased() == "1" || fields[2].lowercased() == "true"
            )
            result[reference] = park
        }
        return result
    }

    /// Parse a CSV line handling quoted fields
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == ",", !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))

        return fields
    }

    /// Build the name index for full-text search
    /// Maps lowercase words to arrays of park references
    private func buildNameIndex() {
        var index: [String: [String]] = [:]

        for (reference, park) in parks {
            // Split name into words and index each
            let words = park.name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && $0.count >= 2 } // Skip very short words

            for word in words {
                if index[word] == nil {
                    index[word] = [reference]
                } else {
                    index[word]?.append(reference)
                }
            }
        }

        nameIndex = index
    }

    /// Calculate distance between two coordinates using Haversine formula
    /// Returns distance in kilometers
    nonisolated private func haversineDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let earthRadiusKm = 6_371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let lat1Rad = lat1 * .pi / 180
        let lat2Rad = lat2 * .pi / 180
        let haversineLat = sin(dLat / 2) * sin(dLat / 2)
        let haversineLon = sin(dLon / 2) * sin(dLon / 2) * cos(lat1Rad) * cos(lat2Rad)
        let centralAngle =
            2 * atan2(sqrt(haversineLat + haversineLon), sqrt(1 - haversineLat - haversineLon))
        return earthRadiusKm * centralAngle
    }
}
