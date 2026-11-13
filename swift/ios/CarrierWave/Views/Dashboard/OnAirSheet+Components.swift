import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - OnAirSheet Row & Metric Components

extension OnAirSheet {
    func conditionMetrics(
        _ solar: EnvironmentalSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let kVal = solar.solarKIndex {
                    metricBox(
                        label: "K-Index",
                        value: String(format: "%.1f", kVal),
                        color: kIndexColor(kVal)
                    )
                }
                if let sfi = solar.solarFlux {
                    metricBox(label: "SFI", value: "\(Int(sfi))", color: .orange)
                }
                if let aIdx = solar.solarAIndex {
                    metricBox(label: "A-Index", value: "\(aIdx)", color: .purple)
                }
                if let weather = latestWeather,
                   let temp = weather.weatherTemperatureF
                {
                    metricBox(
                        label: "Temp",
                        value: UnitFormatter.temperatureCompact(temp),
                        color: .red
                    )
                }
            }

            sparklineChart
                .frame(height: 50)

            Text("\(snapshots.count) samples")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func metricBox(
        label: String,
        value: String,
        color: Color
    ) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func dxRow(
        _ dx: Ham365DXpedition,
        isOnAir: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(dx.callsign)
                    .font(.subheadline.weight(.semibold).monospaced())

                Text(dx.entity)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if isOnAir {
                    Text("ON AIR")
                        .font(.caption2.bold())
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.green, in: RoundedRectangle(cornerRadius: 3))
                } else if dx.isActiveToday {
                    Text("ACTIVE")
                        .font(.caption2.bold())
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 3))
                } else {
                    Text(dx.dateRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            if isOnAir, let spots = onAirSpots[dx.callsign], !spots.isEmpty {
                sheetSpotPills(spots)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    func sheetSpotPills(_ spots: [RBNSpot]) -> some View {
        let grouped = DXpeditionSpotGrouper.group(spots)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(grouped, id: \.label) { entry in
                    Text(entry.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Color.green.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 3)
                        )
                }

                Text("\(spots.count) spots")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Shared Components

    func sectionHeader(
        _ title: String,
        icon: String,
        color: Color,
        badge: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .badgePill(Color.green)
            }
        }
    }

    func noDataRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func noDataCard(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func seeAllLink(
        _ title: String,
        @ViewBuilder destination: @escaping () -> some View
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack {
                Spacer()
                Text(title)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.right")
                    .font(.caption)
                Spacer()
            }
            .foregroundStyle(.blue)
            .padding(.vertical, 12)
        }
    }

    static func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func dateFromDayKey(_ key: String) -> Date {
        let startOfDay = dayFormatter.date(from: key) ?? Date()
        return startOfDay.addingTimeInterval(12 * 3_600)
    }

    // MARK: - Color Helpers

    func kIndexColor(_ kVal: Double) -> Color {
        switch kVal {
        case ..<2: .green
        case ..<3: .blue
        case ..<4: .yellow
        case ..<5: .orange
        default: .red
        }
    }

    func ratingColor(_ rating: String) -> Color {
        switch rating {
        case "Excellent",
             "Good": .green
        case "Fair": .yellow
        case "Poor": .orange
        default: .red
        }
    }
}
