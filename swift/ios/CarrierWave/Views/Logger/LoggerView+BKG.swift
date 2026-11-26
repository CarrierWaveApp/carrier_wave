import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - BKGFormState

/// Logger form state for a BKG session. Rules and field mapping are Rust's
/// (`bkgBuildQso`); this only holds what the operator toggled.
struct BKGFormState: Equatable {
    /// "I sent my grid in CW".
    var sentMyGrid = false
    /// "They sent theirs".
    var receivedTheirGrid = false
    /// Worked through a linear V/U satellite. Sticky for the pass.
    var viaSatellite = false
    var satName = ""
    /// The session's 4-grid corner, empty when it has none.
    var cornerGrids: [String] = []
    /// Session grid being typed when the session's own grid is too short.
    var myGridDraft = ""
    var showExport = false

    /// The two switches are per-contact; satellite and corner stay put.
    mutating func resetAfterLog() {
        sentMyGrid = false
        receivedTheirGrid = false
    }
}

// MARK: - LoggerView BKG

extension LoggerView {
    /// Whether the active session is a BKG log.
    var isBKGSession: Bool {
        sessionManager?.activeSession?.programs.contains(BKGLog.programSlug) == true
    }

    private var bkgMyGrid: String {
        sessionManager?.activeSession?.myGrid ?? ""
    }

    /// The form as Rust sees it: QSO field values, or the reason it can't be logged.
    var bkgDraft: FfiBkgQsoDraft {
        bkgBuildQso(input: FfiBkgQsoInput(
            myGrid: bkgMyGrid,
            theirGrid: theirGrid,
            sentMyGrid: bkgForm.sentMyGrid,
            receivedTheirGrid: bkgForm.receivedTheirGrid,
            viaSatellite: bkgForm.viaSatellite,
            satName: bkgForm.satName.nonEmpty
        ))
    }

    /// Grids, the two "sent in CW" switches, the satellite toggle and the
    /// 4-grid corner toggle. Shown under the callsign card in a BKG session.
    var bkgExchangeCard: some View {
        let rules = bkgRules()
        let myGridCheck = bkgCheckGrid(grid: bkgMyGrid)
        let sessionId = sessionManager?.activeSession?.id

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("BKG", systemImage: "square.grid.2x2")
                    .font(.subheadline.weight(.semibold))
                Text("\(rules.mode) · \(rules.band)" + (bkgForm.viaSatellite ? " ↑ \(rules.satBandRx) ↓" : ""))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    bkgForm.showExport = true
                } label: {
                    Label("Check & Export", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            if let myGrid = myGridCheck.grid {
                bkgGridRow(title: "My grid", value: myGrid)
            } else {
                bkgMyGridEditor(problem: myGridCheck.problem)
            }

            HStack(spacing: 8) {
                Text("Their grid")
                    .font(.subheadline)
                Spacer()
                TextField("CM87xk", text: $theirGrid)
                    .font(.body.monospaced())
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 120)
                    .accessibilityLabel("Their 6-character grid")
            }

            Toggle("I sent my grid in CW", isOn: $bkgForm.sentMyGrid)
            Toggle("They sent theirs", isOn: $bkgForm.receivedTheirGrid)

            Divider()

            Toggle("Linear V/U satellite", isOn: $bkgForm.viaSatellite)
            if bkgForm.viaSatellite {
                HStack(spacing: 8) {
                    Text("Satellite")
                        .font(.subheadline)
                    Spacer()
                    TextField("RS-44", text: $bkgForm.satName)
                        .font(.body.monospaced())
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .frame(maxWidth: 120)
                }
            }

            Toggle("At a 4-grid corner", isOn: bkgCornerBinding)
                .disabled(myGridCheck.grid == nil)
            if !bkgForm.cornerGrids.isEmpty {
                Text(bkgForm.cornerGrids.joined(separator: " · "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if myGridCheck.grid != nil, !theirGrid.isEmpty, let problem = bkgDraft.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .font(.subheadline)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: sessionId) { await loadBKGCorner() }
        .sheet(isPresented: $bkgForm.showExport) {
            if let session = sessionManager?.activeSession {
                BKGExportSheet(
                    sessionId: session.id,
                    callsign: session.stationCallsign?.nonEmpty ?? session.myCallsign
                )
            }
        }
    }

    private func bkgGridRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    /// The session started with a short (or no) grid: take a 6-character one here.
    private func bkgMyGridEditor(problem: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("My grid")
                    .font(.subheadline)
                Spacer()
                TextField("CM87xk", text: $bkgForm.myGridDraft)
                    .font(.body.monospaced())
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 120)
                    .onSubmit { commitBKGMyGrid() }
                Button("Set") { commitBKGMyGrid() }
                    .buttonStyle(.bordered)
                    .disabled(bkgCheckGrid(grid: bkgForm.myGridDraft).grid == nil)
            }
            Label(
                "This session's grid is \(bkgMyGrid.isEmpty ? "not set" : bkgMyGrid). BKG needs 6 characters.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    private func commitBKGMyGrid() {
        guard let grid = bkgCheckGrid(grid: bkgForm.myGridDraft).grid else {
            return
        }
        sessionManager?.updateMyGrid(grid)
        bkgForm.myGridDraft = ""
    }

    /// On: store the four grids around the corner nearest the session grid.
    /// Off: clear them. The grids come from Rust; they go out as MY_VUCC_GRIDS.
    private var bkgCornerBinding: Binding<Bool> {
        Binding(
            get: { !bkgForm.cornerGrids.isEmpty },
            set: { isOn in
                let grids = isOn ? bkgCornerGrids(grid: bkgMyGrid) : []
                if isOn, grids.isEmpty {
                    ToastManager.shared.error("No 4-grid corner near \(bkgMyGrid)")
                    return
                }
                bkgForm.cornerGrids = grids
                Task { await saveBKGCorner(grids) }
            }
        )
    }

    private func bkgSessionKey() -> String? {
        sessionManager?.activeSession.map { SwiftDataStoreImporter.uuid($0.id) }
    }

    private func loadBKGCorner() async {
        guard let key = bkgSessionKey(), let store = try? await CwStoreProvider.shared.store() else {
            bkgForm.cornerGrids = []
            return
        }
        bkgForm.cornerGrids = (try? BkgApi(store: store).cornerGrids(sessionId: key)) ?? []
    }

    private func saveBKGCorner(_ grids: [String]) async {
        guard let key = bkgSessionKey(), let store = try? await CwStoreProvider.shared.store() else {
            ToastManager.shared.error("Couldn't save the corner — the log store is unavailable")
            return
        }
        do {
            bkgForm.cornerGrids = try BkgApi(store: store).setCornerGrids(sessionId: key, grids: grids)
        } catch {
            bkgForm.cornerGrids = []
            ToastManager.shared.error("Couldn't save the 4-grid corner")
        }
    }
}
