import AppKit
import CarrierWaveData
import SwiftData
import SwiftUI

/// Sheet showing generated Cabrillo log with save/copy options.
struct CabrilloPreviewView: View {
    // MARK: Internal

    let contestManager: ContestManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cabrillo Export")
                    .font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            // Preview
            ScrollView {
                Text(cabrilloText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(.background)

            Divider()

            // Actions
            HStack {
                Text("\(lineCount) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cabrilloText, forType: .string)
                    copiedToClipboard = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedToClipboard = false
                    }
                }
                if copiedToClipboard {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }

                Button("Save...") {
                    saveFile()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 400, idealHeight: 500)
        .alert("Save Error", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .task {
            generateCabrillo()
        }
    }

    // MARK: Private

    @State private var cabrilloText = ""
    @State private var copiedToClipboard = false
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var lineCount: Int {
        cabrilloText.components(separatedBy: "\n").count
    }

    private func generateCabrillo() {
        guard let session = contestManager.activeSession,
              let definition = contestManager.definition
        else {
            return
        }

        // Fetch contest QSOs for this session
        let sessionId = session.id
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.loggingSessionId == sessionId && !$0.isHidden }
        )
        descriptor.sortBy = [SortDescriptor(\QSO.timestamp)]

        let qsos = (try? modelContext.fetch(descriptor)) ?? []
        let score = contestManager.score

        let exporter = CabrilloExportService()
        cabrilloText = exporter.generate(
            session: session,
            qsos: qsos,
            definition: definition,
            score: score
        )
    }

    private func saveFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(contestManager.definition?.cabrilloCategoryContest ?? "contest").log"
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            do {
                try cabrilloText.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}
