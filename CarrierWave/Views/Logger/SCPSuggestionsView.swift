import SwiftUI

// MARK: - SCPSuggestionsView

/// Horizontal scrolling chip bar showing callsign autocomplete suggestions.
/// Tapping a chip fills the callsign input field.
/// Shows contact count badges and spot indicators for context.
struct SCPSuggestionsView: View {
    // MARK: Internal

    let suggestions: [String]
    var contactCounts: [String: Int] = [:]
    var spotCallsigns: Set<String> = []
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "text.magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .padding(.trailing, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { callsign in
                        suggestionPill(callsign)
                    }
                }
                .padding(.trailing, 12)
            }
        }
    }

    // MARK: Private

    private func suggestionPill(_ callsign: String) -> some View {
        let count = contactCounts[callsign, default: 0]
        let isSpotted = spotCallsigns.contains(callsign)

        return Button {
            onSelect(callsign)
        } label: {
            HStack(spacing: 4) {
                if isSpotted {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                }

                Text(callsign)
                    .font(.subheadline.monospaced().weight(count > 0 ? .semibold : .regular))

                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("\(callsign)\(count > 0 ? ", \(count) previous contacts" : "")")
        .accessibilityHint("Fill callsign field")
    }
}
