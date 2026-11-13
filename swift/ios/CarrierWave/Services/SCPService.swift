import CarrierWaveData
import Foundation
import SwiftData

// MARK: - SCPService

/// Downloads, caches, and serves the MASTER.SCP callsign database.
/// The database provides real-time callsign suggestions as the user types.
@MainActor
@Observable
final class SCPService {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    static let shared = SCPService()

    /// The loaded SCP database. Empty until `loadAndRefresh()` completes.
    private(set) var database = SCPDatabase(callsigns: [])

    /// Whether a download is in progress.
    private(set) var isLoading = false

    /// When the remote file was last checked (not necessarily updated).
    private(set) var lastChecked: Date? {
        get { UserDefaults.standard.object(forKey: lastCheckedKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastCheckedKey) }
    }

    /// Release in-memory data under memory pressure. Reloads on next `loadAndRefresh`.
    func clearForMemoryPressure() {
        database = SCPDatabase(callsigns: [])
    }

    /// Load from disk cache, then check remote if stale (>7 days).
    /// Disk I/O and parsing run off main thread — only the final assignment
    /// hops to @MainActor for the @Observable mutation.
    func loadAndRefresh() async {
        StartupProfiler.shared.record("scp.diskLoad")
        let cached = await Task.detached {
            self.loadFromDisk()
        }.value
        if let cached {
            database = cached
        }
        StartupProfiler.shared.record("scp.diskLoaded")

        // Check remote if stale
        let staleInterval: TimeInterval = 7 * 24 * 60 * 60
        let needsRefresh = lastChecked.map {
            Date().timeIntervalSince($0) > staleInterval
        } ?? true

        if needsRefresh {
            StartupProfiler.shared.record("scp.fetchRemote")
            await fetchRemote()
            StartupProfiler.shared.record("scp.fetchRemoteDone")
        }
    }

    /// Force re-download from remote, ignoring cache freshness.
    func forceRefresh() async {
        await fetchRemote()
    }

    /// Augment the database with callsigns the user has worked 2+ times.
    /// Runs the QSO query and merge on a background thread to avoid blocking UI.
    func loadUserCallsigns(container: ModelContainer) async {
        StartupProfiler.shared.record("scp.userCallsigns.fetch")
        let currentDB = database
        let merged = await Task.detached {
            StartupProfiler.shared.record("scp.userCallsigns.query")
            let repeatCallsigns = Self.fetchRepeatCallsigns(container: container)
            StartupProfiler.shared.record("scp.userCallsigns.queryDone")
            guard !repeatCallsigns.isEmpty else {
                return nil as SCPDatabase?
            }
            return currentDB.merging(additionalCallsigns: repeatCallsigns)
        }.value

        if let merged {
            database = merged
        }
        StartupProfiler.shared.record("scp.userCallsigns.merged")
    }

    // MARK: Private

    private static let remoteURL = URL(string: "http://www.supercheckpartial.com/MASTER.SCP")!

    private let cacheFileName = "MASTER.SCP"
    private let etagKey = "scpETag"
    private let lastCheckedKey = "scpLastChecked"

    nonisolated private var cacheFileURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent(cacheFileName)
    }

    private var storedETag: String? {
        get { UserDefaults.standard.string(forKey: etagKey) }
        set { UserDefaults.standard.set(newValue, forKey: etagKey) }
    }

    /// Fetch callsigns worked 2+ times from QSO history (runs off main thread).
    /// Uses small batches with autoreleasepool to force SwiftData to release
    /// managed objects between iterations, capping peak memory.
    nonisolated private static func fetchRepeatCallsigns(
        container: ModelContainer
    ) -> [String] {
        let predicate = #Predicate<QSO> { qso in
            !qso.isHidden
                && qso.mode != "WEATHER"
                && qso.mode != "SOLAR"
                && qso.mode != "NOTE"
        }

        let batchSize = 200
        var offset = 0
        var counts: [String: Int] = [:]

        while true {
            // autoreleasepool forces Obj-C bridged objects (SwiftData internals)
            // to release between batches, preventing memory accumulation.
            let result: (callsigns: [String], count: Int)? = autoreleasepool {
                let context = ModelContext(container)
                context.autosaveEnabled = false
                let descriptor = BoundedDescriptor<QSO>(
                    predicate: predicate,
                    limit: batchSize,
                    offset: offset
                )

                guard let batch = try? context.boundedFetch(descriptor),
                      !batch.isEmpty
                else {
                    return nil
                }
                return (batch.map(\.callsign), batch.count)
            }

            guard let result else {
                break
            }

            for callsign in result.callsigns {
                counts[callsign, default: 0] += 1
            }

            offset += result.count
            if result.count < batchSize {
                break
            }
        }

        return counts.compactMap { callsign, count in
            count >= 2 ? callsign : nil
        }
    }

    nonisolated private func loadFromDisk() -> SCPDatabase? {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        let callsigns = parseCallsigns(text)
        guard !callsigns.isEmpty else {
            return nil
        }
        return SCPDatabase(callsigns: callsigns)
    }

    private func fetchRemote() async {
        isLoading = true
        defer { isLoading = false }

        var request = URLRequest(url: Self.remoteURL)
        if let etag = storedETag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return
            }

            lastChecked = Date()

            if http.statusCode == 304 {
                // Not modified — cache is still fresh
                return
            }

            guard http.statusCode == 200,
                  let text = String(data: data, encoding: .utf8)
            else {
                return
            }

            let callsigns = parseCallsigns(text)
            guard !callsigns.isEmpty else {
                return
            }

            // Write to disk cache
            try? data.write(to: cacheFileURL, options: .atomic)

            // Update ETag
            storedETag = http.value(forHTTPHeaderField: "ETag")

            // Rebuild database
            database = SCPDatabase(callsigns: callsigns)
        } catch {
            // Network errors are silent — stale cache is fine
        }
    }

    nonisolated private func parseCallsigns(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
