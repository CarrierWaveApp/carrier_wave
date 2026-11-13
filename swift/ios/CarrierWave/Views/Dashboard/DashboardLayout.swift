import CarrierWaveData
import SwiftUI

// MARK: - DashboardSectionID

/// Identifies a collapsible section on the dashboard.
enum DashboardSectionID: String, CaseIterable, Identifiable {
    case station
    case social
    case stats
    case tools
    case services

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .station: "My Station"
        case .social: "Social"
        case .stats: "Stats & Awards"
        case .tools: "Tools"
        case .services: "Services"
        }
    }

    var icon: String {
        switch self {
        case .station: "antenna.radiowaves.left.and.right"
        case .social: "person.2"
        case .stats: "chart.bar"
        case .tools: "wrench.and.screwdriver"
        case .services: "arrow.triangle.2.circlepath"
        }
    }

    var cards: [DashboardCardID] {
        switch self {
        case .station: [.activity]
        case .social: [.friendActivity]
        case .stats:
            [
                .streaks, .statistics, .gridTracker, .potaAwards, .was, .needs, .bragSheet,
                .favorites, .equipment,
            ]
        case .tools: [.onAir, .callsignLookup]
        case .services: [.syncServices]
        }
    }
}

// MARK: - DashboardCardID

/// Identifies an individual card on the dashboard for visibility toggling.
enum DashboardCardID: String, CaseIterable, Identifiable {
    case gettingStarted
    case activity
    case friendActivity
    case streaks
    case statistics
    case potaAwards
    case was
    case needs
    case bragSheet
    case favorites
    case equipment
    case onAir
    case callsignLookup
    case gridTracker
    case syncServices

    // MARK: Internal

    /// Cards shown on a fresh install (or when the user has never customized the
    /// dashboard). Everything else is opt-in via the Customize sheet so the default
    /// experience stays light and glanceable rather than a wall of cards.
    ///
    /// `gettingStarted` is included because it has its own internal show/hide logic
    /// (onboarding only); listing it here keeps it from being suppressed by the lean
    /// default.
    static let essentialDefaults: Set<DashboardCardID> = [
        .gettingStarted, .activity, .onAir, .syncServices,
    ]

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .gettingStarted: "Getting Started"
        case .activity: "Activity"
        case .friendActivity: "Friend Activity"
        case .streaks: "Streaks"
        case .statistics: "Statistics"
        case .potaAwards: "Awards & Certificates"
        case .was: "WAS"
        case .needs: "Smart Spots"
        case .bragSheet: "Brag Sheet"
        case .favorites: "Favorites"
        case .equipment: "Equipment"
        case .onAir: "On Air Now"
        case .callsignLookup: "Callsign Lookup"
        case .gridTracker: "Grid Tracker"
        case .syncServices: "Logbook Services"
        }
    }

    /// The experimental feature that must be enabled for this card to appear,
    /// or `nil` if the card is always available.
    var requiredExperiment: ExperimentalFeature? {
        switch self {
        case .needs: .needs
        default: nil
        }
    }

    var icon: String {
        switch self {
        case .gettingStarted: "sparkles"
        case .activity: "square.grid.3x3"
        case .friendActivity: "person.2"
        case .streaks: "flame"
        case .statistics: "chart.bar"
        case .potaAwards: "leaf"
        case .was: "map"
        case .needs: "sparkles"
        case .bragSheet: "rosette"
        case .favorites: "star"
        case .equipment: "radio"
        case .onAir: "radio"
        case .callsignLookup: "magnifyingglass"
        case .gridTracker: "square.grid.3x3"
        case .syncServices: "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - DashboardLayoutPrefs

/// Helpers for reading/writing dashboard layout preferences stored as comma-separated
/// strings in @AppStorage. Avoids encoding overhead while staying @AppStorage compatible.
enum DashboardLayoutPrefs {
    static let hiddenCardsKey = "dashboardHiddenCards"
    static let collapsedSectionsKey = "dashboardCollapsedSections"

    // MARK: - Hidden Cards

    static func hiddenCardIDs(from raw: String) -> Set<String> {
        guard !raw.isEmpty else {
            return []
        }
        return Set(raw.components(separatedBy: ","))
    }

    static func encodeHiddenCards(_ cardIDs: Set<String>) -> String {
        cardIDs.sorted().joined(separator: ",")
    }

    static func isCardVisible(_ card: DashboardCardID, hiddenRaw: String) -> Bool {
        // Empty string = the user has never customized the dashboard. Fall back to the
        // lean default (essentials only) instead of showing every card.
        guard !hiddenRaw.isEmpty else {
            return DashboardCardID.essentialDefaults.contains(card)
        }
        return !hiddenCardIDs(from: hiddenRaw).contains(card.rawValue)
    }

    /// Returns a new hidden-cards string after changing `card`'s visibility.
    ///
    /// When the user toggles a card from the uncustomized (lean) state, this
    /// materializes the *full* effective hidden set so untouched non-essential cards
    /// stay hidden — otherwise writing a single entry would flip the string non-empty
    /// and re-reveal every other card.
    static func setCardVisible(
        _ card: DashboardCardID,
        visible: Bool,
        in raw: String,
        available: [DashboardCardID]
    ) -> String {
        var hidden = Set<String>()
        for candidate in available {
            let isVisible = candidate == card
                ? visible
                : isCardVisible(candidate, hiddenRaw: raw)
            if !isVisible {
                hidden.insert(candidate.rawValue)
            }
        }
        return encodeHiddenCards(hidden)
    }

    // MARK: - Collapsed Sections

    static func collapsedSectionIDs(from raw: String) -> Set<String> {
        guard !raw.isEmpty else {
            return []
        }
        return Set(raw.components(separatedBy: ","))
    }

    static func encodeCollapsedSections(_ sectionIDs: Set<String>) -> String {
        sectionIDs.sorted().joined(separator: ",")
    }

    static func isSectionCollapsed(_ section: DashboardSectionID, collapsedRaw: String) -> Bool {
        collapsedSectionIDs(from: collapsedRaw).contains(section.rawValue)
    }
}

// MARK: - CollapsibleDashboardSection

/// A section header with expand/collapse behavior, persisted via @AppStorage binding.
struct CollapsibleDashboardSection<Content: View>: View {
    // MARK: Internal

    let section: DashboardSectionID
    @Binding var collapsedSectionsRaw: String

    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            if !isCollapsed {
                content()
            }
        }
    }

    // MARK: Private

    private var isCollapsed: Bool {
        DashboardLayoutPrefs.isSectionCollapsed(section, collapsedRaw: collapsedSectionsRaw)
    }

    private var sectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                toggleSection()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                Text(section.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(section.title), \(isCollapsed ? "collapsed" : "expanded")")
        .accessibilityHint("Double tap to \(isCollapsed ? "expand" : "collapse")")
    }

    private func toggleSection() {
        var sectionIDs = DashboardLayoutPrefs.collapsedSectionIDs(from: collapsedSectionsRaw)
        if sectionIDs.contains(section.rawValue) {
            sectionIDs.remove(section.rawValue)
        } else {
            sectionIDs.insert(section.rawValue)
        }
        collapsedSectionsRaw = DashboardLayoutPrefs.encodeCollapsedSections(sectionIDs)
    }
}
