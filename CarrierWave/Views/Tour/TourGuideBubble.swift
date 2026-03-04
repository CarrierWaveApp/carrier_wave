import SwiftUI

// MARK: - TourGuideBubble

/// Floating speech bubble for the KI5GTR tour guide.
/// Anchored at the bottom of the screen, above the tab bar.
struct TourGuideBubble: View {
    let message: TourGuideMessage
    let stepIndex: Int
    let totalSteps: Int
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Guide identity
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor)
                    .clipShape(Circle())

                Text("KI5GTR")
                    .font(.subheadline.weight(.bold).monospaced())

                Spacer()

                Text("\(stepIndex + 1) / \(totalSteps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Message body
            Text(message.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            // Action buttons
            HStack {
                if stepIndex < totalSteps - 1 {
                    Button("Skip Tour") {
                        onSkip()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onNext()
                } label: {
                    Text(message.buttonLabel)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        TourGuideBubble(
            message: TourGuideMessage(
                text: "Hey, I'm KI5GTR — I built Carrier Wave and I'll walk you through running a POTA activation.",
                buttonLabel: "Let's Go"
            ),
            stepIndex: 0,
            totalSteps: 10,
            onNext: {},
            onSkip: {}
        )
    }
}
