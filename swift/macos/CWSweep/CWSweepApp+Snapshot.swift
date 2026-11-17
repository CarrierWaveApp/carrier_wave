import AppKit
import CarrierWaveData
import Foundation
import SwiftUI

// MARK: - CWSweepApp + Satellites snapshot

@MainActor
extension CWSweepApp {
    /// Developer hook: `open "CW Sweep.app" --args --snapshot-satellites /tmp/sat.png [seconds] [--grid CM87]`
    /// switches the workspace to Satellites (which starts tracking and the
    /// saved rotator link), waits for live data, captures the main window's
    /// real content to a PNG (falling back to an offscreen render), writes a
    /// `.log` beside it, and exits. Lets a headless session screenshot the UI
    /// without Screen Recording permission. No-op without the argument.
    func runSatelliteSnapshotIfRequested() async {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot-satellites"), args.indices.contains(index + 1) else {
            return
        }
        let path = args[index + 1]
        let wait = args.indices.contains(index + 2) ? Double(args[index + 2]) ?? 60 : 60
        var log = ["start \(Date())"]
        func flush() {
            try? log.joined(separator: "\n").write(toFile: path + ".log", atomically: true, encoding: .utf8)
        }
        // `--grid CM87` supplies an observer when Settings has none; the
        // temporary value is removed again before exiting.
        var temporaryGrid = false
        if let gridIndex = args.firstIndex(of: "--grid"), args.indices.contains(gridIndex + 1),
           (UserDefaults.standard.string(forKey: "myGrid") ?? "").isEmpty
        {
            UserDefaults.standard.set(args[gridIndex + 1], forKey: "myGrid")
            temporaryGrid = true
            log.append("temporary grid \(args[gridIndex + 1])")
        }
        func finish() -> Never {
            if temporaryGrid {
                UserDefaults.standard.removeObject(forKey: "myGrid")
                UserDefaults.standard.synchronize()
            }
            log.append("exit \(Date())")
            flush()
            exit(0)
        }

        try? await Task.sleep(for: .seconds(1))
        let windowDescriptions = NSApp.windows.map {
            "\($0.title) \(Int($0.frame.width))x\(Int($0.frame.height)) visible=\($0.isVisible)"
        }
        log.append("windows: \(windowDescriptions)")
        Self.prepareMainWindowForSnapshot()
        NotificationCenter.default.post(name: .showSatellites, object: nil)
        flush()
        try? await Task.sleep(for: .seconds(wait))
        let model = SharedEnvironment.shared.satellitePassModel
        log.append(
            "model state=\(model.state) passes=\(model.upcoming.count) "
                + "selected=\(model.selectedPass?.name ?? "-") grid=\(model.observerGrid ?? "-")"
        )
        let rotator = SharedEnvironment.shared.rotatorController
        log.append("rotator \(rotator.state.label) pos=\(String(describing: rotator.position))")

        let png = Self.captureSnapshotPNG(model: model, log: &log)
        Self.writeSnapshot(png, to: path, log: &log)
        finish()
    }

    private static func writeSnapshot(_ png: Data?, to path: String, log: inout [String]) {
        guard let png else {
            log.append("no image produced")
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            log.append("wrote \(path) (\(png.count) bytes)")
        } catch {
            log.append("write failed: \(error.localizedDescription)")
        }
    }

    private static func captureSnapshotPNG(model: SatellitePassModel, log: inout [String]) -> Data? {
        var png: Data?
        if let window = Self.mainWindow(), let view = window.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        {
            view.cacheDisplay(in: view.bounds, to: rep)
            png = rep.representation(using: .png, properties: [:])
            log.append("window capture \(Int(view.bounds.width))x\(Int(view.bounds.height)) bytes=\(png?.count ?? 0)")
        } else {
            log.append("window capture unavailable; falling back to ImageRenderer")
            let view = SatellitesView(model: model)
                .sharedEnvironments()
                .frame(width: 1_180, height: 860)
                .background(SatelliteTheme.background)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff)
            {
                png = bitmap.representation(using: .png, properties: [:])
            }
        }
        return png
    }

    private static func prepareMainWindowForSnapshot() {
        guard let window = mainWindow() else {
            return
        }
        window.setContentSize(NSSize(width: 1_400, height: 900))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows
            .filter { $0.isVisible && $0.contentView != nil && $0.frame.width > 600 }
            .max { $0.frame.width < $1.frame.width }
    }
}
