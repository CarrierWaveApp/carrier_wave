import SwiftUI

// MARK: - SDRMeterView

/// Reusable horizontal audio level / S-meter bar
struct SDRMeterView: View {
    // MARK: Lifecycle

    init(level: Float, label: String = "Level") {
        self.level = level
        self.label = label
    }

    // MARK: Internal

    let level: Float
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(meterColor)
                        .frame(width: geo.size.width * CGFloat(level.clamped(to: 0 ... 1)))
                        .animation(.linear(duration: 0.05), value: level)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement()
        .accessibilityLabel("\(label): \(Int(level * 100)) percent")
    }

    // MARK: Private

    private var meterColor: Color {
        if level > 0.9 {
            return .red
        }
        if level > 0.7 {
            return .orange
        }
        return .green
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
