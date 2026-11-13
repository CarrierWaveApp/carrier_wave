import SwiftUI

// MARK: - LazyTabContent

/// Defers content creation until the view appears, improving tab switch performance.
/// Shows a brief loading indicator on first appearance.
struct LazyTabContent<Content: View>: View {
    // MARK: Internal

    var label: String = "unknown"
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if hasAppeared {
                content()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                let event = PerfEvent.now(kind: "lazy.loaded", label: label)
                Task { await PerfUploader.shared.recordEvent(event) }
                if StartupProfiler.shared.isRunning {
                    StartupProfiler.shared.record("lazy.loaded.\(label)")
                }
            }
        }
    }

    // MARK: Private

    @State private var hasAppeared = false
}
