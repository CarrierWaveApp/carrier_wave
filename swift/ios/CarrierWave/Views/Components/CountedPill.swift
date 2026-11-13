import SwiftUI

// MARK: - CountedPill

/// Capsule pill that pairs a label with a parenthesised count, e.g. `20m (12)`.
/// Used across hero sections that summarise band/mode distribution.
struct CountedPill: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
            Text("(\(count))")
                .foregroundStyle(color.opacity(0.7))
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.2))
        .clipShape(Capsule())
    }
}
