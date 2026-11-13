import CarrierWaveData
import SwiftUI

// MARK: - CrossReferenceSuggestionView

/// Inline suggestion row shown when a cross-reference match is found between
/// programs. Rendered as a plain Form row (no nested card) so it reads as a
/// related, optional addition sitting beneath the reference field that spawned
/// it. Tapping "Add" enables the suggested program and fills in the reference.
struct CrossReferenceSuggestionView: View {
    // MARK: Internal

    let suggestion: ProgramCrossReferenceService.Suggestion
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            programToken

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Also activate")
                        .foregroundStyle(.secondary)
                    Text(programLabel)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.accentColor)
                }
                .font(.caption2)

                Text(suggestion.reference)
                    .font(.subheadline.weight(.semibold))
                    .monospaced()

                Text(suggestion.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("Add", action: onAdd)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Color.accentColor)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Dismiss \(programLabel) suggestion")
        }
        .padding(.vertical, 2)
    }

    // MARK: Private

    private var programLabel: String {
        suggestion.program.uppercased()
    }

    /// Tinted rounded-square glyph that gives the suggested program a compact
    /// visual identity — mirrors the selected-state look of `ProgramChip`.
    private var programToken: some View {
        Image(systemName: iconForProgram(suggestion.program))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 32, height: 32)
            .background(Color.accentColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
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
