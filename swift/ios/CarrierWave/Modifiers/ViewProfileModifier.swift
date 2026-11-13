import SwiftUI

// MARK: - ViewProfileModifier

/// Records view appearance timing to both the startup profiler (local trace)
/// and the MetricKit uploader (server telemetry).
/// Attach via `.viewProfiled("MyView")` to instrument any view.
struct ViewProfileModifier: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        content
            .onAppear {
                let event = PerfEvent.now(kind: "view.appear", label: name)
                Task { await PerfUploader.shared.recordEvent(event) }
                if StartupProfiler.shared.isRunning {
                    StartupProfiler.shared.record("view.appear.\(name)")
                }
            }
            .onDisappear {
                let event = PerfEvent.now(kind: "view.disappear", label: name)
                Task { await PerfUploader.shared.recordEvent(event) }
                if StartupProfiler.shared.isRunning {
                    StartupProfiler.shared.record("view.disappear.\(name)")
                }
            }
    }
}

extension View {
    /// Instrument this view's appear/disappear for profiling.
    func viewProfiled(_ name: String) -> some View {
        modifier(ViewProfileModifier(name: name))
    }
}
