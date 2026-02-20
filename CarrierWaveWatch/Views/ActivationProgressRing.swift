import SwiftUI

/// Circular progress ring for POTA activation threshold.
/// Shows X/10 progress filling clockwise. Turns green at completion.
struct ActivationProgressRing: View {
    // MARK: Internal

    let qsoCount: Int
    let target: Int

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 6)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Count text
            VStack(spacing: 0) {
                Text("\(qsoCount)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(progressColor)
                Text("/\(target)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 80, height: 80)
    }

    // MARK: Private

    private var progress: Double {
        min(Double(qsoCount) / Double(target), 1.0)
    }

    private var progressColor: Color {
        if qsoCount >= target {
            return .green
        }
        if qsoCount >= target - 2 {
            return .yellow
        }
        return .blue
    }
}
