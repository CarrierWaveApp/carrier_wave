// POTA Parks Cache for CW Sweep
//
// Downloads and caches park reference data from pota.app for
// local park search in the activation wizard.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "POTAParksCache")

// MARK: - POTAParkEntry

/// Park metadata from the POTA CSV
struct POTAParkEntry: Codable {
    let reference: String
    let name: String
    let locationDesc: String
    let latitude: Double?
    let longitude: Double?
    let grid: String?
    let entityId: Int
    let isActive: Bool
}

// MARK: - POTAParksCache

/// Actor-isolated cache of POTA park data, loaded from a downloaded CSV.
/// Provides synchronous search via lock-protected storage.
actor POTAParksCache {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = POTAParksCache()

    private(set) var status: ParksCacheStatus = .notLoaded

    var parkCount: Int {
        storage.withLock { $0.parks.count }
    }

    /// Ensure cache is loaded; downloads if no local cache exists.
    func ensureLoaded() async {
        guard !isLoaded else {
            return
        }
        status = .loading

        if let cached = loadBinaryCache() {
            storage.withLock { $0.parks = cached }
            buildNameIndex()
            isLoaded = true
            let count = storage.withLock { $0.parks.count }
            status = .loaded(count: count, downloadedAt: loadMetadataDate())
            Task { await refreshIfStale() }
            return
        }

        if let csv = loadCSVFromDisk() {
            storage.withLock { $0.parks = parseCSV(csv) }
            buildNameIndex()
            saveBinaryCache()
            isLoaded = true
            let count = storage.withLock { $0.parks.count }
            status = .loaded(count: count, downloadedAt: loadMetadataDate())
            Task { await refreshIfStale() }
            return
        }

        isLoaded = true
        status = .downloading
        await downloadParks()
    }

    /// Force refresh from the network
    func forceRefresh() async {
        status = .downloading
        await downloadParks()
    }

    /// Synchronous search by name or reference prefix.
    nonisolated func search(
        _ query: String,
        limit: Int = 20
    ) -> [POTAParkEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return []
        }

        let upper = trimmed.uppercased()

        return storage.withLock { state in
            // Direct reference match first
            if let park = state.parks[upper] {
                return [park]
            }

            // Numeric shorthand → US-XXXX
            if upper.allSatisfy(\.isNumber) {
                let ref = "US-\(upper)"
                if let park = state.parks[ref] {
                    return [park]
                }
            }

            // Reference prefix match (e.g., "US-12" matches US-1234, US-1200, etc.)
            if upper.contains("-") {
                let refMatches = state.parks.values
                    .filter { $0.reference.hasPrefix(upper) }
                    .sorted { $0.reference < $1.reference }
                if !refMatches.isEmpty {
                    return Array(refMatches.prefix(limit))
                }
            }

            // Name search via index
            let queryWords = trimmed.lowercased()
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            guard !queryWords.isEmpty else {
                return []
            }

            var matchingRefs: Set<String>?
            for word in queryWords {
                let wordRefs = prefixSearch(word, in: state.nameIndex)
                if let existing = matchingRefs {
                    matchingRefs = existing.intersection(wordRefs)
                } else {
                    matchingRefs = wordRefs
                }
                if matchingRefs?.isEmpty == true {
                    return []
                }
            }

            guard let refs = matchingRefs else {
                return []
            }
            var results = refs.compactMap { state.parks[$0] }
            results.sort { $0.name.count < $1.name.count }
            return Array(results.prefix(limit))
        }
    }

    // MARK: Private

    private struct CacheState {
        var parks: [String: POTAParkEntry] = [:]
        var nameIndex: [(word: String, refs: [String])] = []
    }

    private static let csvURL = URL(string: "https://pota.app/all_parks_ext.csv")!
    private static let cacheFileName = "pota_parks.csv"
    private static let metadataFileName = "pota_parks_metadata.json"
    private static let binaryFileName = "pota_parks.bin"
    private static let refreshInterval: TimeInterval = 14 * 24 * 60 * 60

    private static var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    nonisolated private let storage = NSLockProtected(CacheState())
    private var isLoaded = false

    // MARK: - Download

    private func downloadParks() async {
        do {
            var request = URLRequest(url: Self.csvURL)
            request.setValue("text/csv, text/plain, */*", forHTTPHeaderField: "Accept")
            request.setValue(
                "CWSweep/1.0 (macOS; Amateur Radio Logger)",
                forHTTPHeaderField: "User-Agent"
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse,
                  httpResp.statusCode == 200
            else {
                throw URLError(.badServerResponse)
            }
            guard let csv = String(data: data, encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }
            let trimmedCSV = csv.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedCSV.hasPrefix("<!"), !trimmedCSV.hasPrefix("<html") else {
                throw URLError(.badServerResponse)
            }
            let normalized = csv
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")

            // Save CSV to disk
            let csvPath = Self.cacheDir.appendingPathComponent(Self.cacheFileName)
            try normalized.write(to: csvPath, atomically: true, encoding: .utf8)

            storage.withLock { $0.parks = parseCSV(normalized) }
            buildNameIndex()
            saveBinaryCache()
            saveMetadata()

            let count = storage.withLock { $0.parks.count }
            status = .loaded(count: count, downloadedAt: Date())
            logger.info("Downloaded \(count) POTA parks")
        } catch {
            logger.error("POTA parks download failed: \(error)")
            status = .failed(error.localizedDescription)
        }
    }

    private func refreshIfStale() async {
        guard let date = loadMetadataDate() else {
            await downloadParks()
            return
        }
        if date < Date().addingTimeInterval(-Self.refreshInterval) {
            await downloadParks()
        }
    }

    // MARK: - CSV Parsing

    nonisolated private func parseCSV(_ csv: String) -> [String: POTAParkEntry] {
        var result: [String: POTAParkEntry] = [:]
        var isFirst = true
        for line in csv.split(separator: "\n") {
            if isFirst {
                isFirst = false; continue
            }
            guard !line.isEmpty else {
                continue
            }
            let fields = parseCSVLine(String(line))
            guard fields.count >= 8 else {
                continue
            }
            let reference = fields[0].uppercased()
            let name = fields[1]
            guard !reference.isEmpty, !name.isEmpty else {
                continue
            }
            let park = POTAParkEntry(
                reference: reference,
                name: name,
                locationDesc: fields[4],
                latitude: Double(fields[5]),
                longitude: Double(fields[6]),
                grid: fields[7].isEmpty ? nil : fields[7],
                entityId: Int(fields[3]) ?? 0,
                isActive: fields[2] == "1" || fields[2].lowercased() == "true"
            )
            result[reference] = park
        }
        return result
    }

    nonisolated private func parseCSVLine(_ line: String) -> [String] {
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

    // MARK: - Name Index

    private func buildNameIndex() {
        let snapshot = storage.withLock { $0.parks }
        var index: [String: [String]] = [:]
        for (reference, park) in snapshot {
            let nameWords = park.name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && $0.count >= 2 }
            let refWords = reference.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            for word in nameWords + refWords {
                index[word, default: []].append(reference)
            }
        }
        let built = index
            .map { (word: $0.key, refs: $0.value) }
            .sorted { $0.word < $1.word }
        storage.withLock { $0.nameIndex = built }
    }

    nonisolated private func prefixSearch(
        _ prefix: String,
        in index: [(word: String, refs: [String])]
    ) -> Set<String> {
        guard !index.isEmpty else {
            return []
        }
        var lo = 0
        var hi = index.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if index[mid].word < prefix {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        var result = Set<String>()
        while lo < index.count, index[lo].word.hasPrefix(prefix) {
            result.formUnion(index[lo].refs)
            lo += 1
        }
        return result
    }
}

// MARK: - POTAParksCache + DiskIO

extension POTAParksCache {
    func saveBinaryCache() {
        let snapshot = storage.withLock { $0.parks }
        let url = Self.cacheDir.appendingPathComponent(Self.binaryFileName)
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.warning("Failed to save binary cache: \(error)")
        }
    }

    func loadBinaryCache() -> [String: POTAParkEntry]? {
        let url = Self.cacheDir.appendingPathComponent(Self.binaryFileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: POTAParkEntry].self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    func loadCSVFromDisk() -> String? {
        let url = Self.cacheDir.appendingPathComponent(Self.cacheFileName)
        guard FileManager.default.fileExists(atPath: url.path),
              let csv = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }
        let trimmed = csv.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<!") || trimmed.hasPrefix("<html") {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return csv
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    func saveMetadata() {
        let url = Self.cacheDir.appendingPathComponent(Self.metadataFileName)
        let count = storage.withLock { $0.parks.count }
        let meta = ParksCacheMetadata(downloadedAt: Date(), recordCount: count)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: url)
        }
    }

    func loadMetadataDate() -> Date? {
        let url = Self.cacheDir.appendingPathComponent(Self.metadataFileName)
        guard let data = try? Data(contentsOf: url),
              let meta = try? JSONDecoder().decode(ParksCacheMetadata.self, from: data)
        else {
            return nil
        }
        return meta.downloadedAt
    }
}

// MARK: - ParksCacheStatus

enum ParksCacheStatus {
    case notLoaded
    case loading
    case loaded(count: Int, downloadedAt: Date?)
    case downloading
    case failed(String)
}

// MARK: - ParksCacheMetadata

private struct ParksCacheMetadata: Codable {
    let downloadedAt: Date
    let recordCount: Int
}

// MARK: - NSLockProtected

/// Simple lock-protected value wrapper for nonisolated access.
private final class NSLockProtected<Value>: @unchecked Sendable {
    // MARK: Lifecycle

    init(_ value: Value) {
        self.value = value
    }

    // MARK: Internal

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.withLock { body(&value) }
    }

    // MARK: Private

    private let lock = NSLock()
    private var value: Value
}
