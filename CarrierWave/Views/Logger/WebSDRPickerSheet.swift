import SwiftUI

// MARK: - WebSDRPickerSheet

/// Sheet for selecting a nearby KiwiSDR receiver.
/// Shows receivers sorted by proximity to the user's grid square.
struct WebSDRPickerSheet: View {
    // MARK: Internal

    let myGrid: String?
    let onSelect: (KiwiSDRReceiver) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if receivers.isEmpty {
                    emptyView
                } else {
                    receiverList
                }
            }
            .navigationTitle("Nearby WebSDRs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadReceivers() }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var receivers: [KiwiSDRReceiver] = []
    @State private var isLoading = true

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Finding nearby WebSDRs...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No WebSDRs found")
                .font(.headline)
            Text("Check your internet connection and try again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await loadReceivers() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var receiverList: some View {
        List(receivers) { receiver in
            Button {
                onSelect(receiver)
            } label: {
                receiverRow(receiver)
            }
            .disabled(!receiver.isAvailable)
        }
    }

    private func receiverRow(_ receiver: KiwiSDRReceiver) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(receiver.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(receiver.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(receiver.bands, systemImage: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Label(receiver.antenna, systemImage: "antenna.radiowaves.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let dist = receiver.formattedDistance {
                    Text(dist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                availabilityBadge(receiver)
            }
        }
        .contentShape(Rectangle())
        .opacity(receiver.isAvailable ? 1.0 : 0.5)
    }

    private func availabilityBadge(_ receiver: KiwiSDRReceiver) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(receiver.isAvailable ? .green : .red)
                .frame(width: 6, height: 6)
            if receiver.isAvailable {
                Text("\(receiver.users)/\(receiver.maxUsers)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Full (\(receiver.users)/\(receiver.maxUsers))")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private func loadReceivers() async {
        isLoading = true
        await WebSDRDirectory.shared.refresh()
        receivers = await WebSDRDirectory.shared.findNearby(
            grid: myGrid,
            limit: 20
        )
        isLoading = false
    }
}
