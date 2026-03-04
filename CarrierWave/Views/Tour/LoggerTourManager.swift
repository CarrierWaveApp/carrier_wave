import SwiftUI

// MARK: - LoggerTourStep

enum LoggerTourStep: Int, CaseIterable {
    case welcome
    case startSession
    case pickEquipment
    case setPark
    case activeSession
    case logQSO
    case moreQSOs
    case commands
    case sdrRecording
    case wrapUp
}

// MARK: - LoggerTourManager

/// Drives the interactive logger tour state machine.
/// All data is ephemeral mock structs — no SwiftData, no network, no persistence.
@Observable
@MainActor
final class LoggerTourManager: Identifiable {
    // MARK: Internal

    let id = UUID()
    private(set) var currentStep: LoggerTourStep = .welcome
    private(set) var isActive = false

    let mockSession = MockTourSession()

    /// Mock QSOs visible at the current step
    var visibleQSOs: [MockTourQSO] {
        switch currentStep {
        case .logQSO:
            Array(MockTourQSO.samples.prefix(1))
        case .moreQSOs,
             .commands,
             .sdrRecording,
             .wrapUp:
            MockTourQSO.samples
        default:
            []
        }
    }

    /// Whether the mock session header should be visible
    var showSessionHeader: Bool {
        switch currentStep {
        case .activeSession,
             .logQSO,
             .moreQSOs,
             .commands,
             .sdrRecording,
             .wrapUp:
            true
        default:
            false
        }
    }

    /// Whether the SessionStartSheet should be presented
    var showSessionSheet: Bool {
        switch currentStep {
        case .startSession,
             .pickEquipment,
             .setPark:
            true
        default:
            false
        }
    }

    /// Whether the mock callsign input should be visible
    var showCallsignInput: Bool {
        switch currentStep {
        case .activeSession,
             .logQSO,
             .moreQSOs,
             .commands,
             .sdrRecording,
             .wrapUp:
            true
        default:
            false
        }
    }

    /// Mock callsign text for the input field
    var mockCallsignText: String {
        switch currentStep {
        case .logQSO:
            "AJ7CM"
        case .commands:
            "HELP"
        default:
            ""
        }
    }

    /// Whether the command help overlay should be shown
    var showCommandHelp: Bool {
        currentStep == .commands
    }

    /// Whether the mock SDR indicator should be shown
    var showSDRIndicator: Bool {
        currentStep == .sdrRecording
    }

    /// Current tour guide message
    var currentMessage: TourGuideMessage? {
        TourGuideMessage.steps[currentStep]
    }

    func start() {
        currentStep = .welcome
        isActive = true
    }

    func advance() {
        let allSteps = LoggerTourStep.allCases
        guard let currentIndex = allSteps.firstIndex(of: currentStep) else {
            return
        }
        let nextIndex = allSteps.index(after: currentIndex)
        if nextIndex < allSteps.endIndex {
            currentStep = allSteps[nextIndex]
        } else {
            finish()
        }
    }

    func skip() {
        finish()
    }

    func setOnComplete(_ handler: @escaping () -> Void) {
        onComplete = handler
    }

    // MARK: Private

    private var onComplete: (() -> Void)?

    private func finish() {
        isActive = false
        onComplete?()
    }
}
