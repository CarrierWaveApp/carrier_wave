import CarrierWaveData
import SwiftUI

// MARK: - ContestDetailMacView sections (split for type_body_length)

extension ContestDetailMacView {
    // MARK: - Rules

    func rulesSection(_ definition: ContestDefinition) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Modes") {
                    Text(definition.modes.joined(separator: ", "))
                }
                LabeledContent("Bands") {
                    Text(definition.bands.joined(separator: ", "))
                }
                LabeledContent("Dupe rules") {
                    Text(dupeSummary(definition.dupeRules))
                }
                if let offTime = definition.operatingConstraints?.offTime?.minimumOffMinutes {
                    LabeledContent("Min off-time") {
                        Text("\(offTime) min")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Rules", systemImage: "list.bullet.clipboard")
        }
    }

    // MARK: - Categories

    func categoriesSection(_ categories: [ContestCategory]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(categories) { category in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(category.label)
                                .font(.body)
                            Spacer()
                            Text(category.id)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        if !category.powerClasses.isEmpty {
                            Text(category.powerClasses.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Categories", systemImage: "person.2")
        }
    }

    // MARK: - Constraints

    func constraintsSection(_ constraints: ContestOperatingConstraints) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                if let offTime = constraints.offTime {
                    if let minOff = offTime.minimumOffMinutes {
                        LabeledContent("Min off-time") {
                            Text("\(minOff) min")
                        }
                    }
                    if !offTime.maximumOnHoursByCategory.isEmpty {
                        ForEach(
                            offTime.maximumOnHoursByCategory.sorted(by: { $0.key < $1.key }),
                            id: \.key
                        ) { category, hours in
                            LabeledContent("Max on (\(category))") {
                                Text("\(Int(hours))h")
                            }
                        }
                    }
                }
                if let bandChanges = constraints.bandChanges {
                    if let minOnBand = bandChanges.minMinutesOnBand {
                        LabeledContent("Min time on band") {
                            Text("\(minOnBand) min")
                        }
                    }
                    if let maxChanges = bandChanges.maxChangesPerClockHour {
                        LabeledContent("Max changes/hour") {
                            Text("\(maxChanges)")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Operating Constraints", systemImage: "timer")
        }
    }

    // MARK: - Source

    func sourceSection(_ definition: ContestDefinition) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("ID") {
                    Text(definition.id)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                if let sponsor = definition.sponsor {
                    if let name = sponsor.name {
                        LabeledContent("Sponsor", value: name)
                    }
                    if let urlStr = sponsor.url, let url = URL(string: urlStr) {
                        LabeledContent("Rules") {
                            Link(urlStr, destination: url)
                                .font(.caption)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Source", systemImage: "info.circle")
        }
    }

    // MARK: - Helpers

    func dupeSummary(_ rules: ContestDupeRules) -> String {
        let scope = rules.scope == .contest ? "whole contest" : "per session"
        let key = rules.key.joined(separator: "+")
        return "\(scope) · \(key)"
    }

    func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
