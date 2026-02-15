import Foundation

// MARK: - AppTab

enum AppTab: String, Hashable, CaseIterable, Codable {
    case dashboard
    case logger
    case logs
    case cwDecoder
    case map
    case activity
    case more

    // MARK: Internal

    /// Tabs that can be reordered/hidden by the user
    /// Note: cwDecoder is intentionally excluded - feature is disabled
    static var configurableTabs: [AppTab] {
        [.dashboard, .logger, .logs, .map, .activity]
    }

    /// Default tab order
    static var defaultOrder: [AppTab] {
        [.dashboard, .logger, .logs, .cwDecoder, .map, .activity, .more]
    }

    /// Default hidden tabs (not shown in tab bar initially)
    static var defaultHidden: Set<AppTab> {
        [.logger, .cwDecoder, .activity]
    }

    /// Tabs that are completely disabled and should never appear anywhere
    /// These are filtered out from all tab lists
    static var disabledTabs: Set<AppTab> {
        [.cwDecoder]
    }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .logger: "Logger"
        case .logs: "Logs"
        case .cwDecoder: "CW"
        case .map: "Map"
        case .activity: "Activity"
        case .more: "More"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .logger: "pencil.and.list.clipboard"
        case .logs: "list.bullet"
        case .cwDecoder: "waveform"
        case .map: "map"
        case .activity: "person.2"
        case .more: "ellipsis"
        }
    }

    var description: String {
        switch self {
        case .dashboard: "QSO statistics and sync status"
        case .logger: "Log QSOs during activations"
        case .logs: "View and search logged QSOs"
        case .cwDecoder: "CW transcription and decoding"
        case .map: "QSO locations on a map"
        case .activity: "Friends, clubs, and activity feed"
        case .more: "Settings and hidden tabs"
        }
    }
}

// MARK: - TabConfiguration

/// Manages tab visibility and ordering
enum TabConfiguration {
    // MARK: Internal

    /// Get the ordered list of visible tabs
    static func visibleTabs() -> [AppTab] {
        let order = tabOrder()
        let hidden = hiddenTabs()
        return order.filter { !hidden.contains($0) && !AppTab.disabledTabs.contains($0) }
    }

    /// Get the current tab order (including hidden tabs, but excluding disabled tabs)
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
        for tab in AppTab.defaultOrder
            where !result.contains(tab) && !AppTab.disabledTabs.contains(tab)
        {
            if tab == .more {
                result.append(tab)
            } else {
                result.insert(tab, at: max(0, result.count - 1))
            }
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

    /// Check if a specific tab is enabled
    static func isTabEnabled(_ tab: AppTab) -> Bool {
        !hiddenTabs().contains(tab)
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
    case icloud
}

// MARK: - Notifications

extension Notification.Name {
    static let tabConfigurationChanged = Notification.Name("tabConfigurationChanged")
}
