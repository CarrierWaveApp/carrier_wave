import CarrierWaveCore
import SwiftUI

// MARK: - CWChatView

/// Chat-style display of a CW conversation with message bubbles
struct CWChatView: View {
    // MARK: Internal

    let conversation: CWConversation
    let callsignLookup: ((String) -> CallsignInfo?)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if conversation.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(conversation.messages) { message in
                            CWMessageBubble(
                                message: message,
                                isMe: message.stationId == .me,
                                callsignInfo: lookupCallsign(for: message)
                            )
                            .id(message.id)
                        }
                    }

                    // Anchor for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: conversation.messages.count) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: lastMessageText) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    /// Track last message text for auto-scroll on updates
    private var lastMessageText: String {
        conversation.messages.last?.text ?? ""
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Listening for QSO...")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Decoded text will appear as a conversation")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }

    private func lookupCallsign(for message: CWConversationMessage) -> CallsignInfo? {
        guard let callsign = message.stationId.callsign else {
            return nil
        }
        return callsignLookup?(callsign)
    }
}

// MARK: - Preview

#Preview {
    let conversation: CWConversation = {
        var conv = CWConversation(myCallsign: "N9HO")

        // Other station calling CQ
        conv.addMessage(
            CWConversationMessage(
                frequency: 620,
                text: "CQ CQ CQ DE K4SWL K4SWL K",
                elements: CallsignDetector.parseElements(from: "CQ CQ CQ DE K4SWL K4SWL K"),
                stationId: .other(callsign: "K4SWL"),
                isComplete: true
            )
        )

        // My response
        conv.addMessage(
            CWConversationMessage(
                frequency: 580,
                text: "K4SWL DE N9HO N9HO KN",
                elements: CallsignDetector.parseElements(from: "K4SWL DE N9HO N9HO KN"),
                stationId: .me,
                isComplete: true
            )
        )

        // Other station's exchange
        conv.addMessage(
            CWConversationMessage(
                frequency: 620,
                text: "N9HO GM UR 599 599 NC NC BK",
                elements: CallsignDetector.parseElements(from: "N9HO GM UR 599 599 NC NC BK"),
                stationId: .other(callsign: "K4SWL"),
                isComplete: true
            )
        )

        // My exchange (in progress)
        conv.addMessage(
            CWConversationMessage(
                frequency: 580,
                text: "R R K4SWL UR 559",
                elements: CallsignDetector.parseElements(from: "R R K4SWL UR 559"),
                stationId: .me,
                isComplete: false
            )
        )

        return conv
    }()

    return CWChatView(
        conversation: conversation,
        callsignLookup: { callsign in
            if callsign == "K4SWL" {
                return CallsignInfo(
                    callsign: "K4SWL",
                    name: "Thomas",
                    note: "POTA activator",
                    emoji: "🌳",
                    qth: "Nashville",
                    state: "TN",
                    country: nil,
                    grid: "EM66",
                    licenseClass: "Extra",
                    source: .poloNotes
                )
            }
            return nil
        }
    )
    .frame(height: 400)
    .padding()
}
