import CarrierWaveCore
import SwiftUI

// MARK: - CWMessageBubble

/// A single message bubble in the CW chat view
struct CWMessageBubble: View {
    // MARK: Internal

    let message: CWConversationMessage
    let isMe: Bool
    let callsignInfo: CallsignInfo?

    var body: some View {
        HStack {
            if isMe {
                Spacer(minLength: 40)
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 6) {
                // Header with callsign and name
                headerView

                // Message content
                contentView

                // Footer with timestamp and frequency
                footerView
            }
            .padding(12)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !isMe {
                Spacer(minLength: 40)
            }
        }
    }

    // MARK: Private

    private var bubbleBackground: Color {
        if isMe {
            Color.accentColor.opacity(0.15)
        } else {
            Color(.systemGray5)
        }
    }

    private var displayCallsign: String? {
        switch message.stationId {
        case .me:
            "Me"
        case let .other(callsign):
            callsign ?? "Other Station"
        case .unknown:
            nil // Don't show header for unknown
        }
    }

    @ViewBuilder
    private var headerView: some View {
        if let callsign = displayCallsign {
            HStack(spacing: 6) {
                // Emoji from Polo notes (if available)
                if let emoji = callsignInfo?.emoji {
                    Text(emoji)
                        .font(.caption)
                }

                Text(callsign)
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(isMe ? Color.accentColor : .primary)

                // Name from lookup
                if let name = callsignInfo?.name {
                    Text("- \(name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if !message.elements.isEmpty {
            CWHighlightedText(elements: message.elements)
                .font(.body.monospaced())
        } else {
            Text(message.text)
                .font(.body.monospaced())
                .foregroundStyle(.primary)
        }
    }

    private var footerView: some View {
        HStack(spacing: 8) {
            // Timestamp
            Text(message.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption2)

            // Frequency (if available)
            if let freq = message.frequency {
                Text("\(Int(freq)) Hz")
                    .font(.caption2)
            }

            // Incomplete indicator
            if !message.isComplete {
                ProgressView()
                    .scaleEffect(0.5)
            }
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // Other station message
        CWMessageBubble(
            message: CWConversationMessage(
                frequency: 620,
                text: "CQ CQ CQ DE K4SWL K4SWL K",
                elements: [
                    .prosign("CQ"),
                    .text(" "),
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
                ],
                stationId: .other(callsign: "K4SWL"),
                isComplete: true
            ),
            isMe: false,
            callsignInfo: CallsignInfo(
                callsign: "K4SWL",
                name: "Thomas",
                note: "POTA activator",
                emoji: "🌳",
                qth: "Nashville",
                state: "TN",
                country: "USA",
                grid: "EM66",
                licenseClass: "Extra",
                source: .poloNotes
            )
        )

        // My message
        CWMessageBubble(
            message: CWConversationMessage(
                frequency: 580,
                text: "K4SWL DE N9HO N9HO KN",
                elements: [
                    .callsign("K4SWL", role: .callee),
                    .text(" "),
                    .prosign("DE"),
                    .text(" "),
                    .callsign("N9HO", role: .caller),
                    .text(" "),
                    .callsign("N9HO", role: .caller),
                    .text(" "),
                    .prosign("KN"),
                ],
                stationId: .me,
                isComplete: true
            ),
            isMe: true,
            callsignInfo: nil
        )

        // Unknown station (in progress)
        CWMessageBubble(
            message: CWConversationMessage(
                frequency: 600,
                text: "GM UR 599",
                elements: [
                    .text("GM UR"),
                    .signalReport("599"),
                ],
                stationId: .unknown,
                isComplete: false
            ),
            isMe: false,
            callsignInfo: nil
        )
    }
    .padding()
}
