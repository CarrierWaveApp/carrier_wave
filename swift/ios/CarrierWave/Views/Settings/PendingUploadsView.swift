import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - PendingUploadsView

/// Shows pending upload QSOs grouped by reason, with filtering and export.
struct PendingUploadsView: View {
    // MARK: Internal

    var initialServiceFilter: ServiceType?

    var body: some View {
        List {
            if result.isEmpty {
                emptyState
            } else {
                summarySection
                filterSection
                itemSections
            }
        }
        .navigationTitle("Pending Uploads")
        .toolbar { toolbarContent }
        .task { loadData() }
        .refreshable { loadData() }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                ShareSheet(activityItems: [shareURL])
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var result = PendingUploadResult(items: [], totalCount: 0, truncated: false)
    @State private var serviceFilter: ServiceType?
    @State private var reasonFilter: PendingUploadReason?
    @State private var showShareSheet = false
    @State private var shareURL: URL?

    private let analyzer = PendingUploadAnalyzer()

    private var filteredItems: [PendingUploadItem] {
        result.items.filter { item in
            if let rf = reasonFilter, item.reason != rf {
                return false
            }
            return true
        }
    }

    private var filteredSections: [(PendingUploadSection, [PendingUploadItem])] {
        let grouped = Dictionary(grouping: filteredItems, by: \.section)
        return PendingUploadSection.allCases.compactMap { section in
            guard let items = grouped[section], !items.isEmpty else {
                return nil
            }
            return (section, items)
        }
    }

    private func loadData() {
        if serviceFilter == nil {
            serviceFilter = initialServiceFilter
        }
        result = analyzer.analyze(context: modelContext, serviceFilter: serviceFilter)
    }
}

// MARK: - Sections

private extension PendingUploadsView {
    var emptyState: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("No Pending Uploads")
                    .font(.headline)
                Text("All QSOs are synced or no uploads are needed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    var summarySection: some View {
        Section {
            HStack {
                Label(
                    "\(result.totalCount) pending",
                    systemImage: "arrow.up.circle.badge.clock"
                )
                .font(.subheadline)
                .fontWeight(.medium)
                Spacer()
            }

            HStack(spacing: 12) {
                summaryBadge(
                    count: result.needsAttentionCount,
                    label: "need attention",
                    color: .orange
                )
                summaryBadge(
                    count: result.willRetryCount,
                    label: "will retry",
                    color: .blue
                )
            }
            .font(.caption)

            if result.truncated {
                Label(
                    "Showing first \(PendingUploadAnalyzer.displayLimit) of \(result.totalCount)",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    var filterSection: some View {
        Section {
            serviceFilterPicker
            reasonFilterPicker
        }
    }

    var serviceFilterPicker: some View {
        Picker("Service", selection: $serviceFilter) {
            Text("All Services").tag(nil as ServiceType?)
            ForEach(uploadServices, id: \.self) { service in
                Text(service.displayName).tag(service as ServiceType?)
            }
        }
        .onChange(of: serviceFilter) { _, _ in loadData() }
    }

    var reasonFilterPicker: some View {
        Picker("Reason", selection: $reasonFilter) {
            Text("All Reasons").tag(nil as PendingUploadReason?)
            ForEach(activeReasons, id: \.self) { reason in
                Text(reason.title).tag(reason as PendingUploadReason?)
            }
        }
    }

    var itemSections: some View {
        ForEach(filteredSections, id: \.0) { section, items in
            Section {
                ForEach(items) { item in
                    PendingUploadRow(item: item)
                }
            } header: {
                Label("\(section.title) (\(items.count))", systemImage: section.iconName)
            }
        }
    }

    var uploadServices: [ServiceType] {
        ServiceType.allCases.filter(\.supportsUpload)
    }

    var activeReasons: [PendingUploadReason] {
        let present = Set(result.items.map(\.reason))
        return PendingUploadReason.allCases.filter { present.contains($0) }
    }

    func summaryBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(count > 0 ? color : .secondary.opacity(0.3))
                .frame(width: 8, height: 8)
            Text("\(count) \(label)")
                .foregroundStyle(count > 0 ? .primary : .secondary)
        }
    }
}

// MARK: - Toolbar & Export

private extension PendingUploadsView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    copyMarkdownToClipboard()
                } label: {
                    Label("Copy as Markdown", systemImage: "doc.on.clipboard")
                }
                .disabled(result.isEmpty)

                Button {
                    shareCSV()
                } label: {
                    Label("Share as CSV", systemImage: "tablecells")
                }
                .disabled(result.isEmpty)

                Button {
                    shareADIF()
                } label: {
                    Label("Share as ADIF", systemImage: "square.and.arrow.up")
                }
                .disabled(result.isEmpty)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    func copyMarkdownToClipboard() {
        let content = PendingUploadExporter.markdown(
            items: filteredItems,
            serviceFilter: serviceFilter
        )
        UIPasteboard.general.string = content
    }

    func shareCSV() {
        let content = PendingUploadExporter.csv(
            items: filteredItems,
            serviceFilter: serviceFilter
        )
        shareFile(content: content, extension: "csv")
    }

    func shareADIF() {
        let content = PendingUploadExporter.adif(
            items: filteredItems,
            serviceFilter: serviceFilter
        )
        shareFile(content: content, extension: "adi")
    }

    func shareFile(content: String, extension ext: String) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "pending-uploads-\(fmt.string(from: Date())).\(ext)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            shareURL = url
            showShareSheet = true
        } catch {
            // Silently fail — file write to temp should not fail
        }
    }
}
