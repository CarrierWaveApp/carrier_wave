import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SessionStartSheet Gear Reminders

extension SessionStartSheet {
    var gearRemindersSection: some View {
        Section {
            DisclosureGroup(
                "Pack Checklist",
                isExpanded: $showGearReminders
            ) {
                if selectedRadio != nil || selectedAntenna != nil {
                    connectorTaggingRows
                }

                ForEach(generatedReminders) { reminder in
                    gearReminderRow(reminder)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        } header: {
            HStack {
                Text("Don't Forget")
                Spacer()
                if !checkedReminderIds.isEmpty {
                    let total = generatedReminders.count
                    Text("\(checkedReminderIds.count)/\(total)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if selectedRadio == nil, selectedAntenna == nil {
                Text("Select equipment above for tailored reminders")
            } else {
                Text("Tap items as you pack — resets each session")
            }
        }
    }

    // MARK: - Connector Tagging

    @ViewBuilder
    private var connectorTaggingRows: some View {
        if let radio = selectedRadio {
            connectorRow(
                label: radio,
                connector: radioConnector,
                onChange: { newType in
                    radioConnector = newType
                    GearConnectorStorage.setConnector(
                        newType, for: radio
                    )
                }
            )
        }
        if let antenna = selectedAntenna {
            connectorRow(
                label: antenna,
                connector: antennaConnector,
                onChange: { newType in
                    antennaConnector = newType
                    GearConnectorStorage.setConnector(
                        newType, for: antenna
                    )
                }
            )
        }
    }

    private func connectorRow(
        label: String,
        connector: ConnectorType?,
        onChange: @escaping (ConnectorType?) -> Void
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Menu {
                Button("Not set") { onChange(nil) }
                ForEach(ConnectorType.allCases) { type in
                    Button(type.rawValue) { onChange(type) }
                }
            } label: {
                Text(connector?.rawValue ?? "Connector?")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        connector != nil
                            ? Color.blue.opacity(0.15)
                            : Color.orange.opacity(0.15)
                    )
                    .foregroundStyle(
                        connector != nil ? .blue : .orange
                    )
                    .clipShape(Capsule())
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    // MARK: - Reminder Rows

    private func gearReminderRow(
        _ reminder: GearReminder
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                toggleReminder(reminder.id)
            }
        } label: {
            let isChecked = checkedReminderIds.contains(reminder.id)
            HStack(spacing: 10) {
                Image(
                    systemName: isChecked
                        ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(isChecked ? .green : .secondary)
                .font(.title3)

                Label(reminder.text, systemImage: reminder.icon)
                    .foregroundStyle(
                        isChecked ? .secondary : .primary
                    )
                    .strikethrough(isChecked)

                Spacer()
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    // MARK: - Generation

    var generatedReminders: [GearReminder] {
        GearReminderEngine.generate(
            radioConnector: radioConnector,
            antennaConnector: antennaConnector,
            mode: selectedMode,
            hasAntenna: selectedAntenna != nil,
            hasKey: selectedKey != nil
        )
    }

    // MARK: - Actions

    func loadConnectorProfiles() {
        if let radio = selectedRadio {
            radioConnector = resolveConnector(for: radio)
        }
        if let antenna = selectedAntenna {
            antennaConnector = resolveConnector(for: antenna)
        }
    }

    func refreshConnectorForRadio() {
        if let radio = selectedRadio {
            radioConnector = resolveConnector(for: radio)
        } else {
            radioConnector = nil
        }
        pruneCheckedIds()
    }

    func refreshConnectorForAntenna() {
        if let antenna = selectedAntenna {
            antennaConnector = resolveConnector(for: antenna)
        } else {
            antennaConnector = nil
        }
        pruneCheckedIds()
    }

    /// Resolve connector for equipment by name: user override first,
    /// then catalog default via SwiftData inventory lookup.
    /// Persists the catalog value so the user sees it pre-filled.
    private func resolveConnector(for name: String) -> ConnectorType? {
        if let stored = GearConnectorStorage.connector(for: name) {
            return stored
        }
        guard let catalogId = catalogIdForEquipment(named: name) else {
            return nil
        }
        let catalog = EquipmentCatalogService.shared.catalog
        guard let entry = catalog.first(where: { $0.id == catalogId }),
              let raw = entry.antennaConnector,
              let type = ConnectorType(rawValue: raw)
        else {
            return nil
        }
        GearConnectorStorage.setConnector(type, for: name)
        return type
    }

    /// Look up an EquipmentItem's catalogId by its display name.
    private func catalogIdForEquipment(named name: String) -> String? {
        var descriptor = FetchDescriptor<EquipmentItem>()
        descriptor.fetchLimit = 50
        guard let items = try? modelContext.fetch(descriptor) else {
            return nil
        }
        return items.first { $0.displayName == name }?.catalogId
    }

    private func toggleReminder(_ id: String) {
        if checkedReminderIds.contains(id) {
            checkedReminderIds.remove(id)
        } else {
            checkedReminderIds.insert(id)
        }
    }

    /// Remove checked IDs that no longer match any generated reminder.
    private func pruneCheckedIds() {
        let validIds = Set(generatedReminders.map(\.id))
        checkedReminderIds.formIntersection(validIds)
    }
}
