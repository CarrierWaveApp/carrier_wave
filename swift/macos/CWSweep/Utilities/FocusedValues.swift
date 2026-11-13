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

// MARK: - ShowRadioPaletteAction

struct ShowRadioPaletteAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - OpenQSOEntryAction

struct OpenQSOEntryAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - ShowImportADIFAction

struct ShowImportADIFAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - ShowExportADIFAction

struct ShowExportADIFAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - ReturnToFrequencyAction

struct ReturnToFrequencyAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - EditSpotCommentAction

struct EditSpotCommentAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

// MARK: - SpotNowAction

struct SpotNowAction {
    let action: (String?) -> Void

    func callAsFunction(comment: String? = nil) {
        action(comment)
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

// MARK: - ShowRadioPaletteKey

struct ShowRadioPaletteKey: FocusedValueKey {
    typealias Value = ShowRadioPaletteAction
}

// MARK: - OpenQSOEntryKey

struct OpenQSOEntryKey: FocusedValueKey {
    typealias Value = OpenQSOEntryAction
}

// MARK: - ShowImportADIFKey

struct ShowImportADIFKey: FocusedValueKey {
    typealias Value = ShowImportADIFAction
}

// MARK: - ShowExportADIFKey

struct ShowExportADIFKey: FocusedValueKey {
    typealias Value = ShowExportADIFAction
}

// MARK: - ReturnToFrequencyKey

struct ReturnToFrequencyKey: FocusedValueKey {
    typealias Value = ReturnToFrequencyAction
}

// MARK: - EditSpotCommentKey

struct EditSpotCommentKey: FocusedValueKey {
    typealias Value = EditSpotCommentAction
}

// MARK: - SpotNowKey

struct SpotNowKey: FocusedValueKey {
    typealias Value = SpotNowAction
}

// MARK: - ActivationFrequencyKey

struct ActivationFrequencyKey: FocusedValueKey {
    typealias Value = (Double, String)
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

    var showRadioPalette: ShowRadioPaletteAction? {
        get { self[ShowRadioPaletteKey.self] }
        set { self[ShowRadioPaletteKey.self] = newValue }
    }

    var openQSOEntry: OpenQSOEntryAction? {
        get { self[OpenQSOEntryKey.self] }
        set { self[OpenQSOEntryKey.self] = newValue }
    }

    var showImportADIF: ShowImportADIFAction? {
        get { self[ShowImportADIFKey.self] }
        set { self[ShowImportADIFKey.self] = newValue }
    }

    var showExportADIF: ShowExportADIFAction? {
        get { self[ShowExportADIFKey.self] }
        set { self[ShowExportADIFKey.self] = newValue }
    }

    var returnToFrequency: ReturnToFrequencyAction? {
        get { self[ReturnToFrequencyKey.self] }
        set { self[ReturnToFrequencyKey.self] = newValue }
    }

    var editSpotComment: EditSpotCommentAction? {
        get { self[EditSpotCommentKey.self] }
        set { self[EditSpotCommentKey.self] = newValue }
    }

    var spotNow: SpotNowAction? {
        get { self[SpotNowKey.self] }
        set { self[SpotNowKey.self] = newValue }
    }

    var activationFrequency: (Double, String)? {
        get { self[ActivationFrequencyKey.self] }
        set { self[ActivationFrequencyKey.self] = newValue }
    }
}
