import CarrierWaveCwFfi
import CarrierWaveData
import UIKit

// MARK: - BandScopeViewModel

/// One shared model for both lenses (spec §0/§15: both views stay mounted;
/// flipping preserves scroll, expansion, and the pending pill). Consumes
/// engine snapshots via the provider's shared listener, assembles the
/// Scope rows (unfiltered — Scope dims, never hides) and the Heard feed
/// (churn-controlled), and re-runs the profile filter SQL per generation.
@MainActor
@Observable
final class BandScopeViewModel {
    // MARK: Internal

    let profileStore = GoalProfileStore()
    let filterService = BandScopeFilterService()
    let anchorStore = AnchorStore()

    private(set) var allSpots: [EnrichedSpot] = []
    private(set) var lastError: String?
    private(set) var isReady = false

    private(set) var scopeClusters: [ScopeCluster] = []
    private(set) var scopeGaps: [String: ScopeGap] = [:]
    private(set) var scopeBustedIDs: Set<String> = []
    /// Total spots on the active band (the `173` in `173 → 41`).
    private(set) var scopeUnfilteredCount = 0

    // MARK: - Heard lens state

    private(set) var heardDisplayed: [HeardStation] = []
    private(set) var heardPendingCount = 0
    private(set) var unseenBoundary: Date?
    /// Bands present in the feed; tap-toggled tiles (≥1 always on).
    private(set) var heardBands: [String] = []
    /// Bumped when a merge should scroll Heard to the top (§13).
    private(set) var heardScrollToTopSignal = 0

    // MARK: - Scrubber ↔ list sync (§3)

    /// Frequencies of clusters currently on screen (row visibility
    /// callbacks); the scrubber derives its viewport window from these.
    private(set) var visibleScopeFreqs: [String: Double] = [:]

    /// Scrubber tap → list scroll: the cluster to scroll to, plus a
    /// signal so repeat taps on the same cluster still fire.
    private(set) var scopeScrollTargetID: String?
    private(set) var scopeScrollSignal = 0

    // MARK: - Scope lens state

    /// nil follows the radio VFO (else 20m).
    var manualBand: String? {
        didSet { rebuildScope() }
    }

    var disabledHeardBands: Set<String> = [] {
        didSet { rebuildHeard() }
    }

    var activeBand: String {
        if let manualBand {
            return manualBand
        }
        if let mhz = RadioService.shared.radioFrequencyMHz {
            let band = LoggingSession.bandForFrequency(mhz)
            if !band.isEmpty {
                return band
            }
        }
        return "20m"
    }

    var activeProfile: GoalProfile {
        profileStore.activeProfile
    }

    /// Needed-tier stations currently in the Heard feed (needs shelf).
    var needsShelfStations: [HeardStation] {
        let profile = activeProfile
        return heardDisplayed.filter { $0.latest.tier(for: profile) == .needed }
    }

    var heardVisibleCount: Int {
        heardDisplayed.count
    }

    var heardUnfilteredCount: Int {
        heardAllStations.count
    }

    func start() {
        guard !started else {
            return
        }
        started = true
        let provider = SpotEngineProvider.shared
        guard let engine = provider.engine() else {
            lastError = provider.lastEngineError
            return
        }
        provider.applyConfig()
        provider.feedUserContext()
        provider.feedCTYDatabase()
        provider.feedNeedsSnapshot()
        provider.addSpotsObserver(id: Self.observerID) { [weak self] in
            self?.consumeSnapshot()
        }
        applyProfile()
        isReady = true
        consumeSnapshot()
        Task.detached { await engine.refresh() }
    }

    func stop() {
        guard started else {
            return
        }
        started = false
        SpotEngineProvider.shared.removeSpotsObserver(id: Self.observerID)
    }

    /// Re-apply after a profile/toggle change (also re-runs the SQL).
    func applyProfile() {
        guard let engine = SpotEngineProvider.shared.engineIfBuilt else {
            return
        }
        filterService.apply(
            profile: profileStore.activeProfile,
            toggles: profileStore.quickToggles,
            engine: engine
        )
    }

    /// Merge pending Heard spots: adopt the fresh order, drop the unseen
    /// line at the previous newest timestamp, scroll to top (§13).
    func mergeHeardPending() {
        unseenBoundary = heardDisplayed.first?.latest.spot.timestamp
        heardMergedOrder = heardAllStations.map(\.id)
        heardScrollToTopSignal += 1
        rebuildHeard()
    }

    /// Anchor declaration from Tune / Log QSO (spec §6).
    func declareAnchor(frequencyKHz: Double, band: String) {
        anchorStore.declare(frequencyKHz: frequencyKHz, band: band)
    }

    func setClusterVisible(id: String, frequencyKHz: Double, visible: Bool) {
        if visible {
            visibleScopeFreqs[id] = frequencyKHz
        } else {
            visibleScopeFreqs.removeValue(forKey: id)
        }
    }

    /// Scrubber tap (§3): scroll the list to the cluster nearest the
    /// tapped frequency.
    func requestScopeScroll(toFrequencyKHz target: Double) {
        guard let nearest = scopeClusters.min(by: { lhs, rhs in
            abs(lhs.minFrequencyKHz - target) < abs(rhs.minFrequencyKHz - target)
        }) else {
            return
        }
        scopeScrollTargetID = nearest.id
        scopeScrollSignal += 1
    }

    // MARK: Private

    private static let observerID = "bandScopeV2"

    private var started = false
    /// All stations, newest-first, post busted-dedupe + hide filters.
    private var heardAllStations: [HeardStation] = []
    /// Callsign order adopted at the last merge.
    private var heardMergedOrder: [String] = []

    /// Band the Scope was last assembled for — band changes clear the
    /// anchor immediately (§6).
    private var lastBuiltBand: String?

    private static func orderedBands(in stations: [HeardStation]) -> [String] {
        var seen: Set<String> = []
        var bands: [String] = []
        for station in stations {
            let band = station.latest.spot.band
            if !band.isEmpty, seen.insert(band).inserted {
                bands.append(band)
            }
        }
        return bands.sorted { lhs, rhs in
            (Double(lhs.dropLast()) ?? 0) > (Double(rhs.dropLast()) ?? 0)
        }
    }

    private func consumeSnapshot() {
        guard let engine = SpotEngineProvider.shared.engineIfBuilt else {
            return
        }
        let snapshot = engine.snapshot(filter: nil, worked: nil)
        allSpots = snapshot.spots.map(\.appEnrichedSpot)
        filterService.refresh(engine: engine)
        rebuildScope()
        rebuildHeard()
    }

    private func rebuildScope() {
        // Scope is single-band and UNFILTERED (§17): dimming is applied at
        // render time from filterService sets; gap math sees everything.
        let band = activeBand
        if let lastBuiltBand, lastBuiltBand != band {
            anchorStore.clear()
        }
        lastBuiltBand = band
        let bandSpots = allSpots.filter { $0.spot.band == band }
        scopeUnfilteredCount = bandSpots.count
        scopeClusters = ScopeClustering.clusters(of: bandSpots)
        // Prune visibility entries whose clusters no longer exist. Cluster
        // ids churn with every publish (id = lead spot id), and destroyed
        // rows never report `visible: false` — orphaned entries would pin
        // the scrubber window's extents forever.
        let liveIDs = Set(scopeClusters.map(\.id))
        visibleScopeFreqs = visibleScopeFreqs.filter { liveIDs.contains($0.key) }
        scopeGaps = ScopeClustering.gaps(between: scopeClusters)
            .reduce(into: [:]) { result, gap in
                result[gap.afterClusterID] = gap
            }
        scopeBustedIDs = ScopeClustering.bustedSuspectIDs(in: scopeClusters)
    }

    private func rebuildHeard() {
        // Heard hard-hides (§17): profile/RBN/worked-today drop rows; the
        // WPM ceiling only dims (applied at render). Busted copies are
        // deduped fully here (§10).
        let busted = ScopeClustering.bustedSuspectIDs(
            in: ScopeClustering.clusters(of: allSpots)
        )
        let hidden = filterService.heardPassIDs
        let visible = allSpots.filter {
            !filterService.isFiltering || hidden.contains($0.id)
        }
        var stations = HeardAggregation.stations(from: visible, excluding: busted)
        heardBands = Self.orderedBands(in: stations)
        // ≥1 band always on — an all-off selection READS as all-on. Never
        // write `disabledHeardBands` here: its didSet re-enters this
        // function (that recursion stack-overflowed on first open).
        let disabled = disabledHeardBands.count >= heardBands.count
            ? [] : disabledHeardBands
        if !disabled.isEmpty {
            stations = stations.filter {
                !disabled.contains($0.latest.spot.band)
            }
        }
        heardAllStations = stations

        if heardMergedOrder.isEmpty, !stations.isEmpty {
            // First load: no pill, adopt the feed as already-seen.
            heardMergedOrder = stations.map(\.id)
        }
        let merged = Set(heardMergedOrder)
        // Rows the user has seen keep their positions; their age/count
        // update in place (§13 churn control).
        let byID: [String: HeardStation] = stations.reduce(into: [:]) { result, station in
            result[station.id] = station
        }
        heardDisplayed = heardMergedOrder.compactMap { byID[$0] }
        heardPendingCount = stations.count { !merged.contains($0.id) }
    }
}
