import CarrierWaveData
import SwiftUI

// MARK: - SatelliteRotatorManualControls

/// Hand controls inside the rotator card: jog pad with a 1° / 5° / 15° step,
/// go-to azimuth/elevation, Park, and a coral Stop. Any manual move leaves
/// follow mode so the antenna never fights the tracker.
struct SatelliteRotatorManualControls: View {
    // MARK: Internal

    let rotator: RotatorController

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            jogPad
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Step")
                        .font(SatelliteTheme.label(10, weight: .semibold))
                        .foregroundStyle(SatelliteTheme.textTertiary)
                    Picker("Step", selection: $stepDeg) {
                        ForEach(Self.steps, id: \.self) { step in
                            Text("\(Int(step))°").tag(step)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 130)
                }
                HStack(spacing: 6) {
                    Text("Go to")
                        .font(SatelliteTheme.label(10, weight: .semibold))
                        .foregroundStyle(SatelliteTheme.textTertiary)
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
                    .tint(SatelliteTheme.tx)
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
            }
        }
        .disabled(!rotator.isConnected)
        .onAppear(perform: seedGoTo)
        .overlay(alignment: .bottomTrailing) {
            Text("↑↓←→ jog · ⇧ 15° · ⌥ 1° · esc stop")
                .font(SatelliteTheme.label(9, weight: .medium))
                .foregroundStyle(SatelliteTheme.textTertiary)
                .offset(y: 14)
        }
        .padding(.bottom, 12)
    }

    // MARK: Private

    private static let steps: [Double] = [1, 5, 15]

    @AppStorage("rotator.manualStepDeg") private var stepDeg = 5.0
    @State private var gotoAz = ""
    @State private var gotoEl = ""

    private var canGo: Bool {
        Double(gotoAz) != nil && Double(gotoEl) != nil
    }

    /// Reported on top; the commanded pointing (from jogs / go-to) below.
    private var positionLabel: String {
        let reported = rotator.position.map { String(format: "%03.0f°/%02.0f°", $0.azimuthDeg, $0.elevationDeg) } ?? "—"
        guard let commanded = rotator.commandedTarget else {
            return reported
        }
        return reported + String(format: "\n→%03.0f/%02.0f", commanded.azimuthDeg, commanded.elevationDeg)
    }

    private var jogPad: some View {
        VStack(spacing: 3) {
            jogButton("chevron.up", help: "Elevation up \(Int(stepDeg))°") { await rotator.nudge(elevationBy: stepDeg) }
            HStack(spacing: 3) {
                jogButton("chevron.left", help: "Azimuth counter-clockwise \(Int(stepDeg))°") {
                    await rotator.nudge(azimuthBy: -stepDeg)
                }
                Text(positionLabel)
                    .font(SatelliteTheme.mono(9, weight: .medium))
                    .foregroundStyle(SatelliteTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
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
        HoldRepeatJogButton(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 24)
                .background(SatelliteTheme.panelRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(SatelliteTheme.hairline))
        }
        .help("\(help) — hold to keep moving")
        .accessibilityLabel(help)
    }

    private func degreeField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(SatelliteTheme.label(10, weight: .semibold))
                .foregroundStyle(SatelliteTheme.textTertiary)
            TextField("0", text: text)
                .textFieldStyle(.roundedBorder)
                .font(SatelliteTheme.mono(11))
                .frame(width: 48)
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
        guard let az = Double(gotoAz), let el = Double(gotoEl) else {
            return
        }
        Task { await rotator.moveTo(RotatorPosition(azimuthDeg: az, elevationDeg: el)) }
    }
}

// MARK: - HoldRepeatJogButton

/// Jogs once on mouse-down, then every quarter second while the button stays
/// pressed (after a short initial delay). Tints default to the Satellites
/// console palette; `RotatorControlView` passes system colors instead.
struct HoldRepeatJogButton<Label: View>: View {
    // MARK: Lifecycle

    init(
        tint: Color = SatelliteTheme.accent,
        pressedTint: Color = SatelliteTheme.nearWhite,
        action: @escaping () async -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.tint = tint
        self.pressedTint = pressedTint
        self.action = action
        self.label = label
    }

    // MARK: Internal

    let tint: Color
    let pressedTint: Color
    let action: () async -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        label()
            .foregroundStyle(isPressed ? pressedTint : tint)
            .opacity(isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 30) {} onPressingChanged: { pressing in
                isPressed = pressing
                if pressing {
                    startRepeating()
                } else {
                    stopRepeating()
                }
            }
    }

    // MARK: Private

    @State private var isPressed = false
    @State private var repeatTask: Task<Void, Never>?

    private func startRepeating() {
        repeatTask?.cancel()
        let action = action
        repeatTask = Task {
            // Each jog runs in its own task so releasing the button (which
            // cancels this loop) never aborts a move already in flight.
            await Task { await action() }.value
            try? await Task.sleep(for: .milliseconds(450))
            while !Task.isCancelled {
                await Task { await action() }.value
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}
