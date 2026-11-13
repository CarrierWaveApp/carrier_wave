import SwiftUI

// MARK: - QuickFilter

/// A predefined filter chip with a label and query string.
struct QuickFilter: Identifiable {
    // MARK: Lifecycle

    init(_ label: String, query: String, icon: String? = nil, tint: Color = .blue) {
        id = query
        self.label = label
        self.query = query
        self.icon = icon
        self.tint = tint
    }

    // MARK: Internal

    let id: String
    let label: String
    let query: String
    let icon: String?
    let tint: Color
}

// MARK: - QuickFilterChipsView

/// Horizontal scrollable chip bar for one-tap log filtering.
/// Tapping an active chip clears the query; tapping an inactive chip applies it.
struct QuickFilterChipsView: View {
    // MARK: Internal

    @Binding var queryText: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.filters) { filter in
                    chipButton(filter)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    // MARK: Private

    private static let filters: [QuickFilter] = [
        QuickFilter("Today", query: "date:today", icon: "calendar", tint: .blue),
        QuickFilter("7 Days", query: "after:7d", icon: "clock", tint: .blue),
        QuickFilter("FT8", query: "mode:FT8", tint: .orange),
        QuickFilter("SSB", query: "mode:SSB", tint: .green),
        QuickFilter("CW", query: "mode:CW", tint: .purple),
        QuickFilter("POTA", query: "park:K-*", icon: "leaf", tint: .green),
        QuickFilter("Confirmed", query: "confirmed:lotw", icon: "star.fill", tint: .yellow),
    ]

    private func chipButton(_ filter: QuickFilter) -> some View {
        let isActive = queryText.trimmingCharacters(in: .whitespaces) == filter.query

        return Button {
            if isActive {
                queryText = ""
            } else {
                queryText = filter.query
            }
        } label: {
            HStack(spacing: 4) {
                if let icon = filter.icon {
                    Image(systemName: icon)
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
                Text(filter.label)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? filter.tint.opacity(0.25) : Color(.systemGray5))
            .foregroundStyle(isActive ? filter.tint : .secondary)
            .clipShape(Capsule())
        }
        .accessibilityLabel("Filter: \(filter.label)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
