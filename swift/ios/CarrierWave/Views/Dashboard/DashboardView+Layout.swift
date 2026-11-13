import CarrierWaveData
import SwiftUI

// MARK: - Dashboard Layout

extension DashboardView {
    /// Adaptive dashboard that preserves card view identity across orientation
    /// changes. Uses a custom `Layout` to rearrange children between 1-column
    /// (portrait) and 2-column (landscape) without destroying/recreating views.
    ///
    /// **Why not `if/else`?** An `if verticalSizeClass == .compact` / `else`
    /// branch creates different structural identities. When the branch changes,
    /// SwiftUI destroys all children and recreates them — resetting `@State`
    /// and re-firing `.task` modifiers. This caused 200ms+ hangs on rotation
    /// as GridTracker and FriendsOnAir reloaded data from scratch.
    private var isCompactVertical: Bool {
        verticalSizeClass == .compact
    }

    var adaptiveDashboardContent: some View {
        TwoColumnLayout(
            isLandscape: isCompactVertical,
            splitIndex: leftColumnCardCount,
            spacing: isCompactVertical ? 16 : 20
        ) {
            // --- Left column (landscape) / all cards (portrait) ---
            // Always first and not toggleable — Home's hero is the next
            // action (resume / start / hunt), per ux-north-star.md §3.
            HomeHeroCard(selectedTab: $selectedTab)
            if isCardVisible(.gettingStarted) {
                DashboardGettingStartedCard(
                    tourState: tourState,
                    potaAuth: potaAuth,
                    selectedTab: $selectedTab,
                    settingsDestination: $settingsDestination
                )
            }
            if isCardVisible(.activity) {
                activityCard
            }
            if isCardVisible(.onAir) {
                onAirCard
            }
            if isCardVisible(.friendActivity) {
                friendActivityCard
            }
            if isCardVisible(.callsignLookup) {
                callsignLookupCard
            }

            // --- Right column (landscape) / continued (portrait) ---
            if hasVisibleStatsCards {
                DashboardSectionLabel(title: "Stats & Awards")
            }
            if isCardVisible(.streaks) {
                streaksCard
            }
            if isCardVisible(.statistics) {
                summaryCard
            }
            if isCardVisible(.gridTracker) {
                gridTrackerCard
            }
            if isCardVisible(.potaAwards) {
                potaAwardsCard
            }
            if isCardVisible(.was) {
                wasCard
            }
            if isCardVisible(.needs) {
                needsCard
            }
            if isCardVisible(.bragSheet) {
                bragSheetEntryCard
            }
            if hasVisibleDataCards {
                DashboardSectionLabel(title: "Your Data")
            }
            if isCardVisible(.favorites) {
                favoritesCard
            }
            if isCardVisible(.equipment) {
                equipmentCard
            }
            if isCardVisible(.syncServices) {
                syncCard
            }
            if showAddCardsFooter {
                AddCardsFooter(
                    hiddenSummary: hiddenCardSummary,
                    onTap: { showingCustomizeSheet = true }
                )
            }
        }
    }

    /// Show the discovery footer only when at least one card is currently
    /// hidden — once the user has surfaced everything there's nothing left to
    /// advertise.
    private var showAddCardsFooter: Bool {
        DashboardCardID.allCases.contains { card in
            // Skip cards that require an experiment the user hasn't enabled
            // — surfacing "Brag Sheet" when bragSheet is off is noise.
            if let experiment = card.requiredExperiment,
               !ExperimentalFeature.isEnabled(experiment)
            {
                return false
            }
            // Getting Started is gated by tour state and is not user-toggled.
            if card == .gettingStarted {
                return false
            }
            return !isCardVisible(card)
        }
    }

    /// Short, comma-joined preview of the categories the user is missing.
    /// "+ Show stats, social, tools" reads better than "+ Show 8 more cards"
    /// because it tells them *what* depth they're missing, not just how much.
    private var hiddenCardSummary: String {
        var groups: [String] = []
        let statsCardsHidden = DashboardSectionID.stats.cards.contains { hiddenAndAvailable($0) }
        if statsCardsHidden {
            groups.append("stats")
        }
        let socialHidden = DashboardSectionID.social.cards.contains { hiddenAndAvailable($0) }
        if socialHidden {
            groups.append("social")
        }
        let toolsHidden = DashboardSectionID.tools.cards.contains { hiddenAndAvailable($0) }
        if toolsHidden {
            groups.append("tools")
        }
        return groups.joined(separator: ", ")
    }

    private func hiddenAndAvailable(_ card: DashboardCardID) -> Bool {
        if let experiment = card.requiredExperiment,
           !ExperimentalFeature.isEnabled(experiment)
        {
            return false
        }
        return !isCardVisible(card)
    }

    /// Number of children placed in the left column when in landscape.
    ///
    /// Splits dynamically at the midpoint of all visible children rather than
    /// using a fixed left/right card assignment. The fixed assignment was tuned
    /// for a dashboard with ~10+ visible cards; the lean default (3-4 visible)
    /// would leave the right column with a single small card, making landscape
    /// look half-empty.
    private var leftColumnCardCount: Int {
        let kinds = visibleChildKinds
        guard kinds.count > 1 else {
            return kinds.count
        }
        // Floor — when there's an odd count, the right column carries the
        // extra item, which typically pairs the tall Activity grid in the left
        // with two shorter cards on the right.
        var split = kinds.count / 2
        // Don't end the left column on a section label — its cards would all
        // be in the right column, leaving a bare heading at the bottom of the
        // left. Walk back until the last left-column item is a real card.
        while split > 0, case .sectionLabel = kinds[split - 1] {
            split -= 1
        }
        return max(split, 1)
    }

    /// Sequence of visible children in dashboard order, tagging each as a card
    /// or a section label. Mirrors the order in `adaptiveDashboardContent` so
    /// the split index lines up with the `TwoColumnLayout` subviews.
    private var visibleChildKinds: [DashboardChildKind] {
        var kinds: [DashboardChildKind] = [.card] // HomeHeroCard, always present
        if isCardVisible(.gettingStarted) {
            kinds.append(.card)
        }
        if isCardVisible(.activity) {
            kinds.append(.card)
        }
        if isCardVisible(.onAir) {
            kinds.append(.card)
        }
        if isCardVisible(.friendActivity) {
            kinds.append(.card)
        }
        if isCardVisible(.callsignLookup) {
            kinds.append(.card)
        }
        if hasVisibleStatsCards {
            kinds.append(.sectionLabel)
        }
        if isCardVisible(.streaks) {
            kinds.append(.card)
        }
        if isCardVisible(.statistics) {
            kinds.append(.card)
        }
        if isCardVisible(.gridTracker) {
            kinds.append(.card)
        }
        if isCardVisible(.potaAwards) {
            kinds.append(.card)
        }
        if isCardVisible(.was) {
            kinds.append(.card)
        }
        if isCardVisible(.needs) {
            kinds.append(.card)
        }
        if isCardVisible(.bragSheet) {
            kinds.append(.card)
        }
        if hasVisibleDataCards {
            kinds.append(.sectionLabel)
        }
        if isCardVisible(.favorites) {
            kinds.append(.card)
        }
        if isCardVisible(.equipment) {
            kinds.append(.card)
        }
        if isCardVisible(.syncServices) {
            kinds.append(.card)
        }
        return kinds
    }

    /// Whether the Stats & Awards group has at least one visible card.
    var hasVisibleStatsCards: Bool {
        let statsCards: [DashboardCardID] = [
            .streaks, .statistics, .gridTracker, .potaAwards,
            .was, .needs, .bragSheet,
        ]
        return statsCards.contains { isCardVisible($0) }
    }

    /// Whether the Your Data group has at least one visible card.
    var hasVisibleDataCards: Bool {
        let dataCards: [DashboardCardID] = [.favorites, .equipment]
        return dataCards.contains { isCardVisible($0) }
    }

    /// Whether a section has at least one visible card.
    func hasVisibleCards(in section: DashboardSectionID) -> Bool {
        section.cards.contains { isCardVisible($0) }
    }

    /// Whether a card is visible based on user preferences and experiment state.
    func isCardVisible(_ card: DashboardCardID) -> Bool {
        if let experiment = card.requiredExperiment,
           !ExperimentalFeature.isEnabled(experiment)
        {
            return false
        }
        return DashboardLayoutPrefs.isCardVisible(card, hiddenRaw: hiddenCards)
    }
}

// MARK: - DashboardChildKind

/// Tags each child of `adaptiveDashboardContent` as either a card or a section
/// label so the column-split logic can avoid stranding a heading at the bottom
/// of the left column.
private enum DashboardChildKind {
    case card
    case sectionLabel
}

// MARK: - AddCardsFooter

/// Single muted row beneath the visible dashboard cards advertising the depth
/// available behind the Customize sheet. Replaces the previous "only the
/// slider icon in the toolbar tells you more exists" discoverability hole for
/// the lean default dashboard. Hidden once everything is visible.
struct AddCardsFooter: View {
    // MARK: Internal

    let hiddenSummary: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if !hiddenSummary.isEmpty {
                        Text(hiddenSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show more dashboard cards")
        .accessibilityHint(
            hiddenSummary.isEmpty
                ? "Opens the customize dashboard sheet"
                : "Opens customize; hidden categories: \(hiddenSummary)"
        )
    }

    // MARK: Private

    private var headline: String {
        hiddenSummary.isEmpty ? "Show more cards" : "Show more here"
    }
}

// MARK: - TwoColumnLayout

/// Custom `Layout` that arranges children in 1 or 2 columns.
///
/// When `isLandscape` is false, behaves like a `VStack`.
/// When `isLandscape` is true, splits children at `splitIndex` into
/// left (0..<splitIndex) and right (splitIndex...) columns.
///
/// Because all children remain direct subviews of a single container,
/// SwiftUI preserves their structural identity across layout changes.
/// This prevents `@State` resets when switching orientations.
struct TwoColumnLayout: Layout {
    var isLandscape: Bool
    var splitIndex: Int
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Void
    ) -> CGSize {
        guard !subviews.isEmpty else {
            return .zero
        }
        let width = proposal.width ?? 300
        if isLandscape {
            return landscapeSize(width: width, subviews: subviews)
        }
        return portraitSize(width: width, subviews: subviews)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Void
    ) {
        guard !subviews.isEmpty else {
            return
        }
        if isLandscape {
            placeLandscape(in: bounds, proposal: proposal, subviews: subviews)
        } else {
            placePortrait(in: bounds, proposal: proposal, subviews: subviews)
        }
    }
}

// MARK: - Portrait Layout

private extension TwoColumnLayout {
    func portraitSize(
        width: CGFloat,
        subviews: Subviews
    ) -> CGSize {
        var height: CGFloat = 0
        for (idx, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(
                ProposedViewSize(width: width, height: nil)
            )
            height += size.height
            if idx > 0 {
                height += spacing
            }
        }
        return CGSize(width: width, height: height)
    }

    func placePortrait(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews
    ) {
        let width = proposal.width ?? bounds.width
        var yOffset = bounds.minY
        for (idx, subview) in subviews.enumerated() {
            if idx > 0 {
                yOffset += spacing
            }
            let size = subview.sizeThatFits(
                ProposedViewSize(width: width, height: nil)
            )
            subview.place(
                at: CGPoint(x: bounds.minX, y: yOffset),
                proposal: ProposedViewSize(width: width, height: size.height)
            )
            yOffset += size.height
        }
    }
}

// MARK: - Landscape Layout

private extension TwoColumnLayout {
    func landscapeSize(
        width: CGFloat,
        subviews: Subviews
    ) -> CGSize {
        let colWidth = (width - spacing) / 2
        let split = min(splitIndex, subviews.count)
        let leftHeight = columnHeight(
            subviews: subviews.prefix(split), width: colWidth
        )
        let rightHeight = columnHeight(
            subviews: subviews.suffix(from: split), width: colWidth
        )
        return CGSize(width: width, height: max(leftHeight, rightHeight))
    }

    func columnHeight(
        subviews: Subviews.SubSequence,
        width: CGFloat
    ) -> CGFloat {
        var height: CGFloat = 0
        for (idx, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(
                ProposedViewSize(width: width, height: nil)
            )
            height += size.height
            if idx > 0 {
                height += spacing
            }
        }
        return height
    }

    func placeLandscape(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews
    ) {
        let totalWidth = proposal.width ?? bounds.width
        let colWidth = (totalWidth - spacing) / 2
        let split = min(splitIndex, subviews.count)

        placeColumn(
            subviews: subviews.prefix(split),
            xOrigin: bounds.minX,
            yOrigin: bounds.minY,
            width: colWidth
        )

        placeColumn(
            subviews: subviews.suffix(from: split),
            xOrigin: bounds.minX + colWidth + spacing,
            yOrigin: bounds.minY,
            width: colWidth
        )
    }

    func placeColumn(
        subviews: Subviews.SubSequence,
        xOrigin: CGFloat,
        yOrigin: CGFloat,
        width: CGFloat
    ) {
        var yOffset = yOrigin
        for (idx, subview) in subviews.enumerated() {
            if idx > 0 {
                yOffset += spacing
            }
            let size = subview.sizeThatFits(
                ProposedViewSize(width: width, height: nil)
            )
            subview.place(
                at: CGPoint(x: xOrigin, y: yOffset),
                proposal: ProposedViewSize(width: width, height: size.height)
            )
            yOffset += size.height
        }
    }
}
