import CarrierWaveData
import SwiftUI

// MARK: - WsjtxStatusBadge

/// Status-bar chip for the WSJT-X UDP listener (CAR-282): "WSJT-X" plus the
/// last QSO it logged (or "listening"), with counts in the tooltip. Renders
/// nothing while the listener is stopped, so `StatusBarView` can place it
/// unconditionally.
struct WsjtxStatusBadge: View {
    // MARK: Internal

    var body: some View {
        if service.isRunning {
            HStack(spacing: 4) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                Text("WSJT-X")
                    .fontWeight(.semibold)
                Text(service.lastLoggedSummary ?? "listening")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .help(helpText)
            .accessibilityLabel("WSJT-X listener running")
            Divider()
                .frame(height: 12)
        }
    }

    // MARK: Private

    @Environment(WsjtxIngestService.self) private var service

    private var helpText: String {
        let endpoint = "\(service.host):\(service.boundPort ?? service.port)"
        return "WSJT-X listener on \(endpoint) — \(service.loggedCount) logged, "
            + "\(service.duplicateCount) duplicates skipped"
    }
}
