import SwiftUI

// MARK: - Orientation Section

extension StartupProfileView {
    func orientationSection(
        _ trace: StartupTrace
    ) -> some View {
        Section {
            ForEach(
                Array(trace.orientationMilestones.enumerated()),
                id: \.offset
            ) { _, milestone in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(milestone.label)
                            .font(.caption)
                            .fontDesign(.monospaced)
                        Text(Self.orientationTimeFormatter.string(
                            from: milestone.wallTime
                        ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(
                        format: "%.3f s",
                        milestone.elapsedSeconds
                    ))
                    .font(.caption)
                    .fontDesign(.monospaced)
                }
            }
        } header: {
            Text(
                "Orientation Transitions (\(trace.orientationMilestones.count))"
            )
        }
    }

    // MARK: Private

    private static let orientationTimeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return fmt
    }()
}
