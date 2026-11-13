import CarrierWaveData
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ContestSessionContainer

/// Hosts the customizable layout (`LayoutStore` + `LayoutRenderer`) for a
/// contest session, mirroring how `CustomLayoutView` / `ActivatorLayoutWrapper`
/// work for non-contest sessions. Loads the `ContestDefinition` for the
/// active session's `contestId`, spins up a `ContestManager` against the
/// session, then renders the user's active layout — contest-specific panels
/// (`contestScore`, `contestEntry`, `contestBandBreakdown`, `contestRecent`)
/// read from the manager via `PanelContext`. The Cabrillo Export toolbar item
/// lives on this wrapper so it surfaces on the Sessions toolbar whenever a
/// contest session is being operated.
///
/// Layout linkage: the rendered layout is always `LayoutStore.activeLayout`,
/// so the toolbar `LayoutPicker` stays in sync with what's on screen and the
/// duplicate/edit flow operates on the actual rendered layout. On contest
/// entry, `ensureContestLayoutActive()` switches the store to the built-in
/// Contester preset only when the current active layout has zero contest
/// panels — user-customized contest layouts (any layout with at least one
/// `isContestPanel` slot) are preserved untouched.
///
/// Known limitation: `ContestManager.start()` calls `resumeOrCreateSession`,
/// which may create a second `LoggingSession` for the same contest if the
/// one started via `MacSessionManager` doesn't match the resume predicate.
/// The resume code looks for `statusRawValue == "active"` plus the same
/// `contestId`, so duplicate-creation should be unusual in practice.
struct ContestSessionContainer: View {
    // MARK: Internal

    let session: LoggingSession
    let contestId: String
    let radioManager: RadioManager
    let flexDiscovery: FlexDiscoveryService

    var body: some View {
        Group {
            if let definition {
                layoutBody(definition: definition)
            } else if loadError != nil {
                errorState
            } else {
                ProgressView("Loading contest definition…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: contestId) {
            await loadDefinition()
        }
        .task(id: session.id) {
            ensureContestLayoutActive()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportCabrillo()
                } label: {
                    Label("Export Cabrillo", systemImage: "square.and.arrow.up")
                }
                .disabled(definition == nil || manager.score.totalQSOs == 0)
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDoc,
            contentType: .plainText,
            defaultFilename: manager.cabrilloFilename
        ) { _ in }
    }

    // MARK: Private

    @State private var refresher = ContestDefinitionsRefresher()
    @State private var manager = ContestManager()
    @State private var definition: ContestDefinition?
    @State private var loadError: String?
    @State private var exportDoc: CabrilloFile?
    @State private var showExporter = false
    @AppStorage("contestClubName") private var contestClubName = ""
    @AppStorage("contestEmail") private var contestEmail = ""
    @Environment(DXCCLookupService.self) private var dxccLookup
    @Environment(LayoutStore.self) private var layoutStore
    @Environment(SelectionState.self) private var selectionState
    @Environment(\.modelContext) private var modelContext

    /// The layout currently rendered by the container. Always the
    /// `LayoutStore`'s active layout so the toolbar `LayoutPicker` and the
    /// rendered content stay in sync. If the active layout has no contest
    /// panels on entry, `ensureContestLayoutActive()` switches the store to
    /// the built-in Contester preset; any user layout that already includes
    /// at least one contest panel is honored untouched.
    private var activeLayout: CustomLayout {
        layoutStore.activeLayout
    }

    private var errorState: some View {
        ContentUnavailableView {
            Label("Couldn't load contest", systemImage: "trophy.slash")
        } description: {
            Text(loadError ?? "Unknown error")
        } actions: {
            Button("Retry") {
                Task { await loadDefinition() }
            }
        }
    }

    private func layoutBody(definition: ContestDefinition) -> some View {
        let context = PanelContext(
            radioManager: radioManager,
            flexDiscovery: flexDiscovery,
            activeSession: session,
            contestManager: manager,
            contestDefinition: definition
        )
        return LayoutRenderer(node: activeLayout.root, context: context)
            .task(id: activeLayout.id) {
                selectionState.availablePanes = activeLayout.orderedPanels
                if let first = selectionState.availablePanes.first {
                    selectionState.focusedPane = first
                }
            }
    }

    /// On contest session entry, make sure the active layout actually shows
    /// contest panels. We only override when the user's current layout has
    /// zero contest panels — custom contest layouts (anything with at least
    /// one `isContestPanel` slot) are preserved.
    private func ensureContestLayoutActive() {
        if layoutStore.activeLayout.orderedPanels.contains(where: \.isContestPanel) {
            return
        }
        layoutStore.setActiveLayout(CustomLayout.contesterPreset)
    }

    private func exportCabrillo() {
        guard let text = manager.cabrilloText(
            clubName: contestClubName.isEmpty ? nil : contestClubName,
            email: contestEmail.isEmpty ? nil : contestEmail
        ) else {
            return
        }
        exportDoc = CabrilloFile(text: text)
        showExporter = true
    }

    @MainActor
    private func loadDefinition() async {
        await refresher.refreshIfStale()
        guard let loaded = await refresher.definition(id: contestId) else {
            loadError = refresher.lastError ?? "Contest \(contestId) not in catalog"
            return
        }
        definition = loaded
        loadError = nil
        let station = MyStationContext(
            callsign: session.myCallsign,
            grid: session.myGrid ?? ""
        )
        await manager.start(
            definition: loaded,
            myStation: station,
            dxcc: dxccLookup,
            modelContext: modelContext,
            sessionStart: session.startedAt
        )
    }
}

// MARK: - PanelIdentifier helpers

extension PanelIdentifier {
    var isContestPanel: Bool {
        switch self {
        case .contestScore,
             .contestEntry,
             .contestBandBreakdown,
             .contestRecent:
            true
        default:
            false
        }
    }
}

// MARK: - CabrilloFile

/// Plain-text `FileDocument` wrapper for `.fileExporter` — moved out of the
/// now-deleted `ContestRootView.swift` in CAR-276 PR8.
struct CabrilloFile: FileDocument {
    // MARK: Lifecycle

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(bytes: data, encoding: .utf8) ?? ""
        } else {
            text = ""
        }
    }

    // MARK: Internal

    static let readableContentTypes: [UTType] = [.plainText]

    var text: String

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
