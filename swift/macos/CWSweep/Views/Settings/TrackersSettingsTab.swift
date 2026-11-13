import CarrierWaveData
import SwiftUI

// MARK: - TrackersSettingsTab

/// Settings → Trackers: find CSN S.A.T. trackers and WA4MCM PSR-100 rotors
/// on the LAN, pick the station rotator, and choose which radio slots the
/// Satellites workspace tunes for Doppler. The rotator sections are shared
/// with the Rotator sidebar panel (`RotatorControlView`).
struct TrackersSettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            RotatorStatusSection()
            TrackerDiscoverySections()
            catSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            if discovery.discovered.isEmpty, discovery.lastScanAt == nil {
                await discovery.scan()
            }
        }
    }

    // MARK: Private

    private let discovery = SharedEnvironment.shared.trackerDiscovery
    private let cat = SharedEnvironment.shared.satelliteCAT

    private var uplinkHelp: String {
        switch cat.uplinkTarget {
        case .none:
            "Only the downlink is tuned; the pre-corrected uplink is shown in the pass details for you to dial in."
        case .radio:
            "Two-radio full duplex: the second radio follows the pre-corrected uplink."
        case .subBand:
            "IC-9700 full duplex: satellite mode is switched on for the pass (and put back afterwards), Main "
                + "follows the downlink, Sub follows the uplink. On linear birds, tuning the Main dial moves the "
                + "uplink with it — reversed on inverting transponders. Works over LAN or USB (Unlink, 115200)."
        }
    }

    private var catSection: some View {
        Section("Doppler CAT") {
            Toggle("Tune the radio to the Doppler-corrected downlink during a pass", isOn: Binding(
                get: { cat.isEnabled },
                set: { cat.isEnabled = $0 }
            ))
            Picker("Downlink radio", selection: Binding(
                get: { cat.downlinkSlot },
                set: { cat.downlinkSlot = $0 }
            )) {
                ForEach(RadioSlot.allCases) { slot in
                    Text(slot.label).tag(slot)
                }
            }
            Picker("Uplink", selection: Binding(
                get: { cat.uplinkTarget },
                set: { cat.uplinkTarget = $0 }
            )) {
                ForEach(SatelliteUplinkTarget.allCases) { target in
                    Text(target.label).tag(target)
                }
            }
            LabeledContent("State") {
                Text(cat.linkState.label)
                    .foregroundStyle(.secondary)
            }
            Text(uplinkHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
