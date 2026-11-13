import CarrierWaveData
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ADIFImportModifier

/// Self-contained modifier that adds an ADIF file import button to the toolbar
/// and handles the file picker, import logic, and result/error alerts.
struct ADIFImportModifier: ViewModifier {
    // MARK: Internal

    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: ADIFFileType.importTypes,
                onCompletion: handleFileImport
            )
            .alert(
                "Import Complete",
                isPresented: $showImportResult
            ) {
                Button("OK") {}
            } message: {
                Text(importResultMessage)
            }
            .alert(
                "Import Failed",
                isPresented: $showImportError
            ) {
                Button("OK") {}
            } message: {
                Text(importErrorMessage)
            }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var showImportResult = false
    @State private var importResultMessage = ""
    @State private var showImportError = false
    @State private var importErrorMessage = ""

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            Task { await importADIFFile(from: url) }
        case let .failure(error):
            importErrorMessage = error.localizedDescription
            showImportError = true
        }
    }

    private func importADIFFile(from url: URL) async {
        guard url.startAccessingSecurityScopedResource() else {
            importErrorMessage = "Could not access the selected file."
            showImportError = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let callsign =
            CallsignAliasService.shared.getCurrentCallsign() ?? ""
        let importService = ImportService(modelContext: modelContext)

        do {
            let result = try await importService.importADIF(
                from: url,
                source: .adifFile,
                myCallsign: callsign
            )
            importResultMessage = formatResult(result, filename: url.lastPathComponent)
            showImportResult = true
        } catch {
            importErrorMessage = error.localizedDescription
            showImportError = true
        }
    }

    private func formatResult(
        _ result: ImportService.ImportResult,
        filename: String
    ) -> String {
        var parts: [String] = []
        parts.append("\(result.imported) imported")
        if result.duplicates > 0 {
            parts.append("\(result.duplicates) duplicates skipped")
        }
        if result.errors > 0 {
            parts.append("\(result.errors) errors")
        }
        return "\(filename): \(parts.joined(separator: ", "))"
    }
}

extension View {
    func adifImportable(isPresented: Binding<Bool>) -> some View {
        modifier(ADIFImportModifier(isPresented: isPresented))
    }
}
