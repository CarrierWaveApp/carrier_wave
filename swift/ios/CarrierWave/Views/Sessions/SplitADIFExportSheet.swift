// Split ADIF Export Sheet
//
// Exports multiple ADIF files from a session, split by UTC day,
// park reference (n-fers), and/or operator (multi-op).

import CarrierWaveData
import SwiftUI
import UIKit

// MARK: - SplitADIFExportSheet

struct SplitADIFExportSheet: View {
    // MARK: Internal

    let session: LoggingSession
    let qsos: [QSO]

    var body: some View {
        NavigationStack {
            List {
                splitOptionsSection
                if isGenerating {
                    generatingSection
                } else if !exportFiles.isEmpty {
                    filesSection
                } else if let errorMessage {
                    errorSection(errorMessage)
                } else {
                    previewSection
                }
            }
            .navigationTitle("Split Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { detectSplitOptions() }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var splitByUTCDay = true
    @State private var splitByPark = true
    @State private var splitByOperator = true
    @State private var isGenerating = false
    @State private var exportFiles: [SplitExportFile] = []
    @State private var errorMessage: String?

    // Detected capabilities
    @State private var hasMultipleDays = false
    @State private var hasMultipleParks = false
    @State private var hasMultipleOperators = false

    private var fileCount: Int {
        let config = buildConfig()
        guard let config else {
            return 1
        }
        return splitFileCount(for: config)
    }

    private var previewDescription: String {
        var parts: [String] = []
        if splitByUTCDay, hasMultipleDays {
            parts.append("UTC day")
        }
        if splitByPark, hasMultipleParks {
            parts.append("park")
        }
        if splitByOperator, hasMultipleOperators {
            parts.append("operator")
        }
        if parts.isEmpty {
            return "No splitting — exports a single file"
        }
        let joined = parts.joined(separator: ", ")
        return "Splitting by \(joined)"
    }

    // MARK: - Sections

    private var splitOptionsSection: some View {
        Section {
            if hasMultipleDays {
                Toggle("Split by UTC Day", isOn: $splitByUTCDay)
            }
            if hasMultipleParks {
                Toggle("Split by Park", isOn: $splitByPark)
            }
            if hasMultipleOperators {
                Toggle("Split by Operator", isOn: $splitByOperator)
            }
        } header: {
            Text("Split Options")
        } footer: {
            Text("\(qsos.count) QSOs total")
        }
    }

    private var previewSection: some View {
        Section {
            Button {
                Task { await generateFiles() }
            } label: {
                Label(
                    "Generate \(fileCount) Files",
                    systemImage: "doc.on.doc"
                )
            }
        } header: {
            Text("Export")
        } footer: {
            Text(previewDescription)
        }
    }

    private var generatingSection: some View {
        Section {
            HStack {
                ProgressView()
                Text("Generating ADIF files...")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var filesSection: some View {
        Section {
            shareAllButton
        } header: {
            Text("\(exportFiles.count) Files Ready")
        }

        Section {
            ForEach(exportFiles) { file in
                fileRow(file)
            }
        }
    }

    private var shareAllButton: some View {
        Button {
            shareAllFiles()
        } label: {
            Label(
                "Share All (\(exportFiles.count) files)",
                systemImage: "square.and.arrow.up"
            )
        }
    }

    private func fileRow(_ file: SplitExportFile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(file.qsoCount) QSOs")
                    if let park = file.parkReference {
                        Text(park)
                    }
                    Text(file.displayDate)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            ShareLink(
                item: ShareableADIF(
                    content: file.content,
                    filename: file.filename
                ),
                preview: SharePreview(
                    file.filename,
                    image: Image(systemName: "doc.text")
                )
            ) {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Button("Try Again") {
                errorMessage = nil
            }
        }
    }

    // MARK: - Logic

    private func detectSplitOptions() {
        let utcCal = utcCalendar()
        let dates = Set(qsos.map { utcCal.startOfDay(for: $0.timestamp) })
        hasMultipleDays = dates.count > 1

        // Fan out N-fer refs ("US-1, US-2") so a session with any multi-park
        // QSO counts as having multiple parks even if every QSO shares the
        // same comma-separated string.
        var parks: Set<String> = []
        for qso in qsos {
            guard let raw = qso.parkReference, !raw.isEmpty else {
                continue
            }
            for park in ParkReference.split(raw) {
                parks.insert(park)
            }
        }
        hasMultipleParks = parks.count > 1

        hasMultipleOperators = session.isMultiOp

        // Default toggles to detected state
        splitByUTCDay = hasMultipleDays
        splitByPark = hasMultipleParks
        splitByOperator = hasMultipleOperators
    }

    private func buildConfig() -> SplitExportConfig? {
        guard !qsos.isEmpty else {
            return nil
        }
        let snapshots = qsos.map { QSOExportSnapshot(from: $0) }
        return SplitExportConfig(
            snapshots: snapshots,
            splitByUTCDay: splitByUTCDay && hasMultipleDays,
            splitByPark: splitByPark && hasMultipleParks,
            splitByOperator: splitByOperator && hasMultipleOperators,
            fallbackPark: session.parkReference,
            fallbackCallsign: session.myCallsign,
            parkNames: [:]
        )
    }

    @MainActor
    private func generateFiles() async {
        guard let config = buildConfig() else {
            errorMessage = "No QSOs to export"
            return
        }
        isGenerating = true
        defer { isGenerating = false }

        let service = ADIFExportService()
        exportFiles = await service.generateSplitADIF(for: config)
    }

    private func shareAllFiles() {
        let items: [Any] = exportFiles.map { file in
            let tempDir = FileManager.default.temporaryDirectory
            let url = tempDir.appendingPathComponent(file.filename)
            try? file.content.write(
                to: url, atomically: true, encoding: .utf8
            )
            return url as Any
        }

        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive })
            as? UIWindowScene,
            let root = scene.windows.first?.rootViewController
        else {
            return
        }

        let activityVC = UIActivityViewController(
            activityItems: items, applicationActivities: nil
        )
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = root.view
            popover.sourceRect = CGRect(
                x: root.view.bounds.midX,
                y: root.view.bounds.midY,
                width: 0, height: 0
            )
        }
        root.present(activityVC, animated: true)
    }

    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }
}

// MARK: - Split File Count Helper

/// File-private helper to count split groups without generating ADIF content
private func splitFileCount(for config: SplitExportConfig) -> Int {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    dateFormatter.timeZone = TimeZone(identifier: "UTC")

    let fallbackDateStr = dateFormatter.string(
        from: config.snapshots.first?.timestamp ?? Date()
    )

    struct GroupKey: Hashable {
        let park: String?
        let utcDateStr: String
        let callsign: String
    }

    var keys: Set<GroupKey> = []
    for snapshot in config.snapshots {
        let parks: [String?]
        if config.splitByPark {
            if let raw = snapshot.parkReference, !raw.isEmpty {
                let split = ParkReference.split(raw)
                parks = split.isEmpty ? [nil] : split.map { Optional($0) }
            } else {
                parks = [nil]
            }
        } else {
            parks = [config.fallbackPark]
        }

        let dateStr = config.splitByUTCDay
            ? dateFormatter.string(from: snapshot.timestamp)
            : fallbackDateStr
        let callsign = config.splitByOperator
            ? snapshot.myCallsign.uppercased()
            : config.fallbackCallsign.uppercased()
        for park in parks {
            keys.insert(GroupKey(
                park: park, utcDateStr: dateStr, callsign: callsign
            ))
        }
    }

    return max(keys.count, 1)
}
