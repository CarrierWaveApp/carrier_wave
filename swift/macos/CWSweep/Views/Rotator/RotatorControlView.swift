import CarrierWaveData
import SwiftUI

// MARK: - RotatorControlView

/// Sidebar → System → Rotator: the station rotator console, laid out like the
/// Radio and WinKeyer panels (headline row, then `GroupBox`es that fill the
/// width). Link status and connect / park / stop, hand controls, then LAN
/// discovery and add-by-address. Doppler CAT stays in Settings → Trackers.
struct RotatorControlView: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                GroupBox("Station rotator") {
                    rows { RotatorStatusRows() }
                }
                .padding(.horizontal)

                GroupBox("Hand control") {
                    RotatorManualControls()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
                .padding(.horizontal)

                GroupBox {
                    rows { TrackerDiscoveryRows() }
                    TrackerDiscoveryFooter()
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                } label: {
                    HStack {
                        Text("Trackers on this network")
                        Spacer()
                        TrackerDiscoveryScanButton()
                    }
                }
                .padding(.horizontal)

                GroupBox("Add by address or network") {
                    rows { TrackerManualAddRows() }
                    Text(TrackerManualAddRows.footer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
                .padding(.horizontal)
            }
            .padding(.top)
            .padding(.bottom)
        }
        .task {
            if discovery.discovered.isEmpty, discovery.lastScanAt == nil {
                await discovery.scan()
            }
        }
    }

    // MARK: Private

    private let rotator = SharedEnvironment.shared.rotatorController
    private let discovery = SharedEnvironment.shared.trackerDiscovery

    private var header: some View {
        HStack {
            Text("Rotator")
                .font(.headline)
            if rotator.isConnected {
                Text(rotator.state.label)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RotatorStateStyle.color(for: rotator.state).opacity(0.15), in: Capsule())
                    .foregroundStyle(RotatorStateStyle.color(for: rotator.state))
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    /// Form-style rows inside a GroupBox: full width, leading-aligned.
    private func rows(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
    }
}

// MARK: - RotatorManualControls

/// Hand controls: hold-to-repeat jog pad with a 1° / 5° / 15° step, go-to
/// azimuth/elevation, Park and Stop. Any manual move leaves follow mode so
/// the antenna never fights the tracker. Shares the step setting with the
/// Satellites console's rotator card.
struct RotatorManualControls: View {
    // MARK: Internal

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            jogPad
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Step")
                    Picker("Step", selection: $stepDeg) {
                        ForEach(Self.steps, id: \.self) { step in
                            Text("\(Int(step))°").tag(step)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                HStack {
                    Text("Go to")
                    degreeField("AZ", text: $gotoAz)
                    degreeField("EL", text: $gotoEl)
                    Button("Go") {
                        goTo()
                    }
                    .disabled(!canGo)
                    Button("Park") {
                        Task { await rotator.park() }
                    }
                    Button("Stop") {
                        Task { await rotator.stop() }
                    }
                    .tint(.red)
                    .buttonStyle(.borderedProminent)
                }
                if let commanded = rotator.commandedTarget {
                    Text(String(
                        format: "Commanded AZ %05.1f°  EL %04.1f°",
                        commanded.azimuthDeg,
                        commanded.elevationDeg
                    ))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Text(rotator.isConnected
                    ? "Hold a jog button to keep moving. Any manual move takes the rotator out of follow mode."
                    : "Connect the rotator above to move it by hand.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .disabled(!rotator.isConnected)
        .onAppear(perform: seedGoTo)
    }

    // MARK: Private

    private static let steps: [Double] = [1, 5, 15]

    @AppStorage("rotator.manualStepDeg") private var stepDeg = 5.0
    @State private var gotoAz = ""
    @State private var gotoEl = ""

    private let rotator = SharedEnvironment.shared.rotatorController

    private var canGo: Bool {
        Double(gotoAz) != nil && Double(gotoEl) != nil
    }

    private var positionLabel: String {
        rotator.position.map { String(format: "%03.0f°\n%02.0f°", $0.azimuthDeg, $0.elevationDeg) } ?? "—"
    }

    private var jogPad: some View {
        VStack(spacing: 4) {
            jogButton("chevron.up", help: "Elevation up \(Int(stepDeg))°") { await rotator.nudge(elevationBy: stepDeg) }
            HStack(spacing: 4) {
                jogButton("chevron.left", help: "Azimuth counter-clockwise \(Int(stepDeg))°") {
                    await rotator.nudge(azimuthBy: -stepDeg)
                }
                Text(positionLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize()
                jogButton("chevron.right", help: "Azimuth clockwise \(Int(stepDeg))°") {
                    await rotator.nudge(azimuthBy: stepDeg)
                }
            }
            jogButton("chevron.down", help: "Elevation down \(Int(stepDeg))°") {
                await rotator.nudge(elevationBy: -stepDeg)
            }
        }
    }

    private func jogButton(_ symbol: String, help: String, action: @escaping () async -> Void) -> some View {
        HoldRepeatJogButton(tint: .accentColor, pressedTint: .primary, action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .help("\(help) — hold to keep moving")
        .accessibilityLabel(help)
    }

    private func degreeField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(label, text: text, prompt: Text("000"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .fixedSize()
                .onSubmit(goTo)
        }
    }

    private func seedGoTo() {
        if gotoAz.isEmpty, gotoEl.isEmpty {
            let base = rotator.manualBase
            gotoAz = String(Int(base.azimuthDeg.rounded()))
            gotoEl = String(Int(base.elevationDeg.rounded()))
        }
    }

    private func goTo() {
        guard let azimuth = Double(gotoAz), let elevation = Double(gotoEl) else {
            return
        }
        Task { await rotator.moveTo(RotatorPosition(azimuthDeg: azimuth, elevationDeg: elevation)) }
    }
}
