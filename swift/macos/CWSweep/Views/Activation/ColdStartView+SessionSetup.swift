import CarrierWaveData
import SwiftUI

// MARK: - ColdStartView + SessionSetup

extension ColdStartView {
    var sessionSetupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            equipmentGrid
            powerGridAttendeesRow
            operatorsRow
            roveToggle
            notesField
        }
        .padding(12)
    }

    // MARK: - Equipment Grid (2x2)

    private var equipmentGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                radioField
                antennaField
            }
            GridRow {
                keyField
                micField
            }
        }
    }

    private var radioField: some View {
        LabeledContent("Radio") {
            HStack(spacing: 6) {
                Text(radioManager.connectedRadioName ?? "No radio")
                Circle()
                    .fill(radioManager.isConnected ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var antennaField: some View {
        LabeledContent("Antenna") {
            EquipmentPickerField(selection: $selectedAntenna, type: .antenna)
        }
    }

    private var keyField: some View {
        LabeledContent("Key") {
            EquipmentPickerField(selection: $selectedKey, type: .key)
        }
    }

    private var micField: some View {
        LabeledContent("Mic") {
            EquipmentPickerField(selection: $selectedMic, type: .mic)
        }
    }

    // MARK: - Power / Grid / Attendees Row

    private var powerGridAttendeesRow: some View {
        HStack(spacing: 16) {
            LabeledContent("Power") {
                HStack(spacing: 4) {
                    TextField("", text: $powerText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("W")
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Grid") {
                TextField("e.g. FN31pr", text: $myGrid)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
            LabeledContent("Attendees") {
                TextField("Count", text: $attendeesText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
            }
            Spacer()
        }
    }

    // MARK: - Additional Operators

    private var operatorsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Operators")
                .font(.caption)
                .foregroundStyle(.secondary)
            OperatorChipsView(
                operators: $additionalOperators,
                myCallsign: fullCallsign
            )
        }
    }

    // MARK: - Rove Toggle

    private var roveToggle: some View {
        Toggle("This is a rove", isOn: $isRove)
    }

    // MARK: - Session Notes

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Session Notes")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Notes for this activation...", text: $sessionNotes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2 ... 4)
        }
    }
}
