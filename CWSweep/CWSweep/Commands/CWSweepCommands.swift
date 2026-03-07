import SwiftUI

/// macOS menu bar commands
struct CWSweepCommands: Commands {
    // MARK: Internal

    var body: some Commands {
        // Radio menu
        CommandMenu("Radio") {
            Button("Connect Radio...") {
                connectRadio?()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Disconnect") {
                disconnectRadio?()
            }
            .disabled(radioManager?.isConnected != true)

            Divider()

            Button("Band Up") {
                Task {
                    if let rm = radioManager {
                        let newFreq = nextBandUp(from: rm.frequency)
                        try? await rm.tuneToFrequency(newFreq)
                    }
                }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(radioManager?.isConnected != true)

            Button("Band Down") {
                Task {
                    if let rm = radioManager {
                        let newFreq = nextBandDown(from: rm.frequency)
                        try? await rm.tuneToFrequency(newFreq)
                    }
                }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(radioManager?.isConnected != true)

            Divider()

            Button("Toggle PTT") {
                Task {
                    try? await radioManager?.setPTT(true)
                }
            }
            .disabled(radioManager?.isConnected != true)
        }

        // Logging menu
        CommandMenu("Logging") {
            Button("Focus Entry Field") {
                NotificationCenter.default.post(name: .focusEntryField, object: nil)
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Wipe Entry") {}

            Divider()

            Button("Start Session...") {}
            Button("Pause Session") {}
            Button("End Session") {}

            Divider()

            Button("Self-Spot") {}
        }

        // Sync menu
        CommandMenu("Sync") {
            Button("Sync Now") {}
                .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button("Upload to QRZ") {}
            Button("Upload to POTA") {}
            Button("Upload to LoTW") {}
            Button("Upload to Club Log") {}
        }

        // Contest menu
        CommandMenu("Contest") {
            Button("Start Contest...") {
                showContestSetup?()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(contestManager?.isActive == true)

            Button("End Contest") {
                contestManager?.endContest()
            }
            .disabled(contestManager?.isActive != true)

            Divider()

            Button("CQ Mode") {
                contestManager?.toggleOperatingMode()
            }
            .disabled(contestManager?.isActive != true)

            Button("S&P Mode") {
                contestManager?.toggleOperatingMode()
            }
            .disabled(contestManager?.isActive != true)

            Divider()

            Button("Export Cabrillo...") {
                // Wired in WI-12
            }
            .disabled(contestManager?.isActive != true)

            Button("Score Summary") {
                // Wired when score summary view added
            }
            .disabled(contestManager?.isActive != true)
        }

        // Spots menu
        CommandMenu("Spots") {
            Button("Refresh Spots") {
                refreshSpots?()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Divider()

            Button("Toggle Cluster Connection") {
                toggleCluster?()
            }

            Divider()

            if let agg = spotAggregator {
                let total = agg.spots.count
                Text("\(total) spots loaded")
            }
        }

        // SDR menu
        CommandMenu("SDR") {
            Button("Tune In to Selected Spot") {
                tuneInToSpot?()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button("Disconnect SDR") {
                disconnectSDR?()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(tuneInManager?.isActive != true)

            Divider()

            if let manager = tuneInManager, manager.isActive {
                if let spot = manager.spot {
                    Text("Listening: \(spot.callsign) \(String(format: "%.1f", spot.frequencyMHz * 1_000)) kHz")
                }
                if let receiver = manager.session.receiver {
                    Text("Receiver: \(receiver.name)")
                }
            } else {
                Text("SDR: Off")
                    .foregroundStyle(.secondary)
            }
        }

        // View enhancements
        CommandGroup(after: .sidebar) {
            Button("Toggle Inspector") {
                toggleInspector?()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])

            Divider()

            Button("Command Palette") {
                showCommandPalette?()
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("Radio Palette") {
                showRadioPalette?()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }
    }

    // MARK: Private

    // MARK: - Band Navigation Helpers

    /// Standard HF band center frequencies in MHz
    private static let bandFrequencies: [Double] = [
        1.840, 3.530, 5.332, 7.030, 10.110, 14.030,
        18.080, 21.030, 24.900, 28.030, 50.030,
    ]

    @FocusedValue(\.focusEntryField) private var focusEntryField
    @FocusedValue(\.toggleInspector) private var toggleInspector
    @FocusedValue(\.showCommandPalette) private var showCommandPalette
    @FocusedValue(\.showRadioPalette) private var showRadioPalette
    @FocusedValue(\.connectRadio) private var connectRadio
    @FocusedValue(\.disconnectRadio) private var disconnectRadio
    @FocusedValue(\.radioManager) private var radioManager
    @FocusedValue(\.refreshSpots) private var refreshSpots
    @FocusedValue(\.toggleCluster) private var toggleCluster
    @FocusedValue(\.spotAggregator) private var spotAggregator
    @FocusedValue(\.showContestSetup) private var showContestSetup
    @FocusedValue(\.contestManager) private var contestManager
    @FocusedValue(\.tuneInManager) private var tuneInManager
    @FocusedValue(\.tuneInToSpot) private var tuneInToSpot
    @FocusedValue(\.disconnectSDR) private var disconnectSDR

    private func nextBandUp(from currentMHz: Double) -> Double {
        for freq in Self.bandFrequencies where freq > currentMHz + 0.5 {
            return freq
        }
        return Self.bandFrequencies.first ?? 14.030
    }

    private func nextBandDown(from currentMHz: Double) -> Double {
        for freq in Self.bandFrequencies.reversed() where freq < currentMHz - 0.5 {
            return freq
        }
        return Self.bandFrequencies.last ?? 28.030
    }
}
