import CarrierWaveCore
import SwiftUI

// MARK: - LoggerView Derived State & Action Button Properties

extension LoggerView {
    var userLicenseClass: LicenseClass {
        LicenseClass(rawValue: licenseClassRaw) ?? .extra
    }

    /// Whether the log button should be enabled
    var canLog: Bool {
        guard sessionManager?.hasActiveSession == true else {
            return false
        }

        // Determine which callsign to validate
        let callsignToValidate: String
        if let qeResult = quickEntryResult {
            callsignToValidate = qeResult.callsign
        } else {
            guard !callsignInput.isEmpty, callsignInput.count >= 3 else {
                return false
            }
            callsignToValidate = callsignInput.uppercased()
        }

        // Don't allow logging your own callsign
        let myCallsign = sessionManager?.activeSession?.myCallsign.uppercased() ?? ""
        if !myCallsign.isEmpty, callsignToValidate.uppercased() == myCallsign {
            return false
        }

        // Block POTA duplicates on same band (requirement 6a)
        if case .duplicateBand = potaDuplicateStatus {
            return false
        }

        return true
    }

    /// Whether the action button next to the callsign field is enabled
    var actionButtonEnabled: Bool {
        detectedCommand != nil || canLog
    }

    /// Label for the action button next to the callsign field
    var actionButtonLabel: String {
        if detectedCommand != nil {
            return "RUN"
        } else if editingQSO != nil {
            return "SAVE"
        }
        return "LOG"
    }

    /// Color for the action button next to the callsign field
    var actionButtonColor: Color {
        if detectedCommand != nil {
            return .purple
        } else if editingQSO != nil {
            return .orange
        }
        return Color(uiColor: .systemBlue)
    }

    /// Accessibility label for the action button
    var actionButtonAccessibilityLabel: String {
        if detectedCommand != nil {
            return "Run command"
        } else if editingQSO != nil {
            return "Save callsign edit"
        }
        return "Log QSO"
    }

    /// Current mode (for RST default)
    var currentMode: String {
        sessionManager?.activeSession?.mode ?? "CW"
    }

    /// Whether current mode uses 3-digit RST (CW/digital) vs 2-digit RS (phone)
    var isCWMode: Bool {
        let mode = currentMode.uppercased()
        let threeDigitModes = [
            "CW", "RTTY", "PSK", "PSK31", "FT8", "FT4", "JT65", "JT9", "DATA", "DIGITAL",
        ]
        return threeDigitModes.contains(mode)
    }

    /// Default RST based on current mode
    var defaultRST: String {
        isCWMode ? "599" : "59"
    }

    /// Detected command from input (if any)
    var detectedCommand: LoggerCommand? {
        LoggerCommand.parse(callsignInput)
    }

    /// Whether to show the lookup error banner (when keyboard is not visible)
    var shouldShowLookupError: Bool {
        lookupError != nil && lookupResult == nil && !callsignFieldFocused && !callsignInput.isEmpty
            && callsignInput.count >= 3 && detectedCommand == nil
    }

    /// Key for animating POTA status changes
    var potaDuplicateStatusKey: String {
        switch potaDuplicateStatus {
        case .none: "none"
        case .firstContact: "first"
        case .newBand: "newband"
        case .duplicateBand: "dupe"
        }
    }

    /// Current frequency warning (if any) - convenience property
    var currentWarning: FrequencyWarning? {
        computeCurrentWarning(spotCount: cachedPOTASpots.count, inputText: callsignInput)
    }

    /// Border color for the callsign input field.
    /// Priority: command purple > SCP known green > SCP unknown amber > clear.
    var callsignFieldBorderColor: Color {
        if detectedCommand != nil {
            return .purple
        }
        guard let known = scpCallsignKnown, callsignFieldFocused else {
            return .clear
        }
        return known ? .green.opacity(0.6) : .orange.opacity(0.5)
    }
}
