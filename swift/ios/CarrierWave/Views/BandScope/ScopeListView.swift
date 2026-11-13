import SwiftUI

// MARK: - ScopeListView

/// The frequency lens (spec §1): a frequency-sorted LIST — no leader
/// lines, no to-scale axis. Spectrum position is carried by the scrubber,
/// gap dividers, and sticky frequency headers. Filtered spots are hidden
/// (per-user decision 2026-07-04, superseding §17's dim-only rule); gap
/// math still runs on unfiltered data so QSY claims never lie, and the
/// scrubber keeps filtered ticks dimmed as the honest occupancy picture.
struct ScopeListView: View {
    // MARK: Internal

    let model: BandScopeViewModel

    @Binding var peekSpot: EnrichedSpot?
    @Binding var peekQSY: ScopeGap?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { timeline in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        listSections(now: timeline.date)
                    }
                }
                .onChange(of: model.scopeScrollSignal) {
                    if let target = model.scopeScrollTargetID {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(BandScopeTheme.background)
    }

    // MARK: Private

    /// One section per sticky-header interval (§5), keyed by the lower
    /// boundary in kHz.
    private struct HeaderSection: Identifiable {
        let boundaryKHz: Double
        let clusters: [ScopeCluster]

        var id: Double {
            boundaryKHz
        }
    }

    @State private var expandedClusters: Set<String> = []

    /// Clusters that survive filtering — a pileup stays when ANY member
    /// passes. Gap math still sees the unfiltered set.
    private var visibleClusters: [ScopeCluster] {
        guard model.filterService.isFiltering else {
            return model.scopeClusters
        }
        let pass = model.filterService.scopePassIDs
        return model.scopeClusters.filter { cluster in
            cluster.spots.contains { pass.contains($0.id) }
        }
    }

    private var sections: [HeaderSection] {
        let interval = BandScopeTunables.headerIntervalKHz
        var groups: [Double: [ScopeCluster]] = [:]
        for cluster in visibleClusters {
            let boundary = (cluster.minFrequencyKHz / interval).rounded(.down) * interval
            groups[boundary, default: []].append(cluster)
        }
        return groups.keys.sorted().map {
            HeaderSection(boundaryKHz: $0, clusters: groups[$0] ?? [])
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if model.scopeClusters.isEmpty {
                Text("No spots on \(model.activeBand)")
                    .font(.subheadline)
                    .foregroundStyle(BandScopeTheme.dim)
            } else {
                Text("All \(model.scopeUnfilteredCount) spots on \(model.activeBand) are filtered")
                    .font(.subheadline)
                    .foregroundStyle(BandScopeTheme.dim)
            }
            if let error = model.lastError ?? model.filterService.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 60)
    }

    @ViewBuilder
    private func listSections(now: Date) -> some View {
        let anchor = model.anchorStore.activeAnchor(band: model.activeBand, now: now)
        ForEach(sections) { section in
            Section {
                sectionRows(section, anchor: anchor, now: now)
            } header: {
                FrequencyHeader(boundaryKHz: section.boundaryKHz)
            }
        }
        if visibleClusters.isEmpty {
            emptyState
        }
    }

    private func sectionRows(
        _ section: HeaderSection, anchor: BandScopeAnchor?, now: Date
    ) -> some View {
        ForEach(section.clusters) { cluster in
            // YOU line sits at its sorted frequency position (§6).
            if let anchor, shouldInsertYouLine(before: cluster, anchor: anchor) {
                YouLineRow(anchor: anchor, now: now) {
                    model.anchorStore.clear()
                }
            }
            clusterRows(cluster, anchor: anchor, now: now)
            if let gap = model.scopeGaps[cluster.id] {
                ScopeGapDivider(gap: gap) {
                    peekQSY = gap
                }
            }
        }
    }

    @ViewBuilder
    private func clusterRows(
        _ cluster: ScopeCluster, anchor: BandScopeAnchor?, now: Date
    ) -> some View {
        let expanded = expandedClusters.contains(cluster.id)
        ScopeRow(
            cluster: cluster,
            profile: model.activeProfile,
            anchor: anchor,
            now: now,
            opacity: FreshnessFade.opacity(
                spotted: cluster.lead.spot.timestamp, now: now
            ),
            isExpanded: expanded
        ) {
            if cluster.isPileup {
                if expanded {
                    expandedClusters.remove(cluster.id)
                } else {
                    expandedClusters.insert(cluster.id)
                }
            } else {
                peekSpot = cluster.lead
            }
        }
        .id(cluster.id)
        .onScrollVisibilityChange(threshold: 0.1) { visible in
            model.setClusterVisible(
                id: cluster.id,
                frequencyKHz: cluster.minFrequencyKHz,
                visible: visible
            )
        }
        // LazyVStack reclaims far-off-screen rows WITHOUT firing the
        // visibility callback — onDisappear is the teardown signal that
        // actually arrives, else stale entries widen the scrubber window.
        .onDisappear {
            model.setClusterVisible(
                id: cluster.id,
                frequencyKHz: cluster.minFrequencyKHz,
                visible: false
            )
        }
        if expanded {
            ForEach(visibleSpots(in: cluster)) { spot in
                ScopeSubRow(
                    spot: spot,
                    profile: model.activeProfile,
                    isBustedSuspect: model.scopeBustedIDs.contains(spot.id),
                    opacity: FreshnessFade.opacity(
                        spotted: spot.spot.timestamp, now: now
                    )
                ) {
                    peekSpot = spot
                }
            }
        }
    }

    /// Expanded pileup members also hide when filtered.
    private func visibleSpots(in cluster: ScopeCluster) -> [EnrichedSpot] {
        guard model.filterService.isFiltering else {
            return cluster.spots
        }
        let pass = model.filterService.scopePassIDs
        return cluster.spots.filter { pass.contains($0.id) }
    }

    /// The YOU line renders before the first VISIBLE cluster above the
    /// anchor.
    private func shouldInsertYouLine(
        before cluster: ScopeCluster, anchor: BandScopeAnchor
    ) -> Bool {
        guard cluster.minFrequencyKHz >= anchor.frequencyKHz else {
            return false
        }
        // Only before the FIRST such cluster.
        let firstAbove = visibleClusters.first {
            $0.minFrequencyKHz >= anchor.frequencyKHz
        }
        return firstAbove?.id == cluster.id
    }
}

// MARK: - FrequencyHeader

/// Sticky round-frequency header (§5): `14.060`, 11pt bold mono, dim,
/// hairline rule — carries the ABSOLUTE frequency so per-row absolute can
/// drop when anchored.
private struct FrequencyHeader: View {
    let boundaryKHz: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "%.3f", boundaryKHz / 1_000))
                .font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(BandScopeTheme.dim)
            Rectangle()
                .fill(BandScopeTheme.line)
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .background(BandScopeTheme.background.opacity(0.95))
    }
}

// MARK: - YouLineRow

/// `YOU ─────── 14.0625 · tuned 34s ago ×` (§6) at anchor-trust opacity.
private struct YouLineRow: View {
    // MARK: Internal

    let anchor: BandScopeAnchor
    let now: Date
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("YOU")
                .font(.caption2.weight(.bold).monospaced())
            Rectangle()
                .fill(BandScopeTheme.youLine)
                .frame(height: 1)
            Text(label)
                .font(.caption2.monospaced())
                .lineLimit(1)
                .fixedSize()
            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel("Clear anchor")
        }
        .foregroundStyle(BandScopeTheme.youLine)
        .padding(.horizontal, 16)
        .frame(height: 24)
        .opacity(anchor.trust(at: now))
    }

    // MARK: Private

    private var label: String {
        let freq = String(format: "%.4f", anchor.frequencyKHz / 1_000)
        let seconds = Int(now.timeIntervalSince(anchor.setAt))
        let age = seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m"
        return "\(freq) · tuned \(age) ago"
    }
}
