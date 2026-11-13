import SwiftUI

// MARK: - SessionsIntentView Role Prompt

extension SessionsIntentView {
    /// One-time prompt that appears at the top of the Sessions intent screen
    /// when the user hasn't yet declared their operating style. Disappears the
    /// moment they pick anything — even "A bit of everything" counts as an
    /// answer because that explicit choice still tells the wizard not to
    /// guess at activation-first ordering.
    var operatorRolePromptSection: some View {
        Section {
            OperatorRolePromptCard(
                onPick: { role in
                    withAnimation(.easeOut(duration: 0.25)) {
                        operatorRoleRaw = role.rawValue
                    }
                }
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}

// MARK: - OperatorRolePromptCard

/// The first-launch operator-style picker. Compact, dismissible-by-answering,
/// and intentionally lives in the Sessions tab — the question is "what kind of
/// operating do you do?" so the natural place to answer it is right above the
/// "start operating" intent grid.
struct OperatorRolePromptCard: View {
    let onPick: (OperatorRole) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What kind of operating?")
                    .font(.headline)
                Text("Tunes the session wizard and dashboard to your style. Change anytime in Settings → Logger.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(OperatorRole.allCases) { role in
                    RoleOptionRow(role: role) { onPick(role) }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.purple.opacity(0.18), lineWidth: 0.5)
        )
    }
}

// MARK: - RoleOptionRow

private struct RoleOptionRow: View {
    // MARK: Internal

    let role: OperatorRole
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: role.icon)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(tint)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(role.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(role.blurb)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(role.displayName)
        .accessibilityHint(role.blurb)
    }

    // MARK: Private

    private var tint: Color {
        switch role {
        case .activator: .blue
        case .hunter: .orange
        case .mixed: .gray
        case .newcomer: .green
        }
    }
}
