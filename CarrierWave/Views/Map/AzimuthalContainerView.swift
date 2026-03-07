//
//  AzimuthalContainerView.swift
//  CarrierWave
//
//  Container view that wires up spot data, QSOs, antenna pattern,
//  and compass heading into the azimuthal map view.
//

import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import SwiftUI

// MARK: - AzimuthalContainerView

struct AzimuthalContainerView: View {
    // MARK: Internal

    static let modeOrder = ["CW", "SSB", "FT8", "FT4", "RTTY", "FM", "AM", "DIGI"]

    let myGrid: String
    let spots: [UnifiedSpot]
    let sessionQSOs: [QSO]
    let sessionAntenna: String?
    var isLoadingSpots = false

    @State var compassService = CompassHeadingService()
    @State var selectedAntennaType: AntennaType = .vertical
    @State var manualOrientation: Double = 0
    @State var useCompass = true
    @State var maxDistanceKm = 5_000.0 // Continental default
    @State var showPattern = false
    @State var selectedBand: String?
    @State var selectedMode: String?
    @State var showQSOs = false
    @State var selectedSources: Set<SpotSource> = Set(SpotSource.allCases)
    @State var showMapTiles = true
    @State var tileImage: CGImage?
    @State var tileDistanceKm: Double = 5_000.0 // Distance at which tile was rendered
    @State var tileRenderTask: Task<Void, Never>?
    @State var baseDistanceKm: Double = 5_000.0 // Snapshot at gesture start

    let tileRenderer = AzimuthalTileRenderer()

    var filteredSpots: [UnifiedSpot] {
        spots.filter { spot in
            let sourceMatch = selectedSources.contains(spot.source)
            let bandMatch = selectedBand == nil
                || BandUtilities.deriveBand(from: spot.frequencyKHz) == selectedBand
            let modeMatch = selectedMode == nil
                || spot.mode.uppercased() == selectedMode
            return sourceMatch && bandMatch && modeMatch
        }
    }

    var projectedSpots: [AzimuthalSpotPoint] {
        AzimuthalDataProvider.projectSpots(
            filteredSpots, from: myGrid, maxDistanceKm: maxDistanceKm
        )
    }

    var availableSources: [SpotSource] {
        let sources = Set(spots.map(\.source))
        return SpotSource.allCases.filter { sources.contains($0) }
    }

    var availableBands: [String] {
        let bands = Set(spots.compactMap { BandUtilities.deriveBand(from: $0.frequencyKHz) })
        return BandUtilities.bandOrder.filter { bands.contains($0) }
    }

    var availableModes: [String] {
        let modes = Set(spots.map { $0.mode.uppercased() })
        let ordered = Self.modeOrder.filter { modes.contains($0) }
        let remaining = modes.subtracting(Set(ordered)).sorted()
        return ordered + remaining
    }

    var currentDistanceLabel: String {
        DistanceOption.allCases.first { $0.km == maxDistanceKm }?.shortLabel ?? "Range"
    }

    var body: some View {
        VStack(spacing: 0) {
            bearingHeader
            Divider()
            filtersRow
            Divider()
            azimuthalContent
            Spacer(minLength: 0)
        }
        .onAppear {
            compassService.startUpdating()
            if showMapTiles {
                triggerTileRender()
            }
        }
        .onDisappear { compassService.stopUpdating() }
    }

    // MARK: Private

    private var effectiveOrientation: Double {
        var orientation: Double = if useCompass, let heading = compassService.heading {
            heading + manualOrientation
        } else {
            manualOrientation
        }
        // Normalize to 0..<360
        orientation = orientation.truncatingRemainder(dividingBy: 360.0)
        if orientation < 0 {
            orientation += 360.0
        }
        return orientation
    }

    private var antennaPattern: AntennaPattern? {
        guard showPattern else {
            return nil
        }
        return AntennaPattern.defaultPattern(for: selectedAntennaType, orientationDeg: 0)
    }

    private var projectedQSOs: [AzimuthalSpotPoint] {
        guard showQSOs else {
            return []
        }
        return AzimuthalDataProvider.projectQSOs(
            sessionQSOs, from: myGrid, maxDistanceKm: maxDistanceKm
        )
    }

    private var sectors: [BearingSector] {
        AzimuthalDataProvider.buildSectors(spots: projectedSpots, qsos: projectedQSOs)
    }

    private var spotSummary: String {
        let count = projectedSpots.count
        let total = filteredSpots.count
        if count == total {
            return "\(count) spots"
        }
        return "\(count)/\(total) with grid"
    }
}

// MARK: - Header

extension AzimuthalContainerView {
    var bearingHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(Int(effectiveOrientation))°")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Spacer()

                Picker("Orientation", selection: $useCompass) {
                    Text("Compass").tag(true)
                    Text("Manual").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }

            if !useCompass {
                HStack(spacing: 8) {
                    Text("\(Int(manualOrientation))°")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                    Slider(value: $manualOrientation, in: 0 ... 359, step: 1)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Map Content

extension AzimuthalContainerView {
    private var azimuthalContent: some View {
        AzimuthalMapView(
            sectors: sectors,
            spotPoints: projectedSpots,
            qsoPoints: projectedQSOs,
            antennaPattern: antennaPattern,
            compassHeading: compassService.heading,
            maxDistanceKm: maxDistanceKm,
            worldRotation: -effectiveOrientation,
            tileImage: tileImage,
            tileScale: tileDistanceKm / maxDistanceKm,
            isLoadingSpots: isLoadingSpots
        )
        .padding(8)
        .gesture(pinchZoomGesture)
    }
}

// MARK: - Zoom Gesture

extension AzimuthalContainerView {
    private static let minDistanceKm = 500.0
    private static let maxDistanceKmLimit = AzimuthalProjection.earthHalfCircumferenceKm

    private var pinchZoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // Pinch in (magnification > 1) = zoom in = decrease distance
                let newDistance = baseDistanceKm / value.magnification
                maxDistanceKm = min(
                    max(newDistance, Self.minDistanceKm),
                    Self.maxDistanceKmLimit
                )
            }
            .onEnded { _ in
                baseDistanceKm = maxDistanceKm
                if showMapTiles {
                    triggerTileRender()
                }
            }
    }
}

// MARK: - Tile Rendering

extension AzimuthalContainerView {
    func triggerTileRender() {
        tileRenderTask?.cancel()
        guard let coord = MaidenheadConverter.coordinate(from: myGrid) else {
            return
        }
        let lat = coord.latitude
        let lon = coord.longitude
        let distance = maxDistanceKm
        let renderer = tileRenderer
        tileRenderTask = Task {
            let image = await renderer.render(
                centerLat: lat,
                centerLon: lon,
                maxDistanceKm: distance
            )
            if !Task.isCancelled {
                tileImage = image
                tileDistanceKm = distance
            }
        }
    }
}
