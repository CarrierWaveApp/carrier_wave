//
//  AzimuthalContainerView.swift
//  CarrierWave
//
//  Container view that wires up spot data, QSOs, antenna pattern,
//  and compass heading into the azimuthal map view.
//

import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - AzimuthalContainerView

struct AzimuthalContainerView: View {
    // MARK: Internal

    let myGrid: String
    let spots: [UnifiedSpot]
    let sessionQSOs: [QSO]
    let sessionAntenna: String?
    var isLoadingSpots = false

    var body: some View {
        VStack(spacing: 0) {
            bearingHeader
            Divider()
            filtersRow
            Divider()
            azimuthalContent
        }
        .onAppear { compassService.startUpdating() }
        .onDisappear { compassService.stopUpdating() }
    }

    // MARK: Private

    private static let modeOrder = ["CW", "SSB", "FT8", "FT4", "RTTY", "FM", "AM", "DIGI"]

    @State private var compassService = CompassHeadingService()
    @State private var selectedAntennaType: AntennaType = .vertical
    @State private var manualOrientation: Double = 0
    @State private var useCompass = true
    @State private var maxDistanceKm = 5_000.0 // Continental default
    @State private var showPattern = true
    @State private var selectedBand: String?
    @State private var selectedMode: String?
    @State private var showQSOs = true

    private var effectiveOrientation: Double {
        if useCompass, let heading = compassService.heading {
            return heading + manualOrientation
        }
        return manualOrientation
    }

    private var antennaPattern: AntennaPattern? {
        guard showPattern else {
            return nil
        }
        return AntennaPattern.defaultPattern(for: selectedAntennaType, orientationDeg: 0)
    }

    private var filteredSpots: [UnifiedSpot] {
        spots.filter { spot in
            let bandMatch = selectedBand == nil
                || BandUtilities.deriveBand(from: spot.frequencyKHz) == selectedBand
            let modeMatch = selectedMode == nil
                || spot.mode.uppercased() == selectedMode
            return bandMatch && modeMatch
        }
    }

    private var projectedSpots: [AzimuthalSpotPoint] {
        AzimuthalDataProvider.projectSpots(
            filteredSpots, from: myGrid, maxDistanceKm: maxDistanceKm
        )
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

    private var availableBands: [String] {
        let bands = Set(spots.compactMap { BandUtilities.deriveBand(from: $0.frequencyKHz) })
        return BandUtilities.bandOrder.filter { bands.contains($0) }
    }

    private var availableModes: [String] {
        let modes = Set(spots.map { $0.mode.uppercased() })
        let ordered = Self.modeOrder.filter { modes.contains($0) }
        let remaining = modes.subtracting(Set(ordered)).sorted()
        return ordered + remaining
    }

    private var currentDistanceLabel: String {
        DistanceOption.allCases.first { $0.km == maxDistanceKm }?.shortLabel ?? "Range"
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

// MARK: - Header & Controls

extension AzimuthalContainerView {
    private var bearingHeader: some View {
        HStack(spacing: 16) {
            // Large bearing display
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(effectiveOrientation))°")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(useCompass ? "Compass" : "Manual")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 90, alignment: .leading)

            Spacer()

            // Antenna type
            Menu {
                ForEach(AntennaType.allCases, id: \.self) { type in
                    Button {
                        selectedAntennaType = type
                    } label: {
                        HStack {
                            Text(type.displayName)
                            if type == selectedAntennaType {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Toggle("Show Pattern", isOn: $showPattern)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text(selectedAntennaType.displayName)
                        .lineLimit(1)
                }
                .font(.subheadline)
                .frame(minHeight: 44)
            }

            // Compass / manual toggle
            Button {
                useCompass.toggle()
            } label: {
                Image(
                    systemName: useCompass ? "compass.drawing" : "hand.point.up.left"
                )
                .font(.body)
                .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)

            // Manual slider when in manual mode
            if !useCompass {
                Slider(value: $manualOrientation, in: 0 ... 359, step: 5)
                    .frame(width: 80)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    private var filtersRow: some View {
        HStack(spacing: 8) {
            // Band filter
            Menu {
                Button {
                    selectedBand = nil
                } label: {
                    HStack {
                        Text("All Bands")
                        if selectedBand == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Divider()
                ForEach(availableBands, id: \.self) { band in
                    Button {
                        selectedBand = band
                    } label: {
                        HStack {
                            Text(band)
                            if selectedBand == band {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(selectedBand ?? "All Bands", systemImage: "waveform")
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(minHeight: 44)
            }

            // Mode filter
            Menu {
                Button {
                    selectedMode = nil
                } label: {
                    HStack {
                        Text("All Modes")
                        if selectedMode == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Divider()
                ForEach(availableModes, id: \.self) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        HStack {
                            Text(mode)
                            if selectedMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(selectedMode ?? "All Modes", systemImage: "dot.radiowaves.right")
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(minHeight: 44)
            }

            // Distance
            Menu {
                ForEach(DistanceOption.allCases, id: \.self) { option in
                    Button {
                        maxDistanceKm = option.km
                    } label: {
                        HStack {
                            Text(option.label)
                            if maxDistanceKm == option.km {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(currentDistanceLabel, systemImage: "arrow.left.and.right")
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(minHeight: 44)
            }

            Spacer()

            // QSOs toggle
            Button {
                showQSOs.toggle()
            } label: {
                Image(systemName: showQSOs ? "eye" : "eye.slash")
                    .font(.body)
                    .foregroundStyle(showQSOs ? .green : .secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showQSOs ? "Hide QSOs" : "Show QSOs")

            // Spot count / loading
            if isLoadingSpots {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 44)
            } else {
                Text(spotSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
        .padding(.horizontal)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Map Content

extension AzimuthalContainerView {
    @ViewBuilder
    private var azimuthalContent: some View {
        if isLoadingSpots, spots.isEmpty, sessionQSOs.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Loading spots...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if projectedSpots.isEmpty, projectedQSOs.isEmpty {
            ContentUnavailableView(
                "No Data with Grid Squares",
                systemImage: "mappin.slash",
                description: Text(
                    "Spots and QSOs need grid square data to appear on the azimuthal view."
                )
            )
        } else {
            AzimuthalMapView(
                sectors: sectors,
                spotPoints: projectedSpots,
                qsoPoints: projectedQSOs,
                antennaPattern: antennaPattern,
                compassHeading: compassService.heading,
                maxDistanceKm: maxDistanceKm,
                worldRotation: -effectiveOrientation
            )
            .padding(8)
        }
    }
}

// MARK: - DistanceOption

private enum DistanceOption: CaseIterable {
    case regional // 2,500 km
    case continental // 5,000 km
    case hemispheric // 10,000 km
    case global // 20,000 km

    // MARK: Internal

    var km: Double {
        switch self {
        case .regional: 2_500
        case .continental: 5_000
        case .hemispheric: 10_000
        case .global: AzimuthalProjection.earthHalfCircumferenceKm
        }
    }

    var label: String {
        switch self {
        case .regional: "Regional (2,500 km)"
        case .continental: "Continental (5,000 km)"
        case .hemispheric: "Hemispheric (10,000 km)"
        case .global: "Global"
        }
    }

    var shortLabel: String {
        switch self {
        case .regional: "2.5k km"
        case .continental: "5k km"
        case .hemispheric: "10k km"
        case .global: "Global"
        }
    }
}

// MARK: - AntennaType Display Name

extension AntennaType {
    var displayName: String {
        switch self {
        case .dipole: "Dipole"
        case .vertical: "Vertical"
        case .loop: "Mag Loop"
        case .yagi: "Yagi"
        case .logPeriodic: "Log Periodic"
        case .whip: "Whip"
        case .beverage: "Beverage"
        case .longwire: "Long Wire"
        case .endFed: "EFHW"
        case .hexBeam: "Hex Beam"
        case .unknown: "Unknown"
        }
    }
}
