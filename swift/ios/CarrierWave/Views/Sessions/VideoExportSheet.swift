// Video Export Sheet
//
// Configuration and progress UI for video export.

import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - VideoExportSheet

struct VideoExportSheet: View {
    // MARK: Internal

    let session: LoggingSession
    let hasRecording: Bool

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    @State var progress: VideoExportProgress?
    @State var thumbnailImage: UIImage?

    @State var exportedFileURL: URL?
    @State var videoDuration: String?

    var body: some View {
        NavigationStack {
            Group {
                if exportedFileURL != nil {
                    completionContent
                } else if isExporting {
                    progressContent
                } else {
                    configContent
                }
            }
            .navigationTitle("Export Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if exportedFileURL == nil {
                        Button("Cancel") {
                            if isExporting {
                                cancelExport()
                            } else {
                                dismiss()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if exportedFileURL != nil {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .alert("Export Failed", isPresented: $showError) {
                Button("OK") { dismiss() }
            } message: {
                Text(errorMessage)
            }
        }
    }

    func presentShareSheet(url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.keyWindow?.rootViewController
        else {
            return
        }
        // Find the topmost presented controller
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // On iPad the share sheet is presented as a popover, which requires a
        // source anchor — otherwise UIKit throws an NSInvalidArgumentException
        // from presentationTransitionWillBegin. Anchor it to the presenter.
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(
                x: topVC.view.bounds.midX,
                y: topVC.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        topVC.present(activityVC, animated: true)
    }

    // MARK: Private

    @State private var mode: VideoExportConfig.Mode = .highlightReel
    @State private var includeAudio = true
    @State private var mapStyle: VideoExportConfig.MapStyle = .standard
    @State private var layers: LayerVisibility = .defaults
    @State private var hudDensity: HUDDensity = .full
    @State private var theme: ThemePreset = .classic
    @State private var didLoadDefaults = false
    @State private var isExporting = false
    @State private var exportResult: VideoExportResult?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var exportActor: VideoExportActor?

    // MARK: - Config Content

    private var configContent: some View {
        Form {
            modeSection
            if hasRecording {
                audioSection
            }
            mapStyleSection
            layersSection
            hudSection
            themeSection
            exportButtonSection
        }
        .onAppear {
            guard !didLoadDefaults else {
                return
            }
            let stored = VideoExportDefaults.load()
            mode = stored.mode
            includeAudio = stored.includeAudio
            mapStyle = stored.mapStyle
            layers = stored.layers
            hudDensity = stored.hudDensity
            theme = stored.theme
            didLoadDefaults = true
        }
    }

    private var modeSection: some View {
        Section("Mode") {
            Picker("Mode", selection: $mode) {
                Text("Highlight Reel").tag(VideoExportConfig.Mode.highlightReel)
                Text("Full Replay").tag(VideoExportConfig.Mode.fullReplay)
            }
            .pickerStyle(.segmented)
        }
    }

    private var audioSection: some View {
        Section("Audio") {
            Toggle("Include WebSDR Audio", isOn: $includeAudio)
        }
    }

    private var mapStyleSection: some View {
        Section("Map Style") {
            Picker("Style", selection: $mapStyle) {
                Text("Standard").tag(VideoExportConfig.MapStyle.standard)
                Text("Satellite").tag(VideoExportConfig.MapStyle.satellite)
                Text("Hybrid").tag(VideoExportConfig.MapStyle.hybrid)
            }
            .pickerStyle(.segmented)
        }
    }

    private var layersSection: some View {
        Section("Layers") {
            Toggle("QSO Markers", isOn: $layers.showQSOMarkers)
            Toggle("Geodesic Arcs", isOn: $layers.showArcs)
            Toggle("Callsign Cards", isOn: $layers.showCallsignCards)
            Toggle("Spot Pulses", isOn: $layers.showSpots)
            Toggle("Event Toasts", isOn: $layers.showToasts)
            Toggle("Logger Hero Animation", isOn: $layers.showLoggerOverlay)
            Stepper(
                "Recent cards: \(layers.recentQSOCardCount)",
                value: $layers.recentQSOCardCount,
                in: 0 ... 10
            )
            .disabled(!layers.showCallsignCards)
        }
    }

    private var hudSection: some View {
        Section("HUD") {
            Picker("Density", selection: $hudDensity) {
                ForEach(HUDDensity.allCases, id: \.self) { density in
                    Text(density.label).tag(density)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var themeSection: some View {
        Section("Theme") {
            Picker("Theme", selection: $theme) {
                ForEach(ThemePreset.allCases, id: \.self) { preset in
                    Text(preset.label).tag(preset)
                }
            }
        }
    }

    private var exportButtonSection: some View {
        Section {
            Button {
                startExport()
            } label: {
                Label("Export Video", systemImage: "film")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Export Logic

    private func startExport() {
        let actor = VideoExportActor()
        exportActor = actor
        isExporting = true

        VideoExportDefaults.save(StoredVideoExportConfig(
            mode: mode,
            includeAudio: includeAudio,
            mapStyle: mapStyle,
            layers: layers,
            hudDensity: hudDensity,
            theme: theme
        ))

        let config = VideoExportConfig(
            sessionId: session.id,
            mode: mode,
            includeAudio: includeAudio && hasRecording,
            mapStyle: mapStyle,
            layers: layers,
            hudDensity: hudDensity,
            theme: theme
        )

        Task {
            let stream = await actor.startExport(
                container: modelContext.container,
                config: config
            )

            for await prog in stream {
                progress = prog
                if let thumb = prog.latestThumbnail {
                    thumbnailImage = UIImage(cgImage: thumb)
                }
            }

            if let result = await actor.result {
                handleResult(result)
            }
        }
    }

    private func handleResult(_ result: VideoExportResult) {
        switch result {
        case let .success(url):
            exportedFileURL = url
            isExporting = false
        case .cancelled:
            isExporting = false
        case let .failed(message):
            errorMessage = message
            showError = true
            isExporting = false
        }
    }

    private func cancelExport() {
        Task {
            await exportActor?.cancel()
        }
        isExporting = false
    }
}
