import SwiftUI
import UniformTypeIdentifiers

// MARK: - StartupProfileView

/// Shows the most recent startup profile trace and allows sharing.
struct StartupProfileView: View {
    // MARK: Internal

    @State var shareFileURL: URL?
    @State var showingFileImporter = false
    @State var showingImportError = false
    @State var hangSummaryCopied = false
    @State var refreshID = UUID()
    @State var showTimeline = false

    var profiler: StartupProfiler {
        .shared
    }

    var dateFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .medium
        return fmt
    }

    var timeFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return fmt
    }

    var body: some View {
        List {
            if let trace = profiler.lastTrace {
                timelineChartSection(trace)
                traceHeader(trace)
                if trace.hangCount > 0 {
                    hangsListSection(trace)
                }
                milestonesSection(
                    trace.startupMilestones,
                    header: "Startup Timeline",
                    trace: trace
                )
                if !trace.orientationMilestones.isEmpty {
                    orientationSection(trace)
                }
                if !trace.runtimeMilestones.isEmpty {
                    runtimeSection(trace)
                }
            } else {
                noTraceView
            }
        }
        .id(refreshID)
        .navigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    importButton
                    shareButton
                    copyHangSummaryButton
                    Divider()
                    clearButton
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.json],
            onCompletion: handleFileImport
        )
        .onChange(of: shareFileURL) { _, url in
            guard let url else {
                return
            }
            presentShareSheet(for: url)
        }
        .alert(
            "Import Failed",
            isPresented: $showingImportError
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The file could not be read as a startup profile.")
        }
        .overlay {
            if hangSummaryCopied {
                copiedToast
            }
        }
        .animation(reduceMotion ? .none : .easeInOut, value: hangSummaryCopied)
        .onChange(of: hangSummaryCopied) { _, copied in
            if copied {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    hangSummaryCopied = false
                }
            }
        }
    }

    func deltaColor(_ delta: TimeInterval) -> Color {
        if delta > 1.0 {
            return .red
        } else if delta > 0.3 {
            return .orange
        }
        return .secondary
    }

    func formatMB(_ mb: Int) -> String {
        if mb >= 1_024 {
            return String(format: "%.1f GB", Double(mb) / 1_024.0)
        }
        return "\(mb) MB"
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var importButton: some View {
        Button {
            showingFileImporter = true
        } label: {
            Label("Import Profile…", systemImage: "square.and.arrow.down")
        }
    }

    private var noTraceView: some View {
        ContentUnavailableView(
            "No Profile Yet",
            systemImage: "gauge.with.dots.needle.0percent",
            description: Text(
                "Enable the toggle above and relaunch the app "
                    + "to capture a startup profile."
            )
        )
    }

    private var shareButton: some View {
        Button {
            shareTrace()
        } label: {
            Label("Share Profile", systemImage: "square.and.arrow.up")
        }
        .disabled(profiler.lastTrace == nil)
    }

    private var copiedToast: some View {
        Text("Copied")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .transition(.opacity.combined(with: .scale))
    }

    private var copyHangSummaryButton: some View {
        Button {
            if let trace = profiler.lastTrace {
                UIPasteboard.general.string = trace.hangSummaryText
                hangSummaryCopied = true
            }
        } label: {
            Label("Copy Hang Summary", systemImage: "doc.on.doc")
        }
        .disabled(profiler.lastTrace == nil)
    }

    private var clearButton: some View {
        Button(role: .destructive) {
            profiler.clearTrace()
        } label: {
            Label("Clear Profile", systemImage: "trash")
        }
        .disabled(profiler.lastTrace == nil)
    }
}

// MARK: - Milestone Row Views

extension StartupProfileView {
    func milestoneRow(
        _ milestone: StartupTrace.Milestone,
        delta: TimeInterval,
        isFirst: Bool
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.label)
                    .font(.caption)
                    .fontDesign(.monospaced)
                HStack(spacing: 4) {
                    Text(timeFormatter.string(from: milestone.wallTime))
                    Text("·")
                    Text(milestone.threadName)
                    if let memMB = milestone.residentMemoryMB {
                        Text("·")
                        Text(formatMB(memMB))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.3f s", milestone.elapsedSeconds))
                    .font(.caption)
                    .fontDesign(.monospaced)
                if !isFirst {
                    Text(String(format: "+%.3f s", delta))
                        .font(.caption2)
                        .foregroundStyle(deltaColor(delta))
                }
            }
        }
    }

    func hangMilestoneRow(
        _ milestone: StartupTrace.Milestone,
        delta: TimeInterval,
        trace: StartupTrace
    ) -> some View {
        let correlation = trace.correlatedMilestones(for: milestone)
        return VStack(alignment: .leading, spacing: 4) {
            milestoneRow(milestone, delta: delta, isFirst: false)
            hangCorrelationView(correlation)
        }
    }

    func hangCorrelationView(_ corr: HangCorrelation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let before = corr.before {
                Text("after: \(before.label)")
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.orange)
            }
            ForEach(Array(corr.during.enumerated()), id: \.offset) { _, item in
                Text("during: \(item.label)")
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.yellow)
            }
            ForEach(Array(corr.background.enumerated()), id: \.offset) { _, item in
                Text("bg: \(item.label)")
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
            }
            if let after = corr.after {
                Text("until: \(after.label)")
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.leading, 8)
    }
}

// MARK: - File Import & Sharing

extension StartupProfileView {
    func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            if !profiler.loadTrace(from: url) {
                showingImportError = true
            }
        case .failure:
            showingImportError = true
        }
    }

    func shareTrace() {
        guard let url = profiler.traceFileURL() else {
            return
        }
        shareFileURL = url
    }

    func presentShareSheet(for url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let activityVC = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )
            guard let scene = UIApplication.shared.connectedScenes
                .first as? UIWindowScene,
                let rootVC = scene.keyWindow?.rootViewController
            else {
                return
            }
            var presenter = rootVC
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(
                    x: presenter.view.bounds.midX,
                    y: presenter.view.bounds.midY,
                    width: 0, height: 0
                )
                popover.permittedArrowDirections = []
            }
            presenter.present(activityVC, animated: true) {
                shareFileURL = nil
            }
        }
    }
}
