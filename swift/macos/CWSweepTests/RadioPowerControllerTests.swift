import XCTest
@testable import CWSweep

final class RadioPowerControllerTests: XCTestCase {
    func testNoCandidatesIsNone() {
        XCTAssertEqual(RadioPowerController.choosePort(candidates: [], remembered: nil), .none)
        XCTAssertEqual(RadioPowerController.choosePort(candidates: [], remembered: "/dev/cu.a"), .none)
    }

    func testSingleCandidateIsChosen() {
        XCTAssertEqual(
            RadioPowerController.choosePort(candidates: ["/dev/cu.a"], remembered: nil),
            .one("/dev/cu.a")
        )
    }

    func testSingleCandidateWinsOverStaleRemembered() {
        XCTAssertEqual(
            RadioPowerController.choosePort(candidates: ["/dev/cu.a"], remembered: "/dev/cu.gone"),
            .one("/dev/cu.a")
        )
    }

    func testRememberedCandidateWinsAmongMany() {
        XCTAssertEqual(
            RadioPowerController.choosePort(candidates: ["/dev/cu.a", "/dev/cu.b"], remembered: "/dev/cu.b"),
            .one("/dev/cu.b")
        )
    }

    func testManyWithoutRememberedAsks() {
        XCTAssertEqual(
            RadioPowerController.choosePort(candidates: ["/dev/cu.b", "/dev/cu.a"], remembered: nil),
            .many(["/dev/cu.a", "/dev/cu.b"])
        )
    }
}
