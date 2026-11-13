import CarrierWaveData
import SwiftUI

// MARK: - TrackerDetectedAlert

/// "CSN S.A.T. detected — Connect?" raised by the shared `TrackerAutoDetector`
/// whenever a new rotator answers on the LAN, anywhere in the workspace.
/// Connect links it as the station rotator and jumps to the Satellites
/// workspace; Not Now hides it for this session; Ignore remembers the choice.
private struct TrackerDetectedAlert: ViewModifier {
    // MARK: Internal

    func body(content: Content) -> some View {
        content.alert(
            detector.pending?.detectedTitle ?? "Tracker detected",
            isPresented: Binding(
                get: { detector.pending != nil },
                set: { shown in
                    if !shown, detector.pending != nil {
                        detector.dismiss()
                    }
                }
            ),
            presenting: detector.pending
        ) { _ in
            Button("Connect") {
                Task {
                    await detector.accept()
                    NotificationCenter.default.post(name: .showSatellites, object: nil)
                }
            }
            Button("Not Now", role: .cancel) {
                detector.dismiss()
            }
            Button("Ignore This Device", role: .destructive) {
                detector.ignore()
            }
        } message: { tracker in
            Text(tracker.detectedMessage)
        }
    }

    // MARK: Private

    private let detector = SharedEnvironment.shared.trackerAutoDetector
}

extension View {
    /// Present the rotator auto-detection prompt on this view.
    func trackerDetectedAlert() -> some View {
        modifier(TrackerDetectedAlert())
    }
}
