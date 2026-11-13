import CarrierWaveData
import SwiftUI

// MARK: - ContestMacroBar

/// CW message buttons for contest operating. Sends through whichever keyer
/// path RadioManager has wired (Bridge → WinKeyer → CAT), expanding the
/// operator's call, the worked call, and the next sent serial into the message.
struct ContestMacroBar: View {
    // MARK: Internal

    let manager: ContestManager
    let callsign: String

    var body: some View {
        HStack(spacing: 6) {
            macroButton("CQ", cqMessage)
            macroButton("Exch", exchangeMessage)
            macroButton("TU", "TU \(myCall)")
            macroButton("His Call", workedCall)

            Spacer()

            Button {
                stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }

            if !keyerReady {
                Text("No keyer")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .disabled(!keyerReady)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    // MARK: Private

    @Environment(RadioManager.self) private var radioManager
    @Environment(WinKeyerManager.self) private var winKeyer
    @AppStorage("myCallsign") private var myCallsign = ""

    private var myCall: String {
        myCallsign.uppercased()
    }

    private var workedCall: String {
        callsign.trimmingCharacters(in: .whitespaces).uppercased()
    }

    private var keyerReady: Bool {
        radioManager.cwKeyerAvailable(fallback: winKeyer)
    }

    private var cqMessage: String {
        "CQ TEST \(myCall)"
    }

    private var exchangeMessage: String {
        let serial = String(manager.currentSerial)
        return workedCall.isEmpty ? "5NN \(serial)" : "\(workedCall) 5NN \(serial)"
    }

    private func macroButton(_ label: String, _ message: String) -> some View {
        Button(label) {
            send(message)
        }
        .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func send(_ text: String) {
        Task { _ = await radioManager.sendCW(text, fallback: winKeyer) }
    }

    private func stop() {
        Task { _ = await radioManager.stopCW(fallback: winKeyer) }
    }
}
