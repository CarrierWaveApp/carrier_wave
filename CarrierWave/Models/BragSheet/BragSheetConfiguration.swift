import Foundation

// MARK: - BragSheetPeriodConfig

/// Per-period configuration for a brag sheet card.
/// Stored as JSON in UserDefaults, keyed by period.
struct BragSheetPeriodConfig: Codable, Equatable, Sendable {
    /// Ordered list of enabled stat types (defines both selection and order).
    var enabledStats: [BragSheetStatType]

    /// Stats promoted to the hero row (max 4).
    var heroStats: [BragSheetStatType]

    /// The preset this config was based on (nil if manually customized).
    var basePreset: BragSheetPreset?

    init(
        enabledStats: [BragSheetStatType],
        heroStats: [BragSheetStatType],
        basePreset: BragSheetPreset? = nil
    ) {
        self.enabledStats = enabledStats
        self.heroStats = Array(heroStats.prefix(4))
        self.basePreset = basePreset
    }

    /// Create from a preset.
    static func from(preset: BragSheetPreset) -> BragSheetPeriodConfig {
        BragSheetPeriodConfig(
            enabledStats: preset.stats,
            heroStats: preset.defaultHeroStats,
            basePreset: preset
        )
    }

    /// Toggle a stat on or off.
    mutating func toggle(_ stat: BragSheetStatType) {
        if let index = enabledStats.firstIndex(of: stat) {
            enabledStats.remove(at: index)
            heroStats.removeAll { $0 == stat }
        } else {
            enabledStats.append(stat)
        }
    }

    /// Toggle hero status for a stat. Returns false if at hero limit.
    @discardableResult
    mutating func toggleHero(_ stat: BragSheetStatType) -> Bool {
        guard enabledStats.contains(stat) else { return false }

        if let index = heroStats.firstIndex(of: stat) {
            heroStats.remove(at: index)
            return true
        }
        guard heroStats.count < 4 else { return false }
        heroStats.append(stat)
        return true
    }

    /// Move a stat within the enabled list.
    mutating func move(from source: IndexSet, to destination: Int) {
        enabledStats.move(fromOffsets: source, toOffset: destination)
    }
}

// MARK: - BragSheetConfiguration

/// Top-level brag sheet configuration managing all periods.
/// Persists to UserDefaults as JSON.
struct BragSheetConfiguration: Codable, Equatable, Sendable {
    var weekly: BragSheetPeriodConfig
    var monthly: BragSheetPeriodConfig
    var allTime: BragSheetPeriodConfig
    var includeMap: Bool
    var includeEquipmentSummary: Bool
    var goldRecordBadges: Bool

    init(
        weekly: BragSheetPeriodConfig = .from(preset: .contester),
        monthly: BragSheetPeriodConfig = .from(preset: .general),
        allTime: BragSheetPeriodConfig = .from(preset: .dxer),
        includeMap: Bool = true,
        includeEquipmentSummary: Bool = false,
        goldRecordBadges: Bool = true
    ) {
        self.weekly = weekly
        self.monthly = monthly
        self.allTime = allTime
        self.includeMap = includeMap
        self.includeEquipmentSummary = includeEquipmentSummary
        self.goldRecordBadges = goldRecordBadges
    }

    /// Get config for a specific period.
    func config(for period: BragSheetPeriod) -> BragSheetPeriodConfig {
        switch period {
        case .weekly: weekly
        case .monthly: monthly
        case .allTime: allTime
        }
    }

    /// Set config for a specific period.
    mutating func setConfig(_ config: BragSheetPeriodConfig, for period: BragSheetPeriod) {
        switch period {
        case .weekly: weekly = config
        case .monthly: monthly = config
        case .allTime: allTime = config
        }
    }

    /// Apply a preset to a specific period.
    mutating func applyPreset(_ preset: BragSheetPreset, to period: BragSheetPeriod) {
        setConfig(.from(preset: preset), for: period)
    }

    /// Copy config from one period to another.
    mutating func copyConfig(from source: BragSheetPeriod, to destination: BragSheetPeriod) {
        setConfig(config(for: source), for: destination)
    }
}

// MARK: - Persistence

extension BragSheetConfiguration {
    private static let userDefaultsKey = "bragSheetConfiguration"

    /// Load from UserDefaults, or return defaults.
    static func load() -> BragSheetConfiguration {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(BragSheetConfiguration.self, from: data)
        else {
            return BragSheetConfiguration()
        }
        return config
    }

    /// Save to UserDefaults.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
