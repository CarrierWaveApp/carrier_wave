import SwiftUI

/// Quick session start from Watch. Uses the last-used defaults stored in
/// App Group UserDefaults. Sends a start request to the iPhone via WatchConnectivity.
struct QuickStartView: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                headerRow

                modePicker
                activationPicker

                startButton
            }
            .padding(.horizontal, 4)
        }
        .onAppear { loadDefaults() }
    }

    // MARK: Private

    @State private var isStarting = false
    @State private var startFailed = false
    @State private var selectedMode = "CW"
    @State private var activationType = "casual"

    private let modes = ["CW", "SSB", "FT8", "FT4"]
    private let activationTypes = ["casual", "pota"]

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
            Text("Quick Start")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mode")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(modes, id: \.self) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        Text(mode)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                selectedMode == mode
                                    ? Color.accentColor : Color.secondary.opacity(0.2)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Activation Type

    private var activationPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Type")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(activationTypes, id: \.self) { type in
                    Button {
                        activationType = type
                    } label: {
                        Text(type == "casual" ? "Casual" : "POTA")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                activationType == type
                                    ? Color.accentColor : Color.secondary.opacity(0.2)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Start Button

    private var startButton: some View {
        Button {
            startSession()
        } label: {
            HStack {
                if isStarting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                }
                Text(isStarting ? "Starting..." : "Start Session")
                    .font(.caption.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(isStarting || !WatchSessionDelegate.shared.isPhoneReachable)
        .alert("Start Failed", isPresented: $startFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Could not reach iPhone. Make sure Carrier Wave is open.")
        }
    }

    // MARK: - Logic

    private func loadDefaults() {
        let defaults = UserDefaults(suiteName: WatchShared.appGroupID)
        if let mode = defaults?.string(forKey: "loggerDefaultMode") {
            selectedMode = mode
        }
        if let type = defaults?.string(forKey: "loggerDefaultActivationType") {
            activationType = type
        }
    }

    private func startSession() {
        isStarting = true

        let defaults = UserDefaults(suiteName: WatchShared.appGroupID)
        let callsign = defaults?.string(forKey: "loggerDefaultCallsign") ?? ""
        let parkRef = activationType == "pota"
            ? defaults?.string(forKey: "loggerDefaultParkReference") : nil

        let request = WatchStartRequest(
            myCallsign: callsign,
            mode: selectedMode,
            activationType: activationType,
            parkReference: parkRef,
            frequency: nil
        )

        Task {
            let success = await WatchSessionDelegate.shared.requestStartSession(request)
            isStarting = false
            if !success {
                startFailed = true
            }
        }
    }
}
