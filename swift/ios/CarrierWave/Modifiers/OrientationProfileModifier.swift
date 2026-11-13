import SwiftUI

// MARK: - OrientationProfileModifier

/// Records orientation transition milestones to both the startup profiler
/// (local trace) and the MetricKit uploader (server telemetry).
///
/// Detects when `verticalSizeClass` or `horizontalSizeClass` changes
/// and records a transition event with the old→new labels.
///
/// Attach once at the root view (ContentView) via `.orientationProfiled()`.
struct OrientationProfileModifier: ViewModifier {
    // MARK: Internal

    func body(content: Content) -> some View {
        content
            .onChange(of: verticalSizeClass) { oldValue, newValue in
                recordTransition(
                    axis: "vertical",
                    from: oldValue,
                    to: newValue
                )
            }
            .onChange(of: horizontalSizeClass) { oldValue, newValue in
                recordTransition(
                    axis: "horizontal",
                    from: oldValue,
                    to: newValue
                )
            }
    }

    // MARK: Private

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private func recordTransition(
        axis: String,
        from oldValue: UserInterfaceSizeClass?,
        to newValue: UserInterfaceSizeClass?
    ) {
        let fromLabel = sizeClassLabel(oldValue)
        let toLabel = sizeClassLabel(newValue)
        let transitionLabel = "\(axis).\(fromLabel)→\(toLabel)"

        let event = PerfEvent.now(kind: "orientation", label: transitionLabel)
        Task { await PerfUploader.shared.recordEvent(event) }

        if StartupProfiler.shared.isRunning {
            StartupProfiler.shared.record("orientation.\(transitionLabel)")
        }
    }

    private func sizeClassLabel(
        _ sizeClass: UserInterfaceSizeClass?
    ) -> String {
        switch sizeClass {
        case .compact: "compact"
        case .regular: "regular"
        case .none: "nil"
        @unknown default: "unknown"
        }
    }
}

extension View {
    /// Instrument orientation transitions for profiling.
    func orientationProfiled() -> some View {
        modifier(OrientationProfileModifier())
    }
}
