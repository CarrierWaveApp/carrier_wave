import CarrierWaveData
import SwiftUI

// MARK: - GettingStartedItem

/// A single row in the Getting Started card. Each item is framed as the
/// *value* the user unlocks, not a chore to complete.
struct GettingStartedItem: Identifiable {
    let id: String
    let title: String
    let reward: String
    let icon: String
    let isComplete: Bool
    let action: () -> Void
}

// MARK: - DashboardGettingStartedCard

/// Persistent "Getting Started" card shown on the dashboard while the user
/// still has optional setup steps available. Replaces the mandatory service
/// connection and community-opt-in screens from the original onboarding flow.
///
/// Design principles (see pedagogy discussion in commit history):
/// - Every item is optional and dismissible
/// - Items are framed by *reward*, not task ("auto-upload confirmations",
///   not "connect LoTW")
/// - Progress is shown but never mandatory — user can dismiss at any time
/// - Completed card collapses itself when every item is done
struct DashboardGettingStartedCard: View {
    // MARK: Internal

    @Bindable var tourState: TourState
    var potaAuth: POTAAuthService

    @Binding var selectedTab: AppTab?
    @Binding var settingsDestination: SettingsDestination?

    var body: some View {
        if shouldShow {
            cardBody
                .task(id: refreshTrigger) { await refreshState() }
                .onReceive(
                    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
                ) { _ in refreshTrigger = UUID() }
                .onChange(of: selectedTab) { _, newTab in
                    if newTab == .dashboard {
                        refreshTrigger = UUID()
                    }
                }
        }
    }

    // MARK: Private

    @AppStorage("activitiesServerEnabled") private var activitiesEnabled = false

    @State private var lotwConnected = false
    @State private var qrzConnected = false
    @State private var potaConnected = false
    @State private var refreshTrigger = UUID()

    // MARK: - Derived State

    private var shouldShow: Bool {
        !tourState.hasDismissedGettingStarted && !items.allSatisfy(\.isComplete)
    }

    private var items: [GettingStartedItem] {
        [
            GettingStartedItem(
                id: "lotw",
                title: "LoTW",
                reward: "Auto-upload confirmations to ARRL",
                icon: "checkmark.seal",
                isComplete: lotwConnected,
                action: { openSettings(.lotw) }
            ),
            GettingStartedItem(
                id: "qrz",
                title: "QRZ Logbook",
                reward: "See DXCC progress and callsign lookups",
                icon: "globe",
                isComplete: qrzConnected,
                action: { openSettings(.qrz) }
            ),
            GettingStartedItem(
                id: "pota",
                title: "POTA",
                reward: "Spot yourself and upload park activations",
                icon: "tree",
                isComplete: potaConnected,
                action: { openSettings(.pota) }
            ),
            GettingStartedItem(
                id: "community",
                title: "Community",
                reward: "See activity from friends and clubs",
                icon: "person.3",
                isComplete: activitiesEnabled,
                action: { openActivityTab() }
            ),
        ]
    }

    private var completedCount: Int {
        items.count(where: \.isComplete)
    }

    private var summaryText: String {
        if completedCount == 0 {
            "You're all set to log contacts. These optional extras unlock more."
        } else {
            "\(completedCount) of \(items.count) connected — everything else is optional."
        }
    }

    // MARK: - Card Body

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            progressSummary
            itemList
            exploreLink
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Front-door link to the feature gallery — new users shouldn't have to
    /// excavate Settings to learn what the app can do.
    private var exploreLink: some View {
        NavigationLink {
            ExploreView()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .accessibilityHidden(true)
                Text("Explore what Carrier Wave can do")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel("Explore what Carrier Wave can do")
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.accentColor)
            Text("Getting Started")
                .font(.headline)
            Spacer()
            Button {
                tourState.dismissGettingStarted()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss Getting Started card")
        }
    }

    private var progressSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(completedCount), total: Double(items.count))
                .tint(Color.accentColor)
        }
    }

    private var itemList: some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                itemRow(item)
            }
        }
    }

    private func itemRow(_ item: GettingStartedItem) -> some View {
        Button(action: item.action) {
            HStack(spacing: 12) {
                statusIcon(for: item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(item.reward)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if !item.isComplete {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.isComplete)
    }

    @ViewBuilder
    private func statusIcon(for item: GettingStartedItem) -> some View {
        if item.isComplete {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        } else {
            Image(systemName: item.icon)
                .foregroundStyle(Color.accentColor)
                .font(.title3)
                .frame(width: 24)
        }
    }

    private func openSettings(_ destination: SettingsDestination) {
        settingsDestination = destination
        selectedTab = .more
    }

    private func openActivityTab() {
        selectedTab = .activity
    }

    // MARK: - State Refresh

    @MainActor
    private func refreshState() async {
        lotwConnected = LoTWClient().hasCredentials()
        qrzConnected = QRZClient().hasApiKey()
        potaConnected = potaAuth.isConfigured
    }
}
