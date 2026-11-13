import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SessionsComposerView

/// Inline session composer. Lives in the Sessions sidebar area, between
/// `SessionsLandingView` (idle intent grid) and `CustomLayoutView` (active
/// session). Replaces the deprecated `MacSessionStartSheet` modal.
///
/// Two-column layout: form panels (left) and a Last Session preview rail
/// (right) so the page reads as a dense operator console rather than a sparse
/// floating form.
///
/// Auto-populates as much as possible from the operator's environment:
/// - Callsign from Keychain (`KeychainHelper.Keys.currentCallsign`)
/// - Grid from `UserDefaults` (`operatorGrid`)
/// - Frequency + mode from the active `RadioSession`'s slot state
/// - Rig name from `RadioManager.connectedRadioName`
/// - Power / antenna / key / mic / notes from the most recent matching `LoggingSession`
struct SessionsComposerView: View {
    // MARK: Internal

    let intent: SessionsIntent
    let radioManager: RadioManager
    let sessionManager: MacSessionManager
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            ScrollView {
                composerBody
            }
            Divider().opacity(0.4)
            footer
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task { await loadDefaults() }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @AppStorage("recentPOTAParks") private var recentParksData = ""

    @State private var callsign = ""
    @State private var grid = ""
    @State private var mode = "CW"
    @State private var frequency: Double?
    @State private var parkReference = ""
    @State private var parkName = ""
    @State private var sotaReference = ""
    @State private var wwffReference = ""
    @State private var contestDefinition: ContestDefinition?
    @State private var power: String = ""
    @State private var antenna: String?
    @State private var key: String?
    @State private var mic: String?
    @State private var notes: String = ""
    @State private var lastSession: LoggingSession?
    @State private var lastSessionQSOCount: Int = 0
    @State private var lastRig: String?
}

// MARK: - Layout

private extension SessionsComposerView {
    var composerBody: some View {
        HStack(alignment: .top, spacing: 16) {
            formColumn
                .frame(maxWidth: 560)
            previewColumn
                .frame(width: 280)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: 920, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    var formColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            primaryFieldPanel
                .zIndex(1) // keep ParkSearchField / ContestSearchField overlays above siblings
            radioPanel
            operatorPanel
            equipmentPanel
            notesPanel
            if let reason = startDisabledReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    var previewColumn: some View {
        LastSessionPreviewPanel(
            intent: intent,
            session: lastSession,
            qsoCount: lastSessionQSOCount,
            onReuseEquipment: { ant, newKey, newMic in
                if let ant {
                    antenna = ant
                }
                if let newKey {
                    key = newKey
                }
                if let newMic {
                    mic = newMic
                }
            }
        )
    }

    var header: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Back to intents")

            Image(systemName: intent.systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(intent.tint)
                .frame(width: 32, height: 32)
                .background(intent.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(intent.label)
                    .font(.title2.weight(.semibold))
                Text(headerSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    var footer: some View {
        HStack(spacing: 10) {
            if let radioName = radioManager.connectedRadioName {
                RadioStatusChip(name: radioName)
            } else {
                NoRadioChip()
            }
            Spacer()
            Button("Start") { start() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(intent.tint)
                .disabled(!canStart)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    var headerSubtitle: String {
        switch intent {
        case .activate: "POTA, SOTA or WWFF — pick a reference and go"
        case .hunt: "Casual log with spots focus"
        case .casual: "Ragchew, random QSOs, no rules"
        case .contest: "Pick a contest to begin scoring"
        }
    }
}

// MARK: - Panels

private extension SessionsComposerView {
    @ViewBuilder
    var primaryFieldPanel: some View {
        switch intent {
        case .activate:
            ComposerPanel(title: "REFERENCE", systemImage: "mappin.and.ellipse", tint: intent.tint) {
                activateFields
            }
        case .contest:
            ComposerPanel(title: "CONTEST", systemImage: "trophy", tint: intent.tint) {
                ContestSearchField(selectedContest: $contestDefinition)
            }
        case .hunt,
             .casual:
            EmptyView()
        }
    }

    var activateFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            ParkSearchField(
                selectedReference: $parkReference,
                onParkSelected: handleParkSelected
            )
            if !recentParks.isEmpty {
                RecentChipStrip(
                    items: recentParks,
                    label: { $0.reference },
                    onSelect: { applyRecentPark($0) }
                )
            }
            HStack(spacing: 8) {
                ManualRefField(label: "SOTA", placeholder: "W6/SS-220", text: $sotaReference)
                ManualRefField(label: "WWFF", placeholder: "KFF-1234", text: $wwffReference)
            }
        }
    }

    var radioPanel: some View {
        ComposerPanel(title: "RADIO", systemImage: "antenna.radiowaves.left.and.right", tint: .blue) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    FrequencyReadout(frequency: $frequency, fromRadio: hasRadioFreq)
                    ModeReadout(mode: $mode, fromRadio: hasRadioMode)
                    PowerField(text: $power)
                    Spacer()
                }
                if let band = derivedBand {
                    BandChip(band: band)
                }
            }
        }
    }

    var operatorPanel: some View {
        ComposerPanel(title: "OPERATOR", systemImage: "person.fill", tint: .indigo) {
            HStack(spacing: 12) {
                MonoTextField(label: "CALL", text: $callsign, width: 160, placeholder: "W6JY")
                MonoTextField(label: "GRID", text: $grid, width: 120, placeholder: "DM03")
                Spacer()
            }
        }
    }

    var equipmentPanel: some View {
        ComposerPanel(title: "EQUIPMENT", systemImage: "wrench.and.screwdriver", tint: .teal) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    ComposerEquipmentPicker(type: .antenna, selection: $antenna, width: 168)
                    ComposerEquipmentPicker(type: .key, selection: $key, width: 152)
                    ComposerEquipmentPicker(type: .mic, selection: $mic, width: 152)
                    Spacer()
                }
                rigRow
            }
        }
    }

    @ViewBuilder
    var rigRow: some View {
        if let rigName = radioManager.connectedRadioName ?? lastRig {
            HStack(spacing: 6) {
                Text("RIG")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .leading)
                Text(rigName)
                    .font(.body.monospaced())
                if radioManager.connectedRadioName != nil {
                    FromRadioBadge()
                }
                Spacer()
            }
        }
    }

    var notesPanel: some View {
        ComposerPanel(title: "NOTES", systemImage: "text.alignleft", tint: .gray) {
            ComposerNotesField(text: $notes)
        }
    }

    var hasRadioFreq: Bool {
        radioManager.slotStates.values.contains { $0.frequency > 0 }
    }

    var hasRadioMode: Bool {
        radioManager.slotStates.values.contains { !$0.mode.isEmpty }
    }

    var derivedBand: String? {
        guard let frequency, frequency > 0 else {
            return nil
        }
        return BandUtilities.deriveBand(from: frequency * 1_000.0)
    }
}

// MARK: - Validation

private extension SessionsComposerView {
    var canStart: Bool {
        startDisabledReason == nil
    }

    var startDisabledReason: String? {
        if callsign.trimmingCharacters(in: .whitespaces).count < 3 {
            return "Enter a callsign of 3 or more characters."
        }
        if intent == .activate,
           parkReference.trimmingCharacters(in: .whitespaces).isEmpty,
           sotaReference.trimmingCharacters(in: .whitespaces).isEmpty,
           wwffReference.trimmingCharacters(in: .whitespaces).isEmpty
        {
            return "Pick a reference (POTA park, SOTA summit, or WWFF area)."
        }
        if intent == .contest, contestDefinition == nil {
            return "Pick a contest to begin scoring."
        }
        return nil
    }

    var activationType: ActivationType {
        switch intent {
        case .activate:
            if !parkReference.trimmingCharacters(in: .whitespaces).isEmpty {
                return .pota
            }
            if !sotaReference.trimmingCharacters(in: .whitespaces).isEmpty {
                return .sota
            }
            if !wwffReference.trimmingCharacters(in: .whitespaces).isEmpty {
                return .wwff
            }
            return .pota
        case .hunt,
             .casual,
             .contest:
            return .casual
        }
    }
}

// MARK: - Recents

private extension SessionsComposerView {
    struct RecentPark: Identifiable {
        let reference: String
        let name: String

        var id: String {
            reference
        }
    }

    var recentParks: [RecentPark] {
        struct StoredPark: Codable {
            let reference: String
            let name: String
        }
        guard !recentParksData.isEmpty,
              let data = recentParksData.data(using: .utf8),
              let stored = try? JSONDecoder().decode([StoredPark].self, from: data)
        else {
            return []
        }
        return stored.prefix(4).map { RecentPark(reference: $0.reference, name: $0.name) }
    }

    func applyRecentPark(_ park: RecentPark) {
        parkReference = park.reference
        parkName = park.name
    }

    func handleParkSelected(reference: String, name: String, parkGrid: String?) {
        parkName = name
        if grid.isEmpty, let parkGrid {
            grid = parkGrid
        }
    }
}

// MARK: - Defaults

private extension SessionsComposerView {
    @MainActor
    func loadDefaults() async {
        callsign = readKeychainCallsign()
            ?? UserDefaults.standard.string(forKey: "operatorCallsign") ?? ""
        grid = UserDefaults.standard.string(forKey: "operatorGrid") ?? ""

        if let radioState = radioManager.slotStates.values.first(where: { $0.frequency > 0 }) {
            frequency = radioState.frequency
        }
        if let radioState = radioManager.slotStates.values.first(where: { !$0.mode.isEmpty }) {
            mode = radioState.mode
        }
        await loadLastSessionDefaults()
    }

    func readKeychainCallsign() -> String? {
        let raw = try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.currentCallsign)
        return raw?.isEmpty == false ? raw : nil
    }

    @MainActor
    func loadLastSessionDefaults() async {
        let activationRaw = activationType.rawValue
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.activationTypeRawValue == activationRaw },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let last = try? modelContext.fetch(descriptor).first else {
            return
        }
        lastSession = last
        lastSessionQSOCount = last.qsoCount
        if power.isEmpty, let lastPower = last.power {
            power = String(lastPower)
        }
        if antenna == nil, let lastAntenna = last.myAntenna, !lastAntenna.isEmpty {
            antenna = lastAntenna
        }
        if key == nil, let lastKey = last.myKey, !lastKey.isEmpty {
            key = lastKey
        }
        if mic == nil, let lastMic = last.myMic, !lastMic.isEmpty {
            mic = lastMic
        }
        lastRig = last.myRig
    }
}

// MARK: - Start

private extension SessionsComposerView {
    func start() {
        let trimmedCall = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let trimmedGrid = grid.trimmingCharacters(in: .whitespaces).uppercased()
        let parkRef = parkReference.trimmingCharacters(in: .whitespaces).uppercased()
        let sotaRef = sotaReference.trimmingCharacters(in: .whitespaces).uppercased()
        let wwffRef = wwffReference.trimmingCharacters(in: .whitespaces).uppercased()
        let category = contestDefinition?.categories.first
        let session = sessionManager.startSession(
            myCallsign: trimmedCall,
            mode: mode,
            frequency: frequency,
            activationType: activationType,
            parkReference: parkRef.isEmpty ? nil : parkRef,
            sotaReference: sotaRef.isEmpty ? nil : sotaRef,
            wwffReference: wwffRef.isEmpty ? nil : wwffRef,
            myGrid: trimmedGrid.isEmpty ? nil : trimmedGrid,
            power: Int(power),
            contestId: contestDefinition?.id,
            contestCategory: category?.id,
            contestPower: category?.powerClasses.first
        )
        applySessionExtras(to: session)
        persistOperatorDefaults(callsign: trimmedCall, grid: trimmedGrid)
    }

    func applySessionExtras(to session: LoggingSession) {
        if let radioName = radioManager.connectedRadioName {
            session.myRig = radioName
        } else if session.myRig == nil, let lastRig {
            session.myRig = lastRig
        }
        if let antenna, !antenna.isEmpty {
            session.myAntenna = antenna
        }
        if let key, !key.isEmpty {
            session.myKey = key
        }
        if let mic, !mic.isEmpty {
            session.myMic = mic
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            session.notes = trimmedNotes
        }
        session.cloudDirtyFlag = true
        try? modelContext.save()
    }

    func persistOperatorDefaults(callsign: String, grid: String) {
        if !callsign.isEmpty {
            UserDefaults.standard.set(callsign, forKey: "operatorCallsign")
        }
        if !grid.isEmpty {
            UserDefaults.standard.set(grid, forKey: "operatorGrid")
        }
    }
}
