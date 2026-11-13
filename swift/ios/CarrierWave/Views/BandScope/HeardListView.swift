import SwiftUI

// MARK: - HeardListView

/// The recency lens (spec §13): multi-band, per-station, strictly
/// newest-first — NEVER re-ranked by priority. Incoming spots batch
/// behind the pill; needs get their own shelf; time-bucket sticky headers
/// replace frequency headers. No freshness fade here (position already
/// encodes time). Hard-hiding filtered stations is allowed.
struct HeardListView: View {
    // MARK: Internal

    let model: BandScopeViewModel

    @Binding var peekSpot: EnrichedSpot?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { timeline in
            ScrollViewReader { proxy in
                ZStack(alignment: .top) {
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                            BandFilterTiles(model: model)
                            NeedsShelf(model: model, peekSpot: $peekSpot)
                            Color.clear.frame(height: 1).id(Self.topID)
                            bucketSections(now: timeline.date)
                        }
                    }
                    .onChange(of: model.heardScrollToTopSignal) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(Self.topID, anchor: .top)
                        }
                    }

                    if model.heardPendingCount > 0 {
                        NewSpotsPill(count: model.heardPendingCount) {
                            model.mergeHeardPending()
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
        .background(BandScopeTheme.background)
    }

    // MARK: Private

    private static let topID = "heard-top"

    private var emptyState: some View {
        Text("Nothing heard yet")
            .font(.subheadline)
            .foregroundStyle(BandScopeTheme.dim)
            .padding(.top, 60)
    }

    @ViewBuilder
    private func bucketSections(now: Date) -> some View {
        let buckets = HeardAggregation.bucketed(model.heardDisplayed, now: now)
        let boundary = model.unseenBoundary
        ForEach(buckets, id: \.bucket) { group in
            Section {
                ForEach(group.stations) { station in
                    // Unseen line (§13): at the previous newest-item
                    // timestamp — everything above it arrived unseen.
                    if let boundary, isUnseenBoundary(station, boundary: boundary) {
                        UnseenLine(date: boundary)
                    }
                    HeardRow(
                        station: station,
                        profile: model.activeProfile,
                        isWPMDimmed: isWPMDimmed(station),
                        now: now
                    ) {
                        peekSpot = station.latest
                    }
                }
            } header: {
                BucketHeader(title: group.bucket.title)
            }
        }
        if model.heardDisplayed.isEmpty {
            emptyState
        }
    }

    /// The line sits above the first station at-or-before the boundary.
    private func isUnseenBoundary(_ station: HeardStation, boundary: Date) -> Bool {
        guard station.latest.spot.timestamp <= boundary else {
            return false
        }
        let first = model.heardDisplayed.first {
            $0.latest.spot.timestamp <= boundary
        }
        return first?.id == station.id
    }

    /// WPM ceiling dims (never hides) in Heard too (§17).
    private func isWPMDimmed(_ station: HeardStation) -> Bool {
        guard let pass = model.filterService.wpmPassIDs else {
            return false
        }
        return !pass.contains(station.latest.id)
    }
}

// MARK: - BucketHeader

private struct BucketHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2.weight(.bold))
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

// MARK: - UnseenLine

/// `── new since HH:MM ──` (§13) — the highest-value cue in the view.
private struct UnseenLine: View {
    // MARK: Internal

    let date: Date

    var body: some View {
        HStack(spacing: 6) {
            line
            Text("new since \(date.formatted(date: .omitted, time: .shortened))")
                .font(.caption2.monospaced())
                .foregroundStyle(BandScopeTheme.blue)
                .fixedSize()
            line
        }
        .padding(.horizontal, 16)
        .frame(height: 18)
    }

    // MARK: Private

    private var line: some View {
        Rectangle()
            .fill(BandScopeTheme.blue.opacity(0.5))
            .frame(height: 1)
    }
}

// MARK: - NewSpotsPill

/// `▲ N new spots` (§13): sticky near the top; tapping merges pending,
/// scrolls to top, and drops the unseen line.
struct NewSpotsPill: View {
    let count: Int
    let onMerge: () -> Void

    var body: some View {
        Button(action: onMerge) {
            Label("\(count) new spot\(count == 1 ? "" : "s")", systemImage: "arrowtriangle.up.fill")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .accessibilityLabel("Show \(count) new spots")
    }
}
