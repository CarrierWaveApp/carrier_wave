// Frequency Activity View for Logger
//
// Displays nearby frequency activity and QRM assessment.

import CarrierWaveData
import SwiftUI

// MARK: - FrequencyActivityView

struct FrequencyActivityView: View {
    // MARK: Internal

    let frequencyMHz: Double
    let mode: String?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if activityService.isLoading, activityService.nearbyActivity.isEmpty {
                loadingView
            } else if activityService.nearbyActivity.isEmpty {
                emptyView
            } else {
                activityList
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .onAppear {
            activityService.startMonitoring(frequencyMHz: frequencyMHz, mode: mode)
        }
        .onDisappear {
            activityService.stopMonitoring()
        }
    }

    // MARK: Private

    @State private var activityService = FrequencyActivityService()

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(.purple)

            Text("Nearby Activity")
                .font(.headline)

            Spacer()

            qrmBadge

            Button {
                Task {
                    await activityService.refresh(frequencyMHz: frequencyMHz, mode: mode)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    private var qrmBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: activityService.qrmLevel.icon)
                .font(.system(size: 10))
            Text(activityService.qrmLevel.description)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(activityService.qrmLevel.color.opacity(0.15))
        .foregroundStyle(activityService.qrmLevel.color)
        .clipShape(Capsule())
    }

    // MARK: - Content Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Scanning for activity...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            Text("Frequency is clear!")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("No activity within \u{00B1}\(Int(activityService.bandwidthKHz)) kHz")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var activityList: some View {
        VStack(spacing: 0) {
            // Frequency scale header
            frequencyScale

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(activityService.nearbyActivity) { activity in
                        activityRow(activity)
                        if activity.id != activityService.nearbyActivity.last?.id {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
            .frame(maxHeight: 200)

            if let lastUpdate = activityService.lastUpdate {
                Text("Updated \(lastUpdate.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            }
        }
    }

    private var frequencyScale: some View {
        VStack(spacing: 4) {
            // Center frequency indicator
            HStack {
                Text("-\(Int(activityService.bandwidthKHz))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(spacing: 2) {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.blue)
                    Text(String(format: "%.1f", frequencyMHz * 1_000))
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                }

                Spacer()

                Text("+\(Int(activityService.bandwidthKHz))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            // Activity dots visualization
            activityVisualization
        }
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    private var activityVisualization: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - 32

            ZStack {
                // Baseline
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 2)

                // Center marker
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 2, height: 12)

                // Activity markers
                ForEach(activityService.nearbyActivity) { activity in
                    let offset = (activity.offsetKHz / activityService.bandwidthKHz) * (width / 2)
                    Circle()
                        .fill(activity.source.color)
                        .frame(width: 6, height: 6)
                        .offset(x: offset)
                }
            }
            .frame(height: 16)
            .padding(.horizontal, 16)
        }
        .frame(height: 16)
    }

    private func activityRow(_ activity: NearbyActivity) -> some View {
        HStack(spacing: 12) {
            // Source indicator
            ZStack {
                Circle()
                    .fill(activity.source.color.opacity(0.2))
                    .frame(width: 32, height: 32)

                Image(systemName: activity.source.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(activity.source.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(activity.callsign)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)

                    Spacer()

                    Text(activity.formattedOffset)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(offsetColor(activity.offsetKHz))
                }

                HStack {
                    Text(activity.mode)
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    if let snr = activity.signalReport {
                        Text("\(snr) dB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let notes = activity.notes {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(activity.timeAgo)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func offsetColor(_ offset: Double) -> Color {
        let absOffset = abs(offset)
        if absOffset <= 0.5 {
            return .red
        } else if absOffset <= 1.0 {
            return .orange
        } else {
            return .secondary
        }
    }
}

#Preview {
    FrequencyActivityView(frequencyMHz: 14.060, mode: "CW") {}
        .padding()
}
