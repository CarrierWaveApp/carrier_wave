import SwiftData
import SwiftUI

// MARK: - VimAction

enum VimAction {
    case moveSelection(VimMotion)
    case tune
    case enterEntryMode
    case enterBlankEntry
    case editQSO
    case appendNotes
    case lookup
    case dismiss
    case spot
    case undo
    case toggleSplit
    case adjustWPM(Int)
    case adjustTXOffset(Int)
    case directFrequency(String)
    case dotRepeat
    case sendCWMemory(Int)
    case abortCW
    case jumpToAlert
    case setMark(Character)
    case jumpToMark(Character)
    case jumpToPrevious
    case startMacro(Character)
    case stopMacro
    case playMacro(Character)
    case executeCommand(VimCommand)
    case applyFilter(String)
    case clearFilter
    case openInspector
}

// MARK: - VimActionExecutor

@MainActor
final class VimActionExecutor {
    // MARK: Lifecycle

    init(
        selectionState: SelectionState,
        radioManager: RadioManager,
        spotAggregator: SpotAggregator,
        winKeyer: WinKeyerManager,
        spotService: POTASpotService,
        modelContext: ModelContext
    ) {
        self.selectionState = selectionState
        self.radioManager = radioManager
        self.spotAggregator = spotAggregator
        self.winKeyer = winKeyer
        self.spotService = spotService
        self.modelContext = modelContext
    }

    // MARK: Internal

    let selectionState: SelectionState
    let radioManager: RadioManager
    let spotAggregator: SpotAggregator
    let winKeyer: WinKeyerManager
    let spotService: POTASpotService

    /// Main-actor model context for the informational `:find` / `:last` /
    /// `:count` commands (bounded fetches via `PaletteQSOQueries`).
    let modelContext: ModelContext

    func execute(_ action: VimAction) -> String? {
        switch action {
        case let .moveSelection(motion):
            executeNavigation(motion)
        case .tune:
            executeTune()
        case .enterEntryMode:
            executeEnterEntry()
        case .enterBlankEntry:
            executeEnterBlankEntry()
        case .editQSO:
            executeEditQSO()
        case let .executeCommand(command):
            executeCommand(command)
        case .dismiss:
            executeDismiss()
        case .openInspector:
            executeOpenInspector()
        case .lookup:
            executeLookup()
        default:
            nil
        }
    }
}
