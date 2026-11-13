// Park Card Carousel View
//
// Instagram album-style horizontal swipe showing each park
// with its GIS boundary polygon and grid square overlay.

import CarrierWaveData
import MapKit
import SwiftUI

// MARK: - ParkCardItem

/// A single park card with its boundary and grid square
struct ParkCardItem: Identifiable {
    let id: String
    let reference: String
    let name: String?
    let myGrid: String?
    let qsoCount: Int
    let boundary: ParkBoundary?
}

// MARK: - ParkCardCarouselView

/// Instagram album-style swipeable carousel of park maps with boundaries and grid overlay.
struct ParkCardCarouselView: View {
    // MARK: Internal

    let cards: [ParkCardItem]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentIndex) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    ParkCardView(card: card)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 240)

            if cards.count > 1 {
                pageIndicator
                    .padding(.top, 8)
            }
        }
    }

    // MARK: Private

    @State private var currentIndex = 0

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< cards.count, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.green : Color(.systemGray4))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - ParkCardView

/// Single card showing a park boundary on a map with grid square overlay.
struct ParkCardView: View {
    // MARK: Internal

    let card: ParkCardItem

    var body: some View {
        VStack(spacing: 0) {
            mapContent
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    parkLabel
                }
                .overlay(alignment: .bottomTrailing) {
                    statsLabel
                }

            if let name = card.name {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 12)
        .task {
            computeCamera()
        }
    }

    // MARK: Private

    @State private var cameraPosition: MapCameraPosition = .automatic

    private var mapContent: some View {
        Map(position: $cameraPosition, interactionModes: []) {
            if let boundary = card.boundary {
                ForEach(
                    Array(boundary.mergedPolygons.enumerated()),
                    id: \.offset
                ) { _, polygon in
                    MapPolygon(coordinates: polygon.exterior)
                        .foregroundStyle(.green.opacity(0.2))
                        .stroke(.green, lineWidth: 2)

                    MapPolygon(coordinates: polygon.skirt)
                        .foregroundStyle(.orange.opacity(0.1))
                        .stroke(.orange.opacity(0.3), lineWidth: 1)
                }
            }

            if let grid = card.myGrid,
               let gridInfo = gridSquareInfo(for: grid)
            {
                MapPolyline(coordinates: gridInfo.boundaryPath)
                    .stroke(.cyan.opacity(0.6), lineWidth: 2)

                Annotation(
                    gridInfo.locator,
                    coordinate: gridInfo.center,
                    anchor: .center
                ) {
                    Text(gridInfo.locator)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }

            if let grid = card.myGrid,
               let coord = MaidenheadConverter.coordinate(from: grid)
            {
                Annotation("My Location", coordinate: coord, anchor: .bottom) {
                    MapPinMarker(color: .blue, size: 10)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .allowsHitTesting(false)
    }

    private var parkLabel: some View {
        Text(card.reference)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.green.opacity(0.85), in: Capsule())
            .padding(8)
    }

    @ViewBuilder
    private var statsLabel: some View {
        if let grid = card.myGrid {
            HStack(spacing: 4) {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 8))
                Text(grid)
                    .font(.caption2.monospaced())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .padding(8)
        }
    }

    private func gridSquareInfo(for grid: String) -> GridSquareInfo? {
        guard grid.count >= 4,
              let bounds = MaidenheadConverter.gridBounds(for: grid)
        else {
            return nil
        }
        let locator = String(grid.prefix(4)).uppercased()
        let center = CLLocationCoordinate2D(
            latitude: (bounds.sw.latitude + bounds.ne.latitude) / 2,
            longitude: (bounds.sw.longitude + bounds.ne.longitude) / 2
        )
        let path = [
            bounds.sw,
            CLLocationCoordinate2D(
                latitude: bounds.ne.latitude, longitude: bounds.sw.longitude
            ),
            bounds.ne,
            CLLocationCoordinate2D(
                latitude: bounds.sw.latitude, longitude: bounds.ne.longitude
            ),
            bounds.sw,
        ]
        return GridSquareInfo(
            id: locator, locator: locator,
            center: center, boundaryPath: path
        )
    }

    private func computeCamera() {
        if let boundary = card.boundary {
            let bbox = boundary.bbox
            let center = CLLocationCoordinate2D(
                latitude: bbox.centerLat,
                longitude: bbox.centerLon
            )
            let latSpan = (bbox.maxLat - bbox.minLat) * 1.6
            let lonSpan = (bbox.maxLon - bbox.minLon) * 1.6
            // Ensure minimum span so small parks don't zoom in too tight
            let span = MKCoordinateSpan(
                latitudeDelta: max(latSpan, 0.02),
                longitudeDelta: max(lonSpan, 0.02)
            )
            cameraPosition = .region(
                MKCoordinateRegion(center: center, span: span)
            )
        } else if let grid = card.myGrid,
                  let coord = MaidenheadConverter.coordinate(from: grid)
        {
            // Fall back to grid center if no boundary
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(
                        latitudeDelta: 0.1,
                        longitudeDelta: 0.2
                    )
                )
            )
        }
    }
}
