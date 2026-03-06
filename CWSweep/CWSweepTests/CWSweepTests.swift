import CarrierWaveCore
import Foundation
import Testing
@testable import CWSweep

// MARK: - Operating Role Tests

@Test func operatingRoleDisplayNames() {
    #expect(OperatingRole.contester.displayName == "Contester")
    #expect(OperatingRole.hunter.displayName == "Hunter")
    #expect(OperatingRole.activator.displayName == "Activator")
    #expect(OperatingRole.dxer.displayName == "DXer")
    #expect(OperatingRole.casual.displayName == "Casual")
}

@Test func operatingRoleIcons() {
    #expect(OperatingRole.contester.icon == "trophy")
    #expect(OperatingRole.hunter.icon == "binoculars")
    #expect(OperatingRole.activator.icon == "antenna.radiowaves.left.and.right")
    #expect(OperatingRole.dxer.icon == "globe")
    #expect(OperatingRole.casual.icon == "radio")
}

@Test func operatingRoleKeyboardShortcuts() {
    #expect(OperatingRole.contester.keyboardShortcut == 1)
    #expect(OperatingRole.hunter.keyboardShortcut == 2)
    #expect(OperatingRole.activator.keyboardShortcut == 3)
    #expect(OperatingRole.dxer.keyboardShortcut == 4)
    #expect(OperatingRole.casual.keyboardShortcut == 5)
}

@Test func operatingRoleCodable() throws {
    let role = OperatingRole.hunter
    let data = try JSONEncoder().encode(role)
    let decoded = try JSONDecoder().decode(OperatingRole.self, from: data)
    #expect(decoded == role)
}

// MARK: - Sidebar Tests

@Test func sidebarSections() {
    let operatingSectionItems = SidebarSection.operating.items
    #expect(operatingSectionItems.contains(.logger))
    #expect(operatingSectionItems.contains(.spots))
    #expect(operatingSectionItems.contains(.map))
    #expect(operatingSectionItems.contains(.bandMap))
    #expect(operatingSectionItems.contains(.cluster))
}

@Test func sidebarDataSectionIncludesSessions() {
    let dataItems = SidebarSection.data.items
    #expect(dataItems.contains(.qsoLog))
    #expect(dataItems.contains(.dashboard))
    #expect(dataItems.contains(.sessions))
}

@Test func sidebarSystemSection() {
    let systemItems = SidebarSection.system.items
    #expect(systemItems.contains(.radio))
    #expect(systemItems.contains(.sync))
}

@Test func sidebarModesSection() {
    let modeItems = SidebarSection.modes.items
    #expect(modeItems.contains(.pota))
    #expect(modeItems.contains(.ft8))
    #expect(modeItems.contains(.cw))
}

@Test func allSidebarItemsHaveSections() {
    for item in SidebarItem.allCases {
        let section = item.section
        #expect(section.items.contains(item), "Item \(item) should be in section \(section)")
    }
}

@Test func sidebarItemDisplayNames() {
    #expect(SidebarItem.sessions.displayName == "Sessions")
    #expect(SidebarItem.logger.displayName == "Logger")
    #expect(SidebarItem.bandMap.displayName == "Band Map")
}

// MARK: - Radio Model Tests

@Test func radioModelDefaults() {
    let ic7300 = RadioModel.knownModels.first { $0.id == "ic7300" }
    #expect(ic7300 != nil)
    #expect(ic7300?.civAddress == 0x94)
    #expect(ic7300?.defaultBaudRate == 19_200)
    #expect(ic7300?.protocolType == .civ)
    #expect(ic7300?.dtrDefault == true)
    #expect(ic7300?.rtsDefault == true)
}

@Test func radioModelKenwood() {
    let ts890 = RadioModel.knownModels.first { $0.id == "ts890s" }
    #expect(ts890 != nil)
    #expect(ts890?.protocolType == .kenwood)
    #expect(ts890?.defaultBaudRate == 115_200)
    #expect(ts890?.civAddress == nil)
}

@Test func radioModelElecraft() {
    let k3 = RadioModel.knownModels.first { $0.id == "k3" }
    #expect(k3 != nil)
    #expect(k3?.protocolType == .elecraft)
    #expect(k3?.defaultBaudRate == 38_400)
    #expect(k3?.dtrDefault == false)
    #expect(k3?.rtsDefault == false)
}

@Test func radioProfileFromModel() throws {
    let model = try #require(RadioModel.knownModels.first { $0.id == "ic7610" })
    let profile = RadioProfile(
        name: "My IC-7610",
        protocolType: model.protocolType,
        serialPortPath: "/dev/cu.usbserial-1234",
        baudRate: model.defaultBaudRate,
        civAddress: model.civAddress
    )
    #expect(profile.protocolType == .civ)
    #expect(profile.baudRate == 19_200)
    #expect(profile.civAddress == 0x98)
    #expect(profile.serialPortPath == "/dev/cu.usbserial-1234")
}

@Test func radioProfileFromModelPropagatesDTRRTS() throws {
    let k3 = try #require(RadioModel.knownModels.first { $0.id == "k3" })
    let profile = RadioProfile.from(model: k3, portPath: "/dev/cu.usbserial-TEST")
    #expect(profile.dtrSignal == false)
    #expect(profile.rtsSignal == false)

    let ic7300 = try #require(RadioModel.knownModels.first { $0.id == "ic7300" })
    let icomProfile = RadioProfile.from(model: ic7300, portPath: "/dev/cu.usbserial-TEST")
    #expect(icomProfile.dtrSignal == true)
    #expect(icomProfile.rtsSignal == true)
}

@Test func allKnownModelsHaveUniqueIds() {
    let ids = RadioModel.knownModels.map(\.id)
    #expect(Set(ids).count == ids.count, "Duplicate model IDs found")
}

// MARK: - Frame Assembler Tests

@Test func frameAssemblerCIV() async {
    let assembler = FrameAssembler(frameType: .civ)

    // Feed a complete CI-V frame: FE FE 94 E0 03 FD
    let frame = Data([0xFE, 0xFE, 0x94, 0xE0, 0x03, 0xFD])
    let frames = await assembler.feed(frame)
    #expect(frames.count == 1)
    #expect(frames.first == frame)
}

@Test func frameAssemblerKenwood() async {
    let assembler = FrameAssembler(frameType: .kenwood)

    // Feed a complete Kenwood response: FA00014074000;
    let response = "FA00014074000;".data(using: .ascii)!
    let frames = await assembler.feed(response)
    #expect(frames.count == 1)
}

@Test func frameAssemblerCIVSplitFrame() async {
    let assembler = FrameAssembler(frameType: .civ)

    // Feed first part of CI-V frame
    let part1 = Data([0xFE, 0xFE, 0x94])
    let frames1 = await assembler.feed(part1)
    #expect(frames1.isEmpty, "Incomplete frame should not produce output")

    // Feed remaining part
    let part2 = Data([0xE0, 0x03, 0xFD])
    let frames2 = await assembler.feed(part2)
    #expect(frames2.count == 1, "Complete frame should produce output")
}

@Test func frameAssemblerKenwoodMultipleResponses() async {
    let assembler = FrameAssembler(frameType: .kenwood)

    // Feed two responses concatenated
    let responses = "FA00014074000;MD2;".data(using: .ascii)!
    let frames = await assembler.feed(responses)
    #expect(frames.count == 2)
}

// MARK: - Protocol Handler Tests

@Test func civProtocolHandlerEncodeReadFrequency() {
    let handler = CIVProtocolHandler(civAddress: 0x94)
    let data = handler.encodeReadFrequency()
    #expect(data != nil)

    // Should contain FE FE preamble and FD terminator
    if let data {
        let bytes = [UInt8](data)
        #expect(bytes.first == 0xFE)
        #expect(bytes.last == 0xFD)
    }
}

@Test func civProtocolHandlerEncodeSetFrequency() {
    let handler = CIVProtocolHandler(civAddress: 0x94)
    let data = handler.encodeSetFrequency(14.074)
    let bytes = [UInt8](data)
    #expect(bytes.first == 0xFE)
    #expect(bytes.last == 0xFD)
}

@Test func kenwoodProtocolHandlerEncodeReadFrequency() {
    let handler = KenwoodProtocolHandler()
    let data = handler.encodeReadFrequency()
    #expect(data != nil)

    // Should be ASCII text ending with ;
    if let data, let str = String(data: data, encoding: .ascii) {
        #expect(str.hasSuffix(";"))
    }
}

@Test func kenwoodProtocolHandlerEncodeSetFrequency() {
    let handler = KenwoodProtocolHandler()
    let data = handler.encodeSetFrequency(14.074)
    if let str = String(data: data, encoding: .ascii) {
        #expect(str.hasSuffix(";"))
        #expect(str.contains("14074000"))
    }
}

@Test func kenwoodProtocolHandlerEncodeSetMode() {
    let handler = KenwoodProtocolHandler()
    let data = handler.encodeSetMode("CW")
    if let str = String(data: data, encoding: .ascii) {
        #expect(str.hasSuffix(";"))
    }
}

@Test func kenwoodProtocolHandlerEncodePTT() {
    let handler = KenwoodProtocolHandler()
    let txData = handler.encodeSetPTT(true)
    let rxData = handler.encodeSetPTT(false)

    if let txStr = String(data: txData, encoding: .ascii),
       let rxStr = String(data: rxData, encoding: .ascii)
    {
        #expect(txStr == "TX;")
        #expect(rxStr == "RX;")
    }
}

// MARK: - Layout Configuration Tests

@Test func defaultLayoutConfigurations() {
    let contesterLayout = LayoutConfiguration.default(for: .contester)
    #expect(contesterLayout.showInspector == false)
    #expect(contesterLayout.visibleSidebarItem == SidebarItem.logger.rawValue)

    let hunterLayout = LayoutConfiguration.default(for: .hunter)
    #expect(hunterLayout.showInspector == true)
    #expect(hunterLayout.visibleSidebarItem == SidebarItem.spots.rawValue)
}

@Test func layoutConfigurationCodable() throws {
    let config = LayoutConfiguration.default(for: .dxer)
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(LayoutConfiguration.self, from: data)
    #expect(decoded.role == .dxer)
    #expect(decoded.showInspector == config.showInspector)
    #expect(decoded.inspectorWidth == config.inspectorWidth)
}

// MARK: - Spot Source Tests

@Test func spotSourceFilterDisplayNames() {
    #expect(SpotSourceFilter.all.displayName == "All")
    #expect(SpotSourceFilter.pota.displayName == "POTA")
    #expect(SpotSourceFilter.rbn.displayName == "RBN")
    #expect(SpotSourceFilter.sota.displayName == "SOTA")
    #expect(SpotSourceFilter.wwff.displayName == "WWFF")
    #expect(SpotSourceFilter.cluster.displayName == "Cluster")
}

@Test func spotSourceFilterAllCases() {
    #expect(SpotSourceFilter.allCases.count == 6)
}
