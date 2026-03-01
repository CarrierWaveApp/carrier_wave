import SwiftUI

// MARK: - SCPSuggestionsView

/// Horizontal scrolling chip bar showing SCP callsign suggestions.
/// Tapping a chip fills the callsign input field.
struct SCPSuggestionsView: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(suggestions, id: \.self) { callsign in
                    Button {
                        onSelect(callsign)
                    } label: {
                        Text(callsign)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 28)
    }
}
