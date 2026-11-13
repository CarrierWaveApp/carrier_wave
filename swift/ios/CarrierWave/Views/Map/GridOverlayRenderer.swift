//
//  GridOverlayRenderer.swift
//  CarrierWave
//
//  Renders Maidenhead grid square polygons on the SwiftUI Map as colored overlays.
//

import CarrierWaveCore
import CoreLocation
import MapKit
import SwiftUI

// MARK: - GridMapPolygon

/// A single grid square polygon for map rendering.
struct GridMapPolygon: Identifiable {
    let id: String // 4-char grid (e.g. "FN42")
    let coordinates: [CLLocationCoordinate2D]
    let status: GridSquareStatus
    let qsoCount: Int
}

// MARK: - GridOverlayRenderer

/// Computes grid polygons from a GridTrackerSummary for display on the SwiftUI Map.
nonisolated enum GridOverlayRenderer {
    /// Build polygons for all worked grids.
    static func buildPolygons(from summary: GridTrackerSummary) -> [GridMapPolygon] {
        summary.gridData.values.compactMap { data in
            guard let corners = gridCorners(for: data.grid) else {
                return nil
            }
            return GridMapPolygon(
                id: data.grid,
                coordinates: corners,
                status: data.status,
                qsoCount: data.qsoCount
            )
        }
    }

    /// Compute the four corner coordinates of a 4-character Maidenhead grid square.
    static func gridCorners(for grid: String) -> [CLLocationCoordinate2D]? {
        let grid = grid.uppercased()
        guard grid.count >= 4 else {
            return nil
        }

        let chars = Array(grid)
        guard let lonField = chars[0].asciiValue.map({ Int($0) - 65 }),
              let latField = chars[1].asciiValue.map({ Int($0) - 65 }),
              let lonSquare = chars[2].wholeNumberValue,
              let latSquare = chars[3].wholeNumberValue
        else {
            return nil
        }

        // Base coordinates (southwest corner)
        let swLon = Double(lonField * 20 - 180 + lonSquare * 2)
        let swLat = Double(latField * 10 - 90 + latSquare)

        // Each square is 2° longitude × 1° latitude
        let neLon = swLon + 2.0
        let neLat = swLat + 1.0

        return [
            CLLocationCoordinate2D(latitude: swLat, longitude: swLon),
            CLLocationCoordinate2D(latitude: neLat, longitude: swLon),
            CLLocationCoordinate2D(latitude: neLat, longitude: neLon),
            CLLocationCoordinate2D(latitude: swLat, longitude: neLon),
            CLLocationCoordinate2D(latitude: swLat, longitude: swLon), // close the polygon
        ]
    }

    /// Color for a grid polygon based on its status.
    static func fillColor(for status: GridSquareStatus) -> Color {
        switch status {
        case .notWorked:
            .clear
        case .worked:
            Color.blue.opacity(0.2)
        case .confirmed:
            Color.green.opacity(0.3)
        }
    }

    /// Stroke color for grid polygons.
    static func strokeColor(for status: GridSquareStatus) -> Color {
        switch status {
        case .notWorked:
            .clear
        case .worked:
            Color.blue.opacity(0.3)
        case .confirmed:
            Color.green.opacity(0.4)
        }
    }
}
