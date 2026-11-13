import SwiftUI

// MARK: - DuplicateStatusBadge

/// Compact pill badge for QSO row dupe/new band/new mode status
struct DuplicateStatusBadge: View {
    // MARK: Internal

    let status: CallsignDuplicateStatus
    var isRegularWidth = false

    var body: some View {
        switch status {
        case .firstContact,
             .previouslyWorked:
            EmptyView()
        case let .newBand(previousBands):
            badgePill("NEW BAND", color: .blue)
                .help("Previously worked on: \(previousBands.joined(separator: ", "))")
        case let .newMode(_, previousModes):
            badgePill("NEW MODE", color: .green)
                .help("Previously worked: \(previousModes.joined(separator: ", "))")
        case .duplicateBand:
            badgePill("DUPE", color: .orange)
        }
    }

    // MARK: Private

    private func badgePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(isRegularWidth ? .caption.weight(.bold) : .caption2.weight(.bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - DuplicateStatusBanner

/// Banner showing duplicate or new band status before logging
struct DuplicateStatusBanner: View {
    let status: CallsignDuplicateStatus

    var body: some View {
        switch status {
        case .firstContact:
            EmptyView()

        case let .previouslyWorked(previousBands):
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Previously Worked")
                        .font(.subheadline.weight(.semibold))
                    Text("Worked on \(previousBands.joined(separator: ", ")) today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

        case let .newBand(previousBands):
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Band!")
                        .font(.subheadline.weight(.semibold))
                    Text("Previously worked on \(previousBands.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.blue.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))

        case let .newMode(band, previousModes):
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Mode on \(band)!")
                        .font(.subheadline.weight(.semibold))
                    Text(
                        "Previously worked \(previousModes.joined(separator: ", "))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.green.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))

        case let .duplicateBand(band, isPOTA):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duplicate on \(band)")
                        .font(.subheadline.weight(.semibold))
                    Text(
                        isPOTA
                            ? "Already worked on this band & mode — POTA will reject the dupe"
                            : "Already worked on this band & mode today"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.orange.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - SwipeToDismissPanel

/// Wrapper that adds swipe-to-dismiss gesture to a panel
struct SwipeToDismissPanel<Content: View>: View {
    // MARK: Internal

    @Binding var isPresented: Bool

    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Only allow dragging down
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        // Dismiss if dragged more than 80 points or with velocity
                        if value.translation.height > 80
                            || value.predictedEndTranslation.height > 150
                        {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                        }
                        // Reset offset
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
            )
    }

    // MARK: Private

    @State private var dragOffset: CGFloat = 0
}
