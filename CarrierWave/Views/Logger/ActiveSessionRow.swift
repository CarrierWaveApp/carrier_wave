import SwiftUI

// MARK: - ActiveSessionRow

/// Compact row displaying an active or paused session with Continue and management actions.
/// Used in the Logger tab to show sessions that can be resumed, paused, completed, or deleted.
struct ActiveSessionRow: View {
    // MARK: Internal

    let session: LoggingSession
    let qsoCount: Int
    let onContinue: () -> Void
    let onPause: () -> Void
    let onFinish: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: session.activationType.icon)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)

                Text(session.displayTitle)
                    .font(.subheadline.weight(.medium).monospaced())
                    .lineLimit(1)

                Spacer()

                statusBadge
            }

            HStack(spacing: 8) {
                detailCapsules

                Spacer()

                Button {
                    onContinue()
                } label: {
                    Text("Continue")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                sessionMenu
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Private

    // MARK: - Subviews

    private var sessionMenu: some View {
        Menu {
            if session.status == .active {
                Button {
                    onPause()
                } label: {
                    Label("Pause Session", systemImage: "pause")
                }
            }

            Button {
                onFinish()
            } label: {
                Label("Finish Session", systemImage: "checkmark.circle")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Session", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.semibold))
                .frame(width: 28, height: 28)
                .background(Color(.systemGray4))
                .foregroundStyle(.primary)
                .clipShape(Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusBadge: some View {
        Text(session.status == .paused ? "Paused" : "Active")
            .font(.caption2.weight(.medium))
            .foregroundStyle(session.status == .paused ? .orange : .green)
    }

    private var detailCapsules: some View {
        HStack(spacing: 4) {
            if let band = session.band {
                Text(band)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
            }

            Text(session.mode)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())

            Text("\(qsoCount) QSOs")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(session.formattedDuration)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
