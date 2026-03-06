import SwiftUI

// MARK: - FocusEntryFieldAction

struct FocusEntryFieldAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - ToggleInspectorAction

struct ToggleInspectorAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - ShowCommandPaletteAction

struct ShowCommandPaletteAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - ConnectRadioAction

struct ConnectRadioAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - DisconnectRadioAction

struct DisconnectRadioAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - RefreshSpotsAction

struct RefreshSpotsAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - ToggleClusterAction

struct ToggleClusterAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - ShowContestSetupAction

struct ShowContestSetupAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - TuneInToSpotAction

struct TuneInToSpotAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - DisconnectSDRAction

struct DisconnectSDRAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - ToggleSDRRecordingAction

struct ToggleSDRRecordingAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - FocusEntryFieldKey

struct FocusEntryFieldKey: FocusedValueKey {
    typealias Value = FocusEntryFieldAction
}

// MARK: - ToggleInspectorKey

struct ToggleInspectorKey: FocusedValueKey {
    typealias Value = ToggleInspectorAction
}

// MARK: - ShowCommandPaletteKey

struct ShowCommandPaletteKey: FocusedValueKey {
    typealias Value = ShowCommandPaletteAction
}

// MARK: - ConnectRadioKey

struct ConnectRadioKey: FocusedValueKey {
    typealias Value = ConnectRadioAction
}

// MARK: - DisconnectRadioKey

struct DisconnectRadioKey: FocusedValueKey {
    typealias Value = DisconnectRadioAction
}

// MARK: - RadioManagerKey

struct RadioManagerKey: FocusedValueKey {
    typealias Value = RadioManager
}

// MARK: - RefreshSpotsKey

struct RefreshSpotsKey: FocusedValueKey {
    typealias Value = RefreshSpotsAction
}

// MARK: - ToggleClusterKey

struct ToggleClusterKey: FocusedValueKey {
    typealias Value = ToggleClusterAction
}

// MARK: - SpotAggregatorKey

struct SpotAggregatorKey: FocusedValueKey {
    typealias Value = SpotAggregator
}

// MARK: - ShowContestSetupKey

struct ShowContestSetupKey: FocusedValueKey {
    typealias Value = ShowContestSetupAction
}

// MARK: - ContestManagerKey

struct ContestManagerKey: FocusedValueKey {
    typealias Value = ContestManager
}

// MARK: - TuneInManagerKey

struct TuneInManagerKey: FocusedValueKey {
    typealias Value = TuneInManager
}

// MARK: - TuneInToSpotKey

struct TuneInToSpotKey: FocusedValueKey {
    typealias Value = TuneInToSpotAction
}

// MARK: - DisconnectSDRKey

struct DisconnectSDRKey: FocusedValueKey {
    typealias Value = DisconnectSDRAction
}

// MARK: - ToggleSDRRecordingKey

struct ToggleSDRRecordingKey: FocusedValueKey {
    typealias Value = ToggleSDRRecordingAction
}

// MARK: - FocusedValues Extension

extension FocusedValues {
    var focusEntryField: FocusEntryFieldAction? {
        get { self[FocusEntryFieldKey.self] }
        set { self[FocusEntryFieldKey.self] = newValue }
    }

    var toggleInspector: ToggleInspectorAction? {
        get { self[ToggleInspectorKey.self] }
        set { self[ToggleInspectorKey.self] = newValue }
    }

    var showCommandPalette: ShowCommandPaletteAction? {
        get { self[ShowCommandPaletteKey.self] }
        set { self[ShowCommandPaletteKey.self] = newValue }
    }

    var connectRadio: ConnectRadioAction? {
        get { self[ConnectRadioKey.self] }
        set { self[ConnectRadioKey.self] = newValue }
    }

    var disconnectRadio: DisconnectRadioAction? {
        get { self[DisconnectRadioKey.self] }
        set { self[DisconnectRadioKey.self] = newValue }
    }

    var radioManager: RadioManager? {
        get { self[RadioManagerKey.self] }
        set { self[RadioManagerKey.self] = newValue }
    }

    var refreshSpots: RefreshSpotsAction? {
        get { self[RefreshSpotsKey.self] }
        set { self[RefreshSpotsKey.self] = newValue }
    }

    var toggleCluster: ToggleClusterAction? {
        get { self[ToggleClusterKey.self] }
        set { self[ToggleClusterKey.self] = newValue }
    }

    var spotAggregator: SpotAggregator? {
        get { self[SpotAggregatorKey.self] }
        set { self[SpotAggregatorKey.self] = newValue }
    }

    var showContestSetup: ShowContestSetupAction? {
        get { self[ShowContestSetupKey.self] }
        set { self[ShowContestSetupKey.self] = newValue }
    }

    var contestManager: ContestManager? {
        get { self[ContestManagerKey.self] }
        set { self[ContestManagerKey.self] = newValue }
    }

    var tuneInManager: TuneInManager? {
        get { self[TuneInManagerKey.self] }
        set { self[TuneInManagerKey.self] = newValue }
    }

    var tuneInToSpot: TuneInToSpotAction? {
        get { self[TuneInToSpotKey.self] }
        set { self[TuneInToSpotKey.self] = newValue }
    }

    var disconnectSDR: DisconnectSDRAction? {
        get { self[DisconnectSDRKey.self] }
        set { self[DisconnectSDRKey.self] = newValue }
    }

    var toggleSDRRecording: ToggleSDRRecordingAction? {
        get { self[ToggleSDRRecordingKey.self] }
        set { self[ToggleSDRRecordingKey.self] = newValue }
    }
}
