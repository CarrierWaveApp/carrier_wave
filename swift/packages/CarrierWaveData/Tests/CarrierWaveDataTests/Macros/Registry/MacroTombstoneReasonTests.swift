import CarrierWaveData
import Testing

struct MacroTombstoneReasonTests {
    @Test func serverReasonsParseRoundTrip() {
        let cases: [(String, MacroTombstoneReason)] = [
            ("withdrawn", .withdrawn),
            ("admin_removed", .adminRemoved),
            ("author_deleted", .authorDeleted),
            ("user-deleted", .userDeleted),
        ]
        for (raw, expected) in cases {
            #expect(MacroTombstoneReason.from(raw: raw) == expected)
        }
    }

    @Test func userDeletedIsNotServerOriginated() {
        #expect(MacroTombstoneReason.userDeleted.isServerOriginated == false)
        #expect(MacroTombstoneReason.withdrawn.isServerOriginated == true)
        #expect(MacroTombstoneReason.adminRemoved.isServerOriginated == true)
        #expect(MacroTombstoneReason.authorDeleted.isServerOriginated == true)
    }

    @Test func unknownReasonReturnsNil() {
        #expect(MacroTombstoneReason.from(raw: "future-reason-from-server") == nil)
        #expect(MacroTombstoneReason.from(raw: nil) == nil)
    }
}
