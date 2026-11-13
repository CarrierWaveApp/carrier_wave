import CarrierWaveCore
import CarrierWaveCwFfi
import Foundation

// MARK: - SOTASpotsCache

/// Process-wide cache of currently-active SOTA spots, backed by the Rust
/// spot engine (Phase 4: the dedicated `SOTAClient` fetch path is gone —
/// `refreshNow` polls the engine and converts its SOTA snapshot). The
/// actor's contract is unchanged because the Logger's S2S enrichment needs
/// the synchronous `spotsSync()` read on keystrokes.
///
/// Usage from `@MainActor` UI:
/// ```
/// let spots = SOTASpotsCache.shared.spotsSync()
/// // or, to opportunistically refresh:
/// Task { await SOTASpotsCache.shared.refreshIfStale() }
/// ```
actor SOTASpotsCache {
    // MARK: Internal

    static let shared = SOTASpotsCache()

    /// How long a cached snapshot is considered fresh. Background-driven
    /// refreshes (the Logger's polling tick, a sidebar appearance) won't
    /// hit the network inside this window.
    static let freshnessInterval: TimeInterval = 30

    /// Read the current cached spots without triggering a fetch. Safe from
    /// any context — backed by an `NSLock`-protected snapshot updated only
    /// when a fetch completes, mirroring the pattern used by
    /// `POTAParksCache.parkSync` / `SOTASummitsCache.summitsSnapshot`.
    nonisolated func spotsSync() -> [SOTASpot] {
        Self.snapshot.read()
    }

    /// Refresh from the network if the cache is stale. No-op inside the
    /// freshness window. Errors are swallowed — SOTA enrichment is
    /// opportunistic, not load-bearing.
    func refreshIfStale() async {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < Self.freshnessInterval {
            return
        }
        await refreshNow()
    }

    /// Force a fetch regardless of cache age. Used when the user explicitly
    /// asks for fresh data (e.g. typing the `S2S` command). Polls the spot
    /// engine (all enabled sources) and converts its SOTA snapshot.
    func refreshNow() async {
        guard let engine = await MainActor.run(body: { SpotEngineProvider.shared.engine() })
        else {
            return
        }
        await engine.refresh()
        let spots = engine.snapshot(filter: nil, worked: nil)
            .spots.compactMap(\.appSotaSpot)
        lastFetch = Date()
        Self.snapshot.write(spots)
    }

    // MARK: Private

    /// Lock-protected mutable snapshot so `nonisolated` readers (UI on the
    /// main actor) don't have to await the actor's queue.
    private static let snapshot = SOTASpotsSnapshot()

    private var lastFetch: Date?
}

// MARK: - SOTASpotsSnapshot

/// `NSLock`-backed Sendable container for cross-actor snapshot reads.
/// `cachedSOTASpots` is purely UI state, so we accept the synchronous read
/// path documented in the project's CLAUDE.md ("NSLock-protected storage
/// with lock.withLock for synchronous cross-actor reads").
nonisolated private final class SOTASpotsSnapshot: @unchecked Sendable {
    // MARK: Internal

    func read() -> [SOTASpot] {
        lock.withLock { spots }
    }

    func write(_ next: [SOTASpot]) {
        lock.withLock { spots = next }
    }

    // MARK: Private

    private var spots: [SOTASpot] = []
    private let lock = NSLock()
}
