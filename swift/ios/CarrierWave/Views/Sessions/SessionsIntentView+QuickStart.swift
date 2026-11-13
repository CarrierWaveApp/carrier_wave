import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - SessionsIntentView Quick Start (Skip Wizard)

extension SessionsIntentView {
    /// Most recent session that isn't currently active or paused — the one
    /// the user *finished* most recently. That's what "last session" means
    /// for quick-start purposes; the Continue strip already handles in-flight
    /// sessions.
    var quickStartCandidate: LoggingSession? {
        // Pull a small window and filter rather than predicate-fetch by status
        // — the descriptor sort already orders by `startedAt` so the loop is
        // O(window) and we can keep the existing recent-sessions fetch shape
        // without duplicating it.
        let recent = sessionManager?.getRecentSessions(limit: 10) ?? []
        let activeIDs = Set(activeSessions.map(\.id))
        return recent.first { !activeIDs.contains($0.id) && $0.status == .completed }
    }

    /// Concise one-line description of what "last session" looked like so the
    /// operator can confirm before tapping. Skips empty / default fields.
    func quickStartSubtitle(for session: LoggingSession) -> String {
        var parts: [String] = []
        parts.append(session.mode)
        if let freq = session.frequency {
            parts.append(FrequencyFormatter.formatWithUnit(freq))
        }
        if let power = session.power {
            parts.append("\(power)W")
        }
        let programs = session.programs
        if !programs.isEmpty {
            parts.append(programs.map { $0.uppercased() }.sorted().joined(separator: "+"))
        }
        if let rig = session.myRig, !rig.isEmpty {
            parts.append(rig)
        }
        return parts.joined(separator: " · ")
    }

    /// Bypass the wizard. Pulls the user's most recent finished session and
    /// starts a new one with the same settings — mode, frequency, programs,
    /// equipment, power. Park reference is intentionally *not* carried over
    /// when the prior session was an activation: portable ops typically move
    /// between parks, and starting at the previous park is a footgun the
    /// activator can't undo without ending the session.
    func quickStartFromLastSession() {
        guard let session = quickStartCandidate,
              let manager = sessionManager
        else {
            // Defensive: button shouldn't render without a candidate, but if
            // something raced us into this state, fall back to the wizard.
            showSessionSheet = true
            return
        }
        if tourState.shouldShowMiniTour(.loggerInteractive) {
            // First-time users still get the tour. They wouldn't have a
            // recent session anyway in the normal case, but a re-installed
            // app with restored data could.
            showSessionSheet = true
            return
        }

        // Park ref dropped on purpose (see doc comment). Same logic for
        // SOTA/WWFF/Mission references — those identify a specific location.
        let carryPark = !session.isPOTA
        let carrySota = session.sotaReference == nil

        manager.startSession(
            myCallsign: session.myCallsign,
            mode: session.mode,
            frequency: session.frequency,
            programs: session.programs,
            activationType: session.activationType,
            parkReference: carryPark ? session.parkReference : nil,
            sotaReference: carrySota ? nil : session.sotaReference,
            missionReference: nil,
            wwffReference: nil,
            myGrid: session.myGrid,
            power: session.power,
            myRig: session.myRig,
            myAntenna: session.myAntenna,
            myKey: session.myKey,
            myMic: session.myMic,
            extraEquipment: session.extraEquipment,
            attendees: nil,
            isRove: false,
            autoStartSDR: false,
            stationCallsign: session.stationCallsign,
            operatorCallsigns: session.operatorCallsigns
        )

        ToastManager.shared.success("Session started — same as last time")
        refreshActiveSessions()
    }
}

// MARK: - QuickStartCard

/// Single primary row above the intent grid that bypasses the session-start
/// wizard. Shows up only when there's a finished prior session to clone.
/// Tap → starts a session with the same settings; no sheet.
struct QuickStartCard: View {
    let title: String
    let subtitle: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "play.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.blue.opacity(0.25), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}
