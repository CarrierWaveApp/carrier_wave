import CarrierWaveData
import SwiftUI

// MARK: - RadioPanel

/// Bottom sheet showing radio control state.
struct RadioPanel: View {
    // MARK: Internal

    @Bindable var service: RadioService

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if service.isConnected {
                    connectedContent
                } else {
                    disconnectedContent
                }
                Divider()
                dataLogSection
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    private static let logTimeFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt
    }()

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
                Text("Set up a radio connection in Settings > Radio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Data Log

    private var dataLogSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Data Log")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !service.dataLog.isEmpty {
                    Button("Copy") { copyLog() }
                        .font(.caption)
                    Button("Clear") { service.clearLog() }
                        .font(.caption)
                }
            }
            if service.dataLog.isEmpty {
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(service.dataLog) { entry in
                                logRow(entry).id(entry.id)
                            }
                        }
                    }
                    .onChange(of: service.dataLog.count) {
                        if let last = service.dataLog.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var connectionBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(service.isConnected ? .green : .orange)
                .frame(width: 8, height: 8)
            Text(service.isConnected ? "Connected" : "Disconnected")
                .font(.caption)
        }
    }

    private func logRow(_ entry: RadioLogEntry) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(Self.logTimeFmt.string(from: entry.timestamp))
                .foregroundStyle(.tertiary)
            Text(directionSymbol(entry.direction))
                .foregroundStyle(directionColor(entry.direction))
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.message)
                if let hex = entry.hexData {
                    Text(hex).foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption2.monospaced())
    }

    // MARK: - Helpers

    private func copyLog() {
        let text = service.dataLog.map { entry in
            let ts = Self.logTimeFmt.string(from: entry.timestamp)
            let dir = directionSymbol(entry.direction)
            let hex = entry.hexData.map { "\n  \($0)" } ?? ""
            return "\(ts) \(dir) \(entry.message)\(hex)"
        }.joined(separator: "\n")
        UIPasteboard.general.string = text
    }

    private func directionSymbol(
        _ dir: RadioLogEntry.Direction
    ) -> String {
        switch dir {
        case .sent: "TX"
        case .received: "RX"
        case .info: "--"
        case .error: "!!"
        }
    }

    private func directionColor(
        _ dir: RadioLogEntry.Direction
    ) -> Color {
        switch dir {
        case .sent: .blue
        case .received: .green
        case .info: .secondary
        case .error: .red
        }
    }
}
