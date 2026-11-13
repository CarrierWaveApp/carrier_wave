// Reference Chip
//
// Generic removable chip for displaying a reference code and
// optional name. Parameterized by accent color. Replaces the
// near-identical SummitChip and WWFFChip implementations.

import SwiftUI

// MARK: - ReferenceChip

/// Removable chip showing a reference code and optional resolved name
struct ReferenceChip: View {
    let code: String
    var name: String?
    let accentColor: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(code)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(accentColor)

                if let name {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
            }
            .padding(.leading, 10)
            .padding(.vertical, 8)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(code)")
        }
        .background(accentColor.opacity(0.1))
        .clipShape(Capsule())
    }
}
