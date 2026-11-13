// Video Export Button
//
// Entry point for video export on the session detail screen.

import CarrierWaveData
import SwiftUI

// MARK: - VideoExportButton

struct VideoExportButton: View {
    // MARK: Internal

    let session: LoggingSession
    let hasQSOsWithCoordinates: Bool
    let hasRecording: Bool

    var body: some View {
        Button {
            showExportSheet = true
        } label: {
            HStack(spacing: 6) {
                Label("Export Video", systemImage: "film")
                ExperimentalBadge(feature: .videoExport)
            }
        }
        .disabled(!hasQSOsWithCoordinates)
        .sheet(isPresented: $showExportSheet) {
            VideoExportSheet(
                session: session,
                hasRecording: hasRecording
            )
        }
    }

    // MARK: Private

    @State private var showExportSheet = false
}
