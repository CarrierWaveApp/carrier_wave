import CarrierWaveData
import Foundation
import Testing

@Test func datasetIndexedByCallsignFlattensSourceEmoji() throws {
    let dataset = CallsignEnrichmentDataset(
        sources: [
            CallsignEnrichmentDatasetSource(
                slug: "cwops",
                name: "CWops",
                emoji: "🎹",
                lastFetchedAt: Date()
            ),
        ],
        callsigns: [
            CallsignEnrichmentDatasetEntry(
                callsign: "W6JY",
                memberships: [
                    CallsignEnrichmentDatasetMembership(
                        sourceSlug: "cwops",
                        name: "Jay V",
                        memberNumber: "1532",
                        emoji: nil,
                        note: nil
                    ),
                ]
            ),
        ],
        generatedAt: Date()
    )

    let indexed = dataset.indexedByCallsign()
    let entry = try #require(indexed["W6JY"])
    #expect(entry.memberships.count == 1)

    let membership = entry.memberships[0]
    #expect(membership.sourceSlug == "cwops")
    #expect(membership.sourceName == "CWops")
    // Emoji falls back from per-source default when the row didn't override.
    #expect(membership.emoji == "🎹")
    #expect(membership.memberNumber == "1532")
    #expect(membership.chipLabel == "🎹 CWops #1532")
    #expect(membership.nameAndNumberExchange == "Jay V 1532")
}

@Test func contestEnrichmentMatcherPrefillsEmptyExchangeFields() {
    let entry = CallsignEnrichmentEntry(
        callsign: "W6JY",
        memberships: [
            CallsignEnrichmentMembership(
                sourceSlug: "cwops",
                sourceName: "CWops",
                emoji: "🎹",
                name: "Jay V",
                memberNumber: "1532",
                note: nil
            ),
        ]
    )

    var values: [String: String] = [:]
    let written = ContestEnrichmentMatcher.prefill(
        from: entry,
        contestId: "cwops-cwt",
        into: &values
    )

    // First token, ALL CAPS: "Jay V" → "JAY".
    #expect(written["name"] == "JAY")
    #expect(written["identifier"] == "1532")
    #expect(values["name"] == "JAY")
    #expect(values["identifier"] == "1532")
}

@Test func contestEnrichmentMatcherUppercasesNames() {
    let entry = CallsignEnrichmentEntry(
        callsign: "AA0FO",
        memberships: [
            CallsignEnrichmentMembership(
                sourceSlug: "cwops",
                sourceName: "CWops",
                emoji: "🎹",
                name: "Marshall R",
                memberNumber: "1532",
                note: nil
            ),
        ]
    )

    var values: [String: String] = [:]
    ContestEnrichmentMatcher.prefill(
        from: entry,
        contestId: "cwops-cwt",
        into: &values
    )

    #expect(values["name"] == "MARSHALL")
}

@Test func contestEnrichmentMatcherPrefersPreferredNickname() {
    // K5OHY's CWops PoLo line has "Timothy D" but their CWT-preferred
    // nickname (from QRZ) is "Tim". The lookup-side nickname should win.
    let entry = CallsignEnrichmentEntry(
        callsign: "K5OHY",
        memberships: [
            CallsignEnrichmentMembership(
                sourceSlug: "cwops",
                sourceName: "CWops",
                emoji: "🎹",
                name: "Timothy D",
                memberNumber: "3573",
                note: nil
            ),
        ]
    )

    var values: [String: String] = [:]
    ContestEnrichmentMatcher.prefill(
        from: entry,
        contestId: "cwops-cwt",
        preferredName: "Tim",
        into: &values
    )

    #expect(values["name"] == "TIM")
    #expect(values["identifier"] == "3573")
}

@Test func contestEnrichmentMatcherFillsNonMemberFromFallbacks() {
    // Non-CWops US station: no entry in the CWops dataset, but QRZ
    // gave us a nickname and the caller resolved a state. Both fields
    // should still prefill from the fallbacks.
    var values: [String: String] = [:]
    ContestEnrichmentMatcher.prefill(
        from: nil,
        contestId: "cwops-cwt",
        preferredName: "Mike",
        fallbackIdentifier: "MD",
        into: &values
    )

    #expect(values["name"] == "MIKE")
    #expect(values["identifier"] == "MD")
}

@Test func contestEnrichmentMatcherUppercasesNonMemberIdentifier() {
    // Caller may pass a lowercased state — matcher should normalise.
    var values: [String: String] = [:]
    ContestEnrichmentMatcher.prefill(
        from: nil,
        contestId: "cwops-cwt",
        preferredName: "Hans",
        fallbackIdentifier: "dl",
        into: &values
    )

    #expect(values["identifier"] == "DL")
}

@Test func contestEnrichmentMatcherMembershipNumberWinsOverFallback() {
    // CWops members always send their member number, never their state.
    let entry = CallsignEnrichmentEntry(
        callsign: "W6JY",
        memberships: [
            CallsignEnrichmentMembership(
                sourceSlug: "cwops",
                sourceName: "CWops",
                emoji: "🎹",
                name: "Jay V",
                memberNumber: "9999",
                note: nil
            ),
        ]
    )

    var values: [String: String] = [:]
    ContestEnrichmentMatcher.prefill(
        from: entry,
        contestId: "cwops-cwt",
        preferredName: "Jay",
        fallbackIdentifier: "CA",
        into: &values
    )

    #expect(values["identifier"] == "9999")
}

@Test func contestEnrichmentMatcherPreservesUserTypedValues() {
    let entry = CallsignEnrichmentEntry(
        callsign: "W6JY",
        memberships: [
            CallsignEnrichmentMembership(
                sourceSlug: "cwops",
                sourceName: "CWops",
                emoji: "🎹",
                name: "Jay V",
                memberNumber: "1532",
                note: nil
            ),
        ]
    )

    var values = ["name": "Bob"]
    let written = ContestEnrichmentMatcher.prefill(
        from: entry,
        contestId: "cwops-cwt",
        into: &values
    )

    // identifier was empty so it gets filled, but name stays as the user typed it.
    #expect(written["name"] == nil)
    #expect(written["identifier"] == "1532")
    #expect(values["name"] == "Bob")
    #expect(values["identifier"] == "1532")
}

@Test func contestEnrichmentMatcherIgnoresUnmappedContests() {
    let entry = CallsignEnrichmentEntry(
        callsign: "W6JY",
        memberships: [
            CallsignEnrichmentMembership(
                sourceSlug: "cwops",
                sourceName: "CWops",
                emoji: "🎹",
                name: "Jay V",
                memberNumber: "1532",
                note: nil
            ),
        ]
    )

    var values: [String: String] = [:]
    let written = ContestEnrichmentMatcher.prefill(
        from: entry,
        contestId: "cq-ww-cw",
        into: &values
    )

    #expect(written.isEmpty)
    #expect(values.isEmpty)
}
