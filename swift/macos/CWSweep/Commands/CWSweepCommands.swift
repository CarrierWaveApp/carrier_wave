import Sparkle
import SwiftUI

/// macOS menu bar commands
struct CWSweepCommands: Commands {
    // MARK: Lifecycle

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    // MARK: Internal

    var body: some Commands {
        // App menu — Sparkle "Check for Updates…" entry
        CommandGroup(after: .appInfo) {
            CheckForUpdatesView(updater: updater)
        }

        // File operations
        CommandGroup(after: .newItem) {
            Divider()

            Button("Import ADIF...") {
                showImportADIF?()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Export ADIF...") {
                showExportADIF?()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        // Radio menu
        CommandMenu("Radio") {
            Button("Connect Radio...") {
                connectRadio?()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Button("Disconnect") {
                disconnectRadio?()
            }
            .disabled(radioManager?.isConnected != true)

            Divider()

            Button("Band Up") {
                Task {
                    if let rm = radioManager {
                        let newFreq = nextBandUp(from: rm.frequency)
                        await rm.tuneToFrequency(newFreq)
                    }
                }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(radioManager?.isConnected != true)

            Button("Band Down") {
                Task {
                    if let rm = radioManager {
                        let newFreq = nextBandDown(from: rm.frequency)
                        await rm.tuneToFrequency(newFreq)
                    }
                }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(radioManager?.isConnected != true)

            Divider()

            Button("Toggle PTT") {
                Task {
                    await radioManager?.setPTT(true)
                }
            }
            .disabled(radioManager?.isConnected != true)

            Divider()

            Button("Focus Radio A") {
                radioManager?.setFocusedSlot(.a)
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(radioManager?.slots[.a] == nil)

            Button("Focus Radio B") {
                radioManager?.setFocusedSlot(.b)
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(radioManager?.slots[.b] == nil)

            Button("Swap A ↔ B") {
                Task { await radioManager?.swapFrequencies(.a, .b) }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(radioManager?.slots[.a] == nil || radioManager?.slots[.b] == nil)
        }

        // Logging menu
        CommandMenu("Logging") {
            Button("Add QSO...") {
                openQSOEntry?()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

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
        }

        // POTA menu
        CommandMenu("POTA") {
            Button("Return to My Frequency") {
                returnToFrequency?()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(activationFrequency == nil)

            Button("Edit Spot Comment...") {
                editSpotComment?()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Divider()

            Button("Spot Now") {
                spotNow?()
            }
            .disabled(activationFrequency == nil)
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

        // Query menu — discoverable via the Command Palette (⌘K) too.
        // No global shortcut: ⌘⇧Q collides with macOS's "Log Out"
        // accelerator and the rest of the ⌘⇧X space is occupied by
        // existing CW Sweep commands.
        CommandMenu("Query") {
            Button("Open Query Workbench") {
                openWindow(id: "query-workbench")
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

    @Environment(\.openWindow) private var openWindow

    @FocusedValue(\.openQSOEntry) private var openQSOEntry
    @FocusedValue(\.showImportADIF) private var showImportADIF
    @FocusedValue(\.showExportADIF) private var showExportADIF
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
    @FocusedValue(\.returnToFrequency) private var returnToFrequency
    @FocusedValue(\.editSpotComment) private var editSpotComment
    @FocusedValue(\.spotNow) private var spotNow
    @FocusedValue(\.activationFrequency) private var activationFrequency

    private let updater: SPUUpdater

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
