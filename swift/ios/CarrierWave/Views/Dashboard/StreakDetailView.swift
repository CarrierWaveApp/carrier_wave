import CarrierWaveData
import SwiftUI

// MARK: - StreakDetailView

struct StreakDetailView: View {
    // MARK: Internal

    let asyncStats: AsyncQSOStatistics
    let tourState: TourState

    var body: some View {
        List {
            Section {
                if let streak = asyncStats.dailyStreak {
                    StreakRow(streak: streak)
                }
            } header: {
                Text("Daily Streak")
            }

            Section {
                if let streak = asyncStats.potaActivationStreak {
                    StreakRow(streak: streak)
                }
                HStack {
                    Label("Valid Activations", systemImage: "checkmark.circle.fill")
                    Spacer()
                    Text("\(asyncStats.successfulActivations ?? 0)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Label("Attempted (<10 QSOs)", systemImage: "circle.dashed")
                    Spacer()
                    Text("\(asyncStats.attemptedActivations ?? 0)")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("POTA Activations")
            }

            Section {
                if let streak = asyncStats.hunterStreak {
                    StreakRow(streak: streak)
                }
            } header: {
                Text("Park Hunts")
            }

            if !asyncStats.allModeStreaks.isEmpty {
                Section {
                    ForEach(asyncStats.allModeStreaks.prefix(5)) { streak in
                        StreakRow(streak: streak)
                    }
                } header: {
                    Text("Mode Streaks")
                } footer: {
                    if asyncStats.allModeStreaks.count > 5 {
                        Text("Showing top 5 of \(asyncStats.allModeStreaks.count) modes")
                    }
                }
            }

            if !asyncStats.allBandStreaks.isEmpty {
                Section {
                    ForEach(asyncStats.allBandStreaks.prefix(5)) { streak in
                        StreakRow(streak: streak)
                    }
                } header: {
                    Text("Band Streaks")
                } footer: {
                    if asyncStats.allBandStreaks.count > 5 {
                        Text("Showing top 5 of \(asyncStats.allBandStreaks.count) bands")
                    }
                }
            }

            Section {
                if amt.isSignedIn {
                    if let streak = amt.streakInfo {
                        StreakRow(streak: streak)
                    } else {
                        HStack {
                            Label("Fetching practice stats…", systemImage: "graduationcap")
                                .foregroundStyle(.secondary)
                            Spacer()
                            ProgressView()
                        }
                    }
                } else {
                    NavigationLink {
                        AMTSettingsView()
                    } label: {
                        Label("Connect Another Morse Trainer", systemImage: "graduationcap")
                    }
                }
            } header: {
                Text("Morse Practice")
            } footer: {
                Text("Practice days come from your Another Morse Trainer account and use your local calendar.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("QSO streaks use UTC dates", systemImage: "globe")
                    Label("POTA activations require 10+ QSOs", systemImage: "leaf")
                    Label(
                        "Park hunts are QSOs with their park reference",
                        systemImage: "binoculars"
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("About Streaks")
            }
        }
        .navigationTitle("Streaks")
        .task { await amt.refreshStatsIfNeeded() }
    }

    // MARK: Private

    private var amt: AMTService {
        AMTService.shared
    }
}

// MARK: - StreakRow

struct StreakRow: View {
    // MARK: Internal

    let streak: StreakInfo

    var body: some View {
        HStack {
            Image(systemName: streak.category.icon)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(streak.displayName)
                        .font(.body)
                    if streak.isAtRisk {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if let start = streak.currentStartDate, streak.currentStreak > 0 {
                    Text("Started \(start, style: .date)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(currentStreakColor)
                    Text("\(streak.currentStreak)")
                        .fontWeight(.semibold)
                }

                if let start = streak.longestStartDate, let end = streak.longestEndDate {
                    let startFmt = start.formatted(.dateTime.month().day().year())
                    let endFmt = end.formatted(.dateTime.month().day().year())
                    Text("Best: \(streak.longestStreak) (\(startFmt) - \(endFmt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Best: \(streak.longestStreak)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Private

    private var iconColor: Color {
        switch streak.category {
        case .daily: .orange
        case .pota: .green
        case .hunter: .teal
        case .mode: .blue
        case .band: .purple
        case .amtPractice: ActivityGridColors.amtPractice
        }
    }

    private var currentStreakColor: Color {
        if streak.currentStreak == 0 {
            .gray
        } else if streak.currentStreak >= streak.longestStreak, streak.currentStreak > 0 {
            .red // At or beating personal best
        } else if streak.isAtRisk {
            .orange
        } else {
            .orange
        }
    }
}
