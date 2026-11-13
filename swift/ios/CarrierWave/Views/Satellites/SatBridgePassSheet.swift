import SwiftUI

// MARK: - SatBridgePassSheet

/// Upload + in-pass control for the CW Sat Bridge: kicks off the schedule
/// upload for one pass on appear, then shows the executor's live status
/// (countdown, current doppler-corrected frequencies) with the VFO flip
/// and abort controls. The bridge keeps flying the pass if this sheet — or
/// the whole BLE link — goes away.
struct SatBridgePassSheet: View {
    // MARK: Internal

    let item: UpcomingSatellitePass
    let model: SatelliteTrackerModel

    var body: some View {
        NavigationStack {
            List {
                phaseSection
                statusSection
                controlSection
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .task {
            controller.reset()
            await controller.send(pass: item, model: model)
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private var controller: SatBridgeController {
        .shared
    }

    private var radioService: RadioService {
        .shared
    }

    private var phaseSection: some View {
        Section("Schedule") {
            switch controller.phase {
            case .idle,
                 .building:
                Label("Computing doppler schedule…", systemImage: "function")
            case let .uploading(sent, total):
                HStack {
                    Label("Uploading", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    Text("\(sent)/\(total)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            case .starting:
                Label("Arming pass…", systemImage: "clock.arrow.circlepath")
            case .sent:
                Label("Armed on bridge", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let status = radioService.satBridgeStatus {
            Section("Bridge") {
                LabeledContent("State", value: stateLabel(status))
                LabeledContent("Downlink", value: freqLabel(status.downlinkHz))
                if status.uplinkHz > 0 {
                    LabeledContent("Uplink", value: freqLabel(status.uplinkHz))
                }
                LabeledContent(status.tMs < 0 ? "AOS in" : "Elapsed", value: timeLabel(status.tMs))
            }
        }
    }

    @ViewBuilder
    private var controlSection: some View {
        if case .sent = controller.phase {
            Section {
                Picker("Active VFO", selection: Binding(
                    get: { controller.uplinkSelected },
                    set: { controller.selectVfo(uplink: $0) }
                )) {
                    Text("Downlink (A)").tag(false)
                    Text("Uplink (B)").tag(true)
                }
                .pickerStyle(.segmented)

                Button("Abort Pass", role: .destructive) {
                    controller.abort()
                    dismiss()
                }
            } footer: {
                Text("The bridge keeps both VFOs doppler-corrected; key the radio's own PTT. "
                    + "It flies the pass even if the phone disconnects.")
            }
        }
    }

    private func stateLabel(_ status: SatBridgeStatus) -> String {
        switch status.state {
        case .satIdle: "Idle"
        case .satLoading: "Loading"
        case .satArmed: "Armed"
        case .satRunning: "Running"
        case .satDone: "Done"
        case .satError: status.detail.isEmpty ? "Error" : "Error — \(status.detail)"
        default: "Unknown"
        }
    }

    private func freqLabel(_ hz: UInt64) -> String {
        String(format: "%.4f MHz", Double(hz) / 1_000_000)
    }

    private func timeLabel(_ tMs: Int64) -> String {
        let seconds = abs(Int(tMs / 1_000))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
