import CarrierWaveCore
import SwiftUI

// MARK: - DXpeditionRow

/// A single DXpedition row showing callsign, entity, date range, and status.
struct DXpeditionRow: View {
    // MARK: Internal

    let expedition: Ham365DXpedition
    let daysInMonth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(expedition.callsign)
                    .font(.headline.monospaced())

                if expedition.isOnAir {
                    onAirBadge
                } else if expedition.isActiveToday {
                    activeTodayBadge
                }

                Spacer()

                Text(expedition.dateRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(expedition.entity)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            activityBar
        }
        .padding(.vertical, 4)
    }

    // MARK: Private

    private var onAirBadge: some View {
        Label("On Air", systemImage: "antenna.radiowaves.left.and.right")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.green, in: Capsule())
    }

    private var activeTodayBadge: some View {
        Text("Active")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.blue, in: Capsule())
    }

    /// Horizontal bar showing which days are active in the month.
    private var activityBar: some View {
        GeometryReader { _ in
            HStack(spacing: 1) {
                ForEach(1 ... daysInMonth, id: \.self) { day in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(
                            expedition.activeDays.contains(day)
                                ? dayColor(day)
                                : Color(.systemGray5)
                        )
                }
            }
        }
        .frame(height: 6)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func dayColor(_ day: Int) -> Color {
        if expedition.isOnAir {
            return .green
        }
        if expedition.isActiveToday,
           let todayDay = Calendar.current.dateComponents([.day], from: Date()).day,
           day == todayDay
        {
            return .blue
        }
        return .orange
    }
}
