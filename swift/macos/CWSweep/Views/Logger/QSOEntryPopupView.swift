import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - QSOEntryPopupView

/// Persistent popup window for adding QSOs with dedicated fields for each part
/// of a QSO, plus a quick entry text field with the same functionality as
/// ParsedEntryView (callsign lookups, parsed field summary, etc.).
struct QSOEntryPopupView: View {
    // MARK: Internal

    enum HistoryDirection { case up, down }

    @Environment(\.modelContext) var modelContext

    @State var entryDXCCEntity: String?
    @State var entryNeededStatus: NeededStatus = .unknown
    @State var callsignInfo: CallsignInfo?
    @State var poloEntry: PoloNotesEntry?
    @State var combinedEmoji: String?
    @State var callsignLookupTask: Task<Void, Never>?
    @State var lookupStatus: String?

    @State var dxccLookup = DXCCLookupService()
    @State var neededChecker = DXCCNeededChecker()

    @State var quickEntryText = ""
    @State var parsedResult: QuickEntryResult?
    @State var history: [String] = []
    @State var historyIndex: Int?
    @FocusState var isQuickEntryFocused: Bool

    @State var callsign = ""
    @State var frequency = ""
    @State var mode = "CW"
    @State var band = ""
    @State var rstSent = "599"
    @State var rstReceived = "599"
    @State var theirGrid = ""
    @State var theirPark = ""
    @State var state = ""
    @State var notes = ""
    @State var name = ""
    @State var qth = ""
    @State var power = ""

    @State var lastLoggedCallsign: String?
    @State var logCount = 0
    @State var cachedActiveSession: LoggingSession?

    @Environment(SpotEntryBridge.self) var spotBridge

    var currentCallsign: String {
        (try? KeychainHelper.shared.readString(
            for: KeychainHelper.Keys.currentCallsign
        )) ?? ""
    }

    var canLog: Bool {
        !resolvedCallsign.isEmpty
    }

    var resolvedCallsign: String {
        if !callsign.isEmpty {
            return callsign.uppercased()
        }
        return parsedResult?.callsign.uppercased() ?? ""
    }

    var hasCallsignDetails: Bool {
        callsignInfo?.license != nil
            || callsignInfo?.qrzResult != nil
            || poloEntry != nil
            || combinedEmoji != nil
            || (callsignInfo?.previousQSOCount ?? 0) > 0
            || !memberships.isEmpty
    }

    /// Server enrichment memberships (CWops, future SKCC, …) for the
    /// callsign currently in `resolvedCallsign`. Read synchronously from
    /// the in-memory cache.
    var memberships: [CallsignEnrichmentMembership] {
        guard !resolvedCallsign.isEmpty else {
            return []
        }
        return CallsignEnrichmentStore.shared
            .lookup(callsign: resolvedCallsign)?
            .memberships ?? []
    }

    var resolvedBand: String? {
        if !band.isEmpty {
            return band
        }
        if let parsedBand = parsedResult?.band {
            return parsedBand
        }
        if let freq = resolvedFrequency {
            return BandUtilities.deriveBand(from: freq * 1_000)
        }
        return nil
    }

    var resolvedFrequency: Double? {
        if let manualFreq = Double(frequency), manualFreq > 0 {
            return manualFreq
        }
        return parsedResult?.frequency
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    quickEntrySection
                    callsignInfoSection
                    dedicatedFieldsSection
                }
                .padding()
            }
            Divider()
            footerSection
        }
        .frame(minWidth: 520, minHeight: 480)
        .onAppear { isQuickEntryFocused = true }
        .task {
            await dxccLookup.loadIfNeeded()
            await neededChecker.loadWorkedEntities(
                container: modelContext.container
            )
            loadActiveSession()
        }
        .onChange(of: spotBridge.pendingSpot?.id) { _, newId in
            guard newId != nil,
                  let spot = spotBridge.pendingSpot
            else {
                return
            }
            populateFromSpot(spot)
            spotBridge.pendingSpot = nil
        }
    }

    // MARK: - Dedicated Fields Section

    var dedicatedFieldsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dedicated Fields")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Text("Override quick entry or fill in directly")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                fieldRow("Callsign", text: $callsign, field: .callsign)
                    .onChange(of: callsign) { _, newValue in
                        if !newValue.isEmpty {
                            updateCallsignLookup(
                                callsign: newValue.uppercased(),
                                band: resolvedBand
                            )
                        } else if quickEntryText.isEmpty {
                            clearCallsignLookup()
                        }
                    }

                fieldRow("Frequency", text: $frequency, field: .frequency)
                    .onChange(of: frequency) { _, newValue in
                        autoDeriveBand(from: newValue)
                    }

                GridRow {
                    Text("Mode")
                        .frame(width: 80, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $mode) {
                        Text("CW").tag("CW")
                        Text("SSB").tag("SSB")
                        Text("FT8").tag("FT8")
                        Text("FT4").tag("FT4")
                        Text("RTTY").tag("RTTY")
                        Text("JTTY").tag("JTTY")
                        Text("AM").tag("AM")
                        Text("FM").tag("FM")
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                fieldRow("Band", text: $band, field: .band)

                GridRow {
                    Text("RST Sent")
                        .frame(width: 80, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("599", text: $rstSent)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .rstSent)
                            .frame(width: 80)
                        Text("RST Rcvd")
                            .foregroundStyle(.secondary)
                        TextField("599", text: $rstReceived)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .rstReceived)
                            .frame(width: 80)
                    }
                }

                fieldRow("Their Grid", text: $theirGrid, field: .theirGrid)
                fieldRow("Their Park", text: $theirPark, field: .theirPark)
                fieldRow("State", text: $state, field: .state)
                fieldRow("Name", text: $name, field: .name)
                fieldRow("QTH", text: $qth, field: .qth)
                fieldRow("Power (W)", text: $power, field: .power)
                fieldRow("Notes", text: $notes, field: .notes)
            }
        }
    }

    // MARK: Private

    private enum EntryField: Hashable {
        case callsign
        case frequency
        case mode
        case band
        case rstSent
        case rstReceived
        case theirGrid
        case theirPark
        case state
        case notes
        case name
        case qth
        case power
    }

    @FocusState private var focusedField: EntryField?

    private func fieldRow(
        _ label: String,
        text: Binding<String>,
        field: EntryField
    ) -> some View {
        GridRow {
            Text(label)
                .frame(width: 80, alignment: .trailing)
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: field)
        }
    }
}
