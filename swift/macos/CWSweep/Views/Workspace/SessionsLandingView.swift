import CarrierWaveData
import SwiftUI

// MARK: - SessionsLandingView

/// Intent-first landing for the Sessions sidebar item.
///
/// 2×2 grid of verb-first cards (Activate / Hunt / Casual / Contest), mirroring
/// the iOS `SessionsIntentView` shape so an operator who learned the pattern on
/// iPhone gets identical muscle memory on macOS. A `Continue` strip below
/// surfaces paused sessions (typically existing contest sessions on PR3-era
/// builds, since `ContestManager` is the only thing creating sessions on
/// CW Sweep today).
///
/// PR3 ships the layout + Continue strip; intent card actions and
/// resume/finish are stubbed via the closures passed in by `SessionsSidebarRoot`.
/// PR4 will wire the real lifecycle.
struct SessionsLandingView: View {
    // MARK: Internal

    let pausedSessions: [LoggingSession]
    let onResume: (LoggingSession) -> Void
    let onFinish: (LoggingSession) -> Void
    let onIntent: (SessionsIntent) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                intentGrid
                if !pausedSessions.isEmpty {
                    continueStrip
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: Private

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sessions")
                .font(.largeTitle.weight(.semibold))
            Text("Start operating")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var intentGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(SessionsIntent.allCases) { intent in
                IntentCard(intent: intent) { onIntent(intent) }
            }
        }
    }

    private var continueStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue")
                .font(.headline)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(pausedSessions.enumerated()), id: \.element.id) { index, session in
                    PausedSessionRow(
                        session: session,
                        onResume: { onResume(session) },
                        onFinish: { onFinish(session) }
                    )
                    if index != pausedSessions.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - SessionsIntent

/// The four cards in the macOS intent grid. Mirrors the iOS shape but isn't
/// shared yet — the protocols/types will converge in PR4 when the macOS
/// session-start surface lands.
enum SessionsIntent: String, CaseIterable, Identifiable {
    case activate
    case hunt
    case casual
    case contest

    // MARK: Internal

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .activate: "Activate"
        case .hunt: "Hunt"
        case .casual: "Casual"
        case .contest: "Contest"
        }
    }

    var subtitle: String {
        switch self {
        case .activate: "POTA, SOTA, WWFF & more"
        case .hunt: "Chase spots & DX"
        case .casual: "Ragchew & random QSOs"
        case .contest: "Score & exchange"
        }
    }

    var systemImage: String {
        switch self {
        case .activate: "antenna.radiowaves.left.and.right"
        case .hunt: "binoculars"
        case .casual: "dot.radiowaves.left.and.right"
        case .contest: "trophy"
        }
    }

    var tint: Color {
        switch self {
        case .activate: .blue
        case .hunt: .orange
        case .casual: .green
        case .contest: .purple
        }
    }
}

// MARK: - IntentCard

private struct IntentCard: View {
    let intent: SessionsIntent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: intent.systemImage)
                    .font(.title)
                    .foregroundStyle(intent.tint)
                    .frame(width: 32, height: 32, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(intent.label)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(intent.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(intent.tint.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(intent.label)
        .accessibilityHint(intent.subtitle)
    }
}

// MARK: - PausedSessionRow

private struct PausedSessionRow: View {
    // MARK: Internal

    let session: LoggingSession
    let onResume: () -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sessionIcon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(sessionTitle)
                    .font(.subheadline.weight(.medium))
                Text(sessionSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Resume", action: onResume)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Finish", action: onFinish)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Private

    private var sessionIcon: String {
        if isPreUnificationLog {
            return "archivebox"
        }
        if session.contestId != nil {
            return "trophy"
        }
        if session.isPOTA {
            return "tree"
        }
        return "dot.radiowaves.left.and.right"
    }

    private var sessionTitle: String {
        if let custom = session.customTitle, !custom.isEmpty {
            return custom
        }
        if let contest = session.contestId, !contest.isEmpty {
            return contest.uppercased()
        }
        if let park = session.parkReference, !park.isEmpty {
            return park
        }
        return session.myCallsign.isEmpty ? "Session" : session.myCallsign
    }

    /// Backfilled sessions (CAR-276 PR5) get an `archivebox` icon and italicized
    /// title so operators distinguish historical groupings from operator-started
    /// sessions.
    private var isPreUnificationLog: Bool {
        session.customTitle?.hasPrefix("Pre-unification log") ?? false
    }

    private var sessionSubtitle: String {
        let qsoLabel = session.qsoCount == 1 ? "1 QSO" : "\(session.qsoCount) QSOs"
        let started = session.startedAt.formatted(.relative(presentation: .named))
        return "\(qsoLabel) · started \(started)"
    }
}
