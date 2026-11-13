import SwiftUI

// MARK: - WaterfallPanel

/// Layout panel that displays whatever spectrum waterfall the active radio
/// produces (SCU-LAN10 scope, FlexRadio panadapter via VITA-49). Renders
/// a friendly placeholder when no producer is currently feeding the
/// `WaterfallStore` so the user can drop the panel into a layout regardless
/// of which radio they connect later.
struct WaterfallPanel: View {
    // MARK: Internal

    let radioManager: RadioManager

    var body: some View {
        if radioManager.waterfallStore.source == .none,
           radioManager.waterfallStore.magnitudes.isEmpty
        {
            unavailableState
        } else {
            WaterfallView(
                store: radioManager.waterfallStore,
                radioManager: radioManager
            )
        }
    }

    // MARK: Private

    private var supportingMessage: String {
        let sdr = radioManager.iqPanadapter
        if sdr.settings.enabled {
            return radioManager.isConnected
                ? "SDR input: \(sdr.status.description)"
                : "SDR input is enabled — connect the radio (CAT) so the SDR can follow its frequency."
        }
        if radioManager.isConnected {
            return "Connected radio doesn't expose a waterfall feed.\n"
                + "SCU-LAN10 (FTDX10), FlexRadio SmartSDR, and Icom LAN/WiFi radios push spectrum data;\n"
                + "or add an SDR (e.g. on the radio's IF output) in Settings → SDR."
        }
        return "Connect to an SCU-LAN10 (FTDX10), a FlexRadio SmartSDR, or an Icom radio over LAN/WiFi,\n"
            + "or set up an external SDR in Settings → SDR."
    }

    private var unavailableState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Waterfall unavailable")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(supportingMessage)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}
