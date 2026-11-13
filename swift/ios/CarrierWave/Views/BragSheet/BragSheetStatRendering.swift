import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - BragInlineTableCell

/// Renders inline content for bandTable and modeStreakList values
/// that don't fit the standard hero/subtitle pattern.
struct BragInlineTableCell: View {
    // MARK: Internal

    let value: FfiBragStatValue

    var body: some View {
        switch value {
        case let .bandTable(entries):
            bandTableView(entries: Array(entries.prefix(3)))
        case let .modeStreakList(entries):
            modeStreakView(entries: entries)
        default:
            EmptyView()
        }
    }

    // MARK: Private

    // MARK: - Band Table

    @ViewBuilder
    private func bandTableView(entries: [FfiBandTableEntry]) -> some View {
        if entries.isEmpty {
            Text("--")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entries, id: \.band) { entry in
                    HStack(spacing: 8) {
                        Text(entry.band)
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(width: 40, alignment: .leading)
                        Text(entry.callsign)
                            .font(.caption)
                            .fontDesign(.monospaced)
                        Spacer()
                        Text(entry.distanceKm.map(UnitFormatter.distanceCompact) ?? "--")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Mode Streaks

    @ViewBuilder
    private func modeStreakView(entries: [FfiModeStreakEntry]) -> some View {
        if entries.isEmpty {
            Text("--")
                .foregroundStyle(.secondary)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(entries, id: \.mode) { entry in
                    modeChip(entry)
                }
            }
        }
    }

    private func modeChip(_ entry: FfiModeStreakEntry) -> some View {
        HStack(spacing: 4) {
            Text(entry.mode)
                .font(.caption2)
                .fontWeight(.medium)
            Text("\(entry.current)d")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray5))
        .clipShape(Capsule())
    }
}

// Uses existing FlowLayout from SpotFilterSheet.swift
