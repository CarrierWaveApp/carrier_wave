import CarrierWaveData
import SwiftUI

// MARK: - Display Sections

extension EquipmentItemDetailView {
    func specsSection(_ item: EquipmentItem) -> some View {
        Section("Specifications") {
            if let power = item.maxPowerWatts {
                specRow(
                    label: "Max Power",
                    value: "\(power) W"
                )
            }
            specRow(
                label: "Portability",
                value: item.portability.displayName
            )
            HStack {
                Text("Weight")
                Spacer()
                TextField("oz", text: Binding(
                    get: { item.weightOunces.map { String($0) } ?? "" },
                    set: {
                        item.weightOunces = Int($0)
                        saveAndNotify()
                    }
                ))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                Text("oz").foregroundStyle(.secondary)
            }
            if item.isCustom {
                specRow(label: "Source", value: "Custom")
            } else {
                specRow(label: "Catalog ID", value: item.catalogId)
            }
        }
    }

    func bandsSection(_ item: EquipmentItem) -> some View {
        Group {
            if !item.bands.isEmpty || !item.modes.isEmpty {
                Section("Bands & Modes") {
                    if !item.bands.isEmpty {
                        bandRow(item.bands)
                    }
                    if !item.modes.isEmpty {
                        modeRow(item.modes)
                    }
                }
            }
        }
    }

    func notesSection(_ item: EquipmentItem) -> some View {
        Section("Notes") {
            TextField(
                "Add notes about this equipment...",
                text: $editNotes,
                axis: .vertical
            )
            .lineLimit(3 ... 6)
            .onChange(of: editNotes) { _, newValue in
                item.notes = newValue.isEmpty ? nil : newValue
                saveAndNotify()
            }
        }
    }

    func statusSection(_ item: EquipmentItem) -> some View {
        Section {
            Toggle("Retired", isOn: Binding(
                get: { item.isRetired },
                set: { newValue in
                    item.isRetired = newValue
                    saveAndNotify()
                }
            ))

            if let acquired = item.acquiredDate {
                HStack {
                    Text("Acquired")
                    Spacer()
                    Text(Self.dateFormatter.string(from: acquired))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Added")
                Spacer()
                Text(Self.dateFormatter.string(from: item.createdAt))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Status")
        } footer: {
            if item.isRetired {
                Text(
                    "Retired equipment is hidden from pickers "
                        + "but preserved in your inventory."
                )
            }
        }
    }

    // MARK: - Components

    func specRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    func bandRow(_ bands: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bands")
                .font(.subheadline)
            FlowLayout(spacing: 6) {
                ForEach(bands, id: \.self) { band in
                    Text(band)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }

    func modeRow(_ modes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Modes")
                .font(.subheadline)
            FlowLayout(spacing: 6) {
                ForEach(modes, id: \.self) { mode in
                    Text(mode)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }
}
