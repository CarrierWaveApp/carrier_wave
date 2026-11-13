import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - BragSheetComputedResult

/// Per-period computed brag results plus the QSO count, keyed by stat for O(1)
/// lookup. Built from the shared Rust `BragSheetApi.computeBrag` output.
nonisolated struct BragSheetComputedResult: Sendable {
    // MARK: Lifecycle

    init(period: FfiBragPeriod, results: [FfiBragStatResult], qsoCount: Int) {
        self.period = period
        self.results = results
        byStat = Dictionary(results.map { ($0.statType, $0) }, uniquingKeysWith: { first, _ in first })
        self.qsoCount = qsoCount
    }

    // MARK: Internal

    let period: FfiBragPeriod
    let results: [FfiBragStatResult]
    let byStat: [FfiBragStatType: FfiBragStatResult]
    let qsoCount: Int

    /// The computed value for a stat, or `.noData` if not enabled/computed.
    func value(for stat: FfiBragStatType) -> FfiBragStatValue {
        byStat[stat]?.value ?? .noData
    }

    /// The formatted hero string for a stat, or "--" if not computed.
    func formatted(for stat: FfiBragStatType) -> String {
        byStat[stat]?.formatted ?? "--"
    }
}

// MARK: - AsyncBragSheetStats

/// Observable wrapper for brag sheet statistics, routed entirely through the
/// shared Rust `BragSheetApi` (catalog + config + compute). Config and computed
/// stat values are FFI-sourced; a lean SwiftData snapshot fetch remains only to
/// feed the share-card map + statistician section (raw QSOs the FFI doesn't
/// expose). All FFI + fetch work runs off the main actor; results publish on main.
@MainActor
@Observable
final class AsyncBragSheetStats {
    // MARK: Internal

    private(set) var weeklyResult: BragSheetComputedResult?
    private(set) var monthlyResult: BragSheetComputedResult?
    private(set) var allTimeResult: BragSheetComputedResult?

    private(set) var isComputing = false
    private(set) var hasComputed = false

    var selectedPeriod: FfiBragPeriod = .weekly

    var configuration: FfiBragConfiguration = BragSheetConfigDefaults.value

    /// Catalog metadata (display names, icon keys) keyed by stat type.
    private(set) var catalog: [FfiBragStatType: FfiBragStatMeta] = [:]

    /// Catalog metadata in the shared Rust declaration order (drives the
    /// customize sheet's per-category ordering).
    private(set) var catalogOrdered: [FfiBragStatMeta] = []

    /// Category metadata + ordered stat lists, for grouped rendering.
    private(set) var categories: [FfiBragCategoryMeta] = []

    /// Available presets for the customize sheet.
    private(set) var presets: [FfiBragPresetInfo] = []

    /// Cached API instance for stateless config transforms in the customize
    /// sheet. Populated once the store opens; transforms no-op until then.
    private(set) var api: BragSheetApi?

    /// Raw QSO snapshots for the share map + statistician section (share-only).
    private(set) var cachedSnapshots: [BragSheetQSOSnapshot]?

    /// The result for the currently selected period.
    var currentResult: BragSheetComputedResult? {
        result(for: selectedPeriod)
    }

    /// Summary line for dashboard card (e.g. "This week: 42 QSOs · 12 DXCC").
    var summaryLine: String? {
        guard let result = weeklyResult, result.qsoCount > 0 else {
            return nil
        }
        let qsos = result.qsoCount
        for stat in configuration.weekly.heroStats {
            let value = result.value(for: stat)
            if value.hasData, stat != .totalQsos {
                let name = catalog[stat]?.displayName ?? ""
                return "This week: \(qsos) QSOs · \(value.heroValue) \(name)"
            }
        }
        return "This week: \(qsos) QSOs"
    }

    /// Display metadata for a stat (falls back to a placeholder if the catalog
    /// hasn't loaded yet).
    func meta(for stat: FfiBragStatType) -> FfiBragStatMeta? {
        catalog[stat]
    }

    func result(for period: FfiBragPeriod) -> BragSheetComputedResult? {
        switch period {
        case .weekly: weeklyResult
        case .monthly: monthlyResult
        case .allTime: allTimeResult
        }
    }

    func compute(from container: ModelContainer) {
        guard !isComputing, !hasComputed else {
            return
        }
        startComputation(from: container)
    }

    func recompute(from container: ModelContainer) {
        computeTask?.cancel()
        cachedSnapshots = nil
        hasComputed = false
        startComputation(from: container)
    }

    /// Wait for the current computation to finish (no-op if not computing).
    func waitUntilComplete() async {
        await computeTask?.value
    }

    /// Persist the current configuration through the shared Rust store.
    func saveConfiguration() {
        Task { await persist(configuration) }
    }

    func saveAndRecompute(from container: ModelContainer) {
        let config = configuration
        computeTask?.cancel()
        cachedSnapshots = nil
        hasComputed = false
        startComputation(from: container, saveConfig: config)
    }

    // MARK: - Config mutation (customize sheet)

    /// Apply a preset to a period via the shared Rust transform.
    func applyPreset(_ preset: FfiBragPreset, to period: FfiBragPeriod) {
        guard let api else {
            return
        }
        configuration = api.applyPreset(config: configuration, preset: preset, period: period)
    }

    /// Toggle a stat on/off for a period.
    func toggleStat(_ stat: FfiBragStatType, in period: FfiBragPeriod) {
        guard let api else {
            return
        }
        configuration = api.toggleStat(config: configuration, stat: stat, period: period)
    }

    /// Toggle hero promotion for a stat. Returns false if the hero cap was hit
    /// (config unchanged), so the caller can give haptic feedback.
    @discardableResult
    func toggleHeroStat(_ stat: FfiBragStatType, in period: FfiBragPeriod) -> Bool {
        guard let api else {
            return false
        }
        let updated = api.toggleHeroStat(config: configuration, stat: stat, period: period)
        let changed = updated != configuration
        configuration = updated
        return changed
    }

    /// Reorder a stat within a period's enabled list.
    func moveStat(in period: FfiBragPeriod, from source: Int, to destination: Int) {
        guard let api, source >= 0, destination >= 0 else {
            return
        }
        configuration = api.moveStat(
            config: configuration, period: period,
            from: UInt32(source), to: UInt32(destination)
        )
    }

    // MARK: Private

    nonisolated private struct PeriodResults: Sendable {
        let weekly: BragSheetComputedResult
        let monthly: BragSheetComputedResult
        let allTime: BragSheetComputedResult
    }

    nonisolated private struct Metadata: Sendable {
        let lookup: [FfiBragStatType: FfiBragStatMeta]
        let ordered: [FfiBragStatMeta]
        let categories: [FfiBragCategoryMeta]
        let presets: [FfiBragPresetInfo]
    }

    private var computeTask: Task<Void, Never>?

    /// Load config from the store; on first run, import the legacy UserDefaults
    /// blob (idempotent). Persists `save` when provided (customize-sheet save).
    nonisolated private static func loadAndMigrateConfig(
        api: BragSheetApi,
        save: FfiBragConfiguration?
    ) async -> FfiBragConfiguration {
        await Task.detached {
            if let save {
                try? api.saveConfig(cfg: save)
                return save
            }
            BragSheetConfigMigration.migrateLegacyIfNeeded(api: api)
            return (try? api.loadConfig()) ?? BragSheetConfigDefaults.value
        }.value
    }

    /// Computes all three periods' stat results, using a TRUE per-period QSO
    /// count (from `snapshots`, the same windowed/off-main fetch used for the
    /// share card) rather than deriving presence from whichever stats happen to
    /// be enabled. This avoids a real bug: if the user's config disables Total
    /// QSOs and every other enabled stat is `.noData` for a period that still
    /// has real QSOs, a stat-derived count would read 0 and the empty state
    /// would incorrectly hide those QSOs and disable sharing.
    nonisolated private static func computeAllPeriods(
        api: BragSheetApi, nowUnix: Int64, useMetric: Bool, snapshots: [BragSheetQSOSnapshot]
    ) async -> PeriodResults {
        await Task.detached {
            func compute(_ period: FfiBragPeriod) -> BragSheetComputedResult {
                let results = (try? api.computeBrag(
                    period: period, nowUnix: nowUnix, useMetric: useMetric
                )) ?? []
                let count = trueQsoCount(for: period, snapshots: snapshots)
                return BragSheetComputedResult(period: period, results: results, qsoCount: count)
            }
            return PeriodResults(
                weekly: compute(.weekly),
                monthly: compute(.monthly),
                allTime: compute(.allTime)
            )
        }.value
    }

    /// True per-period QSO count, independent of which stats are enabled.
    /// Filters the already-fetched (windowed, batched, off-main) share
    /// snapshots by the period's UTC date range — the same window math and
    /// snapshot source `BragSheetView.filteredSnapshots` uses for the share
    /// card, so the two stay consistent.
    nonisolated private static func trueQsoCount(
        for period: FfiBragPeriod, snapshots: [BragSheetQSOSnapshot]
    ) -> Int {
        guard period != .allTime else {
            return snapshots.count
        }
        let dateRange = period.dateRange()
        return snapshots.count { $0.timestamp >= dateRange.start && $0.timestamp <= dateRange.end }
    }

    nonisolated private static func loadMetadata(api: BragSheetApi) async -> Metadata {
        await Task.detached {
            let metas = api.catalog()
            let lookup = Dictionary(
                metas.map { ($0.statType, $0) }, uniquingKeysWith: { first, _ in first }
            )
            return Metadata(
                lookup: lookup, ordered: metas,
                categories: api.categories(), presets: api.presets()
            )
        }.value
    }

    /// Fetch all non-hidden, non-metadata QSOs as Sendable snapshots for the
    /// share map + statistician section only. Batched with a fresh
    /// `ModelContext` per batch (≈5 MB peak) per the performance rules.
    nonisolated private static func fetchShareSnapshots(
        container: ModelContainer
    ) async -> [BragSheetQSOSnapshot] {
        await Task.detached {
            let batchSize = BoundedDescriptor<QSO>.maxLimit
            var offset = 0
            var seenIds = Set<UUID>()
            var snapshots: [BragSheetQSOSnapshot] = []

            while true {
                if Task.isCancelled {
                    break
                }
                let context = ModelContext(container)
                context.autosaveEnabled = false
                let descriptor = BoundedDescriptor<QSO>(
                    predicate: #Predicate { !$0.isHidden },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
                    limit: batchSize,
                    offset: offset
                )
                guard let batch = try? context.boundedFetch(descriptor), !batch.isEmpty else {
                    break
                }
                for qso in batch {
                    guard seenIds.insert(qso.id).inserted else {
                        continue
                    }
                    guard !QSOMode.isMetadata(qso.mode) else {
                        continue
                    }
                    snapshots.append(BragSheetQSOSnapshot(from: qso))
                }
                offset += batch.count
                if batch.count < batchSize {
                    break
                }
            }
            return snapshots
        }.value
    }

    /// Persist a configuration via the shared Rust store, off the main actor.
    private func persist(_ config: FfiBragConfiguration) async {
        guard let store = try? await CwStoreProvider.shared.store() else {
            return
        }
        let api = BragSheetApi(store: store)
        try? await Task.detached { try api.saveConfig(cfg: config) }.value
    }

    private func startComputation(
        from container: ModelContainer,
        saveConfig: FfiBragConfiguration? = nil
    ) {
        isComputing = true

        computeTask = Task {
            guard let store = try? await CwStoreProvider.shared.store() else {
                isComputing = false
                return
            }
            let bragApi = BragSheetApi(store: store)

            // One-time legacy migration + config persist happen off-main.
            let loadedConfig = await Self.loadAndMigrateConfig(api: bragApi, save: saveConfig)

            // Lean snapshot fetch feeds both the share map/statistician section
            // AND the true per-period QSO count used below (empty-state gate).
            let snapshots = await Self.fetchShareSnapshots(container: container)

            let nowUnix = Int64(Date().timeIntervalSince1970)
            let useMetric = UnitFormatter.useMetric
            let computed = await Self.computeAllPeriods(
                api: bragApi, nowUnix: nowUnix, useMetric: useMetric, snapshots: snapshots
            )

            // Catalog metadata is cheap + stable; fetch off-main.
            let metadata = await Self.loadMetadata(api: bragApi)

            do {
                try Task.checkCancellation()
            } catch {
                isComputing = false
                return
            }

            api = bragApi
            configuration = loadedConfig
            catalog = metadata.lookup
            catalogOrdered = metadata.ordered
            categories = metadata.categories
            presets = metadata.presets
            weeklyResult = computed.weekly
            monthlyResult = computed.monthly
            allTimeResult = computed.allTime
            cachedSnapshots = snapshots
            isComputing = false
            hasComputed = true
            StartupProfiler.shared.record("dashboard.bragSheetComplete")
        }
    }
}

// MARK: - Config helpers

extension FfiBragConfiguration {
    /// Per-period config accessor (mirrors the deleted Swift `config(for:)`).
    func config(for period: FfiBragPeriod) -> FfiBragPeriodConfig {
        switch period {
        case .weekly: weekly
        case .monthly: monthly
        case .allTime: allTime
        }
    }

    /// Per-period config setter.
    mutating func setConfig(_ config: FfiBragPeriodConfig, for period: FfiBragPeriod) {
        switch period {
        case .weekly: weekly = config
        case .monthly: monthly = config
        case .allTime: allTime = config
        }
    }
}

// MARK: - BragSheetConfigDefaults

/// Shared default configuration, used before the store loads and as a fallback.
nonisolated enum BragSheetConfigDefaults {
    // MARK: Internal

    static let value = FfiBragConfiguration(
        weekly: emptyPeriod,
        monthly: emptyPeriod,
        allTime: emptyPeriod,
        includeMap: true,
        includeEquipmentSummary: false,
        goldRecordBadges: true
    )

    // MARK: Private

    private static let emptyPeriod = FfiBragPeriodConfig(
        enabledStats: [], heroStats: [], basePreset: nil
    )
}
