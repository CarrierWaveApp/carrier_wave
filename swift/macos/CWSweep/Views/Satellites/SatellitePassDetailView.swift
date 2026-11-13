import CarrierWaveData
import SwiftUI

// MARK: - SatellitePassDetailView

/// Right column of the main area: satellite identity + mode, RX/TX Doppler
/// rows, PTT state, the six-tile stats row and the rotator card.
struct SatellitePassDetailView: View {
    // MARK: Internal

    let model: SatellitePassModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let satellite = frame.satellite {
                identityCard(satellite)
                dopplerCard
                statsRow
            } else {
                noSelectionCard
            }
            SatelliteRotatorCard(rotator: model.rotator)
        }
    }

    // MARK: Private

    private var frame: SatellitePassFrame {
        model.frame
    }

    private var modeLine: String {
        var line = frame.transmitter?.modeLine ?? "No transmitter data"
        if let tone = frame.toneHz {
            line += String(format: ", CTCSS %.1f Hz", tone)
        }
        return line
    }

    private var rigLine: String {
        if let hertz = frame.rigFrequencyHz {
            return "Rig \(SatellitePassFormat.mhz(hertz))"
        }
        return "No CAT link"
    }

    private var countdownLabel: String {
        if frame.secondsToLOS != nil {
            return "LOS in"
        }
        if frame.secondsToAOS != nil {
            return "AOS in"
        }
        return "Pass"
    }

    private var countdownValue: String {
        if let seconds = frame.secondsToLOS {
            return SatellitePassFormat.countdown(seconds)
        }
        if let seconds = frame.secondsToAOS {
            return SatellitePassFormat.countdown(seconds)
        }
        return frame.pass == nil ? "—" : "Ended"
    }

    private var countdownTint: Color? {
        frame.secondsToLOS != nil ? SatelliteTheme.satellite : nil
    }

    /// "Dial +1.20 kHz into passband · inverting · duplex" for linear birds.
    private var passbandLine: String? {
        guard let transmitter = frame.transmitter, transmitter.supportsDialFollowing else {
            return nil
        }
        var parts: [String] = []
        if let doppler = frame.doppler, doppler.dialOffsetHz != 0 {
            parts.append("Dial \(SatellitePassFormat.shiftKHz(doppler.dialOffsetHz)) into passband")
        } else {
            parts.append("Dial at passband low edge")
        }
        parts.append(transmitter.invert ? "inverting (REV)" : "non-inverting (NOR)")
        if frame.isDuplexCAT {
            parts.append("uplink follows dial")
        }
        return parts.joined(separator: " · ")
    }

    private var noSelectionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No pass selected")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SatelliteTheme.textPrimary)
            Text("Pick a pass from the list to see Doppler, look angles and the sky track.")
                .font(SatelliteTheme.label(12, weight: .regular))
                .foregroundStyle(SatelliteTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .satelliteCard()
    }

    private var pttPill: some View {
        let transmitting = frame.isTransmitting
        return Text(transmitting ? "TX" : "RX")
            .font(SatelliteTheme.mono(11, weight: .bold))
            .foregroundStyle(SatelliteTheme.background)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(transmitting ? SatelliteTheme.tx : SatelliteTheme.rx))
            .help(transmitting ? "Rig is transmitting" : "Receiving")
    }

    private var dopplerCard: some View {
        VStack(spacing: 0) {
            dopplerHeader
            Rectangle()
                .fill(SatelliteTheme.hairline)
                .frame(height: 1)
            SatelliteDopplerRow(
                tag: "RX",
                tint: SatelliteTheme.rx,
                nominal: SatellitePassFormat.mhz(frame.doppler?.nominalDownlinkHz),
                corrected: SatellitePassFormat.mhz(frame.doppler?.correctedDownlinkHz),
                shift: SatellitePassFormat.shiftKHz(frame.doppler?.downlinkShiftHz),
                highlighted: false
            )
            SatelliteDopplerRow(
                tag: "TX",
                tint: SatelliteTheme.tx,
                nominal: SatellitePassFormat.mhz(frame.doppler?.nominalUplinkHz),
                corrected: SatellitePassFormat.mhz(frame.doppler?.correctedUplinkHz),
                shift: SatellitePassFormat.shiftKHz(frame.doppler?.uplinkShiftHz),
                highlighted: frame.isTransmitting
            )
            if let passbandLine {
                Rectangle()
                    .fill(SatelliteTheme.hairline)
                    .frame(height: 1)
                Text(passbandLine)
                    .font(SatelliteTheme.label(10, weight: .medium))
                    .foregroundStyle(SatelliteTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
        }
        .satelliteCard(padding: 0)
    }

    private var dopplerHeader: some View {
        HStack {
            Text("")
                .frame(width: 34)
            Text("NOMINAL")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("CORRECTED")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("SHIFT")
                .frame(width: 92, alignment: .trailing)
        }
        .font(SatelliteTheme.label(9, weight: .semibold))
        .tracking(0.6)
        .foregroundStyle(SatelliteTheme.textTertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var statsRow: some View {
        let look = frame.look
        return HStack(spacing: 8) {
            SatelliteStatTile(label: "Range", value: SatellitePassFormat.kilometers(look?.rangeKm))
            SatelliteStatTile(label: "Range rate", value: SatellitePassFormat.kmPerSecond(look?.rangeRateKmPerSec))
            SatelliteStatTile(label: countdownLabel, value: countdownValue, tint: countdownTint)
            SatelliteStatTile(
                label: "Max el", value: SatellitePassFormat.degrees(frame.pass?.peakElevationDeg, decimals: 0)
            )
            SatelliteStatTile(label: "Altitude", value: SatellitePassFormat.kilometers(look?.altitudeKm))
            SatelliteStatTile(label: "S-meter", value: frame.sMeterLabel, tint: SatelliteTheme.rx)
        }
    }

    private func identityCard(_ satellite: SweepSatellite) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(satellite.displayName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SatelliteTheme.textPrimary)
                    .lineLimit(1)
                Text("NORAD \(satellite.noradID)")
                    .font(SatelliteTheme.mono(12))
                    .foregroundStyle(SatelliteTheme.textTertiary)
                Spacer()
                pttPill
            }
            HStack(spacing: 10) {
                Text(modeLine)
                    .font(SatelliteTheme.label(12, weight: .regular))
                    .foregroundStyle(SatelliteTheme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text(rigLine)
                    .font(SatelliteTheme.mono(11))
                    .foregroundStyle(
                        frame.rigFrequencyHz == nil ? SatelliteTheme.textTertiary : SatelliteTheme.textSecondary
                    )
            }
        }
        .satelliteCard()
    }
}

// MARK: - SatelliteDopplerRow

struct SatelliteDopplerRow: View {
    let tag: String
    let tint: Color
    let nominal: String
    let corrected: String
    let shift: String
    let highlighted: Bool

    var body: some View {
        HStack {
            Text(tag)
                .font(SatelliteTheme.mono(12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, alignment: .leading)
            Text(nominal)
                .foregroundStyle(SatelliteTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(corrected)
                .foregroundStyle(SatelliteTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(shift)
                .foregroundStyle(tint)
                .frame(width: 92, alignment: .trailing)
        }
        .font(SatelliteTheme.mono(14, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(highlighted ? tint.opacity(0.18) : .clear)
    }
}

// MARK: - SatelliteStatTile

struct SatelliteStatTile: View {
    let label: String
    let value: String
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(SatelliteTheme.label(9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(SatelliteTheme.textTertiary)
                .lineLimit(1)
            Text(value)
                .font(SatelliteTheme.mono(15, weight: .semibold))
                .foregroundStyle(tint ?? SatelliteTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SatelliteTheme.panel)
        )
    }
}

// MARK: - SatelliteRotatorCard

struct SatelliteRotatorCard: View {
    // MARK: Internal

    let rotator: RotatorController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(stateTint)
                    .frame(width: 8, height: 8)
                Text("Rotator")
                    .font(SatelliteTheme.label(12, weight: .semibold))
                    .foregroundStyle(SatelliteTheme.textPrimary)
                Text(rotator.state.label)
                    .font(SatelliteTheme.label(12, weight: .regular))
                    .foregroundStyle(SatelliteTheme.textSecondary)
                if let kind = rotator.endpoint?.kind.displayName {
                    Text("· \(kind)")
                        .font(SatelliteTheme.label(12, weight: .regular))
                        .foregroundStyle(SatelliteTheme.textTertiary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Button("Park") {
                        Task { await rotator.park() }
                    }
                    Button("Stop") {
                        Task { await rotator.stop() }
                    }
                    .tint(SatelliteTheme.tx)
                }
                .controlSize(.small)
                .disabled(!rotator.isConnected)
            }

            if rotator.isConnected {
                HStack(spacing: 18) {
                    labelled("AZ", SatellitePassFormat.degrees(rotator.position?.azimuthDeg))
                    labelled("EL", SatellitePassFormat.degrees(rotator.position?.elevationDeg))
                    labelled("Error", SatellitePassFormat.degrees(rotator.pointingErrorDeg))
                    if let target = rotator.target {
                        let azimuth = SatellitePassFormat.degrees(target.azimuthDeg)
                        let elevation = SatellitePassFormat.degrees(target.elevationDeg)
                        labelled("Target", "\(azimuth) / \(elevation)")
                    }
                }
                if let error = rotator.lastError {
                    Text(error)
                        .font(SatelliteTheme.label(11, weight: .regular))
                        .foregroundStyle(SatelliteTheme.tx)
                        .lineLimit(2)
                }
                SatelliteRotatorManualControls(rotator: rotator)
            } else {
                Text("Open in Settings → Trackers to connect a rotator.")
                    .font(SatelliteTheme.label(11, weight: .regular))
                    .foregroundStyle(SatelliteTheme.textTertiary)
            }
        }
        .satelliteCard()
    }

    // MARK: Private

    private var stateTint: Color {
        switch rotator.state {
        case .following: SatelliteTheme.rx
        case .idle: SatelliteTheme.accent
        case .connecting: SatelliteTheme.satellite
        case .error: SatelliteTheme.tx
        case .disconnected: SatelliteTheme.textTertiary
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .font(SatelliteTheme.label(10, weight: .semibold))
                .foregroundStyle(SatelliteTheme.textTertiary)
            Text(value)
                .font(SatelliteTheme.mono(14, weight: .medium))
                .foregroundStyle(SatelliteTheme.textPrimary)
        }
    }
}

// MARK: - Card modifier

extension View {
    /// Pass-detail card: panel fill, 12 pt radius, hairline edge.
    func satelliteCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SatelliteTheme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(SatelliteTheme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
