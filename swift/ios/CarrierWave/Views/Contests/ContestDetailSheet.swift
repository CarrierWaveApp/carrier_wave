import CarrierWaveCore
import CarrierWaveData
import EventKit
import EventKitUI
import SwiftUI
import UserNotifications

// MARK: - ContestDetailSheet

/// Full detail for a single contest: title, countdown/progress, chips,
/// exchange preview, actions (Log Now, Remind Me, Rules, Add to Calendar).
struct ContestDetailSheet: View {
    // MARK: Internal

    let contest: Contest

    @State var definition: ContestDefinition?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    chipsCard
                    if let definition {
                        definitionSourceCard(definition)
                        definitionExchangeCard(definition)
                        definitionScoringCard(definition)
                    } else if let exchange = contest.enrichment.exchangePreview {
                        exchangeCard(exchange)
                    }
                    actionsCard
                    metadataCard
                }
                .padding()
            }
            .task {
                await loadDefinition()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Contest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK") {}
            } message: {
                Text(alertMessage)
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isStarred = false

    private var reminderKey: String {
        "contestReminder.\(contest.id)"
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(contest.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                Label(
                    contest.isActive ? "Active now" : contest.statusLabel,
                    systemImage: contest.isActive ? "circle.fill" : "clock"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(contest.isActive ? .green : .secondary)

                ContestCountdownLabel(contest: contest)
                    .font(.caption)
            }

            if contest.isActive {
                ContestProgressBar(contest: contest)
                    .padding(.top, 2)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var chipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("At a glance")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ContestChipRow(contest: contest, showTemplateMatch: false)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionsCard: some View {
        VStack(spacing: 8) {
            if contest.enrichment.matchedTemplateId != nil {
                ContestActionButton(
                    title: "Log Now",
                    systemImage: "record.circle.fill",
                    tint: .green,
                    action: logNow
                )
            }
            if contest.isUpcoming {
                ContestActionButton(
                    title: isStarred ? "Reminder Set" : "Remind Me 30 min Before",
                    systemImage: isStarred ? "bell.fill" : "bell",
                    tint: .orange,
                    action: scheduleReminder
                )
                ContestActionButton(
                    title: "Add to Calendar",
                    systemImage: "calendar.badge.plus",
                    tint: .blue,
                    action: addToCalendar
                )
            }
            if let link = contest.link {
                Link(destination: link) {
                    ContestActionLabel(
                        title: "Open Rules",
                        systemImage: "arrow.up.forward.square",
                        tint: .secondary
                    )
                }
            }
        }
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Times (UTC)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Text("Start")
                Spacer()
                Text(contest.formattedStart).monospaced()
            }
            .font(.caption)
            HStack {
                Text("End")
                Spacer()
                Text(contest.formattedEnd).monospaced()
            }
            .font(.caption)
            HStack {
                Text("Duration")
                Spacer()
                Text(contest.durationLabel).monospaced()
            }
            .font(.caption)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func exchangeCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Exchange")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func logNow() {
        guard let templateId = contest.enrichment.matchedTemplateId else {
            return
        }
        NotificationCenter.default.post(
            name: .startContestSession,
            object: nil,
            userInfo: ["templateId": templateId, "contestTitle": contest.title]
        )
        dismiss()
    }

    private func scheduleReminder() {
        Task {
            let granted = await (try? UNUserNotificationCenter
                .current()
                .requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else {
                showAuthDeniedAlert()
                return
            }
            let fireDate = contest.startDate.addingTimeInterval(-30 * 60)
            guard fireDate > Date() else {
                showInlineAlert(
                    title: "Too late",
                    message: "This contest starts in under 30 minutes."
                )
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Contest starting soon"
            content.body = "\(contest.title) starts in 30 minutes."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: fireDate
                ),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: reminderKey, content: content, trigger: trigger
            )
            try? await UNUserNotificationCenter.current().add(request)
            UserDefaults.standard.set(true, forKey: reminderKey)
            isStarred = true
        }
    }

    private func addToCalendar() {
        let store = EKEventStore()
        Task {
            let granted = await (try? store.requestWriteOnlyAccessToEvents()) ?? false
            guard granted else {
                showAuthDeniedAlert()
                return
            }
            let event = EKEvent(eventStore: store)
            event.title = contest.title
            event.startDate = contest.startDate
            event.endDate = contest.endDate
            event.url = contest.link
            event.calendar = store.defaultCalendarForNewEvents
            do {
                try store.save(event, span: .thisEvent)
                showInlineAlert(
                    title: "Added",
                    message: "Saved to your default calendar."
                )
            } catch {
                showInlineAlert(
                    title: "Couldn't save",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func showAuthDeniedAlert() {
        showInlineAlert(
            title: "Permission needed",
            message: "Enable permissions in Settings to use this action."
        )
    }

    private func showInlineAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}

// MARK: - ContestActionButton

struct ContestActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ContestActionLabel(
                title: title, systemImage: systemImage, tint: tint
            )
        }
    }
}

// MARK: - ContestActionLabel

struct ContestActionLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
                .fontWeight(.medium)
            Spacer()
        }
        .padding()
        .foregroundStyle(tint)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Notification name

extension Notification.Name {
    /// Posted when the user taps "Log Now" on a matched contest. UserInfo
    /// keys: `templateId` (String), `contestTitle` (String).
    static let startContestSession = Notification.Name(
        "startContestSession"
    )
}
