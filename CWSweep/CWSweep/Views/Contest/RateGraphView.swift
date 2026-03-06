import Charts
import SwiftUI

/// QSO rate visualization using Swift Charts.
struct RateGraphView: View {
    let timeSeries: [(date: Date, count: Int)]

    var body: some View {
        Chart {
            ForEach(Array(timeSeries.enumerated()), id: \.offset) { _, entry in
                AreaMark(
                    x: .value("Time", entry.date),
                    y: .value("QSOs/hr", entry.count)
                )
                .foregroundStyle(Color.accentColor.opacity(0.3))

                LineMark(
                    x: .value("Time", entry.date),
                    y: .value("QSOs/hr", entry.count)
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 8)) { _ in
                AxisValueLabel(format: .dateTime.hour().minute())
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartYAxisLabel("QSOs/hr")
        .accessibilityLabel("QSO rate chart")
        .frame(minHeight: 150)
    }
}
