// WWFF References Cache
//
// Downloads and caches WWFF reference directory data from wwff.co
// for displaying human-readable area names and supporting autocomplete.
// Supports full-text search and nearby references lookup.

import Foundation

// MARK: - WWFFReferencesCacheMetadata

struct WWFFReferencesCacheMetadata {
    enum CodingKeys: String, CodingKey {
        case downloadedAt
        case recordCount
    }

    let downloadedAt: Date
    let recordCount: Int
}

// MARK: Codable, Sendable

extension WWFFReferencesCacheMetadata: Codable, Sendable {
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

// MARK: - WWFFReferencesCacheStatus

enum WWFFReferencesCacheStatus: Sendable {
    case notLoaded
    case loading
    case loaded(referenceCount: Int, downloadedAt: Date?)
    case downloading
    case failed(String)
}

// MARK: - WWFFReferencesCache

actor WWFFReferencesCache {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = WWFFReferencesCache()

    /// Current status of the cache (for UI display)
    private(set) var status: WWFFReferencesCacheStatus = .notLoaded

    /// Thread-safe references lookup using nonisolated(unsafe) for synchronous access
    /// Safe because: writes only happen during ensureLoaded() which completes before reads
    nonisolated(unsafe) var references: [String: WWFFReference] = [:]
    nonisolated(unsafe) var nameIndex: [String: [String]] = [:]

    /// Number of references in cache
    var referenceCount: Int {
        references.count
    }

    /// Get reference name for a code (e.g., "KFF-1234" -> "Yellowstone NP")
    func name(for code: String) -> String? {
        references[code.uppercased()]?.name
    }

    /// Get full reference data for a code
    func reference(for code: String) -> WWFFReference? {
        references[code.uppercased()]
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
                referenceCount: references.count,
                downloadedAt: loadMetadata()?.downloadedAt
            )
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
                referenceCount: references.count,
                downloadedAt: loadMetadata()?.downloadedAt
            )
        } catch {
            print("WWFFReferencesCache: Failed to download: \(error)")
            status = .failed(error.localizedDescription)
            isLoaded = true
        }
    }

    /// Check if cache is stale and refresh if needed
    func refreshIfNeeded() async {
        guard let metadata = loadMetadata() else {
            status = .downloading
            do {
                try await downloadAndCache()
                status = .loaded(
                    referenceCount: references.count,
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
                    referenceCount: references.count,
                    downloadedAt: loadMetadata()?.downloadedAt
                )
            } catch {
                status = .loaded(
                    referenceCount: references.count,
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
                referenceCount: references.count,
                downloadedAt: loadMetadata()?.downloadedAt
            )
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Get current status snapshot for UI
    func getStatus() -> WWFFReferencesCacheStatus {
        status
    }

    /// Synchronous name lookup (nonisolated for MainActor access)
    nonisolated func nameSync(for code: String) -> String? {
        references[code.uppercased()]?.name
    }

    /// Synchronous full reference lookup (nonisolated for MainActor access)
    nonisolated func referenceSync(for code: String) -> WWFFReference? {
        references[code.uppercased()]
    }

    /// Look up a reference by exact code
    nonisolated func lookupReference(
        _ code: String
    ) -> WWFFReference? {
        references[code.trimmingCharacters(in: .whitespaces).uppercased()]
    }

    /// Search references by name (full-text search on words)
    /// Returns references whose names contain all query words
    nonisolated func searchByName(
        _ query: String,
        limit: Int = 20
    ) -> [WWFFReference] {
        let queryWords = query.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard !queryWords.isEmpty else {
            return []
        }

        var matchingCodes: Set<String>?

        for word in queryWords {
            var wordMatches = Set<String>()
            for (indexWord, codes) in nameIndex where indexWord.hasPrefix(word) {
                wordMatches.formUnion(codes)
            }

            if let existing = matchingCodes {
                matchingCodes = existing.intersection(wordMatches)
            } else {
                matchingCodes = wordMatches
            }

            if matchingCodes?.isEmpty == true {
                return []
            }
        }

        guard let codes = matchingCodes else {
            return []
        }

        var results = codes.compactMap { references[$0] }
            .filter { $0.status == "active" }
        results.sort { lhs, rhs in
            if lhs.name.count != rhs.name.count {
                return lhs.name.count < rhs.name.count
            }
            return lhs.name < rhs.name
        }

        return Array(results.prefix(limit))
    }

    /// Find references near a location
    nonisolated func nearbyReferences(
        latitude: Double,
        longitude: Double,
        limit: Int = 20,
        maxDistanceKm: Double = 100
    ) -> [(reference: WWFFReference, distanceKm: Double)] {
        var results: [(reference: WWFFReference, distanceKm: Double)] = []

        for ref in references.values {
            guard ref.status == "active",
                  let rLat = ref.latitude, let rLon = ref.longitude
            else {
                continue
            }

            let distance = haversineDistance(
                lat1: latitude, lon1: longitude,
                lat2: rLat, lon2: rLon
            )

            if distance <= maxDistanceKm {
                results.append((reference: ref, distanceKm: distance))
            }
        }

        results.sort { $0.distanceKm < $1.distanceKm }
        return Array(results.prefix(limit))
    }

    // MARK: Private

    private static let csvURL = URL(
        string: "https://wwff.co/wwff-data/wwff_directory.csv"
    )!
    private static let cacheFileName = "wwff_directory.csv"
    private static let metadataFileName = "wwff_directory_metadata.json"

    private var isLoaded = false

    private var cacheDirectory: URL {
        FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        )[0]
    }

    private var cacheFileURL: URL {
        cacheDirectory.appendingPathComponent(Self.cacheFileName)
    }

    private var metadataFileURL: URL {
        cacheDirectory.appendingPathComponent(Self.metadataFileName)
    }

    private func loadFromDisk() -> Bool {
        guard FileManager.default.fileExists(
            atPath: cacheFileURL.path
        ) else {
            return false
        }

        do {
            let csvData = try String(
                contentsOf: cacheFileURL, encoding: .utf8
            )
            references = parseCSV(csvData)
            buildNameIndex()
            return !references.isEmpty
        } catch {
            print("WWFFReferencesCache: Failed to load: \(error)")
            return false
        }
    }

    private func loadMetadata() -> WWFFReferencesCacheMetadata? {
        guard let data = try? Data(contentsOf: metadataFileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(
            WWFFReferencesCacheMetadata.self, from: data
        )
    }

    private func saveMetadata(recordCount: Int) {
        let metadata = WWFFReferencesCacheMetadata(
            downloadedAt: Date(),
            recordCount: recordCount
        )
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: metadataFileURL)
        }
    }

    private func downloadAndCache() async throws {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let (tempURL, response) = try await session.download(
            from: Self.csvURL
        )

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw URLError(.badServerResponse)
        }

        let data = try Data(contentsOf: tempURL)
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        let parsed = parseCSV(csvString)
        references = parsed
        buildNameIndex()

        try csvString.write(
            to: cacheFileURL, atomically: true, encoding: .utf8
        )
        saveMetadata(recordCount: parsed.count)

        print("WWFFReferencesCache: Downloaded \(parsed.count) references")
    }
}
