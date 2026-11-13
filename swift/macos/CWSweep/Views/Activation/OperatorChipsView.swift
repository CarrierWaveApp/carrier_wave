import SwiftUI

// MARK: - ChipView

private struct ChipView: View {
    let callsign: String
    let isPrimary: Bool
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(callsign)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isPrimary ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.15), in: Capsule())
        .foregroundStyle(isPrimary ? Color.accentColor : .primary)
    }
}

// MARK: - ChipFlowLayout

private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                totalHeight += rowHeight + spacing
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: max(totalHeight, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.minX + maxWidth, currentX > bounds.minX {
                currentY += rowHeight + spacing
                currentX = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - OperatorChipsView

struct OperatorChipsView: View {
    // MARK: Internal

    @Binding var operators: [String]

    let myCallsign: String

    var body: some View {
        ChipFlowLayout(spacing: 6) {
            primaryChip
            operatorChips
            inputField
        }
    }

    // MARK: Private

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    private var primaryChip: some View {
        ChipView(callsign: myCallsign, isPrimary: true, onRemove: nil)
    }

    private var operatorChips: some View {
        ForEach(operators, id: \.self) { callsign in
            ChipView(callsign: callsign, isPrimary: false) {
                operators.removeAll { $0 == callsign }
            }
        }
    }

    private var inputField: some View {
        TextField("Add operator...", text: $inputText)
            .font(.system(.caption, design: .monospaced))
            .textFieldStyle(.plain)
            .frame(minWidth: 120)
            .focused($isInputFocused)
            .onSubmit { commitInput() }
            .onChange(of: inputText) { _, newValue in
                handleInputChange(newValue)
            }
    }

    private func handleInputChange(_ value: String) {
        guard let last = value.last else {
            return
        }
        if last == "," || last == " " {
            inputText = String(value.dropLast())
            commitInput()
        }
    }

    private func commitInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces).uppercased()
        inputText = ""
        guard !trimmed.isEmpty else {
            return
        }
        guard trimmed != myCallsign else {
            return
        }
        guard !operators.contains(trimmed) else {
            return
        }
        operators.append(trimmed)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var operators: [String] = ["W1AW", "KD9ABC"]
    OperatorChipsView(operators: $operators, myCallsign: "N0CALL")
        .padding()
        .frame(width: 400)
}
