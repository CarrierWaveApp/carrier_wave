import CarrierWaveData
import Foundation

// MARK: - AppTab

enum AppTab: String, Hashable, CaseIterable, Codable {
    case dashboard
    case logger
    case logs
    case cwDecoder
    case map
    case activity
    case remote
    case satellites
    case more

    // MARK: Internal

    /// Tabs that can be reordered/hidden by the user.
    /// Excludes disabled (experiment-gated) tabs.
    static var configurableTabs: [AppTab] {
        [.dashboard, .logger, .logs, .map, .activity, .remote, .satellites]
            .filter { !disabledTabs.contains($0) }
    }

    /// Default tab order. The first four are the sticky default tab bar
    /// (Home, Sessions, Logbook, Map); everything after is hidden by default
    /// and only surfaces if the user un-hides it from More → Customize.
    static var defaultOrder: [AppTab] {
        [.dashboard, .logger, .logs, .map, .cwDecoder, .activity, .remote, .satellites, .more]
    }

    /// Default hidden tabs (not shown in tab bar initially)
    static var defaultHidden: Set<AppTab> {
        [.cwDecoder, .activity, .remote, .satellites]
    }

    /// Tabs that are completely disabled and should never appear anywhere.
    /// These are filtered out from all tab lists.
    /// Gated by `ExperimentalFeature.isEnabled` for experimental tabs.
    static var disabledTabs: Set<AppTab> {
        var disabled: Set<AppTab> = []
        if !ExperimentalFeature.isEnabled(.remoteSweep) {
            disabled.insert(.remote)
        }
        if !ExperimentalFeature.isEnabled(.satellites) {
            disabled.insert(.satellites)
        }
        return disabled
    }

    /// Naming glossary (docs/ux-north-star.md): Home = launchpad, Sessions =
    /// outings (relabels "Hunter Log" for hunters), Logbook = every QSO,
    /// Friends = social feed. Raw values are storage/deep-link keys — never
    /// rename those, only these display strings.
    var title: String {
        switch self {
        case .dashboard: "Home"
        case .logger: "Sessions"
        case .logs: "Logbook"
        case .cwDecoder: "CW"
        case .map: "Map"
        case .activity: "Friends"
        case .remote: "Remote"
        case .satellites: "Satellites"
        case .more: "More"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "house"
        case .logger: "antenna.radiowaves.left.and.right"
        case .logs: "book.closed"
        case .cwDecoder: "waveform"
        case .map: "map"
        case .activity: "person.2"
        case .remote: "iphone.radiowaves.left.and.right"
        case .satellites: "globe.americas"
        case .more: "ellipsis"
        }
    }

    var description: String {
        switch self {
        case .dashboard: "Your launchpad: what's on the air now, stats, and sync"
        case .logger: "Start sessions and review activation history"
        case .logs: "Every QSO you've ever logged, searchable"
        case .cwDecoder: "CW transcription and decoding"
        case .map: "Parks, summits, and QSO locations on a map"
        case .activity: "Friends, clubs, and activity feed"
        case .remote: "Live remote control of CW Sweep on Mac"
        case .satellites: "Live satellite positions from SatNOGS orbital data"
        case .more: "Settings and hidden tabs"
        }
    }
}

// MARK: - TabConfiguration

/// Manages tab visibility and ordering
enum TabConfiguration {
    // MARK: Internal

    /// Maximum configurable tabs on the tab bar (excluding .more).
    /// Exceeding this causes iOS to create a system "More" navigation controller,
    /// which nests our custom More tab and creates double navigation.
    static let maxTabBarTabs = 4

    /// Get the ordered list of visible tabs (capped to avoid system "More" nesting).
    static func visibleTabs() -> [AppTab] {
        let order = tabOrder()
        let hidden = hiddenTabs()
        var visible = order.filter {
            $0 != .more && !hidden.contains($0) && !AppTab.disabledTabs.contains($0)
        }
        // Cap configurable tabs so total (configurable + .more) never exceeds 5.
        // Overflow tabs appear in our custom More tab instead of triggering
        // the system's "More" navigation controller.
        if visible.count > maxTabBarTabs {
            visible = Array(visible.prefix(maxTabBarTabs))
        }
        visible.append(.more)
        return visible
    }

    /// Tabs that are NOT visible on the tab bar — either explicitly hidden
    /// by the user or overflowed because only `maxTabBarTabs` fit.
    /// MoreTabView uses this to populate its list.
    static func tabsForMoreList() -> [AppTab] {
        let order = tabOrder()
        let visibleSet = Set(visibleTabs())
        return order.filter { tab in
            tab != .more && !visibleSet.contains(tab) && !AppTab.disabledTabs.contains(tab)
        }
    }

    /// Get the current tab order (including hidden tabs, but excluding disabled tabs).
    ///
    /// When a tab graduates from experiments and joins `defaultOrder`, existing
    /// users don't have it in their saved order. We splice it in just before
    /// `.more` — but if it's listed in `defaultHidden`, we also persist it as
    /// hidden so it never pushes an existing visible tab out of the 4-tab cap.
    /// Without that, a graduated tab silently appears on the user's tab bar
    /// (this is exactly how `.cwDecoder` displaced `.map` after CW transcription
    /// graduated).
    static func tabOrder() -> [AppTab] {
        guard let data = UserDefaults.standard.data(forKey: orderKey),
              let order = try? JSONDecoder().decode([AppTab].self, from: data)
        else {
            return AppTab.defaultOrder.filter { !AppTab.disabledTabs.contains($0) }
        }
        // Ensure all tabs are present (in case new tabs were added)
        // Filter out disabled tabs
        var result = order.filter {
            AppTab.allCases.contains($0) && !AppTab.disabledTabs.contains($0)
        }
        var hiddenToAdd: Set<AppTab> = []
        for tab in AppTab.defaultOrder
            where !result.contains(tab) && !AppTab.disabledTabs.contains(tab)
        {
            if tab == .more {
                result.append(tab)
            } else {
                result.insert(tab, at: max(0, result.count - 1))
                if AppTab.defaultHidden.contains(tab) {
                    hiddenToAdd.insert(tab)
                }
            }
        }
        if !hiddenToAdd.isEmpty {
            var hidden = hiddenTabs()
            hidden.formUnion(hiddenToAdd)
            saveHidden(hidden)
        }
        return result
    }

    /// Get hidden tabs (excludes disabled tabs which shouldn't appear anywhere)
    /// - Parameter forIPad: When true, defaults to no hidden tabs on first launch
    static func hiddenTabs(forIPad: Bool = false) -> Set<AppTab> {
        // Check if user has ever configured tabs
        guard UserDefaults.standard.data(forKey: hiddenKey) != nil else {
            // First launch: iPad shows all tabs, iPhone uses defaults
            if forIPad {
                return AppTab.disabledTabs
            }
            return AppTab.defaultHidden.subtracting(AppTab.disabledTabs)
        }
        guard let data = UserDefaults.standard.data(forKey: hiddenKey),
              let hidden = try? JSONDecoder().decode([AppTab].self, from: data)
        else {
            if forIPad {
                return AppTab.disabledTabs
            }
            return AppTab.defaultHidden.subtracting(AppTab.disabledTabs)
        }
        // Filter out disabled tabs - they shouldn't appear even in hidden list
        return Set(hidden).subtracting(AppTab.disabledTabs)
    }

    /// Save tab order
    static func saveOrder(_ order: [AppTab]) {
        if let data = try? JSONEncoder().encode(order) {
            UserDefaults.standard.set(data, forKey: orderKey)
        }
    }

    /// Save hidden tabs
    static func saveHidden(_ hidden: Set<AppTab>) {
        if let data = try? JSONEncoder().encode(Array(hidden)) {
            UserDefaults.standard.set(data, forKey: hiddenKey)
        }
    }

    /// Check if a specific tab is visible on the tab bar
    /// (accounts for both hidden tabs and overflow caps)
    static func isTabEnabled(_ tab: AppTab) -> Bool {
        visibleTabs().contains(tab)
    }

    /// Set whether a tab is enabled
    static func setTabEnabled(_ tab: AppTab, enabled: Bool) {
        var hidden = hiddenTabs()
        if enabled {
            hidden.remove(tab)
        } else {
            hidden.insert(tab)
        }
        saveHidden(hidden)
    }

    /// Move a tab from one position to another
    static func moveTab(from source: Int, to destination: Int) {
        var order = tabOrder()
        let tab = order.remove(at: source)
        order.insert(tab, at: destination)
        saveOrder(order)
    }

    /// Get visible tabs for iPad sidebar (respects hidden, excludes .more)
    static func iPadVisibleTabs() -> [AppTab] {
        let order = tabOrder()
        let hidden = hiddenTabs(forIPad: true)
        return order.filter {
            $0 != .more && !hidden.contains($0) && !AppTab.disabledTabs.contains($0)
        }
    }

    /// Reset to defaults
    static func reset() {
        UserDefaults.standard.removeObject(forKey: orderKey)
        UserDefaults.standard.removeObject(forKey: hiddenKey)
    }

    /// One-time migration: unhide .logger (now "Sessions") for users who had it hidden.
    /// Gated by UserDefaults key so it runs only once.
    static func migrateLoggerToSessions() {
        let migrationKey = "tabMigration_loggerToSessions_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            return
        }
        UserDefaults.standard.set(true, forKey: migrationKey)

        // Only act if user has saved tab config (otherwise defaults apply)
        guard UserDefaults.standard.data(forKey: hiddenKey) != nil else {
            return
        }
        var hidden = hiddenTabs()
        if hidden.contains(.logger) {
            hidden.remove(.logger)
            saveHidden(hidden)
        }
    }

    // MARK: Private

    private static let orderKey = "tabOrder"
    private static let hiddenKey = "hiddenTabs"
}

// MARK: - SettingsDestination

enum SettingsDestination: Hashable {
    case qrz
    case pota
    case lofi
    case hamrs
    case lotw
    case clublog
    case eqsl
    case icloud
    case tota
}

// MARK: - Notifications

extension Notification.Name {
    static let tabConfigurationChanged = Notification.Name("tabConfigurationChanged")
}
