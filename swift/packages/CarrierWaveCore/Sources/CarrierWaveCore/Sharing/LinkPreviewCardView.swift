//
//  LinkPreviewCardView.swift
//  CarrierWaveCore
//
//  Cross-platform SwiftUI views that render as the LPLinkMetadata image
//  for enriched share links. Rendered to a PlatformImage by
//  LinkPreviewCardRenderer. Card layouts intentionally use only basic
//  SwiftUI primitives (Text, VStack, HStack, ZStack, RoundedRectangle,
//  LinearGradient) so they render identically on iOS and macOS.
//

import SwiftUI

// MARK: - LinkPreviewCardKind

public enum LinkPreviewCardKind: Sendable {
    case callsign(CallsignPayload)
    case park(ParkPayload)
    case summit(SummitPayload)
    case qso(QSOPayload)
    case activation(ActivationPayload)
}

// MARK: - LinkPreviewCardView

/// Top-level dispatcher view. Renders the appropriate sub-card for the
/// payload kind. Fixed 1200×630 frame (OpenGraph standard) — matches the
/// `og:image` aspect ratio expected by chat-app link unfurlers.
public struct LinkPreviewCardView: View {
    // MARK: Lifecycle

    public init(kind: LinkPreviewCardKind) {
        self.kind = kind
    }

    // MARK: Public

    public static let cardSize = CGSize(width: 1_200, height: 630)

    public var body: some View {
        ZStack {
            background
            content
                .padding(72)
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
    }

    // MARK: Private

    private let kind: LinkPreviewCardKind

    @ViewBuilder
    private var content: some View {
        switch kind {
        case let .callsign(payload):
            CallsignCardContent(payload: payload)
        case let .park(payload):
            ParkCardContent(payload: payload)
        case let .summit(payload):
            SummitCardContent(payload: payload)
        case let .qso(payload):
            QSOCardContent(payload: payload)
        case let .activation(payload):
            ActivationCardContent(payload: payload)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.07, blue: 0.12),
                Color(red: 0.10, green: 0.14, blue: 0.22),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - CallsignCardContent

struct CallsignCardContent: View {
    let payload: CallsignPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("CALLSIGN")
                .font(.system(size: 28, weight: .semibold, design: .default))
                .tracking(4)
                .foregroundStyle(Color.orange.opacity(0.8))
            Text(payload.callsign)
                .font(.system(size: 180, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let name = payload.name {
                Text(name)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            HStack(spacing: 32) {
                if let grid = payload.grid {
                    LinkPreviewBadge(label: "GRID", value: grid)
                }
                if let country = payload.country {
                    LinkPreviewBadge(label: "DXCC", value: country)
                }
                if let workedCount = payload.workedCount, workedCount > 0 {
                    LinkPreviewBadge(label: "WORKED", value: "\(workedCount)×")
                }
            }
            if let hint = payload.propagationHint {
                HStack(spacing: 12) {
                    Text("◉")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(.yellow)
                    Text(hint)
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            Spacer()
            CarrierWaveBranding()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ParkCardContent

struct ParkCardContent: View {
    let payload: ParkPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("PARK")
                .font(.system(size: 28, weight: .semibold))
                .tracking(4)
                .foregroundStyle(Color.green.opacity(0.85))
            Text(payload.reference)
                .font(.system(size: 120, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let name = payload.name {
                Text(name)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(2)
            }
            HStack(spacing: 28) {
                if let state = payload.state {
                    LinkPreviewBadge(label: "STATE", value: state)
                }
                if let activations = payload.userActivations, activations > 0 {
                    LinkPreviewBadge(label: "ACTIVATIONS", value: "\(activations)")
                }
                if let hunts = payload.userHunts, hunts > 0 {
                    LinkPreviewBadge(label: "HUNTS", value: "\(hunts)")
                }
                if payload.isActiveNow == true {
                    LinkPreviewBadge(label: "STATUS", value: "ACTIVE NOW", tint: .green)
                }
            }
            Spacer()
            CarrierWaveBranding()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - SummitCardContent

struct SummitCardContent: View {
    let payload: SummitPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("SUMMIT")
                .font(.system(size: 28, weight: .semibold))
                .tracking(4)
                .foregroundStyle(Color.orange.opacity(0.85))
            Text(payload.reference)
                .font(.system(size: 120, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let name = payload.name {
                Text(name)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(2)
            }
            HStack(spacing: 28) {
                if let altitude = payload.altitudeMeters {
                    LinkPreviewBadge(label: "ALTITUDE", value: "\(altitude) m")
                }
                if let points = payload.points {
                    LinkPreviewBadge(label: "POINTS", value: "\(points)", tint: .orange)
                }
                if let region = payload.regionName, !region.isEmpty {
                    LinkPreviewBadge(label: "REGION", value: region)
                }
                if let activations = payload.activationCount, activations > 0 {
                    LinkPreviewBadge(label: "ACTIVATIONS", value: "\(activations)")
                }
            }
            Spacer()
            CarrierWaveBranding()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - QSOCardContent

struct QSOCardContent: View {
    // MARK: Internal

    let payload: QSOPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("QSO")
                .font(.system(size: 28, weight: .semibold))
                .tracking(4)
                .foregroundStyle(Color.cyan.opacity(0.85))
            HStack(alignment: .firstTextBaseline, spacing: 32) {
                Text(payload.theirCall)
                    .font(.system(size: 120, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("← \(payload.myCall)")
                    .font(.system(size: 52, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            HStack(spacing: 28) {
                LinkPreviewBadge(label: "BAND", value: payload.band)
                LinkPreviewBadge(label: "MODE", value: payload.mode)
                if let rstSent = payload.rstSent, let rstRecv = payload.rstReceived {
                    LinkPreviewBadge(label: "RST", value: "\(rstSent)/\(rstRecv)")
                }
                if let parkRef = payload.parkReference {
                    LinkPreviewBadge(label: "PARK", value: parkRef, tint: .green)
                }
            }
            Text(formattedTimestamp)
                .font(.system(size: 36, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            CarrierWaveBranding()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Private

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: payload.timestamp)
    }
}

// MARK: - ActivationCardContent

struct ActivationCardContent: View {
    let payload: ActivationPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ACTIVATION")
                .font(.system(size: 28, weight: .semibold))
                .tracking(4)
                .foregroundStyle(Color.yellow.opacity(0.85))
            Text(payload.parkReference)
                .font(.system(size: 96, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
            if let parkName = payload.parkName {
                Text(parkName)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
            }
            Text("by \(payload.myCall)")
                .font(.system(size: 36, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
            HStack(spacing: 28) {
                LinkPreviewBadge(label: "QSOs", value: "\(payload.qsoCount)")
                if !payload.bands.isEmpty {
                    LinkPreviewBadge(label: "BANDS", value: payload.bands.joined(separator: " "))
                }
                if let p2p = payload.parkToParkCount, p2p > 0 {
                    LinkPreviewBadge(label: "P2P", value: "\(p2p)")
                }
                if let dxcc = payload.dxccCount, dxcc > 0 {
                    LinkPreviewBadge(label: "DXCC", value: "\(dxcc)")
                }
            }
            Spacer()
            CarrierWaveBranding()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - LinkPreviewBadge

struct LinkPreviewBadge: View {
    let label: String
    let value: String
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 22, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 38, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
        }
    }
}

// MARK: - CarrierWaveBranding

struct CarrierWaveBranding: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.orange)
                .frame(width: 28, height: 28)
            Text("CARRIER WAVE")
                .font(.system(size: 28, weight: .bold))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
