import CarrierWaveData
import SwiftUI

// Shared row components for contest catalog/picker views.
//
// The standalone `ContestsBrowserView` was retired in CAR-276 PR2 — contest
// discovery now lives only inside the session-start contest picker
// (`ContestCalendarView` in picker mode). The row/entry/caption types below
// survive because both `ContestCalendarView+Catalog.swift` and the iOS Logger
// flow render them.

// MARK: - ContestBrowserEntry

struct ContestBrowserEntry: Identifiable, Equatable {
    // MARK: Lifecycle

    init(summary: ContestDefinitionSummary, definition: ContestDefinition?) {
        id = summary.id
        name = summary.name
        displayName = summary.displayName
        sponsorName = summary.sponsorName
        isActive = summary.isActive
        self.definition = definition
        isExperimental = definition?.experimental ?? false
        if let definition {
            let active = ContestScheduleEvaluator.activeOccurrence(schedule: definition.schedule)
            let next = ContestScheduleEvaluator.nextOccurrence(schedule: definition.schedule)
            occurrence = active ?? next
            isLive = active != nil
        } else {
            occurrence = nil
            isLive = false
        }
    }

    // MARK: Internal

    let id: String
    let name: String
    let displayName: String
    let sponsorName: String?
    let isActive: Bool
    let definition: ContestDefinition?
    let occurrence: ContestOccurrence?
    let isLive: Bool
    let isExperimental: Bool

    var nextStart: Date? {
        occurrence?.start
    }
}

// MARK: - ContestBrowserRow

struct ContestBrowserRow: View {
    let entry: ContestBrowserEntry
    var isLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.displayName)
                    .font(.headline)
                if entry.isExperimental {
                    ExperimentalBadge()
                }
                if entry.isLive {
                    Text("LIVE")
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2), in: Capsule())
                        .foregroundStyle(.green)
                } else if !entry.isActive {
                    Text("INACTIVE")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.2), in: Capsule())
                }
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                }
            }
            if let sponsor = entry.sponsorName {
                Text(sponsor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let definition = entry.definition {
                ContestScheduleCaption(definition: definition)
            } else {
                Label("Schedule unavailable", systemImage: "calendar.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ContestScheduleCaption

/// Renders the active or next occurrence of a contest schedule as a caption.
struct ContestScheduleCaption: View {
    // MARK: Internal

    let definition: ContestDefinition

    var body: some View {
        if let text = captionText {
            Label(text, systemImage: icon)
                .font(.caption)
                .foregroundStyle(color)
        }
    }

    // MARK: Private

    private var occurrence: ContestOccurrence? {
        ContestScheduleEvaluator.activeOccurrence(schedule: definition.schedule)
            ?? ContestScheduleEvaluator.nextOccurrence(schedule: definition.schedule)
    }

    private var isLive: Bool {
        guard let occurrence else {
            return false
        }
        return occurrence.contains(Date())
    }

    private var icon: String {
        isLive ? "dot.radiowaves.left.and.right" : "calendar"
    }

    private var color: Color {
        isLive ? .green : .secondary
    }

    private var captionText: String? {
        guard let occurrence else {
            return nil
        }
        if isLive {
            let remaining = occurrence.end.timeIntervalSince(Date())
            return "Live — ends in \(formatDuration(remaining))"
        }
        let relative = occurrence.start.formatted(.relative(presentation: .named))
        return "Next \(relative)"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3_600
        let minutes = (Int(seconds) % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
