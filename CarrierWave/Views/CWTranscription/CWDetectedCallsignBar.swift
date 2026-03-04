import CarrierWaveData
import SwiftUI

// MARK: - CWDetectedCallsignBar

/// Displays the most recently detected callsign with a "Use" button
struct CWDetectedCallsignBar: View {
    // MARK: Internal

    /// The detected callsign to display
    let callsign: DetectedCallsign?

    /// All detected callsigns for picker
    let allCallsigns: [String]

    /// Callback when user taps "Use"
    let onUse: (String) -> Void

    var body: some View {
        if let detected = callsign {
            HStack(spacing: 12) {
                // Label
                Text("Detected callsign")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                // Callsign with context indicator
                HStack(spacing: 6) {
                    if allCallsigns.count > 1 {
                        // Multiple callsigns - show picker button
                        Menu {
                            ForEach(allCallsigns, id: \.self) { cs in
                                Button(cs) {
                                    onUse(cs)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(detected.callsign)
                                    .font(.title3.weight(.bold).monospaced())
                                    .foregroundStyle(callsignColor(for: detected.context))

                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text(detected.callsign)
                            .font(.title3.weight(.bold).monospaced())
                            .foregroundStyle(callsignColor(for: detected.context))
                    }
                }

                // Use button
                Button {
                    onUse(detected.callsign)
                } label: {
                    Text("Use")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Private

    @State private var showingPicker = false

    private func callsignColor(for context: DetectedCallsign.CallsignContext) -> Color {
        switch context {
        case .cqCall:
            .blue
        case .deIdentifier:
            .green
        case .response:
            .orange
        case .unknown:
            .primary
        }
    }
}

// MARK: - CWCallsignChip

/// Small chip showing a detected callsign
struct CWCallsignChip: View {
    let callsign: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(callsign)
                .font(.caption.weight(.medium).monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CWHighlightedText

/// Displays CW text with highlighted callsigns and prosigns
struct CWHighlightedText: View {
    // MARK: Internal

    let elements: [CWTextElement]

    var body: some View {
        Text(attributedString)
    }

    // MARK: Private

    private var attributedString: AttributedString {
        var result = AttributedString()
        for element in elements {
            result.append(attributedText(for: element))
        }
        return result
    }

    private func attributedText(for element: CWTextElement) -> AttributedString {
        switch element {
        case let .text(str):
            var attr = AttributedString(str)
            attr.foregroundColor = .primary
            return attr

        case let .callsign(str, role):
            var attr = AttributedString(str)
            attr.foregroundColor = color(for: role)
            attr.font = .body.weight(.semibold)
            return attr

        case let .prosign(str):
            var attr = AttributedString(str)
            attr.foregroundColor = .secondary
            return attr

        case let .signalReport(str):
            var attr = AttributedString(str)
            attr.foregroundColor = .orange
            attr.font = .body.weight(.medium)
            return attr

        case let .grid(str):
            var attr = AttributedString(str)
            attr.foregroundColor = .cyan
            attr.font = .body.weight(.medium)
            return attr

        case let .power(str):
            var attr = AttributedString(str)
            attr.foregroundColor = .yellow
            attr.font = .body.weight(.medium)
            return attr

        case let .name(str):
            var attr = AttributedString(str)
            attr.foregroundColor = .mint
            attr.font = .body.weight(.medium)
            return attr

        case let .suggestion(original, suggested, _):
            // Show original with superscript suggestion hint
            var originalAttr = AttributedString(original)
            originalAttr.foregroundColor = .primary
            originalAttr.underlineStyle = .single
            originalAttr.underlineColor = .blue

            var suggestionAttr = AttributedString("→\(suggested)")
            suggestionAttr.font = .caption2
            suggestionAttr.foregroundColor = .blue
            suggestionAttr.baselineOffset = 6

            return originalAttr + suggestionAttr
        }
    }

    private func color(for role: CWTextElement.CallsignRole) -> Color {
        switch role {
        case .caller:
            .blue
        case .callee:
            .green
        case .unknown:
            .purple
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        CWDetectedCallsignBar(
            callsign: DetectedCallsign(
                callsign: "K4SWL",
                context: .deIdentifier
            ),
            allCallsigns: ["K4SWL", "N9HO"],
            onUse: { _ in }
        )
        .padding()

        CWDetectedCallsignBar(
            callsign: DetectedCallsign(
                callsign: "W1AW",
                context: .cqCall
            ),
            allCallsigns: ["W1AW"],
            onUse: { _ in }
        )
        .padding()

        HStack {
            CWCallsignChip(callsign: "K4SWL", isSelected: true, onTap: {})
            CWCallsignChip(callsign: "N9HO", isSelected: false, onTap: {})
            CWCallsignChip(callsign: "W1AW", isSelected: false, onTap: {})
        }
        .padding()

        CWHighlightedText(elements: [
            .prosign("CQ"),
            .text(" "),
            .prosign("CQ"),
            .text(" "),
            .prosign("DE"),
            .text(" "),
            .callsign("K4SWL", role: .caller),
            .text(" "),
            .callsign("K4SWL", role: .caller),
            .text(" "),
            .prosign("K"),
        ])
        .font(.body.monospaced())
        .padding()
    }
}
