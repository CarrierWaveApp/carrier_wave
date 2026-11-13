import Foundation

// MARK: - MacroLibraryModel

/// View-model for `MacrosLibraryView`. Holds the segmented-control
/// selection + search text + draft-factory helper. Browse + Updates tabs
/// come online with Plan E; for Phase 1 only `.mine` is populated.
@Observable
@MainActor
public final class MacroLibraryModel {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public enum LibraryTab: String, CaseIterable, Identifiable, Sendable {
        case mine
        case browse
        case updates

        // MARK: Public

        public var id: String {
            rawValue
        }

        public var title: String {
            switch self {
            case .mine: "Mine"
            case .browse: "Browse"
            case .updates: "Updates"
            }
        }
    }

    public var searchText: String = ""
    public var selectedTab: LibraryTab = .mine

    /// Returns an unattached `RadioMacro` for the editor to mutate. Caller
    /// is responsible for inserting into a `ModelContext`.
    public func newDraft() -> RadioMacro {
        RadioMacro(name: "New Macro", appliesToCSV: "civ")
    }
}
