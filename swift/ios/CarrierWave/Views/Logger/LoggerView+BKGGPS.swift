import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - LoggerView BKG Turf Wars GPS + header chip

/// Where the station is, for BKG Turf Wars. The grid and the 4-grid corner
/// come from the device GPS through Rust (`bkgPosition`), which also decides
/// whether the fix is close enough to a corner (`bkgRules().cornerRadiusM`).
///
/// Static (default): the first fix of a session fills a missing or short grid
/// and turns the corner on when the station is at one; after that only
/// "Use GPS" changes them. Live ("Follow GPS (rove)"): every fix moves the
/// grid and the corner with the station.
extension LoggerView {
    // MARK: Header chip

    /// The station's grid — or its 4-grid corner — in the session header.
    /// Tapping it offers "Use GPS now" and the live toggle. Also owns the
    /// BKG session lifecycle: both header layouts always render it, unlike
    /// the card, which can be scrolled or hidden.
    func bkgGridChip(_ session: LoggingSession) -> some View {
        let gridCheck = bkgCheckGrid(grid: session.myGrid ?? "")
        let corner = bkgForm.cornerGrids
        let text = corner.isEmpty ? (gridCheck.grid ?? "NO GRID") : corner.joined(separator: " ")

        return Menu {
            Button {
                applyBKGFix(force: true)
            } label: {
                Label("Use GPS now", systemImage: "location")
            }
            .disabled(sessionManager?.locationService.currentFix == nil)
            Toggle(isOn: bkgLiveGPSBinding) {
                Label("Follow GPS (rove)", systemImage: "location.fill")
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: corner.isEmpty ? "square.grid.2x2" : "square.grid.2x2.fill")
                    .font(.system(size: 9))
                Text(text)
                    .font(.caption.weight(.semibold).monospaced())
                if bkgForm.liveGPS {
                    Image(systemName: "location.fill")
                        .font(.system(size: 8))
                }
            }
            .foregroundStyle(gridCheck.grid == nil ? .orange : .primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((gridCheck.grid == nil ? Color.orange : Color.teal).opacity(0.2))
            .clipShape(Capsule())
        }
        .accessibilityLabel(
            corner.isEmpty ? "My grid \(text)" : "At the corner of \(corner.joined(separator: ", "))"
        )
        .task(id: session.id) { await startBKGSession(session.id) }
        .onChange(of: sessionManager?.locationService.currentFix) { _, _ in
            applyBKGFix(force: false)
        }
        .onChange(of: quickEntryResult?.theirGrid) { previous, parsed in
            syncBKGTheirGrid(from: parsed, previous: previous)
        }
    }

    // MARK: Card section

    /// GPS line in the BKG card: what the fix says, the corner distance, the
    /// live toggle and "Use GPS".
    var bkgGPSSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Follow GPS (rove)", isOn: bkgLiveGPSBinding)
            HStack(spacing: 8) {
                Image(systemName: "location")
                    .foregroundStyle(.secondary)
                Text(bkgGPSSummary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Use GPS") { applyBKGFix(force: true) }
                    .buttonStyle(.cwTinted)
                    .font(.caption)
                    .disabled(bkgForm.position == nil)
            }
        }
    }

    private var bkgGPSSummary: String {
        guard let position = bkgForm.position else {
            if let error = sessionManager?.locationService.locationError {
                return "GPS: \(error)"
            }
            return "Waiting for GPS…"
        }
        guard position.cornerDistanceM >= 0 else {
            return "GPS \(position.grid) · no corner here"
        }
        let distance = Self.formatBKGDistance(position.cornerDistanceM)
        let label = position.atCorner ? "at corner" : "corner"
        return "GPS \(position.grid) · \(label) \(distance)"
    }

    static func formatBKGDistance(_ meters: Double) -> String {
        meters < 1_000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1_000)
    }

    // MARK: Live toggle

    private var bkgLiveGPSBinding: Binding<Bool> {
        Binding(
            get: { bkgForm.liveGPS },
            set: { isOn in
                bkgForm.liveGPS = isOn
                Task { await saveBKGLiveGPS(isOn) }
                if isOn {
                    applyBKGFix(force: true)
                }
            }
        )
    }

    private func saveBKGLiveGPS(_ isOn: Bool) async {
        guard let key = bkgSessionKey(), let store = try? await CwStoreProvider.shared.store() else {
            return
        }
        try? BkgApi(store: store).setLiveGps(sessionId: key, on: isOn)
    }

    // MARK: Applying fixes

    /// Load the session's corner and live flag, then apply the current fix.
    private func startBKGSession(_ sessionId: UUID) async {
        await loadBKGCorner()
        if let key = bkgSessionKey(), let store = try? await CwStoreProvider.shared.store() {
            bkgForm.liveGPS = (try? BkgApi(store: store).liveGps(sessionId: key)) ?? false
        } else {
            bkgForm.liveGPS = false
        }
        if bkgForm.gpsAppliedSession != sessionId {
            bkgForm.position = nil
        }
        applyBKGFix(force: false)
    }

    /// Turn the latest GPS fix into a grid and corner for the session.
    /// `force` (the "Use GPS" button) always applies it.
    func applyBKGFix(force: Bool) {
        guard isBKGSession, let session = sessionManager?.activeSession,
              let fix = sessionManager?.locationService.currentFix,
              let position = bkgPosition(latitude: fix.latitude, longitude: fix.longitude)
        else {
            return
        }
        bkgForm.position = position

        let firstFix = bkgForm.gpsAppliedSession != session.id
        guard force || bkgForm.liveGPS || firstFix else {
            return
        }
        bkgForm.gpsAppliedSession = session.id

        let gridIsValid = bkgCheckGrid(grid: session.myGrid ?? "").grid != nil
        // Static mode's first fix only fills a grid that can't be used yet.
        if force || bkgForm.liveGPS || !gridIsValid, session.myGrid?.uppercased() != position.grid {
            sessionManager?.updateMyGrid(position.grid)
        }

        let corner = position.atCorner ? position.nearestCornerGrids : []
        let shouldSetCorner: Bool = if force || bkgForm.liveGPS {
            corner != bkgForm.cornerGrids
        } else {
            // First fix: turn a corner on, never off.
            !corner.isEmpty && bkgForm.cornerGrids.isEmpty
        }
        guard shouldSetCorner else {
            return
        }
        if !corner.isEmpty {
            ToastManager.shared.success("At the \(corner.joined(separator: " · ")) corner")
        } else if !bkgForm.cornerGrids.isEmpty {
            ToastManager.shared.info("Left the 4-grid corner")
        }
        bkgForm.cornerGrids = corner
        Task { await saveBKGCorner(corner) }
    }

    // MARK: Command bar

    /// BKG field values for the contact being logged; `nil` outside a BKG
    /// session or while a grid is missing.
    var bkgLogFields: FfiBkgQsoFields? {
        isBKGSession ? bkgDraft.fields : nil
    }

    /// In a BKG Turf Wars session a grid typed in the command bar is the
    /// other station's grid: "W1AW EM73AB" fills it with the callsign, and a
    /// grid typed on its own ("EM73AB") is held for the next contact instead
    /// of changing the session's own grid. Returns `true` when it took the
    /// input.
    func handleBKGGridInput(_ input: String) -> Bool {
        guard isBKGSession, editingQSO == nil else {
            return false
        }
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.contains(" "), let grid = bkgCheckGrid(grid: trimmed).grid else {
            return false
        }
        theirGrid = grid
        callsignInput = ""
        quickEntryResult = nil
        quickEntryMultiResults = nil
        quickEntryTokens = []
        ToastManager.shared.info("Their grid \(grid)")
        return true
    }

    /// Keep the card's "Their grid" in step with a grid typed alongside the
    /// callsign, so the card shows it and the log button can enable.
    func syncBKGTheirGrid(from parsed: String?, previous: String?) {
        guard isBKGSession else {
            return
        }
        if let parsed = parsed?.nonEmpty {
            theirGrid = parsed.uppercased()
        } else if let previous = previous?.nonEmpty, theirGrid.uppercased() == previous.uppercased() {
            // The grid was deleted from the command bar.
            theirGrid = ""
        }
    }
}
