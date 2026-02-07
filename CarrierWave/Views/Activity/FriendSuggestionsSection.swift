import SwiftUI

// MARK: - FriendSuggestionsSection

/// Displays friend suggestions in a list section with Add/Dismiss actions.
struct FriendSuggestionsSection: View {
    let suggestions: [FriendSuggestion]
    let onAdd: (FriendSuggestion) -> Void
    let onDismiss: (FriendSuggestion) -> Void

    var body: some View {
        Section {
            ForEach(suggestions) { suggestion in
                SuggestionRow(
                    suggestion: suggestion,
                    onAdd: { onAdd(suggestion) },
                    onDismiss: { onDismiss(suggestion) }
                )
            }
        } header: {
            Label("Suggested Friends", systemImage: "person.badge.plus")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } footer: {
            Text("Based on your QSO history with other Carrier Wave users.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - SuggestionRow

private struct SuggestionRow: View {
    let suggestion: FriendSuggestion
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.callsign)
                    .font(.headline.monospaced())

                Text("\(suggestion.qsoCount) QSOs together")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Add") {
                onAdd()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.secondary)
        }
    }
}
