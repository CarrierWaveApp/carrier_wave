import Foundation

// MARK: - WhatsNewCatalog Archive (CW Sweep)

/// Older CW Sweep (macOS) release notes split out of `+Archive.swift` to keep
/// each archive file under SwiftLint's 500-line file-length cap. Concatenated
/// into `entries` at the catalog's declaration site — order is preserved.
extension WhatsNewCatalog {
    static let archivedSweepEntries: [WhatsNewEntry] = [
        WhatsNewEntry(
            version: "0.10.0",
            date: archiveSweepDate(2_026, 5, 2),
            headline: "CW Bridge over BLE + journal sync",
            platforms: [.macOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "CW Bridge over Bluetooth",
                    detail: "Pair the Carrier Wave CW Bridge from CW Sweep — scan, "
                        + "pair, and connect over BLE. Bridge auto-detects the attached "
                        + "radio (CI-V / Kenwood / Elecraft) and hot-swaps to the right "
                        + "protocol handler with live status."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Server-published contests",
                    detail: "Contest definitions now come from the server (format v0.3) "
                        + "instead of bundled templates — same source of truth as iOS, "
                        + "with shared scoring, dupe checking, and Cabrillo export."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "SKCC member badges",
                    detail: "Spots from SKCC members display the operator's number and "
                        + "award level (Centurion / Tribune / Senator) in the spot inspector."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Share callsigns and QSOs",
                    detail: "Share enriched callsign / QSO / park / SOTA links via the "
                        + "macOS share sheet. Recipients with Carrier Wave installed "
                        + "deeplink straight into the matching detail view."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Band scope redesign",
                    detail: "Structured rows with diagonal leader lines, vim-style keyboard "
                        + "navigation (j/k/h/l, ?), right-click context menu, and "
                        + "fit-to-spots zoom (0 / FIT)."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Journal-only iCloud sync",
                    detail: "iCloud sync is now journal-only on both Mac and iOS — single "
                        + "code path, faster bootstrap on new devices, and the sync "
                        + "report / repair UI is gone in favor of the simpler model. "
                        + "Window also re-fetches on focus so iOS QSOs appear instantly."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "What's New sheet",
                    detail: "Yes, this one — release notes now ship in CW Sweep too."
                ),
            ]
        ),
        WhatsNewEntry(
            version: "0.7.0",
            date: archiveSweepDate(2_026, 4, 2),
            headline: "Faster sync, shared with iOS",
            platforms: [.macOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Journal sync engine",
                    detail: "Full snapshot + journal sync support, matching the iOS app's faster initial-setup flow."
                ),
            ]
        ),
        WhatsNewEntry(
            version: "0.6.0",
            date: archiveSweepDate(2_026, 4, 1),
            headline: "WYSIWYG layout + Flex SmartSDR",
            platforms: [.macOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Visual layout editor",
                    detail: "Drag dividers and drop panes anywhere — every operator role can build their own workspace."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "FlexRadio SmartSDR",
                    detail: "Full CAT control over the LAN, including SmartLink remote access."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Waterfall + spot overlay",
                    detail: "Band-scope waterfall with spot markers overlaid, plus jitter-smoothed adaptive playback."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Spot Detail pane",
                    detail: "Inline map, parsed callsign, and condensed metadata for any selected spot."
                ),
            ]
        ),
    ]

    private static func archiveSweepDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }
}
