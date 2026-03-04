// SOTA Summits Cache
//
// Downloads and caches summit reference data from sotadata.org.uk
// for displaying human-readable summit names throughout the app.
// Supports full-text search and nearby summits lookup.

import CarrierWaveData
import Foundation

// MARK: - SOTASummitsCacheMetadata

struct SOTASummitsCacheMetadata {
    /// Manual Codable implementation to avoid @MainActor inference
    enum CodingKeys: String, CodingKey {
        case downloadedAt
        case recordCount
    }

    let downloadedAt: Date
    let recordCount: Int
}

// MARK: Codable, Sendable

extension SOTASummitsCacheMetadata: Codable, Sendable {
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

// MARK: - SOTASummitsCacheStatus

enum SOTASummitsCacheStatus: Sendable {
    case notLoaded
    case loading
    case loaded(summitCount: Int, downloadedAt: Date?)
    case downloading
    case failed(String)
}

// MARK: - SOTASummitsCache

actor SOTASummitsCache {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = SOTASummitsCache()

    /// Current status of the cache (for UI display)
    private(set) var status: SOTASummitsCacheStatus = .notLoaded

    /// Thread-safe summits lookup using nonisolated(unsafe) for synchronous access
    /// Safe because: writes only happen during ensureLoaded() which completes before reads
    nonisolated(unsafe) var summits: [String: SOTASummit] = [:]
    nonisolated(unsafe) var nameIndex: [String: [String]] = [:]

    /// Number of summits in cache
    var summitCount: Int {
        summits.count
    }

    /// Get summit name for a code (e.g., "W4C/CM-001" -> "Mount Mitchell")
    func name(for code: String) -> String? {
        summits[code.uppercased()]?.name
    }

    /// Get full summit data for a code
    func summit(for code: String) -> SOTASummit? {
        summits[code.uppercased()]
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
            status = .loaded(
                summitCount: summits.count,
                downloadedAt: loadMetadata()?.downloadedAt
            )
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
            status = .loaded(
                summitCount: summits.count,
                downloadedAt: loadMetadata()?.downloadedAt
            )
        } catch {
            print("SOTASummitsCache: Failed to download summits: \(error)")
            status = .failed(error.localizedDescription)
            isLoaded = true // Mark loaded to avoid repeated attempts
        }
    }

    /// Check if cache is stale and refresh if needed (non-blocking)
    func refreshIfNeeded() async {
        guard let metadata = loadMetadata() else {
            status = .downloading
            do {
                try await downloadAndCache()
                status = .loaded(
                    summitCount: summits.count,
                    downloadedAt: loadMetadata()?.downloadedAt
                )
            } catch {
                status = .failed(error.localizedDescription)
            }
            return
        }

        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        if metadata.downloadedAt < thirtyDaysAgo {
            status = .downloading
            do {
                try await downloadAndCache()
                status = .loaded(
                    summitCount: summits.count,
                    downloadedAt: loadMetadata()?.downloadedAt
                )
            } catch {
                // Keep old data, just update status to show we tried
                status = .loaded(
                    summitCount: summits.count,
                    downloadedAt: metadata.downloadedAt
                )
            }
        }
    }

    /// Force refresh the cache, throwing on failure
    func forceRefresh() async throws {
        status = .downloading
        do {
            try await downloadAndCache()
            status = .loaded(
                summitCount: summits.count,
                downloadedAt: loadMetadata()?.downloadedAt
            )
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Get current status snapshot for UI
    func getStatus() -> SOTASummitsCacheStatus {
        status
    }

    /// Synchronous summit name lookup (nonisolated for MainActor access)
    nonisolated func nameSync(for code: String) -> String? {
        summits[code.uppercased()]?.name
    }

    /// Synchronous full summit lookup (nonisolated for MainActor access)
    nonisolated func summitSync(for code: String) -> SOTASummit? {
        summits[code.uppercased()]
    }

    /// Look up a summit by exact code
    nonisolated func lookupSummit(_ code: String) -> SOTASummit? {
        summits[code.trimmingCharacters(in: .whitespaces).uppercased()]
    }

    /// Search summits by name (full-text search on words)
    /// Returns summits whose names contain all query words
    nonisolated func searchByName(_ query: String, limit: Int = 20) -> [SOTASummit] {
        let queryWords = query.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard !queryWords.isEmpty else {
            return []
        }

        // Find codes that match ALL query words
        var matchingCodes: Set<String>?

        for word in queryWords {
            var wordMatches = Set<String>()
            // Find all index entries that start with this word (prefix match)
            for (indexWord, codes) in nameIndex where indexWord.hasPrefix(word) {
                wordMatches.formUnion(codes)
            }

            if let existing = matchingCodes {
                matchingCodes = existing.intersection(wordMatches)
            } else {
                matchingCodes = wordMatches
            }

            // Early exit if no matches
            if matchingCodes?.isEmpty == true {
                return []
            }
        }

        guard let codes = matchingCodes else {
            return []
        }

        // Convert codes to summits and sort by relevance (shorter names first)
        var results = codes.compactMap { summits[$0] }
        results.sort { lhs, rhs in
            if lhs.name.count != rhs.name.count {
                return lhs.name.count < rhs.name.count
            }
            return lhs.name < rhs.name
        }

        return Array(results.prefix(limit))
    }

    /// Find summits near a location
    /// Returns summits sorted by distance, closest first
    nonisolated func nearbySummits(
        latitude: Double,
        longitude: Double,
        limit: Int = 20,
        maxDistanceKm: Double = 100
    ) -> [(summit: SOTASummit, distanceKm: Double)] {
        var results: [(summit: SOTASummit, distanceKm: Double)] = []

        for summit in summits.values {
            guard let sLat = summit.latitude, let sLon = summit.longitude else {
                continue
            }

            let distance = haversineDistance(
                lat1: latitude, lon1: longitude,
                lat2: sLat, lon2: sLon
            )

            if distance <= maxDistanceKm {
                results.append((summit: summit, distanceKm: distance))
            }
        }

        results.sort { $0.distanceKm < $1.distanceKm }
        return Array(results.prefix(limit))
    }

    // MARK: Private

    private static let csvURL = URL(
        string: "https://www.sotadata.org.uk/summitslist.csv"
    )!
    private static let cacheFileName = "sota_summits.csv"
    private static let metadataFileName = "sota_summits_metadata.json"

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
            summits = parseCSV(csvData)
            buildNameIndex()
            return !summits.isEmpty
        } catch {
            print("SOTASummitsCache: Failed to load from disk: \(error)")
            return false
        }
    }

    private func loadMetadata() -> SOTASummitsCacheMetadata? {
        guard let data = try? Data(contentsOf: metadataFileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(SOTASummitsCacheMetadata.self, from: data)
    }

    private func saveMetadata(recordCount: Int) {
        let metadata = SOTASummitsCacheMetadata(
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
        summits = parsed
        buildNameIndex()

        // Save to disk
        try csvString.write(to: cacheFileURL, atomically: true, encoding: .utf8)
        saveMetadata(recordCount: parsed.count)

        print("SOTASummitsCache: Downloaded \(parsed.count) summits")
    }
}
