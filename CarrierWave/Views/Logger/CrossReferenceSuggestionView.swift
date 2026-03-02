import SwiftUI

// MARK: - CrossReferenceSuggestionView

/// Suggestion chip shown when a cross-reference match is found between programs.
/// Tapping "Add" enables the suggested program and fills in the reference.
struct CrossReferenceSuggestionView: View {
    // MARK: Internal

    let suggestion: ProgramCrossReferenceService.Suggestion
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForProgram(suggestion.program))
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(promptText)
                    .font(.subheadline)
                Text(suggestion.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Add") {
                onAdd()
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Dismiss suggestion")
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    private var promptText: String {
        let label = suggestion.program.uppercased()
        return "Also activate \(label) \(suggestion.reference)?"
    }

    private func iconForProgram(_ slug: String) -> String {
        switch slug {
        case "pota": "tree"
        case "wwff": "leaf.fill"
        case "sota": "mountain.2"
        default: "questionmark.circle"
        }
    }
}
