import SwiftData
import SwiftUI
import UIKit

// MARK: - ExportedFile

struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - DatabaseExporter

enum DatabaseExporter {
    enum ExportError: LocalizedError {
        case storeNotFound

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .storeNotFound:
                "Could not locate the database file."
            }
        }
    }

    static func export(
        from container: ModelContainer
    ) async throws -> URL {
        guard let config = container.configurations.first else {
            throw ExportError.storeNotFound
        }
        let storeURL = config.url

        return try await Task.detached(priority: .userInitiated) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let exportFilename =
                "CarrierWave_QSO_Export_\(timestamp).sqlite"

            let tempDir = FileManager.default.temporaryDirectory
            let exportURL = tempDir.appendingPathComponent(exportFilename)

            if FileManager.default.fileExists(atPath: exportURL.path) {
                try FileManager.default.removeItem(at: exportURL)
            }

            try FileManager.default.copyItem(at: storeURL, to: exportURL)

            for ext in ["wal", "shm"] {
                let sourceURL = storeURL.appendingPathExtension(ext)
                let destURL = exportURL.appendingPathExtension(ext)
                if FileManager.default.fileExists(
                    atPath: sourceURL.path
                ) {
                    if FileManager.default.fileExists(
                        atPath: destURL.path
                    ) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(
                        at: sourceURL, to: destURL
                    )
                }
            }

            return exportURL
        }.value
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]?

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
