import CarrierWaveData
import SwiftUI

// MARK: - RotatorManualControls

/// Hand controls for a linked rotator: a step picker (1° / 5° / 15°), a
/// d-pad that jogs once per tap and keeps jogging while held, go-to
/// azimuth/elevation, Park, and a prominent Stop. Any manual move leaves
/// follow mode so the antenna never fights the tracker.
struct RotatorManualControls: View {
    // MARK: Internal

    let rotator: RotatorController
    /// Where the selected satellite is now (or its rise azimuth), if any.
    var target: RotatorPosition?
    var targetSource = ""

    var body: some View {
        VStack(spacing: 16) {
            targetLine

            Picker("Step", selection: $stepDeg) {
                ForEach(Self.steps, id: \.self) { step in
                    Text("\(Int(step))°").tag(step)
                }
            }
            .pickerStyle(.segmented)

            jogPad

            HStack(spacing: 10) {
                Text("Go to")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                degreeField("AZ", text: $gotoAz)
                degreeField("EL", text: $gotoEl)
                Button("Go") {
                    goTo()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canGo)
            }

            if let command = rotator.lastCommand {
                HStack(spacing: 6) {
                    Text("Sent")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(command)
                        .font(.caption2.monospaced())
                    if let reply = rotator.lastReply {
                        Text("→ \(reply)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task { await rotator.park() }
                } label: {
                    Label("Park", systemImage: "house")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Button(role: .destructive) {
                    Task { await rotator.stop() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
            }
        }
        .padding(.vertical, 6)
        .disabled(!rotator.isConnected)
        .onAppear(perform: seedGoTo)
    }

    // MARK: Private

    private static let steps: [Double] = [1, 5, 15]
    private static let padButton: CGFloat = 56

    @AppStorage("rotator.manualStepDeg") private var stepDeg = 5.0
    @State private var gotoAz = ""
    @State private var gotoEl = ""

    /// The pointing your taps have commanded so far.
    private var commanded: RotatorPosition? {
        rotator.commandedTarget
    }

    private var canGo: Bool {
        Double(gotoAz) != nil && Double(gotoEl) != nil
    }

    /// Gap between the rotor and what was commanded, when the rotor reports.
    private var commandedError: Double? {
        guard let commanded, let position = rotator.position else {
            return nil
        }
        return position.maxAxisError(to: commanded)
    }

    /// "Commanded 350° / 0°" (what your taps asked for) and, when a satellite
    /// is selected, "Satellite 207° / 35° · ISS · above horizon" with a
    /// one-tap Go to satellite.
    private var targetLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Commanded")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(commanded.map { String(format: "%03.0f° / %.0f°", $0.azimuthDeg, $0.elevationDeg) } ?? "—")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(commanded == nil ? .secondary : Color.accentColor)
                Spacer(minLength: 0)
                if let error = rotator.pointingErrorDeg ?? commandedError {
                    Text(String(format: "off by %.1f°", error))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Satellite")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(target.map { String(format: "%03.0f° / %.0f°", $0.azimuthDeg, $0.elevationDeg) } ?? "—")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(target == nil ? Color.secondary : Color.green)
                    }
                    if !targetSource.isEmpty {
                        Text(targetSource)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button("Go to satellite") {
                    if let target {
                        Task { await rotator.moveTo(target) }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(target == nil)
            }
        }
    }

    private var jogPad: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                jogButton("chevron.up", label: "Elevation up") { await rotator.nudge(elevationBy: stepDeg) }
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            GridRow {
                jogButton("chevron.left", label: "Azimuth counter-clockwise") {
                    await rotator.nudge(azimuthBy: -stepDeg)
                }
                readout
                jogButton("chevron.right", label: "Azimuth clockwise") { await rotator.nudge(azimuthBy: stepDeg) }
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                jogButton("chevron.down", label: "Elevation down") { await rotator.nudge(elevationBy: -stepDeg) }
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Reported position on top; the desired target (blue) underneath when
    /// one is known, so the gap to close is visible while jogging.
    private var readout: some View {
        VStack(spacing: 1) {
            Text(rotator.position.map { String(format: "%03.0f°", $0.azimuthDeg) } ?? "—")
            Text(rotator.position.map { String(format: "%02.0f°", $0.elevationDeg) } ?? "—")
            if let commanded {
                Text(String(format: "→%03.0f/%02.0f", commanded.azimuthDeg, commanded.elevationDeg))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tint)
            }
        }
        .font(.callout.monospacedDigit().weight(.medium))
        .foregroundStyle(.secondary)
        .frame(width: Self.padButton, height: Self.padButton)
    }

    private func jogButton(_ symbol: String, label: String, action: @escaping () async -> Void) -> some View {
        HoldRepeatButton(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .frame(width: Self.padButton, height: Self.padButton)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel(label)
        .accessibilityHint("Tap to move \(Int(stepDeg))°, hold to keep moving")
    }

    private func degreeField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 44)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("°")
                .foregroundStyle(.secondary)
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

// MARK: - HoldRepeatButton

/// Fires `action` once on touch-down, then again every quarter second while
/// the finger stays down (after a short initial delay), so a jog button can
/// be held to keep the rotor moving.
private struct HoldRepeatButton<Label: View>: View {
    // MARK: Internal

    let action: () async -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        label()
            .foregroundStyle(.tint)
            .opacity(isPressed ? 0.6 : 1)
            .scaleEffect(isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 40) {} onPressingChanged: { pressing in
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
