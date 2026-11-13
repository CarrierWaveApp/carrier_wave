// Renders TOTABragSheetView to a UIImage for share-sheet output.
//
// Mirrors the pattern in ActivationShareRenderer: pre-render the contact
// map to a UIImage (so MapKit/Canvas content snapshots cleanly), embed it
// as Image(uiImage:) inside the brag sheet, then snapshot the SwiftUI view
// with ImageRenderer. This is the same render path POTA, the periodic brag
// sheet, and the activity-feed card all use — every share surface produces
// a complete card with the maps drawn in.

import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - TOTABragSheetRenderer

@MainActor
enum TOTABragSheetRenderer {
    // MARK: Internal

    /// Render the brag sheet to a UIImage. Async because the contact map
    /// is rendered via `MKMapSnapshotter` for adaptive style and via the
    /// Rust `renderShareMap` FFI (off-main) for the custom styles.
    static func render(session: LoggingSession, qsos: [QSO]) async -> UIImage? {
        let myCoord = computeMyCoordinate(session: session)
        let markers = computeMarkers(qsos: qsos)
        let contactMap = await renderContactMap(markers: markers, myCoordinate: myCoord)

        let view = TOTABragSheetView(
            session: session,
            qsos: qsos,
            contactMapImage: contactMap
        )
        return BragSheetImageRenderer.snapshot(view, width: 360)
    }

    // MARK: Private

    private static func computeMyCoordinate(session: LoggingSession) -> CLLocationCoordinate2D? {
        if let lat = session.activationLatitude, let lon = session.activationLongitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if let grid = session.myGrid,
           let coord = MaidenheadConverter.coordinate(from: grid)
        {
            return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
        }
        return nil
    }

    private static func computeMarkers(qsos: [QSO]) -> [ShareMapMarker] {
        qsos.compactMap { qso in
            guard let grid = qso.theirGrid,
                  let coord = MaidenheadConverter.coordinate(from: grid)
            else {
                return nil
            }
            return ShareMapMarker(
                coordinate: CLLocationCoordinate2D(
                    latitude: coord.latitude, longitude: coord.longitude
                ),
                rstColor: RSTColorHelper.uiColor(
                    rstSent: qso.rstSent, rstReceived: qso.rstReceived
                )
            )
        }
    }

    /// Render the contact map to a UIImage at 332×160 (the on-card size).
    /// Custom styles render via the Rust `renderShareMap` FFI; adaptive uses
    /// MKMapSnapshotter.
    private static func renderContactMap(
        markers: [ShareMapMarker],
        myCoordinate: CLLocationCoordinate2D?
    ) async -> UIImage? {
        guard !markers.isEmpty else {
            return nil
        }
        let size = CGSize(width: 332, height: 160)
        let style = ShareMapStyle.current

        // Azimuthal needs a resolved operator QTH as its projection center;
        // with none, fall through to MapKit rather than a (0,0)-centered map.
        // MapKit can't show more than 180° of longitude, so QTH-centered
        // fits wider than that use the Rust renderer in Midnight.
        let ffiStyle: ShareMapStyle? =
            if style.ffiStyle != nil {
                style
            } else if ActivationMapHelpers.needsWideRenderer(
                qsoCoordinates: markers.map(\.coordinate), myCoordinate: myCoordinate
            ) {
                .midnight
            } else {
                nil
            }
        if let ffiStyle, ffiStyle != .azimuthal || myCoordinate != nil {
            let pins = markers.map { marker in
                ShareMapFFIRenderer.Pin.colored(
                    marker.coordinate, color: marker.rstColor
                )
            }
            if let image = await ShareMapFFIRenderer.render(
                pins: pins, myCoordinate: myCoordinate,
                style: ffiStyle, size: size, scale: 2.0,
                qthCentered: true
            ) {
                return image
            }
        }
        // Adaptive / standard MapKit — use MKMapSnapshotter for the share path.
        return await snapshotMap(
            markers: markers, myCoordinate: myCoordinate, size: size
        )
    }

    private static func snapshotMap(
        markers: [ShareMapMarker],
        myCoordinate: CLLocationCoordinate2D?,
        size: CGSize
    ) async -> UIImage? {
        let coords = markers.map(\.coordinate)
        guard let region = ActivationMapHelpers.qthCenteredRegion(
            qsoCoordinates: coords, myCoordinate: myCoordinate
        ) else {
            return nil
        }
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.mapType = .standard
        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await snapshotter.start()
            return drawOverlay(
                snapshot: snapshot, markers: markers, myCoordinate: myCoordinate
            )
        } catch {
            return nil
        }
    }

    /// Draw chaser pins + QTH dot on top of an MKMapSnapshotter image.
    private static func drawOverlay(
        snapshot: MKMapSnapshotter.Snapshot,
        markers: [ShareMapMarker],
        myCoordinate: CLLocationCoordinate2D?
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)
            let ctx = UIGraphicsGetCurrentContext()
            for marker in markers {
                let pt = snapshot.point(for: marker.coordinate)
                ctx?.setFillColor(marker.rstColor.cgColor)
                ctx?.fillEllipse(in: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10))
                ctx?.setStrokeColor(UIColor.white.cgColor)
                ctx?.setLineWidth(1.5)
                ctx?.strokeEllipse(in: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10))
            }
            if let myCoord = myCoordinate {
                let pt = snapshot.point(for: myCoord)
                ctx?.setFillColor(UIColor.white.cgColor)
                ctx?.fillEllipse(in: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10))
                ctx?.setStrokeColor(UIColor.purple.cgColor)
                ctx?.setLineWidth(2.0)
                ctx?.strokeEllipse(in: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10))
            }
        }
    }
}

// MARK: - BragSheetImageRenderer

/// Shared snapshot helper used by every brag-sheet share path. ImageRenderer
/// captures Canvas + Image content (including pre-rendered map images)
/// reliably; UIHostingController+drawHierarchy does not.
@MainActor
enum BragSheetImageRenderer {
    static func snapshot(_ view: some View, width: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 3.0
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
