import CarrierWaveCore
import SwiftUI

// MARK: - PropagationPanelView

/// Center-column propagation section: solar indices, band conditions grid, space weather.
struct PropagationPanelView: View {
    // MARK: Internal

    let propagationService: PropagationService

    @Binding var selectedBand: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            solarIndicesBar
            bandConditionsGrid
            SpaceWeatherView(events: propagationService.donkiEvents)
        }
    }

    // MARK: Private

    private static let bandDisplayOrder = [
        "160m", "80m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m",
    ]

    /// Maps HamQSL grouped band names to individual band names.
    private static let bandGroupMap: [String: [String]] = [
        "80m-40m": ["80m", "40m"],
        "30m-20m": ["30m", "20m"],
        "17m-15m": ["17m", "15m"],
        "12m-10m": ["12m", "10m"],
    ]

    private var solarData: HamQSLSolarData? {
        propagationService.solarData
    }

    private var bandEstimateMap: [String: BandPropagation] {
        Dictionary(
            uniqueKeysWithValues: propagationService.bandEstimates.map { ($0.band, $0) }
        )
    }

    /// Day/night conditions keyed by individual band name, expanded from HamQSL groups.
    private var hamQSLConditionMap: [String: HamQSLBandCondition] {
        guard let solar = solarData else {
            return [:]
        }
        var result: [String: HamQSLBandCondition] = [:]
        for groupCondition in solar.bandConditions {
            let members = Self.bandGroupMap[groupCondition.bandName] ?? []
            for band in members {
                result[band] = groupCondition
            }
        }
        return result
    }

    private var sfiText: String {
        solarData?.solarFlux.map { String(format: "%.0f", $0) } ?? "—"
    }

    private var kIndexText: String {
        solarData.map { String(format: "%.1f", $0.kIndex) } ?? "—"
    }

    private var aIndexText: String {
        solarData?.aIndex.map { "\($0)" } ?? "—"
    }

    private var ssnText: String {
        solarData?.sunspots.map { "\($0)" } ?? "—"
    }

    private var solarIndicesBar: some View {
        HStack(spacing: 12) {
            solarIndexCell(label: "SFI", value: sfiText)
            solarIndexCell(label: "K", value: kIndexText)
            solarIndexCell(label: "A", value: aIndexText)
            solarIndexCell(label: "SSN", value: ssnText)
            Spacer()
            if let muf = propagationService.mufEstimateMHz {
                Text("MUF ~\(String(format: "%.0f", muf)) MHz")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var bandConditionsGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Self.bandDisplayOrder, id: \.self) { band in
                BandConditionTile(
                    bandName: band,
                    dayCondition: dayCondition(for: band),
                    nightCondition: nightCondition(for: band),
                    isBest: propagationService.bestBand?.band == band,
                    isSelected: selectedBand == band,
                    action: { selectedBand = selectedBand == band ? nil : band }
                )
            }
        }
    }

    private func solarIndexCell(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private func dayCondition(for band: String) -> String {
        if let hamQSL = hamQSLConditionMap[band] {
            return hamQSL.day
        }
        return estimateConditionLabel(for: band)
    }

    private func nightCondition(for band: String) -> String {
        if let hamQSL = hamQSLConditionMap[band] {
            return hamQSL.night
        }
        return estimateConditionLabel(for: band)
    }

    /// Fallback label from PropagationEstimator when HamQSL has no data for a band.
    private func estimateConditionLabel(for band: String) -> String {
        bandEstimateMap[band]?.quality.label ?? "—"
    }
}
