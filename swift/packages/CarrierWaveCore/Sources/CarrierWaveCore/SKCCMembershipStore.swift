// SKCC Membership Store
//
// Downloads and caches the SKCC (Straight Key Century Club) roster so spots
// can be enriched with member numbers and award levels. The roster lives at
// https://www.skccgroup.com/membership_data/skccdata.txt and is the same
// source used by K7MJG's `skcc_skimmer` Python tool.

import Foundation
import OSLog

private let logger = Logger(subsystem: "app.carrierwave.core", category: "SKCCMembershipStore")

// MARK: - SKCCMembershipStore

/// Actor-isolated store of SKCC roster entries, refreshed at most once a day.
/// Lookups are exposed via a synchronous `nonisolated` API backed by an
/// `NSLock`, so spot enrichment can run inline without awaiting the actor.
public actor SKCCMembershipStore {
    // MARK: Lifecycle

    private init() {}

    // MARK: Public

    /// Status of the last load attempt for surfacing in settings later.
    public enum Status: Equatable, Sendable {
        case notLoaded
        case loading
        case loaded(count: Int, downloadedAt: Date?)
        case failed(String)
    }

    public static let shared = SKCCMembershipStore()

    /// Roster URL (pipe-delimited, one record per line). Format documented
    /// at https://www.skccgroup.com/about_skcc/data_files.htm.
    public static let rosterURL = URL(string: "https://www.skccgroup.com/membership_data/skccdata.txt")!

    public private(set) var status: Status = .notLoaded

    public var memberCount: Int {
        storage.withLock { $0.byCallsign.count }
    }

    /// Load from disk if available, otherwise download. Refreshes in the
    /// background if the cached roster is older than `refreshInterval`.
    public func ensureLoaded() async {
        guard !isLoaded else {
            return
        }
        status = .loading

        if let cached = loadDiskCache() {
            storage.withLock { $0 = cached }
            isLoaded = true
            status = .loaded(count: cached.byCallsign.count, downloadedAt: loadMetadataDate())
            Task { await refreshIfStale() }
            return
        }

        await downloadRoster()
        isLoaded = true
    }

    /// Force a network refresh.
    public func forceRefresh() async {
        await downloadRoster()
        isLoaded = true
    }

    /// Every callsign key in the roster index (current and prior calls,
    /// normalized). Used to seed the spot engine's `scope.club_members`
    /// table for SQL-side club filtering.
    nonisolated public func allCallsigns() -> [String] {
        storage.withLock { state in
            Array(state.byCallsign.keys)
        }
    }

    /// Synchronous lookup by callsign (current call or any prior call recorded
    /// in the roster). Callsigns are normalized to uppercase / no `/` suffix.
    nonisolated public func member(for callsign: String) -> SKCCMember? {
        let key = Self.normalize(callsign)
        guard !key.isEmpty else {
            return nil
        }
        return storage.withLock { state in
            state.byCallsign[key]
        }
    }

    // MARK: Internal

    /// Mutable state guarded by `NSLock` so synchronous lookups can run from
    /// any thread without awaiting the actor.
    struct CacheState: Codable {
        var byCallsign: [String: SKCCMember] = [:]
    }

    struct CacheMetadata: Codable {
        let downloadedAt: Date
        let recordCount: Int
    }

    static let cacheFileName = "skcc_roster.json"
    static let metadataFileName = "skcc_roster_metadata.json"
    static let refreshInterval: TimeInterval = 24 * 60 * 60 // 24 hours

    static var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    nonisolated let storage = NSLockProtected(CacheState())
    var isLoaded = false

    static func normalize(_ callsign: String) -> String {
        let upper = callsign.uppercased()
        if let slash = upper.firstIndex(of: "/") {
            return String(upper[..<slash])
        }
        return upper
    }
}

// MARK: - SKCCMembershipStore + Parsing

public extension SKCCMembershipStore {
    /// Parse a roster file body into `SKCCMember` records.
    /// The file uses `|` as a delimiter and may include a single header line.
    /// Delegates to the shared Rust parser (`cw_domain::skcc`).
    static func parseRoster(_ body: String) -> [SKCCMember] {
        parseSkccRoster(body: body).map(SKCCMember.init(ffi:))
    }

    /// Parse a single roster line, returning nil if the line cannot be parsed.
    /// Delegates to the shared Rust parser (`cw_domain::skcc`).
    static func parseMemberLine(_ line: String) -> SKCCMember? {
        parseSkccMemberLine(line: line).map(SKCCMember.init(ffi:))
    }

    /// Build the `byCallsign` index used for lookups.
    static func buildIndex(from members: [SKCCMember]) -> [String: SKCCMember] {
        var index: [String: SKCCMember] = [:]
        index.reserveCapacity(members.count * 2)
        for member in members {
            index[member.callsign] = member
            for other in member.otherCallsigns where index[other] == nil {
                index[other] = member
            }
        }
        return index
    }
}

// MARK: - SKCCMembershipStore + DiskIO

extension SKCCMembershipStore {
    func downloadRoster() async {
        do {
            var request = URLRequest(url: Self.rosterURL)
            request.setValue("text/plain, */*", forHTTPHeaderField: "Accept")
            request.setValue(
                "CarrierWave/1.0 (Amateur Radio Logger)",
                forHTTPHeaderField: "User-Agent"
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse,
                  httpResp.statusCode == 200
            else {
                throw URLError(.badServerResponse)
            }
            guard let body = String(data: data, encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }
            let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBody.hasPrefix("<!"), !trimmedBody.hasPrefix("<html") else {
                throw URLError(.badServerResponse)
            }

            let members = Self.parseRoster(body)
            guard !members.isEmpty else {
                throw URLError(.cannotParseResponse)
            }
            let index = Self.buildIndex(from: members)
            storage.withLock { $0.byCallsign = index }
            saveDiskCache()
            saveMetadata(recordCount: members.count)

            status = .loaded(count: members.count, downloadedAt: Date())
            logger.info("Downloaded SKCC roster: \(members.count) members")
        } catch {
            logger.error("SKCC roster download failed: \(error.localizedDescription)")
            status = .failed(error.localizedDescription)
        }
    }

    func refreshIfStale() async {
        guard let date = loadMetadataDate() else {
            await downloadRoster()
            return
        }
        if date < Date().addingTimeInterval(-Self.refreshInterval) {
            await downloadRoster()
        }
    }

    func saveDiskCache() {
        let snapshot = storage.withLock { $0 }
        let url = Self.cacheDir.appendingPathComponent(Self.cacheFileName)
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.warning("Failed to save SKCC cache: \(error.localizedDescription)")
        }
    }

    func loadDiskCache() -> CacheState? {
        let url = Self.cacheDir.appendingPathComponent(Self.cacheFileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CacheState.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    func saveMetadata(recordCount: Int) {
        let url = Self.cacheDir.appendingPathComponent(Self.metadataFileName)
        let meta = CacheMetadata(downloadedAt: Date(), recordCount: recordCount)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: url)
        }
    }

    func loadMetadataDate() -> Date? {
        let url = Self.cacheDir.appendingPathComponent(Self.metadataFileName)
        guard let data = try? Data(contentsOf: url),
              let meta = try? JSONDecoder().decode(CacheMetadata.self, from: data)
        else {
            return nil
        }
        return meta.downloadedAt
    }
}

// MARK: - NSLockProtected

/// Lock-protected value wrapper enabling synchronous access from any thread.
final class NSLockProtected<Value>: @unchecked Sendable {
    // MARK: Lifecycle

    init(_ value: Value) {
        self.value = value
    }

    // MARK: Internal

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock { body(&value) }
    }

    // MARK: Private

    private let lock = NSLock()
    private var value: Value
}
