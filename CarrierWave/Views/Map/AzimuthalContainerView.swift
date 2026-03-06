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

    var body: some View {
        VStack(spacing: 0) {
            controlsBar
            Divider()
            azimuthalContent
        }
        .navigationTitle("Azimuthal")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { compassService.startUpdating() }
        .onDisappear { compassService.stopUpdating() }
    }

    // MARK: Private

    @State private var compassService = CompassHeadingService()
    @State private var selectedAntennaType: AntennaType = .vertical
    @State private var manualOrientation: Double = 0
    @State private var useCompass = true
    @State private var maxDistanceKm = AzimuthalProjection.earthHalfCircumferenceKm
    @State private var showPattern = true
    @State private var selectedBand: String?

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
        return AntennaPattern.defaultPattern(
            for: selectedAntennaType,
            orientationDeg: effectiveOrientation
        )
    }

    private var filteredSpots: [UnifiedSpot] {
        guard let band = selectedBand else {
            return spots
        }
        return spots.filter { spot in
            BandUtilities.deriveBand(from: spot.frequencyKHz) == band
        }
    }

    private var projectedSpots: [AzimuthalSpotPoint] {
        AzimuthalDataProvider.projectSpots(
            filteredSpots, from: myGrid, maxDistanceKm: maxDistanceKm
        )
    }

    private var projectedQSOs: [AzimuthalSpotPoint] {
        AzimuthalDataProvider.projectQSOs(
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

    private var spotSummary: String {
        let count = projectedSpots.count
        let total = filteredSpots.count
        if count == total {
            return "\(count) spots"
        }
        return "\(count)/\(total) spots with grid"
    }

    private var controlsBar: some View {
        VStack(spacing: 8) {
            // Antenna type and orientation
            HStack(spacing: 12) {
                antennaTypePicker
                Spacer()
                orientationControls
            }
            .padding(.horizontal)

            // Band filter and distance
            HStack(spacing: 12) {
                bandFilterPicker
                Spacer()
                distancePicker
            }
            .padding(.horizontal)

            // Status line
            HStack {
                Text(spotSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let heading = compassService.heading {
                    Text("Compass: \(Int(heading))°")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    private var antennaTypePicker: some View {
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
            Label(selectedAntennaType.displayName, systemImage: "antenna.radiowaves.left.and.right")
                .font(.subheadline)
        }
    }

    private var orientationControls: some View {
        HStack(spacing: 8) {
            if useCompass {
                Image(systemName: "location.north.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
            }
            Button {
                useCompass.toggle()
            } label: {
                Image(systemName: useCompass ? "compass.drawing" : "hand.point.up.left")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if !useCompass {
                // Manual orientation slider
                Slider(value: $manualOrientation, in: 0 ... 359, step: 5)
                    .frame(width: 80)
                Text("\(Int(manualOrientation))°")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 30)
            }
        }
    }

    private var bandFilterPicker: some View {
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
        }
    }

    private var distancePicker: some View {
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
            Label("Range", systemImage: "arrow.left.and.right")
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var azimuthalContent: some View {
        if projectedSpots.isEmpty, projectedQSOs.isEmpty {
            ContentUnavailableView(
                "No Data with Grid Squares",
                systemImage: "mappin.slash",
                description: Text("Spots and QSOs need grid square data to appear on the azimuthal view.")
            )
        } else {
            AzimuthalMapView(
                sectors: sectors,
                spotPoints: projectedSpots,
                qsoPoints: projectedQSOs,
                antennaPattern: antennaPattern,
                compassHeading: compassService.heading,
                maxDistanceKm: maxDistanceKm
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
