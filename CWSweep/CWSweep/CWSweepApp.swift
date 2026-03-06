import AppKit
import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        Task { await CloudSyncService.shared.handleRemoteNotification(userInfo) }
    }
}

// MARK: - CWSweepApp

@main
struct CWSweepApp: App {
    // MARK: Lifecycle

    init() {
        let schema = Schema(CarrierWaveSchema.models)
        let config = ModelConfiguration(
            "CWSweep",
            schema: schema,
            cloudKitDatabase: .none
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Trigger iCloud KVS sync on launch
        NSUbiquitousKeyValueStore.default.synchronize()

        // Observe remote KVS changes to refresh Polo notes
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { _ in
            Task { await PoloNotesStore.shared.forceRefresh() }
        }
    }

    // MARK: Internal

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let modelContainer: ModelContainer

    var body: some Scene {
        Window("CW Sweep", id: "workspace") {
            WorkspaceView()
                .task {
                    CloudSyncService.shared.configure(container: modelContainer)
                }
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1_400, height: 900)
        .commands { CWSweepCommands() }

        Window("Band Map", id: "bandmap") {
            BandMapPanel()
        }
        .modelContainer(modelContainer)

        Window("Spot Cluster", id: "cluster") {
            ClusterPanel()
        }
        .modelContainer(modelContainer)

        Settings {
            SettingsView()
        }
        .modelContainer(modelContainer)

        MenuBarExtra("CW Sweep", systemImage: "antenna.radiowaves.left.and.right") {
            MenuBarExtraView()
        }
        .menuBarExtraStyle(.window)
        .modelContainer(modelContainer)
    }
}
