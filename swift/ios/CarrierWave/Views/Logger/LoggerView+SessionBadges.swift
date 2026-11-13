import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - Session Control Bar Badges

extension LoggerView {
    /// Space weather storm warning as a compact chip
    @ViewBuilder
    var spaceWeatherChip: some View {
        let impact = DONKIPollingService.shared.worstActiveImpact
        if impact >= .moderate {
            Button {
                showSpaceWeatherSheet = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                    Text(spaceWeatherChipLabel(impact))
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(impact >= .severe ? .red : .orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    (impact >= .severe ? Color.red : Color.orange)
                        .opacity(0.15)
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    func spaceWeatherChipLabel(
        _ impact: RadioImpactLevel
    ) -> String {
        switch impact {
        case .extreme: "HF Down"
        case .severe: "HF↓"
        case .moderate: "Storm"
        default: "WX"
        }
    }

    /// Situational chips for the session controls bar — operating shift,
    /// equipment, duration, space weather, and SDR/radio status. Hidden in
    /// Simple Logging Mode so the bar stays short during a pileup.
    @ViewBuilder
    func situationalChips(_ session: LoggingSession) -> some View {
        activeShiftPill(session)
        equipmentCapsule(session)
        durationChip(session)
        spaceWeatherChip
        sdrTitleBarPill
        webSDRBadgeIfNeeded(session)
        if !showRadioPanel {
            radioInlineBadge
        }
    }

    /// SDR status pill for the title bar (always visible when SDR is active)
    @ViewBuilder
    var sdrTitleBarPill: some View {
        if let manager = sessionManager,
           manager.webSDRSession.state.isActive
        {
            Button {
                present(.webSDR)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: manager.webSDRSession.state.statusIcon)
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                        .symbolEffect(
                            .pulse,
                            isActive: manager.webSDRSession.state == .recording
                        )
                    Text("SDR")
                        .font(.caption2.weight(.medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.red.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// Compact inline WebSDR recording badge for the session controls bar
    func webSDRInlineBadge(session: WebSDRSession) -> some View {
        Button {
            present(.webSDR)
        } label: {
            HStack(spacing: 3) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                Text(formatWebSDRDuration(session.recordingDuration))
                    .font(.caption2.monospacedDigit())
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Inline radio status badge for the session controls bar
    @ViewBuilder
    var radioInlineBadge: some View {
        let service = RadioService.shared
        if service.isConnected {
            radioBadgeButton(color: .green)
        } else if service.isConfigured {
            radioBadgeButton(color: .orange)
        }
    }

    private func radioBadgeButton(color: Color) -> some View {
        Button {
            present(.radio)
        } label: {
            HStack(spacing: 3) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text("Radio")
                    .font(.caption2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    func hasAnyEquipment(_ session: LoggingSession) -> Bool {
        [session.myRig, session.myAntenna, session.myKey, session.myMic]
            .contains { $0 != nil && !$0!.isEmpty }
    }

    func equipmentCapsuleLabel(_ session: LoggingSession) -> String {
        if let rig = session.myRig, !rig.isEmpty {
            let extras = [session.myAntenna, session.myKey, session.myMic]
                .compactMap { $0 }.filter { !$0.isEmpty }.count
            let truncatedRig = rig.count > 12 ? String(rig.prefix(10)) + "…" : rig
            return extras > 0 ? "\(truncatedRig) +\(extras)" : truncatedRig
        }
        if hasAnyEquipment(session) {
            return "Equipment"
        }
        return "Equip"
    }
}
