import CarrierWaveCore
import SwiftUI

// MARK: - StreakDetailView

struct StreakDetailView: View {
    let stats: QSOStatistics
    let tourState: TourState

    var body: some View {
        List {
            Section {
                StreakRow(streak: stats.dailyStreak)
            } header: {
                Text("Daily Streak")
            }

            Section {
                StreakRow(streak: stats.potaActivationStreak)
                HStack {
                    Label("Valid Activations", systemImage: "checkmark.circle.fill")
                    Spacer()
                    Text("\(stats.successfulActivations)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Label("Attempted (<10 QSOs)", systemImage: "circle.dashed")
                    Spacer()
                    Text("\(stats.attemptedActivations)")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("POTA Activations")
            }

            if !stats.modeStreaks.isEmpty {
                Section {
                    ForEach(stats.modeStreaks.prefix(5)) { streak in
                        StreakRow(streak: streak)
                    }
                } header: {
                    Text("Mode Streaks")
                } footer: {
                    if stats.modeStreaks.count > 5 {
                        Text("Showing top 5 of \(stats.modeStreaks.count) modes")
                    }
                }
            }

            if !stats.bandStreaks.isEmpty {
                Section {
                    ForEach(stats.bandStreaks.prefix(5)) { streak in
                        StreakRow(streak: streak)
                    }
                } header: {
                    Text("Band Streaks")
                } footer: {
                    if stats.bandStreaks.count > 5 {
                        Text("Showing top 5 of \(stats.bandStreaks.count) bands")
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("All streaks use UTC dates", systemImage: "globe")
                    Label("POTA activations require 10+ QSOs", systemImage: "leaf")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("About Streaks")
            }
        }
        .navigationTitle("Streaks")
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
        case .mode: .blue
        case .band: .purple
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
