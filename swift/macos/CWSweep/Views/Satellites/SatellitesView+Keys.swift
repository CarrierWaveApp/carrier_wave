import CarrierWaveData
import SwiftUI

// MARK: - RotatorArrowKeys

/// Keyboard jogging for the Satellites workspace: arrow keys nudge the
/// linked rotator by the manual step (⇧ = 15°, ⌥ = 1°); holding a key
/// repeats; Esc stops both axes. Text fields keep their own arrow handling
/// because the focused field sees the key first.
private struct RotatorArrowKeys: ViewModifier {
    // MARK: Internal

    let rotator: RotatorController

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onAppear {
                DispatchQueue.main.async { focused = true }
            }
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                guard rotator.isConnected else {
                    return .ignored
                }
                let step: Double = if press.modifiers.contains(.shift) {
                    15
                } else if press.modifiers.contains(.option) {
                    1
                } else {
                    stepDeg
                }
                switch press.key {
                case .upArrow: Task { await rotator.nudge(elevationBy: step) }
                case .downArrow: Task { await rotator.nudge(elevationBy: -step) }
                case .leftArrow: Task { await rotator.nudge(azimuthBy: -step) }
                case .rightArrow: Task { await rotator.nudge(azimuthBy: step) }
                default: return .ignored
                }
                return .handled
            }
            .onKeyPress(.escape) {
                guard rotator.isConnected else {
                    return .ignored
                }
                Task { await rotator.stop() }
                return .handled
            }
    }

    // MARK: Private

    @AppStorage("rotator.manualStepDeg") private var stepDeg = 5.0
    @FocusState private var focused: Bool
}

extension View {
    /// Arrow keys jog the rotator, Esc stops it, while this view (or a
    /// non-text descendant) has keyboard focus.
    func rotatorArrowKeys(_ rotator: RotatorController) -> some View {
        modifier(RotatorArrowKeys(rotator: rotator))
    }
}
