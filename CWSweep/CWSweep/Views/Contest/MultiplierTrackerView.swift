import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - MultiplierTrackerView

/// Band-by-multiplier matrix showing worked/needed multipliers.
struct MultiplierTrackerView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Multiplier Tracker")
                    .font(.headline)
                Spacer()
                Toggle("Needed on current band", isOn: $showNeededOnly)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Text("\(contestManager.score.multiplierCount) mults")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if let definition = contestManager.definition {
                ScrollView([.vertical, .horizontal]) {
                    ForEach(definition.multipliers.types, id: \.rawValue) { multType in
                        MultiplierTypeSection(
                            type: multType,
                            bands: bands,
                            perBand: definition.multipliers.perBand,
                            currentBand: currentBand,
                            showNeededOnly: showNeededOnly,
                            contestManager: contestManager
                        )
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Active Contest",
                    systemImage: "trophy",
                    description: Text("Start a contest to track multipliers")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: contestManager.score.multiplierCount) { oldValue, newValue in
            if newValue > oldValue, oldValue > 0 {
                NSSound.beep()
            }
        }
    }

    // MARK: Private

    @Environment(ContestManager.self) private var contestManager
    @Environment(RadioManager.self) private var radioManager
    @State private var showNeededOnly = false

    private var bands: [String] {
        contestManager.definition?.bands ?? []
    }

    private var currentBand: String? {
        BandUtilities.deriveBand(from: radioManager.frequency * 1_000)
    }
}

// MARK: - MultiplierTypeSection

private struct MultiplierTypeSection: View {
    // MARK: Internal

    let type: MultiplierType
    let bands: [String]
    let perBand: Bool
    let currentBand: String?
    let showNeededOnly: Bool
    let contestManager: ContestManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sectionTitle(for: type))
                .font(.subheadline.bold())
                .padding(.horizontal)
                .padding(.top, 8)

            // Header
            MultHeaderRow(type: type, bands: bands, perBand: perBand)

            // Value rows
            let allValues = valuesForType(type)
            let displayValues = showNeededOnly ? neededValues(allValues) : allValues

            ForEach(displayValues, id: \.self) { value in
                MultValueRow(
                    value: value,
                    bands: bands,
                    perBand: perBand,
                    workedValues: workedValues
                )
            }
        }
        .padding(.bottom, 8)
        .task(id: contestManager.score.multiplierCount) {
            await refreshWorkedValues()
        }
    }

    // MARK: Private

    @State private var workedValues: [String: Set<String>] = [:]

    private func refreshWorkedValues() async {
        if perBand {
            for band in bands {
                let values = await contestManager.multiplierValues(for: type, band: band)
                workedValues[band] = values
            }
        } else {
            let values = await contestManager.multiplierValues(for: type, band: nil)
            workedValues["ALL"] = values
        }
    }

    private func neededValues(_ allValues: [String]) -> [String] {
        guard let band = currentBand else {
            return allValues
        }
        let bandKey = perBand ? band : "ALL"
        let worked = workedValues[bandKey] ?? []
        return allValues.filter { !worked.contains($0) }
    }

    private func valuesForType(_ type: MultiplierType) -> [String] {
        switch type {
        case .cqZone:
            return (1 ... 40).map { String($0) }
        case .ituZone:
            return (1 ... 90).map { String($0) }
        case .state:
            return [
                "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DC", "DE", "FL",
                "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME",
                "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH",
                "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI",
                "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
            ]
        case .arrlSection:
            return Array(ContestExchangeParser.arrlSections).sorted()
        default:
            let all = workedValues.values.reduce(into: Set<String>()) { $0.formUnion($1) }
            return Array(all).sorted()
        }
    }

    private func sectionTitle(for type: MultiplierType) -> String {
        switch type {
        case .dxcc: "DXCC Entities"
        case .cqZone: "CQ Zones"
        case .ituZone: "ITU Zones"
        case .state: "States/Provinces"
        case .arrlSection: "ARRL Sections"
        case .county: "Counties"
        case .wpxPrefix: "WPX Prefixes"
        }
    }
}

// MARK: - MultHeaderRow

private struct MultHeaderRow: View {
    let type: MultiplierType
    let bands: [String]
    let perBand: Bool

    var body: some View {
        HStack(spacing: 2) {
            Text(type.rawValue.uppercased())
                .font(.caption.bold())
                .frame(width: 60, alignment: .leading)

            if perBand {
                ForEach(bands, id: \.self) { band in
                    Text(band.replacingOccurrences(of: "m", with: ""))
                        .font(.caption.bold())
                        .frame(width: 30)
                }
            } else {
                Text("Wkd")
                    .font(.caption.bold())
                    .frame(width: 30)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - MultValueRow

private struct MultValueRow: View {
    let value: String
    let bands: [String]
    let perBand: Bool
    let workedValues: [String: Set<String>]

    var body: some View {
        HStack(spacing: 2) {
            Text(value)
                .font(.caption.monospaced())
                .frame(width: 60, alignment: .leading)

            if perBand {
                ForEach(bands, id: \.self) { band in
                    MultCell(worked: workedValues[band]?.contains(value) == true, band: band, value: value)
                }
            } else {
                MultCell(worked: workedValues["ALL"]?.contains(value) == true, band: "all bands", value: value)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - MultCell

private struct MultCell: View {
    let worked: Bool
    var band: String = ""
    var value: String = ""

    var body: some View {
        Group {
            if worked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(nsColor: .systemGreen))
                    .font(.caption2)
            } else {
                Circle()
                    .strokeBorder(.secondary.opacity(0.3), lineWidth: 1)
                    .frame(width: 10, height: 10)
            }
        }
        .frame(width: 30)
        .accessibilityLabel(worked ? "\(value) on \(band): worked" : "\(value) on \(band): needed")
    }
}
