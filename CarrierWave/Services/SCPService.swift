import CarrierWaveCore
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

    /// When the remote file was last checked (not necessarily updated).
    private(set) var lastChecked: Date? {
        get { UserDefaults.standard.object(forKey: lastCheckedKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastCheckedKey) }
    }

    /// Whether a download is in progress.
    private(set) var isLoading = false

    /// Load from disk cache, then check remote if stale (>7 days).
    func loadAndRefresh() async {
        // Load cached file first for instant availability
        if let cached = loadFromDisk() {
            database = cached
        }

        // Check remote if stale
        let staleInterval: TimeInterval = 7 * 24 * 60 * 60
        let needsRefresh = lastChecked.map { Date().timeIntervalSince($0) > staleInterval } ?? true

        if needsRefresh {
            await fetchRemote()
        }
    }

    /// Force re-download from remote, ignoring cache freshness.
    func forceRefresh() async {
        await fetchRemote()
    }

    /// Augment the database with callsigns the user has worked 2+ times.
    /// Runs the QSO query on a background context to avoid blocking UI.
    func loadUserCallsigns(container: ModelContainer) async {
        let repeatCallsigns = await Task.detached {
            Self.fetchRepeatCallsigns(container: container)
        }.value

        guard !repeatCallsigns.isEmpty else { return }
        database = database.merging(additionalCallsigns: repeatCallsigns)
    }

    // MARK: Private

    private static let remoteURL = URL(string: "http://www.supercheckpartial.com/MASTER.SCP")!
    private let cacheFileName = "MASTER.SCP"
    private let etagKey = "scpETag"
    private let lastCheckedKey = "scpLastChecked"

    private var cacheFileURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent(cacheFileName)
    }

    private var storedETag: String? {
        get { UserDefaults.standard.string(forKey: etagKey) }
        set { UserDefaults.standard.set(newValue, forKey: etagKey) }
    }

    private func loadFromDisk() -> SCPDatabase? {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        let callsigns = parseCallsigns(text)
        guard !callsigns.isEmpty else { return nil }
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
            guard let http = response as? HTTPURLResponse else { return }

            lastChecked = Date()

            if http.statusCode == 304 {
                // Not modified — cache is still fresh
                return
            }

            guard http.statusCode == 200,
                  let text = String(data: data, encoding: .utf8)
            else { return }

            let callsigns = parseCallsigns(text)
            guard !callsigns.isEmpty else { return }

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

    private func parseCallsigns(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Fetch callsigns worked 2+ times from QSO history (runs off main thread).
    private nonisolated static func fetchRepeatCallsigns(
        container: ModelContainer
    ) -> [String] {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let predicate = #Predicate<QSO> { qso in
            !qso.isHidden
                && qso.mode != "WEATHER"
                && qso.mode != "SOLAR"
                && qso.mode != "NOTE"
        }
        var descriptor = FetchDescriptor<QSO>(predicate: predicate)
        descriptor.propertiesToFetch = [\.callsign]

        guard let qsos = try? context.fetch(descriptor) else { return [] }

        // Count occurrences per callsign
        var counts: [String: Int] = [:]
        counts.reserveCapacity(qsos.count / 2)
        for qso in qsos {
            counts[qso.callsign, default: 0] += 1
        }

        return counts.compactMap { callsign, count in
            count >= 2 ? callsign : nil
        }
    }
}
