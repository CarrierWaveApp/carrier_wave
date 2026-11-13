import CarrierWaveData
import SwiftUI

// MARK: - SatellitesHeaderView

/// Title strip: workspace name + selected satellite, CAT / rotator toggles,
/// waterfall presentation picker, refresh, and a live UTC clock.
struct SatellitesHeaderView: View {
    // MARK: Internal

    let model: SatellitePassModel

    @Binding var waterfallCorrected: Bool

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Text("Satellites")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SatelliteTheme.textPrimary)
                if let name = model.frame.satellite?.displayName {
                    Text("·")
                        .foregroundStyle(SatelliteTheme.textTertiary)
                    Text(name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SatelliteTheme.satellite)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Toggle("CAT", isOn: catEnabled)
                .toggleStyle(.switch)
                .help("Push Doppler-corrected frequencies to the rig")

            Toggle("Rotator follow", isOn: rotatorFollowing)
                .toggleStyle(.switch)
                .disabled(!model.rotator.isConnected)
                .help(model.rotator.isConnected ? "Steer the rotator along the pass" : "No rotator connected")

            Picker("Waterfall", selection: $waterfallCorrected) {
                Text("Corrected").tag(true)
                Text("Uncorrected").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
            .help("Corrected keeps the signal centred; Uncorrected shows the Doppler drift")

            Button {
                Task { await model.reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.state == .loading)
            .help("Refresh TLEs and transmitters")

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(SatellitePassFormat.utcClock(context.date))
                    .font(SatelliteTheme.mono(15, weight: .medium))
                    .foregroundStyle(SatelliteTheme.textPrimary)
            }
            .frame(minWidth: 108, alignment: .trailing)
        }
        .controlSize(.small)
        .font(SatelliteTheme.label(12))
        .foregroundStyle(SatelliteTheme.textSecondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(SatelliteTheme.panel)
    }

    // MARK: Private

    private var catEnabled: Binding<Bool> {
        Binding(
            get: { model.cat.isEnabled },
            set: { model.cat.isEnabled = $0 }
        )
    }

    private var rotatorFollowing: Binding<Bool> {
        Binding(
            get: { model.rotator.isFollowing },
            set: { follow in
                if follow {
                    Task { await model.rotator.startFollowing() }
                } else {
                    model.rotator.stopFollowing()
                }
            }
        )
    }
}

// MARK: - SatelliteStatusRowView

/// Themed status bar for the workspace: rig + CAT link, rotator, station
/// callsign, TLE age and observer grid.
struct SatelliteStatusRowView: View {
    // MARK: Internal

    let model: SatellitePassModel
    let callsign: String

    var body: some View {
        HStack(spacing: 10) {
            item(systemImage: "antenna.radiowaves.left.and.right", text: rigLabel, tint: rigTint)
            Text(model.cat.summaryLabel)
                .foregroundStyle(SatelliteTheme.textSecondary)
            divider
            item(systemImage: "dial.medium", text: rotatorLabel, tint: rotatorTint)
            divider
            item(systemImage: "person.text.rectangle", text: callsign.isEmpty ? "No callsign" : callsign, tint: nil)
            divider
            item(systemImage: "clock.arrow.2.circlepath", text: model.tleAgeLabel, tint: nil)
            divider
            item(systemImage: "mappin.and.ellipse", text: model.observerGrid ?? "Grid not set", tint: nil)
            Spacer()
            if let look = model.frame.look {
                Text(look.isAboveHorizon ? "Above horizon" : "Below horizon")
                    .foregroundStyle(look.isAboveHorizon ? SatelliteTheme.rx : SatelliteTheme.textTertiary)
            }
        }
        .font(SatelliteTheme.mono(11))
        .foregroundStyle(SatelliteTheme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(SatelliteTheme.panel)
    }

    // MARK: Private

    private var rigLabel: String {
        if model.radioManager.isConnected {
            return model.radioManager.connectedRadioName ?? "Radio"
        }
        return "No rig"
    }

    private var rigTint: Color? {
        model.radioManager.isConnected ? SatelliteTheme.rx : nil
    }

    private var rotatorLabel: String {
        let kind = model.rotator.endpoint?.kind.displayName ?? model.rotator.savedEndpoint?.kind.displayName
        if let kind {
            return "Rotator \(model.rotator.state.label) · \(kind)"
        }
        return "Rotator \(model.rotator.state.label)"
    }

    private var rotatorTint: Color? {
        switch model.rotator.state {
        case .following: SatelliteTheme.rx
        case .idle: SatelliteTheme.accent
        case .error: SatelliteTheme.tx
        case .connecting,
             .disconnected: nil
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(SatelliteTheme.hairline)
            .frame(width: 1, height: 12)
    }

    private func item(systemImage: String, text: String, tint: Color?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(tint ?? SatelliteTheme.textTertiary)
            Text(text)
                .foregroundStyle(tint ?? SatelliteTheme.textSecondary)
                .lineLimit(1)
        }
    }
}
