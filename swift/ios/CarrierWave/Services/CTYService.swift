// CTY.dat Download Service
//
// Downloads and caches the AD1C CTY.dat country file for DXCC entity resolution.
// Refreshes weekly or on-demand. Cached to app support directory.

import CarrierWaveCore
import Foundation

// MARK: - CTYService

/// Downloads, caches, and serves CTY.dat DXCC entity lookups.
actor CTYService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = CTYService()

    /// The parsed database, if loaded.
    func database() async -> CTYDatabase? {
        if let db = cachedDatabase {
            return db
        }
        return await loadOrDownload()
    }

    /// Look up DXCC entity for a callsign.
    func lookup(_ callsign: String) async -> CarrierWaveCore.DXCCEntity? {
        guard let db = await database() else {
            return nil
        }
        return db.lookup(callsign)
    }

    /// Force a fresh download regardless of cache age.
    func refresh() async -> CTYDatabase? {
        await download()
    }

    /// Raw CTY.dat text for consumers that parse it themselves (the Rust
    /// spot engine). Ensures the cache is populated first.
    func rawDatabaseContent() async -> String? {
        guard await database() != nil else {
            return nil
        }
        return try? String(contentsOf: cacheFileURL, encoding: .utf8)
    }

    // MARK: Private

    private static let downloadURL = "https://www.country-files.com/bigcty/cty.dat"
    private static let fallbackURL = "https://www.country-files.com/cty/cty.dat"

    /// Maximum cache age before re-downloading (7 days).
    private static let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60

    private var cachedDatabase: CTYDatabase?
    private var isLoading = false

    private var cacheFileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("CTY", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cty.dat")
    }

    private func loadOrDownload() async -> CTYDatabase? {
        guard !isLoading else {
            return nil
        }
        isLoading = true
        defer { isLoading = false }

        // Try loading from cache first
        if let db = loadFromCache() {
            cachedDatabase = db
            // Trigger background refresh if stale
            if isCacheStale() {
                Task { [weak self] in
                    _ = await self?.download()
                }
            }
            return db
        }

        // No cache — must download
        return await download()
    }

    private func loadFromCache() -> CTYDatabase? {
        let url = cacheFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }
        let db = CTYParser.parse(content)
        guard !db.entities.isEmpty else {
            return nil
        }
        return db
    }

    private func isCacheStale() -> Bool {
        let url = cacheFileURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date
        else {
            return true
        }
        return Date().timeIntervalSince(modified) > Self.maxCacheAge
    }

    private func download() async -> CTYDatabase? {
        // Try primary URL first, then fallback
        for urlString in [Self.downloadURL, Self.fallbackURL] {
            guard let url = URL(string: urlString) else {
                continue
            }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let content = String(data: data, encoding: .utf8)
                else {
                    continue
                }

                let db = CTYParser.parse(content)
                guard !db.entities.isEmpty else {
                    continue
                }

                // Save to cache
                try? data.write(to: cacheFileURL, options: .atomic)
                cachedDatabase = db
                return db
            } catch {
                continue
            }
        }

        // Download failed — try stale cache as last resort
        if let db = loadFromCache() {
            cachedDatabase = db
            return db
        }

        return nil
    }
}
