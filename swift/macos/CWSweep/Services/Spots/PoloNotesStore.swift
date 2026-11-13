// Polo Notes Store
//
// Downloads and caches Polo notes from configured sources for CWSweep.
// Sources are synced from Carrier Wave (iOS) via iCloud KVS.

import CarrierWaveCore
import CarrierWaveData
import Foundation
import OSLog

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
            await seedQueryStore()
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

    /// All emoji from all matching sources for a callsign
    func combinedEmoji(for callsign: String) -> String? {
        let key = callsign.uppercased()
        guard let emojis = emojisByCallsign[key], !emojis.isEmpty else {
            return entries[key]?.emoji
        }
        return emojis.joined()
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

        init(from entry: PoloNotesEntry, allEmojis: [String]? = nil) {
            callsign = entry.callsign
            emoji = entry.emoji
            name = entry.name
            note = entry.note
            self.allEmojis = allEmojis
        }

        // MARK: Internal

        let callsign: String
        let emoji: String?
        let name: String?
        let note: String?
        let allEmojis: [String]?

        func toEntry() -> PoloNotesEntry {
            PoloNotesEntry(callsign: callsign, emoji: emoji, name: name, note: note)
        }
    }

    private static let stalenessInterval: TimeInterval = 24 * 60 * 60 // 24 hours

    private var entries: [String: PoloNotesEntry] = [:]
    private var emojisByCallsign: [String: [String]] = [:]
    private var isLoaded = false
    private var downloadedAt: Date?

    private var cacheFileURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("polo_notes.json")
    }

    /// Push the current entries snapshot to the SQL mirror as a full replace.
    /// Polo notes are downloaded as opaque list files; we don't have per-entry
    /// diffs, so the simplest correct semantics is wipe + insert in one tx.
    private func seedQueryStore() async {
        guard let store = QueryFacade.current else {
            return
        }
        let rows = entries.values.map { entry in
            PoloNoteRow(
                callsign: entry.callsign,
                tag: entry.emoji ?? entry.name,
                body: entry.note ?? entry.name
            )
        }
        do {
            try await store.seedPoloNotes(rows)
        } catch {
            Logger(subsystem: "com.jsvana.CWSweep", category: "PoloNotesStore")
                .error("seedPoloNotes failed: \(error.localizedDescription, privacy: .public)")
        }
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
            emojisByCallsign = [:]
            saveToDisk()
            return
        }

        let urls = configs.compactMap { URL(string: $0.url) }
        guard !urls.isEmpty else {
            return
        }

        var merged: [String: PoloNotesEntry] = [:]
        var allEmojis: [String: [String]] = [:]

        await withTaskGroup(of: [String: PoloNotesEntry].self) { group in
            for url in urls {
                group.addTask {
                    await (try? PoloNotesParser.load(from: url)) ?? [:]
                }
            }
            for await sourceResult in group {
                for (callsign, entry) in sourceResult {
                    if let emoji = entry.emoji, !emoji.isEmpty {
                        allEmojis[callsign, default: []].append(emoji)
                    }
                }
                merged.merge(sourceResult) { existing, _ in existing }
            }
        }

        entries = merged
        emojisByCallsign = allEmojis
        downloadedAt = Date()
        saveToDisk()
        await seedQueryStore()
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

        // Restore emojisByCallsign from cached allEmojis
        var emojis: [String: [String]] = [:]
        for (callsign, cached) in cache.entries {
            if let allEmojis = cached.allEmojis, !allEmojis.isEmpty {
                emojis[callsign] = allEmojis
            }
        }
        emojisByCallsign = emojis

        return !entries.isEmpty
    }

    private func saveToDisk() {
        let cache = DiskCache(
            downloadedAt: downloadedAt ?? Date(),
            entries: entries.mapValues { entry in
                CodableEntry(
                    from: entry,
                    allEmojis: emojisByCallsign[entry.callsign]
                )
            }
        )
        guard let data = try? JSONEncoder().encode(cache) else {
            return
        }
        try? data.write(to: cacheFileURL, options: .atomic)
    }
}
