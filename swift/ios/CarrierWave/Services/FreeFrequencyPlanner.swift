import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - ActiveSpotsLoader

/// Loads currently-active stations from every live source — POTA, RBN, and
/// SOTA — de-duplicated by callsign + band. Shared by the frequency band
/// suggestions list, the band scope, and the session wizard's auto-frequency
/// pick so all three see the same on-air picture. Errors from any single
/// source are swallowed; the remaining sources still contribute.
///
/// Concurrent callers for the same mode share one in-flight fetch, and a
/// caller that can't wait (the wizard) can take a *bounded* look via
/// `load(mode:within:)`: it gets whichever sources have answered by the
/// deadline while the fetch keeps running to fill the cache for everyone else.
///
/// Main-actor isolated (the target default) — the merge work is a few
/// hundred structs, and it keeps `ActiveStation.band` reachable.
enum ActiveSpotsLoader {
    // MARK: Internal

    /// Result of a bounded load: the stations seen so far and whether every
    /// source had answered before the deadline.
    struct BoundedResult: Sendable {
        let stations: [ActiveStation]
        /// False when at least one source was still in flight at the deadline.
        let complete: Bool
    }

    /// Spots older than this are ignored when judging what's on-air.
    static let maxSpotAgeSec: TimeInterval = 12 * 60

    /// A recent `load` is reused for this long, so the auto-frequency pick, the
    /// scope, and band switches don't each re-hit POTA/RBN/SOTA. Short enough
    /// that the on-air picture stays fresh within a wizard session.
    static let cacheTTLSec: TimeInterval = 45

    /// How long the session wizard waits for live spots before picking from
    /// whatever has arrived. The sources' own request timeouts run 15–30 s,
    /// which is far too long to hold up a "start activation" flow.
    static let wizardDeadlineSec: TimeInterval = 3

    /// Every source, waited for in full (bounded only by each client's own
    /// request timeout). Shares an in-flight fetch with concurrent callers.
    static func load(
        mode: String,
        maxAgeSec: TimeInterval = maxSpotAgeSec
    ) async -> [ActiveStation] {
        let key = cacheKey(mode: mode, maxAgeSec: maxAgeSec)
        if let cached = cache.value(for: key, ttl: cacheTTLSec) {
            return cached
        }
        return await fetch(mode: mode, maxAgeSec: maxAgeSec, key: key).completed()
    }

    /// Whatever has arrived within `deadline` seconds. Returns immediately on
    /// a cache hit; otherwise waits at most `deadline` for the shared fetch
    /// and then answers with the sources that have reported so far. The
    /// fetch is *not* cancelled — it finishes in the background and lands in
    /// the cache for the scope and the band list.
    static func load(
        mode: String,
        within deadline: TimeInterval,
        maxAgeSec: TimeInterval = maxSpotAgeSec
    ) async -> BoundedResult {
        let key = cacheKey(mode: mode, maxAgeSec: maxAgeSec)
        if let cached = cache.value(for: key, ttl: cacheTTLSec) {
            return BoundedResult(stations: cached, complete: true)
        }
        let inflight = fetch(mode: mode, maxAgeSec: maxAgeSec, key: key)
        if let full = await firstOf({ await inflight.completed() }, orTimeout: deadline) {
            return BoundedResult(stations: full, complete: true)
        }
        return BoundedResult(stations: inflight.partial(), complete: false)
    }

    // MARK: Fileprivate

    /// A single POTA+RBN+SOTA fetch. Each source is recorded as it lands so a
    /// deadline-bound caller can read a partial picture; the merged full
    /// result is written to the shared cache on completion.
    fileprivate final class SpotFetch {
        // MARK: Lifecycle

        init(mode: String, maxAgeSec: TimeInterval, key: String) {
            self.key = key
            task = Task {
                await withTaskGroup(of: (Source, [ActiveStation]).self) { group in
                    group.addTask { await (.pota, fetchPOTA()) }
                    group.addTask { await (.sota, fetchSOTA()) }
                    group.addTask { await (.rbn, fetchRBN(mode: mode, maxAgeSec: maxAgeSec)) }
                    for await (source, stations) in group {
                        self.sources[source] = stations
                    }
                }
                let merged = self.partial()
                cache.store(merged, for: key)
                return merged
            }
        }

        // MARK: Internal

        /// Dedupe priority: POTA, then SOTA, then RBN (program spots carry
        /// richer metadata than a skimmer hit).
        enum Source: Int, CaseIterable, Sendable {
            case pota
            case sota
            case rbn
        }

        let key: String

        func completed() async -> [ActiveStation] {
            await task.value
        }

        /// Merge of every source that has answered so far.
        func partial() -> [ActiveStation] {
            var seen: Set<String> = []
            var merged: [ActiveStation] = []
            for source in Source.allCases {
                for station in sources[source] ?? [] {
                    let dedupeKey = "\(station.callsign)-\(station.band)"
                    if seen.insert(dedupeKey).inserted {
                        merged.append(station)
                    }
                }
            }
            return merged
        }

        // MARK: Private

        private var task: Task<[ActiveStation], Never>!
        private var sources: [Source: [ActiveStation]] = [:]
    }

    // MARK: Private

    private static let cache = SpotCache()

    private static func cacheKey(mode: String, maxAgeSec: TimeInterval) -> String {
        "\(mode.uppercased())|\(Int(maxAgeSec))"
    }

    /// The in-flight fetch for `key`, starting one if none is running.
    private static func fetch(mode: String, maxAgeSec: TimeInterval, key: String) -> SpotFetch {
        cache.inflight(for: key) {
            SpotFetch(mode: mode, maxAgeSec: maxAgeSec, key: key)
        }
    }

    /// `operation`'s value if it finishes within `timeout` seconds, else
    /// `nil`. Only the *wait* is abandoned on timeout — the operation itself
    /// (an unstructured task elsewhere) keeps running.
    private static func firstOf<T: Sendable>(
        _ operation: @escaping @Sendable () async -> T,
        orTimeout timeout: TimeInterval
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next().flatMap { $0 }
            group.cancelAll()
            return first
        }
    }

    private static func fetchPOTA() async -> [ActiveStation] {
        do {
            let client = POTAClient(authService: POTAAuthService())
            return try await client.fetchActiveSpots()
                .compactMap { ActiveStation.fromPOTA($0) }
        } catch {
            return []
        }
    }

    private static func fetchRBN(mode: String, maxAgeSec: TimeInterval) async -> [ActiveStation] {
        do {
            let client = RBNClient()
            return try await client.spots(
                mode: mode,
                since: Date().addingTimeInterval(-maxAgeSec),
                limit: 200
            ).map { ActiveStation.fromRBN($0) }
        } catch {
            return []
        }
    }

    private static func fetchSOTA() async -> [ActiveStation] {
        await SOTASpotsCache.shared.refreshIfStale()
        return SOTASpotsCache.shared.spotsSync().compactMap { ActiveStation.fromSOTA($0) }
    }
}

// MARK: - SpotCache

/// Small TTL cache shared by `ActiveSpotsLoader` so the auto-pick, the scope,
/// and band switches within a wizard session don't each re-hit the networks.
/// Also tracks the in-flight fetch per key so concurrent callers share it.
private final class SpotCache {
    // MARK: Internal

    func value(for key: String, ttl: TimeInterval) -> [ActiveStation]? {
        guard let entry = entries[key], Date().timeIntervalSince(entry.at) < ttl else {
            return nil
        }
        return entry.spots
    }

    func store(_ spots: [ActiveStation], for key: String) {
        entries[key] = (spots, Date())
        inflight[key] = nil
    }

    /// The running fetch for `key`, or a new one from `make`.
    func inflight(for key: String, make: () -> ActiveSpotsLoader.SpotFetch) -> ActiveSpotsLoader.SpotFetch {
        if let running = inflight[key] {
            return running
        }
        let fetch = make()
        inflight[key] = fetch
        return fetch
    }

    // MARK: Private

    private var entries: [String: (spots: [ActiveStation], at: Date)] = [:]
    private var inflight: [String: ActiveSpotsLoader.SpotFetch] = [:]
}

// MARK: - FreeFrequencyPlanner

/// Picks a free frequency on a band by nestling among the active stations
/// with enough clearance to avoid interference, honouring the operator's
/// license privileges and the band's usage zones. Extracted from
/// `FrequencyBandView` so the session wizard can reuse the exact same logic.
struct FreeFrequencyPlanner {
    // MARK: Internal

    /// Minimum spacing from the nearest active station (2 kHz).
    static let minClearanceMHz = 0.002

    let mode: String
    let license: LicenseClass

    /// Stations relevant to `mode` and legal for `license` — the same filter
    /// the band suggestions list applies before recommending a frequency.
    func relevantStations(_ stations: [ActiveStation]) -> [ActiveStation] {
        let modeFilter = ModeFilter.from(modeName: mode)
        return stations.filter { station in
            guard modeFilter.matches(station.mode) else {
                return false
            }
            if let violation = BandPlanService.validate(
                frequencyMHz: station.frequencyMHz,
                mode: station.mode,
                license: license
            ) {
                switch violation.type {
                case .outOfBand,
                     .noPrivileges,
                     .wrongMode:
                    return false
                case .unusualFrequency:
                    return true
                }
            }
            return true
        }
    }

    /// A free frequency nestled among `stations` on `band`, plus a short
    /// human reason (e.g. "3 kHz clear"). Returns `nil` when there's no live
    /// activity to nestle against or no clear slot exists.
    func recommend(
        band: String,
        stations: [ActiveStation]
    ) -> (frequency: Double?, reason: String) {
        let recent = stations.filter {
            Date().timeIntervalSince($0.timestamp) <= ActiveSpotsLoader.maxSpotAgeSec
        }
        let occupied = recent.map(\.frequencyMHz).sorted()
        guard !occupied.isEmpty else {
            return (nil, "")
        }

        let privileged = BandPlanService.privilegedSegments(for: license)
            .filter { $0.band == band }
        let widePrivileged = privileged.filter { $0.minimumLicense != .extra }
        let preferWide = !widePrivileged.isEmpty

        let allZones = BandPlan.usageZones(forBand: band, mode: mode)
        let primary = allZones.filter { $0.isPrimaryZone(for: mode) }
        let secondary = allZones.filter { !$0.isPrimaryZone(for: mode) }

        let attempts: [([UsageZone], [BandSegment])] = [
            (primary, preferWide ? widePrivileged : privileged),
            (primary, privileged),
            (secondary, preferWide ? widePrivileged : privileged),
            (secondary, privileged),
        ]

        for (zones, segs) in attempts where !zones.isEmpty && !segs.isEmpty {
            let result = nestledFrequency(zones: zones, privileged: segs, occupied: occupied)
            if result.0 != nil {
                return result
            }
        }
        return (nil, "")
    }

    // MARK: Private

    private func nestledFrequency(
        zones: [UsageZone],
        privileged: [BandSegment],
        occupied: [Double]
    ) -> (Double?, String) {
        var candidates: [(freq: Double, clearance: Double)] = []

        for zone in zones {
            let startKHz = Int(zone.startMHz * 1_000)
            let endKHz = Int(zone.endMHz * 1_000)
            var kHz = startKHz
            while kHz < endKHz {
                let mhz = Double(kHz) / 1_000.0
                let licensed = privileged.contains { $0.contains(frequencyMHz: mhz) }
                if licensed {
                    let clearance = occupied.map { abs(mhz - $0) }.min() ?? .infinity
                    if clearance >= Self.minClearanceMHz {
                        candidates.append((mhz, clearance))
                    }
                }
                kHz += 1
            }
        }

        guard !candidates.isEmpty else {
            return (nil, "No clear frequency found")
        }

        let center = occupied.reduce(0.0, +) / Double(occupied.count)
        let best = candidates.min { abs($0.freq - center) < abs($1.freq - center) }!
        return (best.freq, "\(Int(best.clearance * 1_000)) kHz clear")
    }
}
