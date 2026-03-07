//
//  AzimuthalTileRenderer.swift
//  CarrierWave
//
//  Background actor that captures a Mercator map snapshot via MKMapSnapshotter
//  and reprojects it pixel-by-pixel into azimuthal equidistant projection space.
//

import CarrierWaveCore
import CoreGraphics
import MapKit
import os.log

// MARK: - AzimuthalTileRenderer

actor AzimuthalTileRenderer {
    // MARK: Internal

    /// Render a tile image reprojected into azimuthal equidistant space.
    func render(
        centerLat: Double,
        centerLon: Double,
        maxDistanceKm: Double,
        resolution: Int = 512
    ) async -> CGImage? {
        let key = CacheKey(
            centerLat: round(centerLat * 100) / 100,
            centerLon: round(centerLon * 100) / 100,
            maxDistanceKm: maxDistanceKm,
            resolution: resolution
        )

        if let cached = cache[key] {
            return cached
        }

        guard let data = await captureSnapshotData(
            centerLat: centerLat,
            centerLon: centerLon,
            maxDistanceKm: maxDistanceKm,
            resolution: resolution
        ) else {
            return nil
        }

        let result = reprojectImage(
            source: data.image,
            mapping: data.mapping,
            center: (centerLat, centerLon),
            maxDistanceKm: maxDistanceKm,
            resolution: resolution
        )

        if let result {
            cache[key] = result
            trimCache()
        }

        return result
    }

    // MARK: Private

    private struct CacheKey: Hashable, Sendable {
        let centerLat: Double
        let centerLon: Double
        let maxDistanceKm: Double
        let resolution: Int
    }

    private struct SnapshotData: Sendable {
        let image: CGImage
        let mapping: SnapshotMapping
    }

    /// Calibrated mapping from lat/lon to source image pixel coordinates.
    /// Derived from snapshot.point(for:) reference samples.
    private struct SnapshotMapping: Sendable {
        let centerPixelX: Double
        let centerPixelY: Double
        let pixelsPerDegreeLon: Double
        let pixelsPerMercUnit: Double // negative: higher lat → smaller pixel Y

        let imageWidth: Int

        func pixelX(lon: Double) -> Int {
            let raw = Int((centerPixelX + lon * pixelsPerDegreeLon).rounded(.down))
            // Wrap by image width — the snapshot is centered on the user's longitude,
            // so coordinates within the visible ~180° range map correctly.
            var px = raw % imageWidth
            if px < 0 {
                px += imageWidth
            }
            return px
        }

        func pixelY(lat: Double) -> Int {
            let clamped = min(max(lat, -85.0), 85.0)
            let latRad = clamped * .pi / 180.0
            let merc = log(tan(latRad) + 1.0 / cos(latRad))
            return Int((centerPixelY + merc * pixelsPerMercUnit).rounded(.down))
        }
    }

    private static let maxCacheEntries = 4

    nonisolated private let logger = Logger(subsystem: "com.jsvana.FullDuplex", category: "TileRenderer")

    private var cache: [CacheKey: CGImage] = [:]

    /// Capture a focused map snapshot centered on the user's location.
    /// MKMapRect.world and full-globe MKCoordinateRegion always render ~180°
    /// centered on 0° longitude. A focused region is properly respected.
    @MainActor
    private func captureSnapshotData(
        centerLat: Double,
        centerLon: Double,
        maxDistanceKm: Double,
        resolution: Int
    ) async -> SnapshotData? {
        // Size region to cover the azimuthal circle with margin.
        let arcDeg = min(
            90.0, maxDistanceKm / AzimuthalProjection.earthHalfCircumferenceKm * 180.0
        )
        let latDelta = min(170.0, arcDeg * 2 + 20)
        let cosCenter = max(cos(centerLat * .pi / 180.0), 0.1)
        let lonDelta = min(360.0, (arcDeg * 2 + 20) / cosCenter * 1.5)

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
        options.size = CGSize(width: resolution * 2, height: resolution * 2)
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false

        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start(),
              let cgImage = snapshot.image.cgImage
        else {
            return nil
        }

        // Calibrate using reference points near the user (guaranteed visible).
        let imgScale = snapshot.image.scale
        let pRef = snapshot.point(
            for: CLLocationCoordinate2D(latitude: 0, longitude: centerLon)
        )
        let pRefPlus10 = snapshot.point(
            for: CLLocationCoordinate2D(latitude: 0, longitude: centerLon + 10)
        )
        let pLat30 = snapshot.point(
            for: CLLocationCoordinate2D(latitude: 30, longitude: centerLon)
        )

        let pxPerDegLon = (pRefPlus10.x - pRef.x) * imgScale / 10.0
        let centerPxX = pRef.x * imgScale - centerLon * pxPerDegLon
        let centerPxY = pRef.y * imgScale

        let merc30 = log(tan(30.0 * .pi / 180.0) + 1.0 / cos(30.0 * .pi / 180.0))
        let pxPerMercUnit = (pLat30.y - pRef.y) * imgScale / merc30

        let mapping = SnapshotMapping(
            centerPixelX: centerPxX,
            centerPixelY: centerPxY,
            pixelsPerDegreeLon: pxPerDegLon,
            pixelsPerMercUnit: pxPerMercUnit,
            imageWidth: cgImage.width
        )

        logger.info("image: \(cgImage.width)×\(cgImage.height), scale: \(imgScale)")
        logger.info("region: \(latDelta)° × \(lonDelta)° centered on (\(centerLat), \(centerLon))")
        logger.info("pxPerDegLon: \(pxPerDegLon), pxPerMercUnit: \(pxPerMercUnit)")

        return SnapshotData(image: cgImage, mapping: mapping)
    }

    /// Rasterize a CGImage into an RGBA bitmap for direct pixel access.
    private func rasterize(_ image: CGImage) -> (ptr: UnsafeMutablePointer<UInt8>, bytesPerRow: Int)? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let ptr = ctx.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }
        return (ptr, ctx.bytesPerRow)
    }

    private func reprojectImage(
        source: CGImage,
        mapping: SnapshotMapping,
        center: (lat: Double, lon: Double),
        maxDistanceKm: Double,
        resolution: Int
    ) -> CGImage? {
        let proj = AzimuthalProjection(centerLatDeg: center.lat, centerLonDeg: center.lon)
        let scale = maxDistanceKm / AzimuthalProjection.earthHalfCircumferenceKm

        let srcWidth = source.width
        let srcHeight = source.height

        guard let src = rasterize(source) else {
            return nil
        }
        let srcPtr = src.ptr
        let srcBytesPerRow = src.bytesPerRow

        let outWidth = resolution
        let outHeight = resolution
        let outBytesPerRow = outWidth * 4
        var outBuffer = [UInt8](repeating: 0, count: outHeight * outBytesPerRow)

        var rendered = 0, skippedCircle = 0, skippedInverse = 0, skippedBounds = 0

        for py in 0 ..< outHeight {
            for px in 0 ..< outWidth {
                let nx = (Double(px) / Double(outWidth - 1) * 2.0 - 1.0) * scale
                let ny = (1.0 - Double(py) / Double(outHeight - 1) * 2.0) * scale

                if nx * nx + ny * ny > 1.0 {
                    skippedCircle += 1; continue
                }

                guard let coord = proj.inverseProject(nx: nx, ny: ny) else {
                    skippedInverse += 1; continue
                }

                let srcX = mapping.pixelX(lon: coord.lonDeg)
                let srcY = mapping.pixelY(lat: coord.latDeg)

                guard srcX >= 0, srcX < srcWidth, srcY >= 0, srcY < srcHeight else {
                    skippedBounds += 1; continue
                }

                let srcOffset = srcY * srcBytesPerRow + srcX * 4
                let dstOffset = py * outBytesPerRow + px * 4

                outBuffer[dstOffset] = srcPtr[srcOffset]
                outBuffer[dstOffset + 1] = srcPtr[srcOffset + 1]
                outBuffer[dstOffset + 2] = srcPtr[srcOffset + 2]
                outBuffer[dstOffset + 3] = 255
                rendered += 1
            }
        }
        logger.info(
            "rendered: \(rendered), circle: \(skippedCircle), inverse: \(skippedInverse), bounds: \(skippedBounds)"
        )
        logger.info("srcSize: \(srcWidth)×\(srcHeight), srcBytesPerRow: \(srcBytesPerRow) (min: \(srcWidth * 4))")

        return createCGImage(from: &outBuffer, width: outWidth, height: outHeight)
    }

    private func createCGImage(from buffer: inout [UInt8], width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: &buffer, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        return context.makeImage()
    }

    private func trimCache() {
        while cache.count > Self.maxCacheEntries {
            cache.removeValue(forKey: cache.keys.first!)
        }
    }
}
