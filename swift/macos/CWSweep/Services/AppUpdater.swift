import Combine
import Sparkle
import SwiftUI

// MARK: - AppUpdaterController

/// Wraps Sparkle's `SPUStandardUpdaterController` so `CWSweepApp` can install
/// it once at launch and `CWSweepCommands` can drive the "Check for
/// Updates…" menu item.
///
/// Sparkle reads `SUFeedURL` and `SUPublicEDKey` from `Info.plist`; the
/// updater starts itself on init.
@MainActor
final class AppUpdaterController {
    // MARK: Lifecycle

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    // MARK: Internal

    let updaterController: SPUStandardUpdaterController

    var updater: SPUUpdater {
        updaterController.updater
    }
}

// MARK: - CheckForUpdatesViewModel

/// Reactive wrapper around `SPUUpdater.canCheckForUpdates` so the menu item
/// dims while a check is already in flight.
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    // MARK: Lifecycle

    init(updater: SPUUpdater) {
        updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    // MARK: Internal

    @Published var canCheckForUpdates = false
}

// MARK: - CheckForUpdatesView

/// Menu-bar button for `CommandGroup(after: .appInfo)`. Mirrors Sparkle's
/// canonical SwiftUI integration sample.
struct CheckForUpdatesView: View {
    // MARK: Lifecycle

    init(updater: SPUUpdater) {
        self.updater = updater
        _viewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    // MARK: Internal

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }

    // MARK: Private

    @StateObject private var viewModel: CheckForUpdatesViewModel

    private let updater: SPUUpdater
}
