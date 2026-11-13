import CarrierWaveCore
import CarrierWaveData
import Foundation
import OSLog
import SwiftData

// MARK: - ClubsFetch

/// Bounded fetch size for club/member reads (matches the Rust store's limit).
/// In a `nonisolated` namespace so the off-main snapshot builder can read it
/// under the project's default-MainActor isolation.
nonisolated private enum ClubsFetch {
    static let limit: Int64 = 1_000
}

// MARK: - ClubsSyncService

/// Clubs are backed entirely by the shared Rust core: the encrypted `FieldStore`
/// holds the club + membership cache, and `ClubsApi` (cw-net) does the
/// fetch→parse→store→reconcile sync. This service is the @MainActor facade the
/// SwiftUI layer talks to — it keeps the same `clubs(for:)` / `callsigns(inClub:)`
/// string lookups every spot/QSO row uses (rebuilt in-memory from the store after
/// each sync for O(1) main-thread reads) and publishes the `[FfiClub]` list and
/// per-club members the dedicated club views render.
@Observable
@MainActor
final class ClubsSyncService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    /// Shared singleton — call `configure()` from the app entry point.
    static let shared = ClubsSyncService()

    var isSyncing = false
    var syncError: String?

    /// The user's clubs (cached, name-sorted). Drives the clubs list views.
    private(set) var clubs: [FfiClub] = []

    /// In-memory set of all club member callsigns for O(1) membership checks.
    private(set) var clubMemberCallsigns: Set<String> = []

    /// Map of uppercased callsign -> [club name] for badges in logger/QSO rows.
    private(set) var clubsByCallsign: [String: [String]] = [:]

    /// Map of club name -> member callsigns, for finding friends in a club.
    private(set) var callsignsByClub: [String: Set<String>] = [:]

    /// Monotonic counter bumped every time a sync changes the roster cache.
    /// Persisted so derived data (session brag sheet club counts) can tell
    /// whether it was computed against the current roster.
    private(set) var membershipRevision: Int = UserDefaults.standard.integer(
        forKey: ClubsSyncService.membershipRevisionKey
    )

    /// Configure the shared instance. Loads the cache from the Rust store on a
    /// background task so it never blocks the scene-update window.
    func configure() {
        Task { await reloadFromStore() }
    }

    /// Back-compat shim: the SwiftData container is no longer used (clubs live in
    /// the Rust store). Kept so the single app-startup call site is unchanged.
    func configure(container _: ModelContainer) {
        configure()
    }

    // MARK: - Lookups

    /// Club names the callsign belongs to (from the in-memory cache).
    func clubs(for callsign: String) -> [String] {
        clubsByCallsign[callsign.uppercased()] ?? []
    }

    /// All member callsigns in a club by name (from the in-memory cache).
    func callsigns(inClub clubName: String) -> Set<String> {
        callsignsByClub[clubName] ?? []
    }

    /// A cached club by its server id (UUID string).
    func club(id: String) -> FfiClub? {
        clubs.first { $0.id == id }
    }

    /// Members of a club, loaded from the Rust store off the main thread.
    func members(inClubId clubId: String) async -> [FfiClubMember] {
        guard let store = try? await CwStoreProvider.shared.store() else {
            return []
        }
        return await Task.detached {
            (try? store.fetchClubMembers(
                filter: FfiClubMemberFilter(clubId: clubId, callsign: nil),
                limit: ClubsFetch.limit,
                offset: 0
            )) ?? []
        }.value
    }

    /// The operator's locally-entered member number for a club, if any.
    func memberNumber(clubId: String, callsign: String) async -> String? {
        await members(inClubId: clubId)
            .first { $0.callsign.caseInsensitiveCompare(callsign) == .orderedSame }?
            .number
    }

    /// Set (or clear) the operator's local-only member number for a club.
    func setMemberNumber(clubId: String, callsign: String, number: String?) async {
        guard let store = try? await CwStoreProvider.shared.store() else {
            return
        }
        await Task.detached {
            try? store.setClubMemberNumber(
                clubId: clubId,
                callsign: callsign,
                number: number?.isEmpty == true ? nil : number
            )
        }.value
    }

    // MARK: - Sync

    /// Sync the user's clubs + membership cache via the Rust `ClubsApi`, then
    /// rebuild the in-memory lookups from the store.
    func syncClubs(sourceURL _: String) async throws {
        // Cooldown: skip if synced within the last minute.
        let now = Date()
        if let last = lastSyncDate, now.timeIntervalSince(last) < syncCooldownSeconds {
            return
        }
        guard let bearer = await resolvedClient.ensureAuthToken() else {
            throw ClubsSyncError.notAuthenticated
        }
        let api = try await ensureApi()

        isSyncing = true
        syncError = nil
        // Suspension while the membership apply holds the cw-store SQLite lock
        // is a 0xdead10cc RunningBoard kill; the apply is ETag-gated and
        // idempotent, so if the grant expires the next sync resumes cleanly.
        let suspensionGuard = BackgroundTaskAssertion(name: "ClubsSyncService.syncClubs")
        defer {
            suspensionGuard.release()
            isSyncing = false
        }

        // Prior callsigns so a recently-changed call still sees old memberships.
        let priorCallsigns = CallsignAliasService.shared.getPreviousCallsigns()
        do {
            let summary = try await api.syncClubs(bearer: bearer, priorCallsigns: priorCallsigns)
            await reloadFromStore()
            lastSyncDate = now
            if summary.membershipChanged || summary.clubsChanged {
                bumpMembershipRevision()
            }
        } catch {
            syncError = error.localizedDescription
            throw error
        }
    }

    /// Fetch one club's full detail (members) via the Rust `ClubsApi` and persist
    /// it to the store. The view re-reads members via ``members(inClubId:)``.
    func syncClubDetails(clubId: UUID, sourceURL _: String) async throws {
        guard let bearer = await resolvedClient.ensureAuthToken() else {
            throw ClubsSyncError.notAuthenticated
        }
        let api = try await ensureApi()
        // Roster applies are thousands of member upserts in one commit — hold a
        // background assertion so suspension mid-commit isn't a 0xdead10cc kill.
        let suspensionGuard = BackgroundTaskAssertion(name: "ClubsSyncService.syncClubDetails")
        defer { suspensionGuard.release() }
        try await api.syncClubDetails(bearer: bearer, clubId: clubId.uuidString.lowercased())
    }

    /// A page of a club's activity feed (presentation-only, not cached).
    func fetchActivity(
        clubId: UUID,
        cursor: String?,
        limit: Int64 = 20
    ) async throws -> FfiClubActivityPage {
        guard let bearer = await resolvedClient.ensureAuthToken() else {
            throw ClubsSyncError.notAuthenticated
        }
        let api = try await ensureApi()
        return try await api.fetchActivity(
            bearer: bearer,
            clubId: clubId.uuidString.lowercased(),
            cursor: cursor,
            limit: limit
        )
    }

    /// Real-time member online status for a club.
    func fetchStatus(clubId: UUID) async throws -> [FfiMemberStatus] {
        guard let bearer = await resolvedClient.ensureAuthToken() else {
            throw ClubsSyncError.notAuthenticated
        }
        let api = try await ensureApi()
        return try await api.fetchStatus(bearer: bearer, clubId: clubId.uuidString.lowercased())
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CarrierWave",
        category: "ClubsSync"
    )

    private static let membershipRevisionKey = "clubMembershipRevision"

    /// Record that the roster cache changed and tell interested parties.
    private func bumpMembershipRevision() {
        membershipRevision += 1
        UserDefaults.standard.set(membershipRevision, forKey: Self.membershipRevisionKey)
        Self.logger.info("Club roster cache changed (revision \(self.membershipRevision))")
        NotificationCenter.default.post(name: .clubMembershipDidChange, object: nil)
    }

    private var clubsApi: ClubsApi?
    private var client: ActivitiesClient?
    private var lastSyncDate: Date?
    private let syncCooldownSeconds: TimeInterval = 60

    private var resolvedClient: ActivitiesClient {
        if let client {
            return client
        }
        let newClient = ActivitiesClient()
        client = newClient
        return newClient
    }

    /// Read all clubs + members from the store and assemble the caches. Members
    /// are paged so a large roster never exceeds the store's fetch limit.
    nonisolated private static func buildSnapshot(store: FieldStore) -> ClubSnapshot {
        let clubs = (try? store.fetchClubs(
            filter: FfiClubFilter(callsignMember: nil),
            limit: ClubsFetch.limit,
            offset: 0
        )) ?? []
        let nameById = Dictionary(uniqueKeysWithValues: clubs.map { ($0.id, $0.name) })

        var callsigns = Set<String>()
        var byCallsign: [String: Set<String>] = [:]
        var byClub: [String: Set<String>] = [:]

        var offset: Int64 = 0
        while true {
            let batch = (try? store.fetchClubMembers(
                filter: FfiClubMemberFilter(clubId: nil, callsign: nil),
                limit: ClubsFetch.limit,
                offset: offset
            )) ?? []
            if batch.isEmpty {
                break
            }
            for member in batch {
                guard let clubName = nameById[member.clubId] else {
                    continue
                }
                let key = member.callsign.uppercased()
                callsigns.insert(key)
                byCallsign[key, default: []].insert(clubName)
                byClub[clubName, default: []].insert(key)
            }
            if batch.count < Int(ClubsFetch.limit) {
                break
            }
            offset += Int64(batch.count)
        }

        return ClubSnapshot(
            clubs: clubs,
            callsigns: callsigns,
            byCallsign: byCallsign.mapValues { Array($0) },
            byClub: byClub
        )
    }

    /// Lazily build the `ClubsApi` over the shared store + activities base URL.
    private func ensureApi() async throws -> ClubsApi {
        if let clubsApi {
            return clubsApi
        }
        let store = try await CwStoreProvider.shared.store()
        let baseURL = ActivitiesClient.normalizeBase(ActivitiesClient.resolvedBaseURL)
        let api = try ClubsApi(store: store, baseUrl: baseURL)
        clubsApi = api
        return api
    }

    /// Rebuild the published clubs list and the in-memory callsign caches from
    /// the Rust store (off the main thread).
    private func reloadFromStore() async {
        guard let store = try? await CwStoreProvider.shared.store() else {
            return
        }
        let snapshot = await Task.detached { Self.buildSnapshot(store: store) }.value
        clubs = snapshot.clubs
        clubMemberCallsigns = snapshot.callsigns
        clubsByCallsign = snapshot.byCallsign
        callsignsByClub = snapshot.byClub
    }
}

// MARK: - ClubSnapshot

private struct ClubSnapshot {
    var clubs: [FfiClub]
    var callsigns: Set<String>
    var byCallsign: [String: [String]]
    var byClub: [String: Set<String>]
}

// MARK: - ClubsSyncError

enum ClubsSyncError: LocalizedError {
    case notAuthenticated
    case syncFailed(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Please sign in to view clubs"
        case let .syncFailed(message):
            "Sync failed: \(message)"
        }
    }
}
