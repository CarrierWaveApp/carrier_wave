import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - RadioConnectionSheet

/// Per-item radio connection editor.
///
/// Reads/writes `EquipmentItem.connectionProfile`. The actual transport
/// implementations (BLE scanning, RS-BA1 auth, SmartLink) still live on
/// `RadioService` and are reached via the "Open Radio Settings…" link
/// at the bottom — this sheet only owns the persisted profile.
struct RadioConnectionSheet: View {
    // MARK: Internal

    let itemID: UUID
    var onSave: (() -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                if item == nil {
                    Section {
                        ContentUnavailableView(
                            "Item Not Found",
                            systemImage: "questionmark.circle"
                        )
                    }
                } else {
                    transportSection
                    transportDetailSection
                    bridgeSection
                    metadataSection
                    deepLinkSection
                }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .task { loadItem() }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var item: EquipmentItem?

    @State private var transport: RadioTransportKind = .ble
    @State private var protocolKind: RadioProtocolKind = .civ
    @State private var bleDeviceName = ""
    @State private var bleDeviceUUIDString = ""
    @State private var bleViaBridge = false
    @State private var hostAddress = ""
    @State private var portText = ""
    @State private var civAddressHex = ""
    @State private var flexSliceText = "0"
    @State private var useSmartLink = false

    private var isBridgeCompatible: Bool {
        guard let item else {
            return true
        }
        if let entry = catalogEntry(for: item.catalogId) {
            return RadioCatalogMetadata.isBridgeCompatible(for: entry)
        }
        // Custom items: assume bridge-compatible
        return true
    }

    private var transportSection: some View {
        Section("Transport") {
            Picker("Transport", selection: $transport) {
                ForEach(RadioTransportKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            Picker("Protocol", selection: $protocolKind) {
                ForEach(RadioProtocolKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
        }
    }

    @ViewBuilder
    private var transportDetailSection: some View {
        switch transport {
        case .ble: bleDetailSection
        case .wifi: wifiDetailSection
        case .flex: flexDetailSection
        case .scuLan10: scuLan10DetailSection
        }
    }

    private var bleDetailSection: some View {
        Section("Bluetooth") {
            HStack {
                Text("Device")
                Spacer()
                Text(bleDeviceName.isEmpty ? "Not selected" : bleDeviceName)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("UUID")
                Spacer()
                Text(bleDeviceUUIDString.isEmpty ? "—" : bleDeviceUUIDString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var wifiDetailSection: some View {
        Section("Wi-Fi (RS-BA1)") {
            TextField("IP address", text: $hostAddress)
                .textInputAutocapitalization(.never)
                .keyboardType(.numbersAndPunctuation)
            TextField("CI-V address (hex)", text: $civAddressHex)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private var flexDetailSection: some View {
        Section("FlexRadio") {
            TextField("IP address", text: $hostAddress)
                .textInputAutocapitalization(.never)
                .keyboardType(.numbersAndPunctuation)
            TextField("Port", text: $portText)
                .keyboardType(.numberPad)
            TextField("Slice index", text: $flexSliceText)
                .keyboardType(.numberPad)
            Toggle("Use SmartLink (WAN)", isOn: $useSmartLink)
        }
    }

    private var scuLan10DetailSection: some View {
        Section("SCU-LAN10") {
            TextField("IP address or hostname", text: $hostAddress)
                .textInputAutocapitalization(.never)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
            TextField("Control port", text: $portText)
                .keyboardType(.numberPad)
        }
    }

    @ViewBuilder
    private var bridgeSection: some View {
        if transport == .ble, isBridgeCompatible {
            Section {
                Toggle("Use CW Bridge", isOn: $bleViaBridge)
            } footer: {
                Text(
                    "Route CAT through the CW Bridge over BLE. "
                        + "The bridge must be owned and paired separately."
                )
            }
        }
    }

    private var metadataSection: some View {
        Section {
            if let item {
                HStack {
                    Text("Item")
                    Spacer()
                    Text(item.displayName)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Status")
                Spacer()
                Text(item?.connectionProfile?.isConfigured == true
                    ? "Configured" : "Not configured")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deepLinkSection: some View {
        Section {
            NavigationLink {
                RadioSettingsView(radioService: RadioService.shared)
            } label: {
                Label(
                    "Scan / Pair / SmartLink Login\u{2026}",
                    systemImage: "wrench.and.screwdriver"
                )
            }
        } footer: {
            Text(
                "Device scanning, RS-BA1 credentials, and SmartLink "
                    + "login still live in the global Radio settings. "
                    + "After pairing there, return here to save those "
                    + "details onto this item."
            )
        }
    }

    private func catalogEntry(for catalogId: String) -> CatalogEntry? {
        EquipmentCatalogService.shared.catalog.first { $0.id == catalogId }
    }

    private func loadItem() {
        let targetID = itemID
        var descriptor = FetchDescriptor<EquipmentItem>()
        descriptor.fetchLimit = 1
        descriptor.predicate = #Predicate<EquipmentItem> { eq in
            eq.id == targetID
        }
        guard let fetched = try? modelContext.fetch(descriptor).first else {
            return
        }
        item = fetched
        hydrate(from: fetched)
    }

    private func hydrate(from item: EquipmentItem) {
        let profile = item.connectionProfile
            ?? seedProfileFromCatalog(item: item)
            ?? RadioConnectionProfile(transport: .ble)

        transport = profile.transport
        protocolKind = profile.protocolKind ?? .civ
        bleDeviceName = profile.bleDeviceName ?? ""
        bleDeviceUUIDString = profile.bleDeviceUUID?.uuidString ?? ""
        bleViaBridge = profile.bleViaBridge
        hostAddress = profile.hostAddress ?? ""
        portText = profile.port.map(String.init) ?? ""
        civAddressHex = profile.civAddress.map { String($0, radix: 16) } ?? ""
        flexSliceText = (profile.flexSliceIndex ?? 0).description
        useSmartLink = profile.useSmartLink
    }

    /// Seed a fresh profile from catalog metadata so the editor opens
    /// with sensible transport defaults rather than always-BLE.
    private func seedProfileFromCatalog(item: EquipmentItem) -> RadioConnectionProfile? {
        guard let entry = catalogEntry(for: item.catalogId) else {
            return nil
        }
        let transports = RadioCatalogMetadata.supportedTransports(for: entry)
        let proto = RadioCatalogMetadata.protocolKind(for: entry)
        return RadioConnectionProfile(
            transport: transports.first ?? .ble,
            protocolKind: proto
        )
    }

    private func save() {
        guard let item else {
            dismiss()
            return
        }
        item.connectionProfile = buildProfile()
        try? modelContext.save()
        onSave?()
        dismiss()
    }

    private func buildProfile() -> RadioConnectionProfile {
        var profile = RadioConnectionProfile(transport: transport)
        profile.protocolKind = protocolKind
        switch transport {
        case .ble:
            profile.bleDeviceUUID = UUID(uuidString: bleDeviceUUIDString)
            profile.bleDeviceName = bleDeviceName.isEmpty ? nil : bleDeviceName
            profile.bleViaBridge = bleViaBridge
        case .wifi:
            profile.hostAddress = hostAddress.isEmpty ? nil : hostAddress
            profile.civAddress = UInt8(civAddressHex, radix: 16)
        case .flex:
            profile.hostAddress = hostAddress.isEmpty ? nil : hostAddress
            profile.port = Int(portText)
            profile.flexSliceIndex = Int(flexSliceText)
            profile.useSmartLink = useSmartLink
        case .scuLan10:
            profile.hostAddress = hostAddress.isEmpty ? nil : hostAddress
            profile.port = Int(portText)
        }
        profile.keychainCredentialRef = itemID.uuidString
        return profile
    }
}
