//
//  ADIFExportServiceSplitTests.swift
//  CarrierWaveTests
//
//  Verifies that N-fer POTA sessions export one ADIF file per park.
//

import CarrierWaveCore
import CarrierWaveData
import XCTest
@testable import CarrierWave

@MainActor
final class ADIFExportServiceSplitTests: XCTestCase {
    // MARK: Internal

    // MARK: - 5-fer

    func testFiveFerProducesFiveFilesOnePerPark() async {
        let parks = ["US-0001", "US-0002", "US-0003", "US-0004", "US-0005"]
        let multiRef = parks.joined(separator: ", ")
        let snapshots = makeSnapshots(parkReference: multiRef, count: 4)

        let config = SplitExportConfig(
            snapshots: snapshots,
            splitByUTCDay: false,
            splitByPark: true,
            splitByOperator: false,
            fallbackPark: nil,
            fallbackCallsign: "W6JY",
            parkNames: [:]
        )

        let files = await ADIFExportService().generateSplitADIF(for: config)
        let parkRefs = files.compactMap(\.parkReference).sorted()
        XCTAssertEqual(parkRefs, parks)
        XCTAssertEqual(files.count, 5)

        // Every file should contain all 4 QSOs and write only its own park into MY_POTA_REF.
        for file in files {
            XCTAssertEqual(file.qsoCount, 4)
            guard let park = file.parkReference else {
                XCTFail("file missing park ref")
                continue
            }
            XCTAssertTrue(
                file.content.contains("<MY_POTA_REF:\(park.utf8.count)>\(park)"),
                "expected MY_POTA_REF=\(park) in file \(file.filename)"
            )
            for other in parks where other != park {
                XCTAssertFalse(
                    file.content.contains("<MY_POTA_REF:\(other.utf8.count)>\(other)"),
                    "file \(file.filename) leaked other park \(other)"
                )
            }
        }
    }

    // MARK: - 3-fer

    func testThreeFerProducesThreeFilesOnePerPark() async {
        let parks = ["K-0010", "K-0020", "K-0030"]
        let snapshots = makeSnapshots(
            parkReference: parks.joined(separator: ", "), count: 7
        )

        let config = SplitExportConfig(
            snapshots: snapshots,
            splitByUTCDay: false,
            splitByPark: true,
            splitByOperator: false,
            fallbackPark: nil,
            fallbackCallsign: "W6JY",
            parkNames: [:]
        )

        let files = await ADIFExportService().generateSplitADIF(for: config)
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(
            files.compactMap(\.parkReference).sorted(),
            parks.sorted()
        )
        for file in files {
            XCTAssertEqual(file.qsoCount, 7)
        }
    }

    // MARK: - Single-park

    func testSinglePackProducesOneFile() async {
        let snapshots = makeSnapshots(parkReference: "US-1234", count: 3)
        let config = SplitExportConfig(
            snapshots: snapshots,
            splitByUTCDay: false,
            splitByPark: true,
            splitByOperator: false,
            fallbackPark: nil,
            fallbackCallsign: "W6JY",
            parkNames: [:]
        )

        let files = await ADIFExportService().generateSplitADIF(for: config)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.parkReference, "US-1234")
        XCTAssertEqual(files.first?.qsoCount, 3)
    }

    // MARK: - Mixed N-fer

    func testMixedSinglePackAndTwoFerFansOutCorrectly() async {
        let single = makeSnapshots(
            parkReference: "US-0001",
            count: 2,
            startOffset: 0
        )
        let twofer = makeSnapshots(
            parkReference: "US-0001, US-0002",
            count: 3,
            startOffset: 100
        )

        let config = SplitExportConfig(
            snapshots: single + twofer,
            splitByUTCDay: false,
            splitByPark: true,
            splitByOperator: false,
            fallbackPark: nil,
            fallbackCallsign: "W6JY",
            parkNames: [:]
        )

        let files = await ADIFExportService().generateSplitADIF(for: config)
        XCTAssertEqual(files.count, 2)

        let byPark = Dictionary(uniqueKeysWithValues: files.map { ($0.parkReference ?? "", $0) })
        XCTAssertEqual(byPark["US-0001"]?.qsoCount, 5, "US-0001 should appear in single + twofer QSOs")
        XCTAssertEqual(byPark["US-0002"]?.qsoCount, 3, "US-0002 should only contain twofer QSOs")
    }

    // MARK: - Bulk (multi-activation) split by park

    func testBulkSplitConfigMergesParksAcrossActivationsAndDays() async {
        // Activation 1: single park US-0001 on day A.
        let dayA = makeSnapshots(
            parkReference: "US-0001", count: 2, startOffset: 0
        )
        // Activation 2: two-fer US-0001 + US-0002 on a different day.
        let dayB = makeSnapshots(
            parkReference: "US-0001, US-0002", count: 3, startOffset: 90_000
        )

        let config = makeBulkSplitConfig(
            snapshots: dayA + dayB,
            callsign: "W6JY",
            parkNames: [:]
        )

        let files = await ADIFExportService().generateSplitADIF(for: config)
        XCTAssertEqual(files.count, 2, "expected one file per unique park")

        let byPark = Dictionary(
            uniqueKeysWithValues: files.map { ($0.parkReference ?? "", $0) }
        )
        // US-0001 appears in both activations regardless of day → all 5 QSOs.
        XCTAssertEqual(byPark["US-0001"]?.qsoCount, 5)
        // US-0002 only from the two-fer activation → 3 QSOs.
        XCTAssertEqual(byPark["US-0002"]?.qsoCount, 3)

        // Each file must carry only its own park in MY_POTA_REF.
        for (park, file) in byPark {
            XCTAssertTrue(
                file.content.contains("<MY_POTA_REF:\(park.utf8.count)>\(park)"),
                "expected MY_POTA_REF=\(park)"
            )
            let otherPark = park == "US-0001" ? "US-0002" : "US-0001"
            XCTAssertFalse(
                file.content.contains("<MY_POTA_REF:\(otherPark.utf8.count)>\(otherPark)"),
                "file for \(park) leaked \(otherPark)"
            )
        }
    }

    // MARK: - File count preview

    func testSplitFileCountMatchesGeneratedFiles() async {
        let parks = ["US-0001", "US-0002", "US-0003", "US-0004", "US-0005"]
        let snapshots = makeSnapshots(
            parkReference: parks.joined(separator: ", "), count: 1
        )
        let config = SplitExportConfig(
            snapshots: snapshots,
            splitByUTCDay: false,
            splitByPark: true,
            splitByOperator: false,
            fallbackPark: nil,
            fallbackCallsign: "W6JY",
            parkNames: [:]
        )

        let service = ADIFExportService()
        let predicted = await service.splitFileCount(for: config)
        let actual = await service.generateSplitADIF(for: config).count
        XCTAssertEqual(predicted, 5)
        XCTAssertEqual(predicted, actual)
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeSnapshots(
        parkReference: String,
        count: Int,
        startOffset: TimeInterval = 0
    ) -> [QSOExportSnapshot] {
        let base = Date(timeIntervalSince1970: 1_714_000_000) + startOffset
        return (0 ..< count).map { idx in
            let qso = QSO.testQSO(
                callsign: String(format: "W%dABC", idx + 1),
                timestamp: base.addingTimeInterval(Double(idx) * 60),
                myCallsign: "W6JY",
                parkReference: parkReference
            )
            return QSOExportSnapshot(from: qso)
        }
    }
}
