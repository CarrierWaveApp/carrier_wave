//
//  AzimuthalContainerView+Filters.swift
//  CarrierWave
//
//  Filter pills and source toggles for the azimuthal map container.
//

import CarrierWaveCore
import SwiftUI

// MARK: - Filter Controls

extension AzimuthalContainerView {
    var filtersRow: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    antennaFilterPill
                    bandFilterPill
                    modeFilterPill
                    distanceFilterPill
                    qsoTogglePill
                    mapTileTogglePill
                    ForEach(availableSources, id: \.self) { source in
                        sourceTogglePill(source)
                    }
                }
            }

            spotCountIndicator
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Individual Pills

    private var antennaFilterPill: some View {
        filterPill(
            label: showPattern ? selectedAntennaType.displayName : "Antenna",
            icon: "antenna.radiowaves.left.and.right",
            isActive: showPattern
        ) {
            ForEach(AntennaType.allCases, id: \.self) { type in
                Button {
                    selectedAntennaType = type
                    showPattern = true
                } label: {
                    HStack {
                        Text(type.displayName)
                        if showPattern, type == selectedAntennaType {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button {
                showPattern.toggle()
            } label: {
                HStack {
                    Text(showPattern ? "Hide Pattern" : "Show Pattern")
                    if showPattern {
                        Image(systemName: "eye.slash")
                    }
                }
            }
        }
    }

    private var bandFilterPill: some View {
        filterPill(
            label: selectedBand ?? "Band",
            icon: "waveform",
            isActive: selectedBand != nil
        ) {
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
        }
    }

    private var modeFilterPill: some View {
        filterPill(
            label: selectedMode ?? "Mode",
            icon: "dot.radiowaves.right",
            isActive: selectedMode != nil
        ) {
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
        }
    }

    private var distanceFilterPill: some View {
        filterPill(
            label: currentDistanceLabel,
            icon: "arrow.left.and.right",
            isActive: maxDistanceKm != 5_000.0
        ) {
            ForEach(DistanceOption.allCases, id: \.self) { option in
                Button {
                    maxDistanceKm = option.km
                    baseDistanceKm = option.km
                    if showMapTiles {
                        triggerTileRender()
                    }
                } label: {
                    HStack {
                        Text(option.label)
                        if maxDistanceKm == option.km {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }

    private var qsoTogglePill: some View {
        Button {
            showQSOs.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: showQSOs ? "eye" : "eye.slash")
                    .font(.system(size: 10))
                Text("QSOs")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(showQSOs ? .primary : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(showQSOs ? 0.2 : 0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showQSOs ? "Hide QSOs" : "Show QSOs")
    }

    private var mapTileTogglePill: some View {
        Button {
            showMapTiles.toggle()
            if showMapTiles {
                triggerTileRender()
            } else {
                tileImage = nil
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: showMapTiles ? "map.fill" : "map")
                    .font(.system(size: 10))
                Text("Map")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(showMapTiles ? .primary : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(showMapTiles ? 0.2 : 0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showMapTiles ? "Hide map tiles" : "Show map tiles")
    }

    @ViewBuilder
    private var spotCountIndicator: some View {
        if isLoadingSpots {
            ProgressView()
                .controlSize(.small)
        } else {
            Label("\(projectedSpots.count)", systemImage: "dot.radiowaves.up.forward")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    // MARK: - Helpers

    func filterPill(
        label: String,
        icon: String,
        isActive: Bool,
        @ViewBuilder menuContent: @escaping () -> some View
    ) -> some View {
        Menu {
            menuContent()
        } label: {
            HStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isActive ? Color.blue.opacity(0.2) : Color(.systemGray5))
            .clipShape(Capsule())
        }
    }

    func sourceTogglePill(_ source: SpotSource) -> some View {
        let isActive = selectedSources.contains(source)
        return Button {
            if isActive {
                selectedSources.remove(source)
            } else {
                selectedSources.insert(source)
            }
        } label: {
            Text(source.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(isActive ? .primary : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    source.color.opacity(isActive ? 0.2 : 0.08)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isActive ? "Hide \(source.displayName)" : "Show \(source.displayName)"
        )
    }
}
