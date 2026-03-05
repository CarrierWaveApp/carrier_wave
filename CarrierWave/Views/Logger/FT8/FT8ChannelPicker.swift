//
//  FT8ChannelPicker.swift
//  CarrierWave
//

import SwiftUI

// MARK: - FT8ChannelPicker

/// Sheet for selecting an FT8 TX channel, showing recommended clear frequencies.
struct FT8ChannelPicker: View {
    // MARK: Internal

    let recommendations: [ChannelRecommendation]
    @Binding var selectedFrequency: Double

    let onConfirm: () -> Void
    let onSwitchToWaterfall: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                channelList
                Divider()
                confirmSection
            }
            .navigationTitle("Pick a Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        dismiss()
                        onSwitchToWaterfall()
                    } label: {
                        Label("Waterfall", systemImage: "waveform.path")
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .caption) private var barMaxWidth: CGFloat = 80

    private var selectionBinding: Binding<Double?> {
        Binding(
            get: { selectedFrequency },
            set: {
                if let v = $0 {
                    selectedFrequency = v
                }
            }
        )
    }

    // MARK: - Channel List

    private var channelList: some View {
        let top = Array(recommendations.prefix(8))
        return List(top, selection: selectionBinding) { channel in
            Button {
                selectedFrequency = channel.frequency
            } label: {
                channelRow(channel)
            }
            .listRowBackground(
                isSelected(channel) ? Color.accentColor.opacity(0.1) : Color.clear
            )
        }
        .listStyle(.plain)
    }

    // MARK: - Confirm Section

    private var confirmSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Selected:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(Int(selectedFrequency)) Hz")
                    .font(.subheadline.bold().monospacedDigit())
            }

            Button {
                dismiss()
                onConfirm()
            } label: {
                Text("Start CQ on \(Int(selectedFrequency)) Hz")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private func channelRow(_ channel: ChannelRecommendation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected(channel) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected(channel) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .font(.body)

            Text("\(Int(channel.frequency))")
                .font(.body.monospacedDigit())
                .frame(width: 50, alignment: .trailing)

            Text("Hz")
                .font(.caption)
                .foregroundStyle(.secondary)

            activityBar(channel)

            Spacer()

            occupancyBadge(channel.occupancy)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Activity Bar

    private func activityBar(_ channel: ChannelRecommendation) -> some View {
        let maxActivity = recommendations.map(\.activityCount).max() ?? 1
        let fraction = maxActivity > 0
            ? CGFloat(channel.activityCount) / CGFloat(maxActivity)
            : 0

        return RoundedRectangle(cornerRadius: 2)
            .fill(barColor(channel.occupancy))
            .frame(width: max(4, fraction * barMaxWidth), height: 8)
    }

    // MARK: - Occupancy Badge

    private func occupancyBadge(
        _ level: ChannelRecommendation.OccupancyLevel
    ) -> some View {
        Text(level.rawValue)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(badgeForeground(level))
            .background(badgeBackground(level))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func isSelected(_ channel: ChannelRecommendation) -> Bool {
        abs(channel.frequency - selectedFrequency) < 25
    }

    private func barColor(_ level: ChannelRecommendation.OccupancyLevel) -> Color {
        switch level {
        case .clear: .green
        case .quiet: .green.opacity(0.7)
        case .fair: .orange
        case .busy: .red
        }
    }

    private func badgeForeground(
        _ level: ChannelRecommendation.OccupancyLevel
    ) -> Color {
        switch level {
        case .clear: .green
        case .quiet: .green
        case .fair: .orange
        case .busy: .red
        }
    }

    private func badgeBackground(
        _ level: ChannelRecommendation.OccupancyLevel
    ) -> Color {
        switch level {
        case .clear: .green.opacity(0.15)
        case .quiet: .green.opacity(0.1)
        case .fair: .orange.opacity(0.15)
        case .busy: .red.opacity(0.15)
        }
    }
}
