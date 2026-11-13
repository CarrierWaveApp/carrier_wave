import CarrierWaveData
import SwiftUI

// MARK: - TrackerDetectedAlert

/// "CSN S.A.T. detected — Connect?" raised by `TrackerAutoDetector` whenever
/// a new rotator answers on the LAN. Connect links it (and starts the feed
/// loop), Not Now hides it for this session, Ignore remembers the choice.
private struct TrackerDetectedAlert: ViewModifier {
    // MARK: Internal

    let model: SatelliteTrackerModel

    func body(content: Content) -> some View {
        content.alert(
            service.autoDetect.pending?.detectedTitle ?? "Tracker detected",
            isPresented: Binding(
                get: { service.autoDetect.pending != nil },
                set: { shown in
                    if !shown, service.autoDetect.pending != nil {
                        service.autoDetect.dismiss()
                    }
                }
            ),
            presenting: service.autoDetect.pending
        ) { _ in
            Button("Connect") {
                Task { await service.acceptDetected(model: model) }
            }
            Button("Not Now", role: .cancel) {
                service.autoDetect.dismiss()
            }
            Button("Ignore This Device", role: .destructive) {
                service.autoDetect.ignore()
            }
        } message: { tracker in
            Text(tracker.detectedMessage)
        }
    }

    // MARK: Private

    @State private var service = SatelliteRotatorService.shared
}

extension View {
    /// Present the rotator auto-detection prompt on this view.
    func trackerDetectedAlert(model: SatelliteTrackerModel) -> some View {
        modifier(TrackerDetectedAlert(model: model))
    }
}
