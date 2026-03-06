// Polo Notes Store
//
// Downloads and caches Polo notes from configured sources for CWSweep.
// Sources are synced from Carrier Wave (iOS) via iCloud KVS.

import CarrierWaveCore
import Foundation

// MARK: - PoloNotesStore

/// Manages Polo callsign notes for CWSweep, using iCloud KVS for source config sync.
actor PoloNotesStore {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = PoloNotesStore()

    /// KVS key matching the iOS app's sync key
    static let kvsKey = "v1.callsignNotesSources"

    /// Ensure notes are loaded, loading from disk cache or downloading if needed
    func ensureLoaded() async {
        guard !isLoaded else {
            return
        }
        isLoaded = true

        // Try disk cache first
        if loadFromDisk() {
            // Check staleness in background
            Task { await refreshIfStale() }
            return
        }

        // No disk cache — download fresh
        await downloadAll()
    }

    /// Force re-download from all sources (e.g., after KVS config change)
    func forceRefresh() async {
        await downloadAll()
    }

    /// Look up Polo notes for a callsign
    func info(for callsign: String) -> PoloNotesEntry? {
        entries[callsign.uppercased()]
    }

    /// Current source configs from iCloud KVS
    func sourceConfigs() -> [CallsignNotesSourceConfig] {
        readSourceConfigs()
    }

    // MARK: Private

    private struct DiskCache: Codable {
        let downloadedAt: Date
        let entries: [String: CodableEntry]
    }

    private struct CodableEntry: Codable {
        // MARK: Lifecycle

        init(from entry: PoloNotesEntry) {
            callsign = entry.callsign
            emoji = entry.emoji
            name = entry.name
            note = entry.note
        }

        // MARK: Internal

        let callsign: String
        let emoji: String?
        let name: String?
        let note: String?

        func toEntry() -> PoloNotesEntry {
            PoloNotesEntry(callsign: callsign, emoji: emoji, name: name, note: note)
        }
    }

    private static let stalenessInterval: TimeInterval = 24 * 60 * 60 // 24 hours

    private var entries: [String: PoloNotesEntry] = [:]
    private var isLoaded = false
    private var downloadedAt: Date?

    private var cacheFileURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("polo_notes.json")
    }

    // MARK: - Source Config

    private func readSourceConfigs() -> [CallsignNotesSourceConfig] {
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: Self.kvsKey) else {
            // Fall back to UserDefaults (for non-iCloud scenarios)
            guard let localData = UserDefaults.standard.data(forKey: "callsignNotesSources") else {
                return []
            }
            return (try? JSONDecoder().decode([CallsignNotesSourceConfig].self, from: localData)) ?? []
        }
        return (try? JSONDecoder().decode([CallsignNotesSourceConfig].self, from: data)) ?? []
    }

    // MARK: - Download

    private func downloadAll() async {
        let configs = readSourceConfigs().filter(\.isEnabled)
        guard !configs.isEmpty else {
            entries = [:]
            saveToDisk()
            return
        }

        let urls = configs.compactMap { URL(string: $0.url) }
        guard !urls.isEmpty else {
            return
        }

        var merged: [String: PoloNotesEntry] = [:]

        await withTaskGroup(of: [String: PoloNotesEntry].self) { group in
            for url in urls {
                group.addTask {
                    await (try? PoloNotesParser.load(from: url)) ?? [:]
                }
            }
            for await result in group {
                merged.merge(result) { _, new in new }
            }
        }

        entries = merged
        downloadedAt = Date()
        saveToDisk()
    }

    private func refreshIfStale() async {
        guard let downloadedAt else {
            await downloadAll()
            return
        }
        if Date().timeIntervalSince(downloadedAt) > Self.stalenessInterval {
            await downloadAll()
        }
    }

    // MARK: - Disk Cache

    private func loadFromDisk() -> Bool {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let cache = try? JSONDecoder().decode(DiskCache.self, from: data)
        else {
            return false
        }

        entries = cache.entries.mapValues { $0.toEntry() }
        downloadedAt = cache.downloadedAt
        return !entries.isEmpty
    }

    private func saveToDisk() {
        let cache = DiskCache(
            downloadedAt: downloadedAt ?? Date(),
            entries: entries.mapValues { CodableEntry(from: $0) }
        )
        guard let data = try? JSONEncoder().encode(cache) else {
            return
        }
        try? data.write(to: cacheFileURL, options: .atomic)
    }
}
