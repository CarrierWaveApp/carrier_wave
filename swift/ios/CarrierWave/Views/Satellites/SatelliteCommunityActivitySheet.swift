import SwiftUI

// MARK: - SatelliteCommunityActivitySheet

/// AMSAT's community status grid ("who heard what, when") rebuilt from the
/// server's accumulated report history and enriched by the engine: every
/// AMSAT-tracked transmitter as a list row whose full-width strip holds the
/// whole week in AMSAT's legend colours, with the catalog's SatNOGS mode,
/// your next pass of that bird, and how many QSOs you logged through it.
/// Tapping a row pushes the hour-by-hour history, where "Show on Map"
/// selects the satellite.
struct SatelliteCommunityActivitySheet: View {
    // MARK: Internal

    let model: SatelliteTrackerModel
    /// A capability row id to open straight away (from the info card).
    var initialRowID: String?
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack(path: $path) {
            content
                .safeAreaInset(edge: .top) {
                    legend
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                }
                .navigationTitle("Community Activity")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: String.self) { rowID in
                    if let row = activity?.rows.first(where: { $0.id == rowID }) {
                        CommunityTransmitterDetailView(model: model, row: row) { noradID in
                            onSelect(noradID)
                            dismiss()
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        optionsMenu
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        .task(id: cellSeconds) {
            await load(force: false)
        }
    }

    // MARK: Private

    /// Cell widths offered, in seconds.
    private static let cellChoices: [(label: String, seconds: Int)] = [
        ("1 hour", 3_600),
        ("3 hours", 3 * 3_600),
        ("6 hours", 6 * 3_600),
        ("1 day", 24 * 3_600),
    ]

    @Environment(\.dismiss) private var dismiss
    @State private var activity: CommunityActivity?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var path = NavigationPath()
    @State private var openedInitialRow = false
    /// Shared zoom/pan window for every strip (nil until data arrives).
    @State private var viewport: CommunityViewport?

    @AppStorage("satellite.communityCellSeconds") private var cellSeconds = 3 * 3_600
    @AppStorage("satellite.communityFavoritesOnly") private var favoritesOnly = false
    @AppStorage("satellite.communityHideSilent") private var hideSilent = false
    @AppStorage("satellite.communityCatalogOnly") private var catalogOnly = false

    private var favorites: FavoriteSatellitesStore {
        .shared
    }

    private var visibleRows: [CommunityActivityRow] {
        guard let activity else {
            return []
        }
        let rows = activity.rows.filter { row in
            (!favoritesOnly || isFavorite(row))
                && (!hideSilent || row.heardInWindow)
                && (!catalogOnly || row.inCatalog)
        }
        // Favorites float to the top, AMSAT's order otherwise.
        let starred = rows.filter { isFavorite($0) }
        let others = rows.filter { !isFavorite($0) }
        return starred + others
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Cell width", selection: $cellSeconds) {
                ForEach(Self.cellChoices, id: \.seconds) { choice in
                    Text(choice.label).tag(choice.seconds)
                }
            }
            Toggle("Favorites Only", isOn: $favoritesOnly)
            Toggle("Hide Silent Birds", isOn: $hideSilent)
            Toggle("In My Catalog Only", isOn: $catalogOnly)
            Divider()
            Button {
                Task { await load(force: true) }
            } label: {
                Label("Refresh Reports", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
        } label: {
            Image(systemName: favoritesOnly || hideSilent || catalogOnly
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Grid options")
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if let viewport, viewport.isZoomed, let activity {
                    Button {
                        self.viewport = CommunityViewport(activity: activity)
                    } label: {
                        Label(zoomLabel(viewport), systemImage: "arrow.down.left.and.arrow.up.right")
                            .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .accessibilityLabel("Reset zoom")
                }
                ForEach(
                    [CommunityActivityStatus.heard, .telemetryOnly, .notHeard, .conflicting],
                    id: \.label
                ) { status in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(status.color)
                            .frame(width: 10, height: 10)
                        Text(status.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading, activity == nil {
            ProgressView("Loading community reports…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError, activity == nil {
            ContentUnavailableView {
                Label("Reports Unavailable", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text(loadError)
            } actions: {
                Button("Try Again") {
                    Task { await load(force: true) }
                }
            }
        } else if let activity {
            if visibleRows.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to Show", systemImage: "moon.zzz")
                } description: {
                    Text("Every row is hidden by the current filters.")
                } actions: {
                    Button("Show All Rows") {
                        favoritesOnly = false
                        hideSilent = false
                        catalogOnly = false
                    }
                }
            } else {
                VStack(spacing: 0) {
                    CommunityActivityList(
                        activity: activity,
                        rows: visibleRows,
                        favorites: favorites.noradIDs,
                        viewport: Binding(
                            get: { viewport ?? CommunityViewport(activity: activity) },
                            set: { viewport = $0 }
                        )
                    )
                    footer(for: activity)
                }
            }
        }
    }

    private func footer(for activity: CommunityActivity) -> some View {
        HStack(spacing: 4) {
            AmsatAttributionLabel()
            Text("· pinch to zoom, drag sideways to pan")
            if let updatedAt = activity.updatedAt {
                Text("· updated \(updatedAt, style: .relative) ago")
            }
            if activity.isStale {
                Text("· offline, showing cached")
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text("\(activity.rows.count) transmitters")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    /// "2d 6h" style span of the zoomed slice, for the reset chip.
    private func zoomLabel(_ viewport: CommunityViewport) -> String {
        let hours = Int((viewport.span / 3_600).rounded())
        if hours >= 48 {
            return "\(hours / 24)d \(hours % 24)h"
        }
        return "\(hours)h"
    }

    private func isFavorite(_ row: CommunityActivityRow) -> Bool {
        row.noradID.map(favorites.isFavorite) ?? false
    }

    private func load(force: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await model.communityActivity(force: force, cellSeconds: cellSeconds)
            activity = loaded
            // Keep the zoomed slice across cell-width changes; re-snap to the
            // new bucket size.
            viewport = viewport.map { CommunityViewport(activity: loaded, range: $0.start ... $0.end) }
            loadError = nil
            if !openedInitialRow, let initialRowID, loaded.rows.contains(where: { $0.id == initialRowID }) {
                openedInitialRow = true
                path.append(initialRowID)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - CommunityActivityStatus + Color

extension CommunityActivityStatus {
    /// AMSAT's own (colour-blind-safe) legend colours so the grid reads the
    /// same as amsat.org; quiet cells take the system fill.
    var color: Color {
        switch self {
        case .quiet: Color(.systemGray5)
        case .heard: Color(red: 0.39, green: 0.56, blue: 1.0)
        case .telemetryOnly: Color(red: 1.0, green: 0.69, blue: 0.0)
        case .notHeard: Color(red: 0.86, green: 0.15, blue: 0.50)
        case .conflicting: Color(red: 1.0, green: 0.38, blue: 0.0)
        }
    }
}
