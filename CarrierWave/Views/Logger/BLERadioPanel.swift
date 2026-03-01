import CarrierWaveCore
import SwiftUI

// MARK: - BLERadioPanel

/// Bottom sheet showing BLE radio control state.
struct BLERadioPanel: View {
    // MARK: Internal

    @Bindable var service: BLERadioService

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if service.isConnected {
                    connectedContent
                } else {
                    disconnectedContent
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Radio Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    connectionBadge
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private var connectionStatusDetail: String {
        switch service.connectionStatus {
        case let .connecting(phase): "Connecting: \(phase)"
        case let .error(msg): msg
        default: "Radio is not connected"
        }
    }

    // MARK: - Connected

    private var connectedContent: some View {
        VStack(spacing: 16) {
            // Frequency display
            VStack(spacing: 4) {
                Text("Frequency")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let freq = service.radioFrequencyMHz {
                    Text(FrequencyFormatter.format(freq))
                        .font(.system(.title, design: .monospaced, weight: .bold))
                } else {
                    Text("Reading...")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }

            // Mode display
            VStack(spacing: 4) {
                Text("Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(service.radioMode ?? "---")
                    .font(.title3.weight(.semibold))
            }

            Divider()

            // Controls
            HStack(spacing: 16) {
                Button {
                    service.refreshRadioState()
                } label: {
                    Label("Read Radio", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
            }

            if let name = service.savedDeviceName {
                Text("Connected to \(name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Disconnected

    private var disconnectedContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            if service.isConfigured {
                Text("Not Connected")
                    .font(.headline)
                Text(connectionStatusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Connect") {
                    service.connectToSavedDevice()
                }
                .buttonStyle(.bordered)
            } else {
                Text("No Radio Configured")
                    .font(.headline)
                Text("Set up a BLE CAT proxy in Settings > BLE Radio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Helpers

    private var connectionBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(service.isConnected ? .green : .orange)
                .frame(width: 8, height: 8)
            Text(service.isConnected ? "Connected" : "Disconnected")
                .font(.caption)
        }
    }
}
