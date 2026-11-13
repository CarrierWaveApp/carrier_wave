import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - QSOEditSheet

/// Sheet for editing QSO fields from the Logs tab detail view.
///
/// Sections use iOS 17+ collapsible `Section(isExpanded:)` so the sheet stays scannable:
/// the core contact fields are expanded by default; less-common groups expand on demand.
struct QSOEditSheet: View {
    // MARK: Lifecycle

    init(qso: QSO, onSave: @escaping () -> Void) {
        self.qso = qso
        self.onSave = onSave

        _callsign = State(initialValue: qso.callsign)
        _originalCallsign = State(initialValue: qso.callsign)
        _band = State(initialValue: qso.band)
        _mode = State(initialValue: qso.mode)
        _frequencyText = State(
            initialValue: qso.frequency.map { FrequencyFormatter.format($0) } ?? ""
        )
        _timestamp = State(initialValue: qso.timestamp)
        _rstSent = State(initialValue: qso.rstSent ?? "")
        _rstReceived = State(initialValue: qso.rstReceived ?? "")
        _name = State(initialValue: qso.name ?? "")

        _myCallsign = State(initialValue: qso.myCallsign)
        _stationCallsign = State(initialValue: qso.stationCallsign ?? "")
        _myRig = State(initialValue: qso.myRig ?? "")
        _stationProfileName = State(initialValue: qso.stationProfileName ?? "")
        _myGrid = State(initialValue: qso.myGrid ?? "")
        _powerText = State(initialValue: qso.power.map { String($0) } ?? "")

        _theirGrid = State(initialValue: qso.theirGrid ?? "")
        _qth = State(initialValue: qso.qth ?? "")
        _state = State(initialValue: qso.state ?? "")
        _country = State(initialValue: qso.country ?? "")
        _dxccText = State(initialValue: qso.dxcc.map { String($0) } ?? "")
        _licenseClass = State(initialValue: qso.theirLicenseClass ?? "")

        _parkReference = State(initialValue: qso.parkReference ?? "")
        _theirParkReference = State(initialValue: qso.theirParkReference ?? "")
        _sotaRef = State(initialValue: qso.sotaRef ?? "")
        _wwffRef = State(initialValue: qso.wwffRef ?? "")
        _aoaCode = State(initialValue: qso.aoaCode ?? "")

        _contestName = State(initialValue: qso.contestName ?? "")
        _contestSerialSent = State(initialValue: qso.contestSerialSent.map { String($0) } ?? "")
        _contestSerialReceived = State(
            initialValue: qso.contestSerialReceived.map { String($0) } ?? ""
        )
        _contestExchangeSent = State(initialValue: qso.contestExchangeSent ?? "")
        _contestExchangeReceived = State(initialValue: qso.contestExchangeReceived ?? "")

        _satName = State(initialValue: qso.satName ?? "")
        _propMode = State(initialValue: qso.propMode ?? "")

        _notes = State(initialValue: qso.notes ?? "")

        _myStationExpanded = State(initialValue: false)
        _signalExpanded = State(initialValue: false)
        _theirLocationExpanded = State(initialValue: false)
        // Auto-expand the references section if the QSO carries any
        // activity reference, so users opening "Edit QSO" can immediately
        // see whether `sotaRef` (their summit) or `theirParkReference`
        // got tagged without having to tap the disclosure.
        _referencesExpanded = State(initialValue: Self.hasAnyReference(qso))
        _contestExpanded = State(initialValue: qso.contestName?.isEmpty == false)
        _satelliteExpanded = State(initialValue: qso.satName?.isEmpty == false)
        _notesExpanded = State(initialValue: qso.notes?.isEmpty == false)
    }

    // MARK: Internal

    // MARK: Internal - Section State

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    // Contact
    @State var callsign: String
    @State var originalCallsign: String
    @State var band: String
    @State var mode: String
    @State var frequencyText: String
    @State var timestamp: Date
    @State var name: String

    // My Station
    @State var myCallsign: String
    @State var stationCallsign: String
    @State var myRig: String
    @State var stationProfileName: String
    @State var myGrid: String
    @State var powerText: String

    // Signal
    @State var rstSent: String
    @State var rstReceived: String

    // Their Location
    @State var theirGrid: String
    @State var qth: String
    @State var state: String
    @State var country: String
    @State var dxccText: String
    @State var licenseClass: String

    // Activity References
    @State var parkReference: String
    @State var theirParkReference: String
    @State var sotaRef: String
    @State var wwffRef: String
    @State var aoaCode: String

    /// Operator's own summit reference for this QSO. Sourced from the
    /// parent `LoggingSession` because there's no per-QSO `mySotaRef`
    /// today — same place the ADIF exporter pulls `MY_SOTA_REF` from.
    /// Read-only here; surfaced so users can verify which QSOs in a
    /// SOTA session got an S2S tag (`sotaRef`) vs. those that didn't.
    @State var mySotaReference: String = ""

    // Contest
    @State var contestName: String
    @State var contestSerialSent: String
    @State var contestSerialReceived: String
    @State var contestExchangeSent: String
    @State var contestExchangeReceived: String

    // Satellite
    @State var satName: String
    @State var propMode: String

    /// Notes
    @State var notes: String

    // Disclosure state
    @State var myStationExpanded: Bool
    @State var signalExpanded: Bool
    @State var theirLocationExpanded: Bool
    @State var referencesExpanded: Bool
    @State var contestExpanded: Bool
    @State var satelliteExpanded: Bool
    @State var notesExpanded: Bool

    // Picker presentation state
    @State var activePickerCategory: EquipmentCategory?
    @State var showMyParkPicker = false
    @State var showTheirParkPicker = false
    @State var showSummitPicker = false
    @State var showWWFFPicker = false
    @State var showContestPicker = false
    @State var showDXCCPicker = false
    @State var showModePicker = false
    @State var showBandPicker = false
    @State var showStatePicker = false
    @State var selectedContest: ContestDefinition?

    let qso: QSO
    let onSave: () -> Void

    var isValid: Bool {
        let hasBand = !band.isEmpty
            || BandUtilities.deriveBand(
                from: FrequencyFormatter.parse(frequencyText).map { $0 * 1_000 }
            ) != nil
        return !callsign.trimmingCharacters(in: .whitespaces).isEmpty
            && !myCallsign.trimmingCharacters(in: .whitespaces).isEmpty
            && hasBand
            && !mode.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if let changeNote = qso.callsignChangeNote {
                    callsignChangeNoteSection(changeNote)
                }

                contactSection

                collapsibleSection("My Station", isExpanded: $myStationExpanded) {
                    myStationSectionContent
                }

                collapsibleSection("Signal", isExpanded: $signalExpanded) {
                    signalSectionContent
                }

                collapsibleSection("Their Location", isExpanded: $theirLocationExpanded) {
                    theirLocationSectionContent
                }

                collapsibleSection("Activity References", isExpanded: $referencesExpanded) {
                    referencesSectionContent
                }

                collapsibleSection("Contest", isExpanded: $contestExpanded) {
                    contestSectionContent
                }

                collapsibleSection("Satellite", isExpanded: $satelliteExpanded) {
                    satelliteSectionContent
                }

                collapsibleSection("Notes", isExpanded: $notesExpanded) {
                    notesSectionContent
                }
            }
            .navigationTitle("Edit QSO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
        .sheet(item: $activePickerCategory) { category in
            InventoryPickerSheet(
                category: category,
                selection: equipmentBinding(for: category)
            )
            .landscapeAdaptiveDetents(portrait: [.medium])
        }
        .sheet(isPresented: $showMyParkPicker) {
            ParkPickerSheet(
                selectedParks: parkReference.nonEmpty.map { [$0] } ?? [],
                userGrid: myGrid.nonEmpty,
                onAdd: { park in
                    parkReference = park.reference
                    showMyParkPicker = false
                },
                onDismiss: { showMyParkPicker = false }
            )
        }
        .sheet(isPresented: $showTheirParkPicker) {
            ParkPickerSheet(
                selectedParks: theirParkReference.nonEmpty.map { [$0] } ?? [],
                userGrid: theirGrid.nonEmpty ?? myGrid.nonEmpty,
                onAdd: { park in
                    theirParkReference = park.reference
                    showTheirParkPicker = false
                },
                onDismiss: { showTheirParkPicker = false }
            )
        }
        .sheet(isPresented: $showSummitPicker) {
            SummitPickerSheet(
                userGrid: myGrid.nonEmpty,
                onSelect: { summit in
                    sotaRef = summit.code
                    showSummitPicker = false
                },
                onDismiss: { showSummitPicker = false }
            )
        }
        .sheet(isPresented: $showWWFFPicker) {
            WWFFReferencePickerSheet(
                userGrid: myGrid.nonEmpty,
                onSelect: { ref in
                    wwffRef = ref.reference
                    showWWFFPicker = false
                },
                onDismiss: { showWWFFPicker = false }
            )
        }
        .sheet(isPresented: $showContestPicker, onDismiss: syncContestNameFromPicker) {
            contestPickerSheetContent
        }
        .sheet(isPresented: $showDXCCPicker) {
            DXCCPickerSheet(
                currentNumber: Int(dxccText),
                onSelect: { entity in
                    applyDXCCSelection(entity)
                    showDXCCPicker = false
                },
                onDismiss: { showDXCCPicker = false }
            )
        }
        .sheet(isPresented: $showModePicker) {
            ModePickerSheet(
                currentCode: mode,
                onSelect: { code in
                    mode = code
                    showModePicker = false
                },
                onDismiss: { showModePicker = false }
            )
        }
        .sheet(isPresented: $showBandPicker) {
            BandPickerSheet(
                currentCode: band,
                onSelect: { code in
                    band = code
                    showBandPicker = false
                },
                onDismiss: { showBandPicker = false }
            )
        }
        .sheet(isPresented: $showStatePicker) {
            StatePickerSheet(
                currentCode: state,
                onSelect: { entry in
                    applyStateSelection(entry)
                    showStatePicker = false
                },
                onSelectCustom: { code in
                    state = code
                    showStatePicker = false
                },
                onDismiss: { showStatePicker = false }
            )
        }
        .task {
            loadParentSessionContext()
            await loadContestDefinitionIfNeeded()
        }
    }

    static func hasAnyReference(_ qso: QSO) -> Bool {
        qso.parkReference?.isEmpty == false
            || qso.theirParkReference?.isEmpty == false
            || qso.sotaRef?.isEmpty == false
            || qso.wwffRef?.isEmpty == false
            || qso.aoaCode?.isEmpty == false
    }
}

// MARK: - Picker helpers

extension QSOEditSheet {
    func callsignChangeNoteSection(_ note: String) -> some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Apply a State/Province picker selection. If the country field is empty,
    /// populate it from the selection so the two stay consistent.
    func applyStateSelection(_ entry: ADIFCatalog.StateProvince) {
        state = entry.code
        if country.trimmingCharacters(in: .whitespaces).isEmpty {
            country = entry.country.rawValue
        }
    }

    /// Apply a DXCC picker selection back to the edit sheet's state.
    /// Populates both the DXCC number and the country name so the two fields
    /// stay consistent after a pick.
    func applyDXCCSelection(_ entity: DXCCEntityRef) {
        dxccText = String(entity.number)
        if country.trimmingCharacters(in: .whitespaces).isEmpty {
            country = entity.name
        }
    }

    /// Backing binding for InventoryPickerSheet.
    /// Currently only Rig is wired (ADIF `MY_RIG`); other categories funnel into
    /// `myRig` as well, since the QSO model only tracks a single rig string.
    func equipmentBinding(for _: EquipmentCategory) -> Binding<String?> {
        Binding(
            get: { myRig.nonEmpty },
            set: { myRig = $0 ?? "" }
        )
    }

    /// Propagate picker selection back to the `contestName` state (which is the
    /// authoritative id stored on `QSO.contestName`).
    func syncContestNameFromPicker() {
        if let definition = selectedContest {
            contestName = definition.id
        }
    }

    /// Resolve `contestName` → `ContestDefinition` so the picker highlights the
    /// current selection when the edit sheet opens.
    func loadContestDefinitionIfNeeded() async {
        let currentId = contestName.trimmingCharacters(in: .whitespaces)
        guard !currentId.isEmpty, selectedContest == nil else {
            return
        }
        if let definition = await ContestDefinitions.definition(id: currentId) {
            selectedContest = definition
        }
    }
}
