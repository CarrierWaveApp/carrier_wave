import CoreLocation
import MapKit
import SwiftUI

// MARK: - GridSquareMapContent

/// MapKit content that renders Maidenhead 4-char grid square boundaries and labels
/// within the currently visible map region.
struct GridSquareMapContent: MapContent {
    let visibleGrids: [GridSquareInfo]

    var body: some MapContent {
        ForEach(visibleGrids) { grid in
            MapPolyline(coordinates: grid.boundaryPath)
                .stroke(.cyan.opacity(0.4), lineWidth: 1)

            Annotation(
                grid.locator,
                coordinate: grid.center,
                anchor: .center
            ) {
                Text(grid.locator)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.cyan.opacity(0.7))
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - GridSquareInfo

/// A single 4-char grid square with precomputed geometry for map display
struct GridSquareInfo: Identifiable {
    let id: String
    let locator: String
    let center: CLLocationCoordinate2D
    let boundaryPath: [CLLocationCoordinate2D]
}

// MARK: - GridSquareComputation

/// Computes visible grid squares from a map region
enum GridSquareComputation {
    /// Maximum number of grid squares to render for performance
    static let maxVisibleGrids = 400

    /// Compute grid squares visible in the given map region.
    /// Returns empty if the region is too large (too many grids).
    static func visibleGrids(
        in region: MKCoordinateRegion
    ) -> [GridSquareInfo] {
        let center = region.center
        let span = region.span

        // Don't render at very zoomed-out levels
        // At 2° lon × 1° lat per grid, a 40° span ≈ 20×40 = 800 grids
        guard span.latitudeDelta < 30, span.longitudeDelta < 60 else {
            return []
        }

        let swLat = max(center.latitude - span.latitudeDelta / 2, -90)
        let neLat = min(center.latitude + span.latitudeDelta / 2, 90)
        let swLon = max(center.longitude - span.longitudeDelta / 2, -180)
        let neLon = min(center.longitude + span.longitudeDelta / 2, 180)

        let sw = CLLocationCoordinate2D(latitude: swLat, longitude: swLon)
        let ne = CLLocationCoordinate2D(latitude: neLat, longitude: neLon)

        let locators = MaidenheadConverter.gridsInRegion(sw: sw, ne: ne)
        guard locators.count <= maxVisibleGrids else {
            return []
        }

        return locators.compactMap { locator in
            guard let bounds = MaidenheadConverter.gridBounds(for: locator) else {
                return nil
            }
            let centerCoord = CLLocationCoordinate2D(
                latitude: (bounds.sw.latitude + bounds.ne.latitude) / 2,
                longitude: (bounds.sw.longitude + bounds.ne.longitude) / 2
            )
            // Closed rectangle path
            let path = [
                bounds.sw,
                CLLocationCoordinate2D(latitude: bounds.ne.latitude, longitude: bounds.sw.longitude),
                bounds.ne,
                CLLocationCoordinate2D(latitude: bounds.sw.latitude, longitude: bounds.ne.longitude),
                bounds.sw,
            ]
            return GridSquareInfo(
                id: locator,
                locator: locator,
                center: centerCoord,
                boundaryPath: path
            )
        }
    }
}

// MARK: - GridSearchBar

/// Compact grid-square search control.
///
/// Renders as an icon-only pill by default to keep the map overlay clean, and
/// expands to a full text field only while the user is actively searching.
struct GridSearchBar: View {
    // MARK: Internal

    @Binding var searchText: String
    @Binding var isExpanded: Bool

    let onSearch: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                    if isExpanded {
                        isTextFieldFocused = true
                    } else {
                        searchText = ""
                    }
                }
            } label: {
                Image(systemName: isExpanded ? "xmark" : "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(width: 14, height: 14)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(isExpanded ? "Close grid search" : "Search grid")

            if isExpanded {
                TextField("Grid (e.g. FN31)", text: $searchText)
                    .font(.system(.caption, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($isTextFieldFocused)
                    .frame(minWidth: 100, maxWidth: 140)
                    .onSubmit {
                        submitSearch()
                    }

                if !searchText.isEmpty {
                    Button("Go") {
                        submitSearch()
                    }
                    .font(.caption.bold())
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    // MARK: Private

    @FocusState private var isTextFieldFocused: Bool

    private func submitSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard MaidenheadConverter.isValid(trimmed) else {
            return
        }
        onSearch(trimmed.uppercased())
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded = false
            searchText = ""
        }
    }
}

// MARK: - CurrentGridLabel

/// Shows the grid square at the map center
struct CurrentGridLabel: View {
    let grid: String

    var body: some View {
        Text(grid)
            .font(.system(.caption, design: .monospaced))
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
    }
}
