import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - HomeHeroCard

/// State-driven "next action" hero pinned to the top of Home.
///
/// Home's job is launching the next thing, not summarizing the past
/// (docs/ux-north-star.md §3) — this card makes the single most likely
/// action one tap from app launch:
///
/// - **Open session** (active or paused) → one prominent Resume row.
/// - **Idle** → Start Session + Hunt Spots tiles, ordered by `OperatorRole`
///   (hunters get Hunt first).
///
/// Always visible — it is the screen's hero, not a toggleable card. The
/// open-session check is a single `fetchLimit = 1` SwiftData fetch, so the
/// main-thread cost is O(1) regardless of log size.
struct HomeHeroCard: View {
    // MARK: Internal

    @Binding var selectedTab: AppTab?

    var body: some View {
        Group {
            if let session = openSession {
                resumeRow(session)
            } else {
                actionTiles
            }
        }
        .task(id: refreshTrigger) { refreshOpenSession() }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .dashboard {
                refreshTrigger = UUID()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didLogQSO)
        ) { _ in
            refreshTrigger = UUID()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didStartSessionExternally)
        ) { _ in
            refreshTrigger = UUID()
        }
    }

    // MARK: Private

    /// Lightweight snapshot of the most recent open session — only what the
    /// row renders, so the model object doesn't outlive the fetch.
    private struct OpenSession: Equatable {
        let title: String
        let isPaused: Bool
    }

    @Environment(\.modelContext) private var modelContext
    @AppStorage(OperatorRole.storageKey) private var operatorRoleRaw = ""

    @State private var openSession: OpenSession?
    @State private var refreshTrigger = UUID()

    private var roleIsHunter: Bool {
        OperatorRole(rawValue: operatorRoleRaw) == .hunter
    }

    // MARK: - Idle Actions

    /// Start + Hunt side by side; the role's preferred verb leads.
    private var actionTiles: some View {
        HStack(spacing: 12) {
            if roleIsHunter {
                huntTile
                startTile
            } else {
                startTile
                huntTile
            }
        }
    }

    private var startTile: some View {
        heroTile(
            title: "Start Session",
            subtitle: "Activate, casual, or contest",
            icon: "antenna.radiowaves.left.and.right",
            tint: .blue
        ) {
            selectedTab = .logger
        }
    }

    private var huntTile: some View {
        heroTile(
            title: "Hunt Spots",
            subtitle: "Live POTA, SOTA & DX",
            icon: "binoculars.fill",
            tint: .orange
        ) {
            // Same route as the hunt widget: handled centrally so tab
            // switching and first-time Hunter Log setup behave correctly.
            NotificationCenter.default.post(
                name: .didReceiveWidgetDeepLink,
                object: nil,
                userInfo: ["target": "hunt"]
            )
        }
    }

    // MARK: - Resume

    private func resumeRow(_ session: OpenSession) -> some View {
        Button {
            selectedTab = .logger
            // Tab switching alone lands on the Sessions intent screen when
            // the session is paused (or the manager hasn't restored it yet).
            // Ask the tab to actually reopen the session; deferred so
            // SessionsTabView is mounted and listening first.
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .didRequestResumeSession, object: nil
                )
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.isPaused ? "Resume \(session.title)" : "Back to \(session.title)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(
                        session.isPaused
                            ? "Paused session — pick up where you left off"
                            : "Session in progress"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Color.green.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Resume \(session.title)")
    }

    private func heroTile(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(12)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(tint.opacity(0.25), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    // MARK: - Data

    private func refreshOpenSession() {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate {
                $0.statusRawValue == "active" || $0.statusRawValue == "paused"
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let session = (try? modelContext.fetch(descriptor))?.first else {
            openSession = nil
            return
        }
        openSession = OpenSession(
            title: session.displayTitle,
            isPaused: session.statusRawValue == LoggingSessionStatus.paused.rawValue
        )
    }
}
