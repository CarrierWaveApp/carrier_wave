import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - RadioMacroReadSourceTests

@MainActor
final class RadioMacroReadSourceTests: XCTestCase {
    func testCountAndFieldParityAfterMirroredUpsert() async throws {
        let container = try ModelContainer(
            for: Schema([RadioMacro.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        let cqMacro = RadioMacro(
            name: "Call CQ",
            icon: "antenna.radiowaves.left.and.right",
            macroDescription: "Send a CQ call",
            tagsCSV: "cw,calling",
            appliesToCSV: "kenwood,elecraft",
            author: "W6JY",
            argsJSON: Data([0x01]),
            stepsJSON: Data([0x02, 0x03]),
            sortOrder: 0
        )
        let qrzMacro = RadioMacro(
            name: "Set Power",
            tombstoned: true,
            tombstoneReason: "superseded"
        )
        context.insert(cqMacro)
        context.insert(qrzMacro)
        try context.save()

        let store = try FieldStore.openInMemory(key: "radio-macro-read")
        try store.upsertRadioMacro(item: SwiftDataStoreImporter.project(cqMacro))
        try store.upsertRadioMacro(item: SwiftDataStoreImporter.project(qrzMacro))

        let swiftData = SwiftDataRadioMacroReadSource(context: context)
        let rust = RustRadioMacroReadSource(store: store)

        let sdCount = try await swiftData.count()
        let rustCount = try await rust.count()
        XCTAssertEqual(sdCount, 2)
        XCTAssertEqual(rustCount, 2)
        XCTAssertTrue(
            StoreCountParity().compare(entity: "RadioMacro", swiftData: sdCount, rust: rustCount).matches
        )

        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 2)
        XCTAssertEqual(sdAll, rustAll)
    }

    func testParityHoldsAfterEdit() async throws {
        let container = try ModelContainer(
            for: Schema([RadioMacro.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "radio-macro-update")

        let macro = RadioMacro(name: "Tune", sortOrder: 1)
        context.insert(macro)
        try context.save()
        try store.upsertRadioMacro(item: SwiftDataStoreImporter.project(macro))

        macro.macroDescription = "Tune the ATU"
        macro.stepsJSON = Data([0xAA, 0xBB, 0xCC])
        try context.save()
        try store.upsertRadioMacro(item: SwiftDataStoreImporter.project(macro))

        let swiftData = SwiftDataRadioMacroReadSource(context: context)
        let rust = RustRadioMacroReadSource(store: store)
        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 1)
        XCTAssertEqual(sdAll, rustAll)
        XCTAssertEqual(rustAll.first?.macroDescription, "Tune the ATU")
        XCTAssertEqual(rustAll.first?.stepsJson, Data([0xAA, 0xBB, 0xCC]))
    }
}
