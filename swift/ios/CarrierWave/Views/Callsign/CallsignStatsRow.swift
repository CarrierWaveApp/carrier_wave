import SwiftUI

// MARK: - CallsignStatsRow

/// Three-column stats grid showing QSO count, unique bands, and recorded time.
struct CallsignStatsRow: View {
    // MARK: Internal

    let qsoCount: Int
    let uniqueBands: Set<String>
    let totalRecordedSeconds: Double

    var body: some View {
        HStack(spacing: 12) {
            statBox(
                icon: "antenna.radiowaves.left.and.right",
                value: "\(qsoCount)",
                label: qsoCount == 1 ? "QSO" : "QSOs"
            )
            statBox(
                icon: "dial.medium.fill",
                value: "\(uniqueBands.count)",
                label: uniqueBands.count == 1 ? "Band" : "Bands"
            )
            statBox(
                icon: "waveform",
                value: formattedDuration,
                label: "Recorded"
            )
        }
    }

    // MARK: Private

    private var formattedDuration: String {
        let total = Int(totalRecordedSeconds)
        if total == 0 {
            return "--"
        }
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func statBox(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
