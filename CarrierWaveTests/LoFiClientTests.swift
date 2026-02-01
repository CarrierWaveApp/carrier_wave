import XCTest
@testable import CarrierWave

// MARK: - LoFiClientTests

@MainActor
final class LoFiClientTests: XCTestCase {
    func testParseRegistrationResponse() throws {
        let json = """
        {
            "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test",
            "client": {
                "uuid": "client-uuid-123",
                "name": "CarrierWave"
            },
            "account": {
                "uuid": "account-uuid-456",
                "call": "W1AW",
                "name": "Test User",
                "email": "test@example.com",
                "cutoff_date": "2024-01-01",
                "cutoff_date_millis": 1704067200000
            },
            "meta": {
                "flags": {
                    "suggested_sync_batch_size": 50,
                    "suggested_sync_loop_delay": 10000,
                    "suggested_sync_check_period": 300000
                }
            }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try JSONDecoder().decode(LoFiRegistrationResponse.self, from: data)

        XCTAssertEqual(response.token, "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test")
        XCTAssertEqual(response.client.uuid, "client-uuid-123")
        XCTAssertEqual(response.client.name, "CarrierWave")
        XCTAssertEqual(response.account.call, "W1AW")
        XCTAssertEqual(response.account.name, "Test User")
        XCTAssertEqual(response.meta.flags.suggestedSyncBatchSize, 50)
    }

    func testParseOperationsResponse() throws {
        let json = """
        {
            "operations": [
                {
                    "uuid": "op-uuid-123",
                    "stationCall": "W1AW",
                    "account": "account-uuid",
                    "createdAtMillis": 1704067200000,
                    "updatedAtMillis": 1704153600000,
                    "title": "at US-1234",
                    "subtitle": "Test Park",
                    "grid": "FN31",
                    "refs": [
                        {
                            "type": "potaActivation",
                            "ref": "US-1234",
                            "name": "Test National Park",
                            "program": "POTA"
                        }
                    ],
                    "qsoCount": 25
                }
            ],
            "meta": {
                "operations": {
                    "total_records": 1,
                    "synced_until_millis": 1704153600000,
                    "limit": 50,
                    "records_left": 0
                }
            }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try JSONDecoder().decode(LoFiOperationsResponse.self, from: data)

        XCTAssertEqual(response.operations.count, 1)
        XCTAssertEqual(response.operations[0].uuid, "op-uuid-123")
        XCTAssertEqual(response.operations[0].stationCall, "W1AW")
        XCTAssertEqual(response.operations[0].qsoCount, 25)
        XCTAssertEqual(response.operations[0].potaRef?.reference, "US-1234")
        XCTAssertEqual(response.meta.operations.recordsLeft, 0)
    }

    func testParseQsosResponse() throws {
        let data = try XCTUnwrap(TestData.qsosResponseJSON.data(using: .utf8))
        let response = try JSONDecoder().decode(LoFiQsosResponse.self, from: data)

        XCTAssertEqual(response.qsos.count, 1)
        XCTAssertEqual(response.meta.qsos.recordsLeft, 0)
    }

    func testParseQsoFields() throws {
        let data = try XCTUnwrap(TestData.qsosResponseJSON.data(using: .utf8))
        let response = try JSONDecoder().decode(LoFiQsosResponse.self, from: data)
        let qso = response.qsos[0]

        XCTAssertEqual(qso.uuid, "qso-uuid-123")
        XCTAssertEqual(qso.band, "20m")
        XCTAssertEqual(qso.mode, "SSB")
        XCTAssertEqual(qso.theirCall, "K1ABC")
        XCTAssertEqual(qso.ourCall, "W1AW")
        XCTAssertEqual(qso.rstSent, "59")
        XCTAssertEqual(qso.rstRcvd, "59")
        XCTAssertEqual(qso.theirGrid, "FN42")
        XCTAssertEqual(qso.theirName, "John")
        XCTAssertEqual(qso.theirPotaRef, "US-5678")
        XCTAssertEqual(qso.notes, "Test QSO")
        XCTAssertEqual(qso.freqMHz, 14.25)
    }

    func testLoFiQsoTimestamp() throws {
        let json = """
        {
            "uuid": "qso-uuid",
            "startAtMillis": 1704067200000
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let qso = try JSONDecoder().decode(LoFiQso.self, from: data)

        // 1704067200000 ms = 2024-01-01 00:00:00 UTC
        let expected = Date(timeIntervalSince1970: 1_704_067_200)
        XCTAssertEqual(qso.timestamp, expected)
    }

    func testLoFiOperationPotaRef() throws {
        let json = """
        {
            "uuid": "op-uuid",
            "stationCall": "W1AW",
            "account": "account-uuid",
            "createdAtMillis": 1704067200000,
            "updatedAtMillis": 1704067200000,
            "refs": [
                {
                    "type": "potaActivation",
                    "ref": "US-1234",
                    "program": "POTA"
                },
                {
                    "type": "sotaActivation",
                    "ref": "W1/MB-001",
                    "program": "SOTA"
                }
            ],
            "qsoCount": 10
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let operation = try JSONDecoder().decode(LoFiOperation.self, from: data)

        XCTAssertEqual(operation.potaRef?.reference, "US-1234")
        XCTAssertEqual(operation.sotaRef?.reference, "W1/MB-001")
    }
}

// MARK: - TestData

private enum TestData {
    static let qsosResponseJSON = """
    {
        "qsos": [{
            "uuid": "qso-uuid-123", "operation": "op-uuid-123", "startAtMillis": 1704067200000,
            "band": "20m", "freq": 14250.0, "mode": "SSB",
            "their": {"call": "K1ABC", "sent": "59",
                     "guess": {"name": "John", "state": "MA", "grid": "FN42", "entity_name": "United States"}},
            "our": {"call": "W1AW", "sent": "59"},
            "refs": [{"type": "pota", "ref": "US-5678", "program": "POTA"}],
            "notes": "Test QSO"
        }],
        "meta": {"qsos": {"total_records": 1, "synced_until_millis": 1704067200000, "limit": 50,
                         "records_left": 0}}
    }
    """
}
