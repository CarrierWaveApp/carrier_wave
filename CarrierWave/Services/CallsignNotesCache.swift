// Callsign Notes Cache
//
// Downloads and caches Polo notes from configured sources (clubs and user URLs)
// for fast callsign lookup. Refreshes daily in background.

import Foundation
import SwiftData

// MARK: - CallsignNotesCacheStatus

enum CallsignNotesCacheStatus: Sendable {
    case notLoaded
    case loading
    case loaded(callsignCount: Int, downloadedAt: Date?)
    case downloading
    case failed(String)
}

// MARK: - NotesSourceInfo

/// Info about a notes source (club or user-configured URL)
/// Must be fetched on MainActor and passed to the cache
struct NotesSourceInfo: Sendable {
    let url: URL
    let title: String

    /// Fetch all configured notes sources from SwiftData
    /// Must be called on MainActor
    @MainActor
    static func fetchAll(modelContext: ModelContext) -> [NotesSourceInfo] {
        var sources: [NotesSourceInfo] = []

        // Fetch from clubs
        do {
            let clubDescriptor = FetchDescriptor<Club>()
            let clubs = try modelContext.fetch(clubDescriptor)

            for club in clubs {
                if !club.poloNotesListURL.isEmpty,
                   let url = URL(string: club.poloNotesListURL)
                {
                    sources.append(NotesSourceInfo(url: url, title: club.name))
                }
            }
        } catch {
            print("CallsignNotesCache: Failed to load clubs: \(error)")
        }

        // Fetch from user-configured sources
        do {
            let sourceDescriptor = FetchDescriptor<CallsignNotesSource>(
                predicate: #Predicate { $0.isEnabled }
            )
            let userSources = try modelContext.fetch(sourceDescriptor)

            for source in userSources {
                if let url = URL(string: source.url) {
                    sources.append(NotesSourceInfo(url: url, title: source.title))
                }
            }
        } catch {
            print("CallsignNotesCache: Failed to load callsign notes sources: \(error)")
        }

        return sources
    }
}

// MARK: - CallsignNotesCache

actor CallsignNotesCache {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = CallsignNotesCache()

    /// Current status of the cache (for UI display)
    private(set) var status: CallsignNotesCacheStatus = .notLoaded

    /// Number of callsigns in cache (for display/debugging)
    var callsignCount: Int {
        notes.count
    }

    /// Get callsign info for a callsign (e.g., "W1AW" -> CallsignInfo with emoji/note)
    /// Returns nil if callsign not found or cache not loaded
    func info(for callsign: String) -> CallsignInfo? {
        notes[callsign.uppercased()]
    }

    /// Synchronous callsign lookup for UI use (nonisolated for MainActor access)
    /// Returns nil if callsign not found or cache not yet loaded
    nonisolated func infoSync(for callsign: String) -> CallsignInfo? {
        notes[callsign.uppercased()]
    }

    /// Ensure cache is loaded, loading from disk or downloading if necessary
    /// Call this on app launch or when entering views that need callsign lookup
    /// Sources must be fetched on the main actor and passed in
    func ensureLoaded(sources: [NotesSourceInfo]) async {
        guard !isLoaded else {
            return
        }

        status = .loading

        // Try to load from disk first
        if loadFromDisk() {
            isLoaded = true
            status = .loaded(callsignCount: notes.count, downloadedAt: loadMetadata()?.downloadedAt)
            // Check if refresh needed in background
            Task {
                await refreshIfNeeded(sources: sources)
            }
            return
        }

        // No cache on disk, download
        do {
            status = .downloading
            try await downloadAndCache(sources: sources)
            isLoaded = true
            status = .loaded(callsignCount: notes.count, downloadedAt: loadMetadata()?.downloadedAt)
        } catch {
            print("CallsignNotesCache: Failed to download notes: \(error)")
            status = .failed(error.localizedDescription)
            isLoaded = true // Mark loaded to avoid repeated attempts
        }
    }

    /// Check if cache is stale and refresh if needed (non-blocking)
    /// Refreshes if cache is older than 24 hours
    func refreshIfNeeded(sources: [NotesSourceInfo]) async {
        guard let metadata = loadMetadata() else {
            // No metadata, need to download
            status = .downloading
            do {
                try await downloadAndCache(sources: sources)
                status = .loaded(
                    callsignCount: notes.count, downloadedAt: loadMetadata()?.downloadedAt
                )
            } catch {
                status = .failed(error.localizedDescription)
            }
            return
        }

        let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        if metadata.downloadedAt < oneDayAgo {
            status = .downloading
            do {
                try await downloadAndCache(sources: sources)
                status = .loaded(
                    callsignCount: notes.count, downloadedAt: loadMetadata()?.downloadedAt
                )
            } catch {
                // Keep old data, just update status to show we tried
                status = .loaded(callsignCount: notes.count, downloadedAt: metadata.downloadedAt)
            }
        }
    }

    /// Force refresh the cache, throwing on failure
    func forceRefresh(sources: [NotesSourceInfo]) async throws {
        status = .downloading
        do {
            try await downloadAndCache(sources: sources)
            status = .loaded(callsignCount: notes.count, downloadedAt: loadMetadata()?.downloadedAt)
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
    func getStatus() -> CallsignNotesCacheStatus {
        status
    }

    /// Clear the cache (for testing or user-initiated clear)
    func clear() {
        notes = [:]
        isLoaded = false
        status = .notLoaded
        try? FileManager.default.removeItem(at: cacheFileURL)
        try? FileManager.default.removeItem(at: metadataFileURL)
    }

    // MARK: Private

    // MARK: - Types

    private struct NotesEntry {
        let title: String
        let emoji: String?
        let note: String?
        let name: String?
    }

    private static let cacheFileName = "callsign_notes.json"
    private static let metadataFileName = "callsign_notes_metadata.json"

    /// Thread-safe notes lookup using nonisolated(unsafe) for synchronous access
    /// Safe because: writes only happen during ensureLoaded() which completes before reads
    nonisolated(unsafe) private var notes: [String: CallsignInfo] = [:] // callsign -> info
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

    // MARK: - Disk Operations

    private func loadFromDisk() -> Bool {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            return false
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let cached = try JSONDecoder().decode([String: CachedCallsignInfo].self, from: data)
            notes = cached.mapValues { $0.toCallsignInfo() }
            return !notes.isEmpty
        } catch {
            print("CallsignNotesCache: Failed to load from disk: \(error)")
            return false
        }
    }

    private func saveToDisk() {
        do {
            let cached = notes.mapValues { CachedCallsignInfo(from: $0) }
            let data = try JSONEncoder().encode(cached)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            print("CallsignNotesCache: Failed to save to disk: \(error)")
        }
    }

    private func loadMetadata() -> CallsignNotesCacheMetadata? {
        guard let data = try? Data(contentsOf: metadataFileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(CallsignNotesCacheMetadata.self, from: data)
    }

    private func saveMetadata(callsignCount: Int, sourceCount: Int) {
        let metadata = CallsignNotesCacheMetadata(
            downloadedAt: Date(),
            callsignCount: callsignCount,
            sourceCount: sourceCount
        )
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: metadataFileURL)
        }
    }

    // MARK: - Download and Parse

    private func downloadAndCache(sources: [NotesSourceInfo]) async throws {
        guard !sources.isEmpty else {
            notes = [:]
            saveToDisk()
            saveMetadata(callsignCount: 0, sourceCount: 0)
            return
        }

        let entriesByCallsign = await downloadAllSources(sources)
        let merged = mergeEntries(entriesByCallsign)

        notes = merged
        saveToDisk()
        saveMetadata(callsignCount: merged.count, sourceCount: sources.count)

        print(
            "CallsignNotesCache: Downloaded \(merged.count) callsigns from \(sources.count) sources"
        )
    }

    /// Download notes from all sources concurrently
    private func downloadAllSources(
        _ sources: [NotesSourceInfo]
    ) async -> [String: [NotesEntry]] {
        var entriesByCallsign: [String: [NotesEntry]] = [:]

        await withTaskGroup(of: (String, [String: CallsignInfo]).self) { group in
            for source in sources {
                group.addTask {
                    let entries = await (try? PoloNotesParser.load(from: source.url)) ?? [:]
                    return (source.title, entries)
                }
            }

            for await (sourceTitle, entries) in group {
                for (callsign, info) in entries {
                    var existing = entriesByCallsign[callsign] ?? []
                    existing.append(
                        NotesEntry(
                            title: sourceTitle,
                            emoji: info.emoji,
                            note: info.note,
                            name: info.name
                        )
                    )
                    entriesByCallsign[callsign] = existing
                }
            }
        }

        return entriesByCallsign
    }

    /// Merge entries from multiple sources into CallsignInfo objects
    private func mergeEntries(_ entriesByCallsign: [String: [NotesEntry]]) -> [String: CallsignInfo] {
        var merged: [String: CallsignInfo] = [:]

        for (callsign, entries) in entriesByCallsign {
            let sortedEntries = entries.sorted { $0.title < $1.title }
            let allEmojis = sortedEntries.compactMap(\.emoji).filter { !$0.isEmpty }
            let sourceTitles = sortedEntries.map(\.title)
            let name = sortedEntries.compactMap(\.name).first
            let note = sortedEntries.compactMap(\.note).first

            merged[callsign] = CallsignInfo(
                callsign: callsign,
                name: name,
                note: note,
                emoji: allEmojis.first,
                source: .poloNotes,
                allEmojis: allEmojis.isEmpty ? nil : allEmojis,
                matchingSources: sourceTitles
            )
        }

        return merged
    }
}

// MARK: - CallsignNotesCacheMetadata

/// Metadata for the callsign notes cache - must be nonisolated for actor use
private struct CallsignNotesCacheMetadata: Sendable {
    let downloadedAt: Date
    let callsignCount: Int
    let sourceCount: Int
}

// MARK: Codable

extension CallsignNotesCacheMetadata: Codable {
    enum CodingKeys: String, CodingKey {
        case downloadedAt
        case callsignCount
        case sourceCount
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        downloadedAt = try container.decode(Date.self, forKey: .downloadedAt)
        callsignCount = try container.decode(Int.self, forKey: .callsignCount)
        sourceCount = try container.decode(Int.self, forKey: .sourceCount)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(downloadedAt, forKey: .downloadedAt)
        try container.encode(callsignCount, forKey: .callsignCount)
        try container.encode(sourceCount, forKey: .sourceCount)
    }
}

// MARK: - CachedCallsignInfo

/// Simplified Codable representation for disk caching - must be nonisolated for actor use
private struct CachedCallsignInfo: Sendable {
    // MARK: Lifecycle

    nonisolated init(from info: CallsignInfo) {
        callsign = info.callsign
        name = info.name
        note = info.note
        emoji = info.emoji
        allEmojis = info.allEmojis
        matchingSources = info.matchingSources
    }

    // MARK: Internal

    let callsign: String
    let name: String?
    let note: String?
    let emoji: String?
    let allEmojis: [String]?
    let matchingSources: [String]?

    nonisolated func toCallsignInfo() -> CallsignInfo {
        CallsignInfo(
            callsign: callsign,
            name: name,
            note: note,
            emoji: emoji,
            source: .poloNotes,
            allEmojis: allEmojis,
            matchingSources: matchingSources
        )
    }
}

// MARK: Codable

extension CachedCallsignInfo: Codable {
    enum CodingKeys: String, CodingKey {
        case callsign
        case name
        case note
        case emoji
        case allEmojis
        case matchingSources
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callsign = try container.decode(String.self, forKey: .callsign)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        allEmojis = try container.decodeIfPresent([String].self, forKey: .allEmojis)
        matchingSources = try container.decodeIfPresent([String].self, forKey: .matchingSources)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callsign, forKey: .callsign)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(emoji, forKey: .emoji)
        try container.encodeIfPresent(allEmojis, forKey: .allEmojis)
        try container.encodeIfPresent(matchingSources, forKey: .matchingSources)
    }
}
