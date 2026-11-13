import CarrierWaveCore
import CarrierWaveCwFfi
import UIKit

// MARK: - BandScopeFilterService

/// Runs the active goal profile's compiled SQL against the spot engine's
/// scope DB and publishes the per-lens spot-id sets (spec §17, amended
/// 2026-07-04: Scope hides rather than dims):
///
/// - `scopePassIDs` — spots that pass ALL filtering; Scope hides the
///   complement (scrubber ticks stay, dimmed).
/// - `heardPassIDs` — spots that survive Heard's hide semantics.
/// - `wpmPassIDs` — spots within the WPM ceiling; Heard dims the
///   complement (nil when the ceiling is off).
///
/// SQL is compiled in Rust (`compileProfileQueries`) only when the profile
/// or toggles change; the queries re-run on every engine generation.
@MainActor
@Observable
final class BandScopeFilterService {
    // MARK: Internal

    private(set) var scopePassIDs: Set<String> = []
    private(set) var heardPassIDs: Set<String> = []
    private(set) var wpmPassIDs: Set<String>?

    /// True when the active profile/toggles exclude anything — drives the
    /// honest `173 → 41` count indicator.
    private(set) var isFiltering = false

    private(set) var lastError: String?

    /// Recompile for a new profile/toggle state and re-run against the
    /// current scope DB contents.
    func apply(profile: GoalProfile, toggles: QuickToggles, engine: SpotEngineApi) {
        compiled = compileProfileQueries(
            profile: profile.ffiProfile, toggles: toggles.ffiToggles
        )
        isFiltering = profile.predicate != .all || toggles.isFiltering
        seedClubRosterIfNeeded(profile: profile, engine: engine)
        refresh(engine: engine)
    }

    /// Re-run the compiled queries (call on every `on_spots_updated`).
    func refresh(engine: SpotEngineApi) {
        guard let compiled else {
            return
        }
        let generation = refreshGeneration &+ 1
        refreshGeneration = generation
        Task { [weak self] in
            // The SQL runs off the main actor; only the result hops back.
            let result = await Task.detached(priority: .userInitiated) {
                Self.runQueries(compiled, engine: engine)
            }.value
            guard let self, refreshGeneration == generation else {
                return
            }
            switch result {
            case let .success(sets):
                scopePassIDs = sets.scope
                heardPassIDs = sets.heard
                wpmPassIDs = sets.wpm
                lastError = nil
            case let .failure(message):
                // A broken filter must be visible, never silent (spec
                // §17) — keep the last good sets but surface it.
                lastError = message
            }
        }
    }

    // MARK: Private

    private struct PassSets {
        let scope: Set<String>
        let heard: Set<String>
        let wpm: Set<String>?
    }

    private enum QueryOutcome {
        case success(PassSets)
        case failure(String)
    }

    /// Matches the engine's own `allowed_spot_ids` row cap.
    nonisolated private static let rowLimit: UInt32 = 10_000

    private var compiled: FfiCompiledProfileQueries?
    private var refreshGeneration: UInt64 = 0
    private var clubRosterSeeded = false

    nonisolated private static func runQueries(
        _ compiled: FfiCompiledProfileQueries,
        engine: SpotEngineApi
    ) -> QueryOutcome {
        do {
            let scope = try spotIDs(engine.runQuery(sql: compiled.scopePass, limit: rowLimit))
            let heard = try spotIDs(engine.runQuery(sql: compiled.heardPass, limit: rowLimit))
            let wpm = try compiled.wpmDim.map {
                try spotIDs(engine.runQuery(sql: $0, limit: rowLimit))
            }
            return .success(PassSets(scope: scope, heard: heard, wpm: wpm))
        } catch let SpotQueryError.Query(reason, _, _) {
            return .failure(reason)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    nonisolated private static func spotIDs(_ result: FfiQueryResultSet) -> Set<String> {
        guard let index = result.columns.firstIndex(of: "spot_id") else {
            return []
        }
        return Set(result.rows.compactMap { row in
            row.values.indices.contains(index) ? row.values[index] : nil
        })
    }

    /// Seed `scope.club_members` from the SKCC roster the first time a
    /// club-predicate profile activates. LICW/CWOps have no roster —
    /// SQL club filtering is SKCC-complete only (tier badges for the
    /// others still come from per-callsign enrichment host-side).
    private func seedClubRosterIfNeeded(profile: GoalProfile, engine: SpotEngineApi) {
        guard !clubRosterSeeded, profile.predicate == .clubMembers,
              profile.clubs.contains(.skcc)
        else {
            return
        }
        clubRosterSeeded = true
        Task.detached(priority: .utility) { [weak self] in
            await SKCCMembershipStore.shared.ensureLoaded()
            let members = SKCCMembershipStore.shared.allCallsigns().map {
                FfiScopeClubMember(callsign: $0, club: GoalProfile.Club.skcc.rawValue)
            }
            do {
                try engine.seedClubMembers(rows: members)
                await MainActor.run { [weak self] in
                    self?.refresh(engine: engine)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.lastError = "Club roster unavailable: \(error.localizedDescription)"
                    self?.clubRosterSeeded = false
                }
            }
        }
    }
}
