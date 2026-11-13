import SwiftUI

// MARK: - RemoteStraightKeyPad

//
// On-phone "tap straight key" surface for the Remote pane. One large pad:
// tap → dit, hold past 180 ms → dah. Each gesture fires exactly one CW
// element through Sweep's keyer (Bridge → WinKeyer → CAT-direct), since
// Sweep's CW transports are text-mode and don't have a raw key-line API.
// True keyDown/keyUp lives behind a future CW Bridge firmware change; this
// is the pragmatic version that works across all three transports today.
//

struct RemoteStraightKeyPad: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("STRAIGHT KEY")
            keyButton
            footerText
        }
    }

    // MARK: Private

    private enum Element: String {
        case dit
        case dah

        // MARK: Internal

        var wireText: String {
            switch self {
            case .dit: "E"
            case .dah: "T"
            }
        }

        var glyph: String {
            switch self {
            case .dit: "•"
            case .dah: "—"
            }
        }
    }

    /// 180 ms ≈ two dit-times at 20 WPM. Long enough to make a deliberate
    /// "hold for dah" reliable, short enough that real taps stay dits.
    private static let dahHoldThreshold: TimeInterval = 0.18

    @Environment(RemoteSweepCoordinator.self) private var coordinator
    @State private var pressing = false
    @State private var pressedAt: Date?
    @State private var pendingElement: Element?
    @State private var lastSent: Element?
    @State private var lastSentAt: Date = .distantPast
    @State private var lastError: String?

    private var keyerAvailable: Bool {
        coordinator.isRemoteCWKeyerAvailable
    }

    private var tint: Color {
        let element = pendingElement ?? lastSent
        switch element {
        case .dah: return .orange
        case .dit,
             .none: return .blue
        }
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard keyerAvailable else {
                    return
                }
                if !pressing {
                    pressing = true
                    pressedAt = Date()
                    pendingElement = .dit
                    schedulePromotionToDah()
                }
            }
            .onEnded { _ in
                guard pressing else {
                    return
                }
                pressing = false
                let element = pendingElement ?? .dit
                pendingElement = nil
                send(element)
            }
    }

    private var keyButton: some View {
        Text(pendingElement?.glyph ?? lastSent?.glyph ?? "•")
            .font(.system(size: 88, weight: .semibold, design: .monospaced))
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .foregroundStyle(tint)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(pressing ? 0.32 : 0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        keyerAvailable ? tint.opacity(0.55) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .scaleEffect(pressing ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.08), value: pressing)
            .contentShape(Rectangle())
            .gesture(pressGesture)
            .accessibilityLabel("CW key. Tap for dit, hold for dah.")
            .opacity(keyerAvailable ? 1 : 0.4)
    }

    @ViewBuilder
    private var footerText: some View {
        if let lastError {
            Text(lastError)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.red.opacity(0.85))
        } else if !keyerAvailable {
            Text("NO CW PATH AT SWEEP")
                .font(.system(.caption2, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.35))
        } else {
            Text("TAP DIT · HOLD DAH")
                .font(.system(.caption2, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .tracking(1.8)
            .foregroundStyle(.white.opacity(0.35))
    }

    /// After the threshold elapses, if the finger is still down, promote
    /// the pending element from dit to dah. We don't fire on promotion —
    /// fire happens on release — but the visible glyph flips so the user
    /// knows what they're about to send.
    private func schedulePromotionToDah() {
        let stamp = pressedAt
        Task {
            let nanos = UInt64(Self.dahHoldThreshold * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            await MainActor.run {
                guard pressing, pressedAt == stamp else {
                    return
                }
                pendingElement = .dah
            }
        }
    }

    private func send(_ element: Element) {
        guard keyerAvailable else {
            return
        }
        lastSent = element
        lastSentAt = Date()
        let stamp = lastSentAt
        Task {
            let ok = await coordinator.cwSendText(element.wireText)
            await MainActor.run {
                lastError = ok ? nil : "Send failed"
            }
            try? await Task.sleep(nanoseconds: 220_000_000)
            await MainActor.run {
                if stamp == lastSentAt {
                    lastSent = nil
                }
            }
        }
    }
}
