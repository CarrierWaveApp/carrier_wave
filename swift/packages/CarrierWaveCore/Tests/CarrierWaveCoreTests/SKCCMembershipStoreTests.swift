//
//  SKCCMembershipStoreTests.swift
//  CarrierWaveCoreTests
//

import Foundation
import Testing
@testable import CarrierWaveCore

struct SKCCMembershipStoreTests {
    // MARK: - Roster Parsing

    @Test("parses plain member line")
    func parsesPlainMemberLine() throws {
        let line = "12345|W1AW|Hiram|Newington|CT||12345|2010-01-15"
        let member = try #require(SKCCMembershipStore.parseMemberLine(line))
        #expect(member.number == 12_345)
        #expect(member.callsign == "W1AW")
        #expect(member.name == "Hiram")
        #expect(member.spc == "CT")
        #expect(member.award == .member)
        #expect(member.tribuneMultiplier == nil)
        #expect(member.badge == "12345")
    }

    @Test("parses Centurion from C date column")
    func parsesCenturionFromCDateColumn() throws {
        let line = "23456|K1JT|Joe|Princeton|NJ||23456|2008-03-01|2009-04-12"
        let member = try #require(SKCCMembershipStore.parseMemberLine(line))
        #expect(member.award == .centurion)
        #expect(member.badge == "23456C")
    }

    @Test("parses Tribune with suffix multiplier")
    func parsesTribuneWithSuffixMultiplier() throws {
        let line = "67890Tx5|N0AX|Ward||WA||67890|2007-01-01|2008-04-01|2010-06-15"
        let member = try #require(SKCCMembershipStore.parseMemberLine(line))
        #expect(member.number == 67_890)
        #expect(member.award == .tribune)
        #expect(member.tribuneMultiplier == 5)
        #expect(member.badge == "67890Tx5")
    }

    @Test("parses plain Tribune when no multiplier")
    func parsesPlainTribuneWhenNoMultiplier() throws {
        let line = "11111T|K9LA|Carl||IN||11111|2005-01-01|2006-04-01|2009-12-01"
        let member = try #require(SKCCMembershipStore.parseMemberLine(line))
        #expect(member.award == .tribune)
        #expect(member.tribuneMultiplier == nil)
        #expect(member.badge == "11111T")
    }

    @Test("parses Senator from S date column")
    func parsesSenatorFromSDateColumn() throws {
        let line = "22222S|W3LPL|Frank||MD||22222|2001-01-01|2002-04-01|2004-12-01|2006-06-01|2010-01-01"
        let member = try #require(SKCCMembershipStore.parseMemberLine(line))
        #expect(member.award == .senator)
        #expect(member.badge == "22222S")
    }

    @Test("parseRoster skips header line")
    func parseRosterSkipsHeader() {
        let body = """
        NUMBER|CURRENT_CALL|NAME|CITY|SPC|OTHER_CALLS|PLAIN_NUMBER|JOIN_DATE
        12345|W1AW|Hiram|Newington|CT||12345|2010-01-15
        23456|K1JT|Joe|Princeton|NJ||23456|2008-03-01|2009-04-12
        """
        let members = SKCCMembershipStore.parseRoster(body)
        #expect(members.count == 2)
        #expect(members[0].callsign == "W1AW")
        #expect(members[1].award == .centurion)
    }

    @Test("parseRoster tolerates blank lines and CRLF")
    func parseRosterTolerantOfBlankLinesAndCRLF() {
        let body = "12345|W1AW|Hiram|Newington|CT\r\n\r\n23456|K1JT|Joe||NJ||23456|2008|2009\r\n"
        let members = SKCCMembershipStore.parseRoster(body)
        #expect(members.count == 2)
    }

    // MARK: - Index + Lookup

    @Test("buildIndex includes other callsigns")
    func buildIndexIncludesOtherCallsigns() throws {
        let line = "34567|N6TR|Larry|||K0RF,W7TR|34567|2001-01-01|2003-04-01"
        let member = try #require(SKCCMembershipStore.parseMemberLine(line))
        let index = SKCCMembershipStore.buildIndex(from: [member])
        #expect(index["N6TR"]?.number == 34_567)
        #expect(index["K0RF"]?.number == 34_567)
        #expect(index["W7TR"]?.number == 34_567)
        #expect(index["XXXXX"] == nil)
    }

    @Test("buildIndex prefers current call over older entry")
    func buildIndexPrefersCurrentCallOverOlderEntry() throws {
        // If the same callsign appears as "other" for a different member, the
        // member whose CURRENT call it is should win.
        let aLine = "100|N6TR|Larry|||OLDCALL|100|2001-01-01"
        let bLine = "200|OLDCALL|Other||||200|2005-01-01"
        let memberA = try #require(SKCCMembershipStore.parseMemberLine(aLine))
        let memberB = try #require(SKCCMembershipStore.parseMemberLine(bLine))
        let index = SKCCMembershipStore.buildIndex(from: [memberA, memberB])
        #expect(index["OLDCALL"]?.number == 200)
        #expect(index["N6TR"]?.number == 100)
    }

    // MARK: - Badge formatting

    @Test("badge formats all award levels")
    func badgeFormatsAllAwardLevels() {
        let plain = SKCCMember(
            number: 1, callsign: "A", name: nil, spc: nil,
            award: .member, tribuneMultiplier: nil, otherCallsigns: []
        )
        let centurion = SKCCMember(
            number: 2, callsign: "B", name: nil, spc: nil,
            award: .centurion, tribuneMultiplier: nil, otherCallsigns: []
        )
        let tribune = SKCCMember(
            number: 3, callsign: "C", name: nil, spc: nil,
            award: .tribune, tribuneMultiplier: nil, otherCallsigns: []
        )
        let tribuneX5 = SKCCMember(
            number: 4, callsign: "D", name: nil, spc: nil,
            award: .tribune, tribuneMultiplier: 5, otherCallsigns: []
        )
        let senator = SKCCMember(
            number: 5, callsign: "E", name: nil, spc: nil,
            award: .senator, tribuneMultiplier: nil, otherCallsigns: []
        )

        #expect(plain.badge == "1")
        #expect(centurion.badge == "2C")
        #expect(tribune.badge == "3T")
        #expect(tribuneX5.badge == "4Tx5")
        #expect(senator.badge == "5S")
    }
}
