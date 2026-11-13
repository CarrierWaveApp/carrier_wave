import SwiftUI

// MARK: - LocationSessionServiceKey

private struct LocationSessionServiceKey: EnvironmentKey {
    @MainActor
    static let defaultValue = LocationSessionService()
}

extension EnvironmentValues {
    var locationSessionService: LocationSessionService {
        get { self[LocationSessionServiceKey.self] }
        set { self[LocationSessionServiceKey.self] = newValue }
    }
}
