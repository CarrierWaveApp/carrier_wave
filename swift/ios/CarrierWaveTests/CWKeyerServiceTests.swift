import XCTest
@testable import CarrierWave

@MainActor
final class CWKeyerServiceTests: XCTestCase {
    // MARK: Internal

    override func setUp() async throws {
        try await super.setUp()
        // Clear any persisted slots from previous test runs
        for idx in 1 ... 8 {
            UserDefaults.standard.removeObject(forKey: "cwKeyer.slot.\(idx).label")
            UserDefaults.standard.removeObject(forKey: "cwKeyer.slot.\(idx).text")
        }
        UserDefaults.standard.removeObject(forKey: "cwKeyer.wpm")
        service = CWKeyerService()
    }

    // MARK: - Slot Storage

    func testInitialSlotsAreEmpty() {
        XCTAssertEqual(service.slots.count, 8)
        XCTAssertTrue(service.programmedSlots.isEmpty)
    }

    func testUpdateSlotStoresLabelAndText() {
        service.updateSlot(id: 1, label: "CQ", text: "CQ CQ DE {MYCALL} K")

        let slot = service.slot(for: 1)
        XCTAssertEqual(slot?.label, "CQ")
        XCTAssertEqual(slot?.text, "CQ CQ DE {MYCALL} K")
        XCTAssertEqual(service.programmedSlots.count, 1)
    }

    func testUpdateSlotTruncatesLabel() {
        service.updateSlot(id: 1, label: "VERY LONG LABEL", text: "TEST")

        let slot = service.slot(for: 1)
        XCTAssertEqual(slot?.label.count, 8)
    }

    func testUpdateSlotTruncatesText() {
        let longText = String(repeating: "X", count: 200)
        service.updateSlot(id: 1, label: "T", text: longText)

        let slot = service.slot(for: 1)
        XCTAssertEqual(slot?.text.count, CWKeyerService.maxSlotLength)
    }

    func testNextEmptySlotID() {
        XCTAssertEqual(service.nextEmptySlotID(), 1)

        service.updateSlot(id: 1, label: "CQ", text: "CQ TEST")
        XCTAssertEqual(service.nextEmptySlotID(), 2)
    }

    func testSlotPersistsToUserDefaults() {
        service.updateSlot(id: 3, label: "TU", text: "TU {MYCALL}")

        // Create a new instance — should load from UserDefaults
        let fresh = CWKeyerService()
        let slot = fresh.slot(for: 3)
        XCTAssertEqual(slot?.label, "TU")
        XCTAssertEqual(slot?.text, "TU {MYCALL}")
    }

    // MARK: - Display Label

    func testDisplayLabelUsesExplicitLabel() {
        service.updateSlot(id: 1, label: "CQ", text: "CQ CQ DE W6JY")
        XCTAssertEqual(service.slot(for: 1)?.displayLabel, "CQ")
    }

    func testDisplayLabelDerivesFromFirstWord() {
        service.updateSlot(id: 1, label: "", text: "TEST DE W6JY")
        XCTAssertEqual(service.slot(for: 1)?.displayLabel, "TEST")
    }

    func testDisplayLabelStripsBraces() {
        service.updateSlot(id: 1, label: "", text: "{CALL} 5NN")
        XCTAssertEqual(service.slot(for: 1)?.displayLabel, "CALL")
    }

    // MARK: - WPM

    func testWpmDefaultsTo20() {
        XCTAssertEqual(service.wpm, 20)
    }

    func testWpmClampsToRange() {
        service.wpm = 3
        XCTAssertGreaterThanOrEqual(service.wpm, 5)

        service.wpm = 100
        XCTAssertLessThanOrEqual(service.wpm, 60)
    }

    // MARK: - Template Expansion

    func testExpandForPreviewReplacesAllMacros() {
        let result = service.expandForPreview(
            "{CALL} DE {MYCALL} 5NN {NR}",
            myCall: "W6JY",
            exchange: "CT"
        )
        XCTAssertEqual(result, "W1AW DE W6JY 5NN 001")
    }

    func testExpandForPreviewUsesDefaultMyCall() {
        let result = service.expandForPreview("{MYCALL} TEST")
        XCTAssertTrue(result.contains("W6JY"))
    }

    func testExpandForPreviewReplacesMyName() {
        let result = service.expandForPreview("DE {MYCALL} TU {MYNAME}", myCall: "W6JY", myName: "JAY")
        XCTAssertEqual(result, "DE W6JY TU JAY")
    }

    func testExpandForPreviewUsesDefaultMyName() {
        let result = service.expandForPreview("TU {MYNAME}")
        XCTAssertTrue(result.contains("JAY"))
        XCTAssertFalse(result.contains("{MYNAME}"))
    }

    func testExpandForPreviewReplacesExchange() {
        let result = service.expandForPreview("{EXCH}", exchange: "CT")
        XCTAssertEqual(result, "CT")
    }

    // MARK: - Context Building

    func testBuildContextReturnsAllKeys() {
        let ctx = service.buildContext(
            from: CWKeyerContext(
                callsign: "W1AW",
                myCall: "W6JY",
                myName: "JAY",
                serial: 42,
                rstSent: "559",
                name: "HIRAM",
                exchange: "CT"
            )
        )
        XCTAssertEqual(ctx["CALL"], "W1AW")
        XCTAssertEqual(ctx["MYCALL"], "W6JY")
        XCTAssertEqual(ctx["MYNAME"], "JAY")
        XCTAssertEqual(ctx["NR"], "042")
        XCTAssertEqual(ctx["RST"], "559")
        XCTAssertEqual(ctx["NAME"], "HIRAM")
        XCTAssertEqual(ctx["EXCH"], "CT")
    }

    func testBuildContextDefaultsRSTTo599() {
        let ctx = service.buildContext(
            from: CWKeyerContext(
                callsign: "W1AW",
                myCall: "W6JY",
                myName: "",
                serial: 1,
                rstSent: "",
                name: "",
                exchange: ""
            )
        )
        XCTAssertEqual(ctx["RST"], "599")
    }

    // MARK: Private

    private var service: CWKeyerService!
}
