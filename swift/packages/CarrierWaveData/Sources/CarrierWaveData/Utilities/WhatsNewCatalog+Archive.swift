import Foundation

// MARK: - WhatsNewCatalog Archive

/// Older release notes split out of `WhatsNewCatalog.recentEntries` to keep the
/// main catalog under SwiftLint's 300-line type-body cap. Concatenated into
/// `entries` at the catalog's declaration site — order is preserved.
extension WhatsNewCatalog {
    static let archivedEntries: [WhatsNewEntry] = [
        // MARK: iOS — 1.97.0

        WhatsNewEntry(
            version: "1.97.0",
            date: archiveDate(2_026, 7, 16),
            headline: "Split-by-park exports and faster sign-in",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Split ADIF export by park",
                    detail: "Bulk-exporting several activations can now write "
                        + "one ADIF per park — n-fer QSOs fan out into each "
                        + "park, and the same park across days merges into a "
                        + "single file — or stay combined as before."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Sign-in link opens the app",
                    detail: "Tapping the emailed verification link now hands "
                        + "off to the app and finishes sign-in itself, instead "
                        + "of stranding you in the browser."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Right callsign on every session",
                    detail: "A new session now takes your callsign straight "
                        + "from your profile, so a callsign you've corrected "
                        + "can't get frozen into a session's QSOs or exports."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "No more sign-out crash on close",
                    detail: "A background sync that overran while you closed "
                        + "the app could crash on suspension; it now stops "
                        + "cleanly and resumes on next launch."
                ),
            ]
        ),

        // MARK: iOS — 1.96.0

        WhatsNewEntry(
            version: "1.96.0",
            date: archiveDate(2_026, 7, 9),
            headline: "A clearer session start wizard",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .improvement,
                    title: "Rebuilt session wizard",
                    detail: "Starting a session now flows top to bottom — "
                        + "your callsign and gear, then the essentials "
                        + "(programs, mode, frequency, power), with the "
                        + "optional bits tucked under More Options."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Auto-picks a frequency",
                    detail: "Leave the frequency blank and the wizard "
                        + "picks your most-active band and finds a clear "
                        + "spot on it, nestled among live spots with room "
                        + "to avoid interference."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Fills in the park",
                    detail: "For a POTA activation, the park field "
                        + "prepopulates with the best nearby candidate — "
                        + "the one you activate most within 16 km, or the "
                        + "closest — updating once your GPS fix lands."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Set session from quick entry",
                    detail: "A callsign-less line like `14.046 CW CN87` in "
                        + "the quick entry bar now updates the active "
                        + "session's frequency, mode, and grid for QSOs "
                        + "logged from now on."
                ),
            ]
        ),

        // MARK: iOS — 1.95.0

        WhatsNewEntry(
            version: "1.95.0",
            date: archiveDate(2_026, 7, 8),
            headline: "Fresher spots and safer respots",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Pull to refresh spots",
                    detail: "Pull the Hunter Log spot list down to poll "
                        + "immediately instead of waiting out the timer, "
                        + "and a new pill shows how long ago spots were "
                        + "last refreshed."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Spots arrive faster",
                    detail: "New spots now appear about a second after "
                        + "each poll instead of waiting up to 15 seconds "
                        + "for callsign enrichment to finish."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Respot without sign-in",
                    detail: "Respotting an activator no longer requires "
                        + "a POTA sign-in, and the Spot action always "
                        + "shows a confirmation previewing exactly what "
                        + "will be posted."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Callsign stays corrected",
                    detail: "A previously mistyped callsign can no "
                        + "longer sneak back from iCloud and silently "
                        + "overwrite the corrected one."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Sync uses your account",
                    detail: "Carrier Wave Sync now signs in with a "
                        + "verified email account, so a synced log is "
                        + "always recoverable by its owner."
                ),
            ]
        ),

        // MARK: iOS — 1.94.1

        WhatsNewEntry(
            version: "1.94.1",
            date: archiveDate(2_026, 7, 4),
            headline: "Stability fixes and a tidier Settings",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .fix,
                    title: "Large logbook launches",
                    detail: "Fixed a crash loop after updating on big "
                        + "logbooks — the first-launch import no longer "
                        + "blocks the app until iOS kills it."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Sync survives backgrounding",
                    detail: "Switching apps mid-sync no longer gets "
                        + "Carrier Wave terminated while it finishes "
                        + "saving your QSOs."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Club sync freezes",
                    detail: "Applying large club rosters no longer "
                        + "freezes the app on launch."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Settings reorganized",
                    detail: "Settings are regrouped around what you're "
                        + "doing — My Profile, Account & Data, Services, "
                        + "Features, Hardware, and more — with clearer "
                        + "screen headers throughout."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "More spot sources",
                    detail: "DX Summit, DXHeat, DXWatch, and telnet DX "
                        + "cluster spots are available as optional "
                        + "sources in the Hunt spot filters."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Resume session",
                    detail: "Home's resume row now lands directly in "
                        + "the live logger instead of the Sessions "
                        + "screen."
                ),
            ]
        ),

        // MARK: iOS — 1.94.0

        WhatsNewEntry(
            version: "1.94.0",
            date: archiveDate(2_026, 7, 1),
            headline: "New Home, Explore gallery, and simpler logging",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Home hero",
                    detail: "Your next action is pinned to the top of "
                        + "Home — resume an open session, or jump "
                        + "straight to starting one or hunting spots."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Explore feature gallery",
                    detail: "Browse the app's marquee features with "
                        + "quick pitches and where to find them, from "
                        + "More → Explore Features."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Simple Logging Mode",
                    detail: "An optional toggle mutes the situational "
                        + "chips in the session header, keeping the "
                        + "controls bar short during a pileup."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Operating style",
                    detail: "Tell the app how you operate — activator, "
                        + "hunter, a bit of everything, or new — and "
                        + "defaults adapt. Change it anytime in My "
                        + "Profile."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "New spots divider",
                    detail: "The Hunter Log marks how many spots "
                        + "arrived since you last looked."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Same as Last Session",
                    detail: "One tap starts a new session with your "
                        + "last session's mode, frequency, programs, "
                        + "and gear."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Today's Gear row",
                    detail: "Session start shows your current radio, "
                        + "antenna, key, and mic as chips — tap to "
                        + "tweak gear for the day."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Clearer tab names",
                    detail: "Dashboard is now Home, Logs is Logbook, "
                        + "and Activity is Friends."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Transcription + scanning stable",
                    detail: "CW Transcription and handwritten log "
                        + "scanning graduated from Experiments and are "
                        + "always available."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Calmer On Air card",
                    detail: "Spot sections condense to a one-line "
                        + "summary — the full list is one tap away on "
                        + "the On Air sheet."
                ),
            ]
        ),

        // MARK: CW Sweep — 0.13.0

        WhatsNewEntry(
            version: "0.13.0",
            date: archiveDate(2_026, 5, 28),
            headline: "Sessions: intent picker, contest as a session, Cabrillo on the toolbar",
            platforms: [.macOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Sessions sidebar with intent picker",
                    detail: "The Logger sidebar is now \"Sessions\" with a "
                        + "2×2 grid (Activate / Hunt / Casual / Contest) and "
                        + "a Continue strip of paused sessions."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Contest as a Sessions intent",
                    detail: "Tap Contest, pick a definition, and the live "
                        + "operating UI opens inline with the score "
                        + "header, exchange bar, and Cabrillo export on "
                        + "the toolbar — no separate sidebar item."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "End / Pause from the toolbar",
                    detail: "The active session now sits next to the "
                        + "layout picker with End and Pause actions. The "
                        + "same commands appear in Cmd+K under Active "
                        + "Session."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Pre-unification log auto-grouped",
                    detail: "Loose QSOs from before this release are "
                        + "silently grouped into per-day Casual sessions "
                        + "on first launch."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Contester scoreboard stays put",
                    detail: "The contester layout pins the score panel "
                        + "to a slim fixed slot so it no longer drifts as "
                        + "the log fills."
                ),
            ]
        ),

        // MARK: iOS — 1.93.0

        WhatsNewEntry(
            version: "1.93.0",
            date: archiveDate(2_026, 5, 30),
            headline: "Radio macros + contest as a session intent",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Radio macros",
                    detail: "Build, share, and run reusable CAT routines "
                        + "for your rig — tune-and-set-mode, voice memory "
                        + "triggers, RIT/XIT, CW templates with live "
                        + "preview. Enable under Settings → Experiments → "
                        + "Radio CAT Control → Macros."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Browse the macros library",
                    detail: "The Macros editor's Browse tab lists "
                        + "community-curated starters (POTA hunter, "
                        + "tuner cycle, voice memory, more) — install "
                        + "with one tap. Updates tab alerts you when "
                        + "an installed macro has a newer revision."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "Contest intent on the Sessions tab",
                    detail: "The 2×2 intent grid is now "
                        + "Activate / Hunt / Casual / Contest. Tap Contest "
                        + "to pick a contest and start scoring in one flow."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Richer contest picker",
                    detail: "Selecting a contest from session start or "
                        + "QSO edit now opens the full calendar/catalog "
                        + "browser with Live-now and schedule captions."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Sessions landing is the default",
                    detail: "The intent picker graduated from Experiments. "
                        + "Every Sessions tab visit lands on Activate / "
                        + "Hunt / Casual / Contest."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Yaesu CAT command catalog",
                    detail: "Vendor command picker now ships 15 common "
                        + "Yaesu CAT commands (VFO/mode/PTT/power/split/"
                        + "RIT/XIT/preamp/AGC) for FT-857/897/817/991(A) "
                        + "and FT-DX10/710/DX101."
                ),
            ]
        ),

        // MARK: iOS — 1.92.0

        WhatsNewEntry(
            version: "1.92.0",
            date: archiveDate(2_026, 5, 22),
            headline: "Unified day summary, RST auto-advance, sturdier sync",
            platforms: [.iOS],
            items: [
                WhatsNewItem(
                    kind: .feature,
                    title: "Unified day summary",
                    detail: "Tap any activity-grid cell to open a full "
                        + "day view: hero stats, map + states mosaic, "
                        + "band timeline, and every session that "
                        + "overlapped the day."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "RST auto-advance",
                    detail: "Typing RST Sent jumps focus to RST Received "
                        + "once the value is the right length for the "
                        + "mode (3 digits for CW/digital, 2 for phone)."
                ),
                WhatsNewItem(
                    kind: .feature,
                    title: "6m FT8 in hunter spots",
                    detail: "Hunter spot monitor now rotates through "
                        + "6m FT8 (50.313 ±3 kHz) alongside HF, so "
                        + "sporadic-E openings show up without "
                        + "switching sources."
                ),
                WhatsNewItem(
                    kind: .improvement,
                    title: "Hunter Log day summary refresh",
                    detail: "Matches the session detail layout: hero "
                        + "stats, swipeable insights carousel, band "
                        + "timeline, and a cleaner QSO list."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Clear All QSOs restores from iCloud",
                    detail: "Wiping the local log now re-bootstraps "
                        + "the logbook from iCloud immediately, the "
                        + "same way a fresh install would. Disable "
                        + "sync first if you want a clean wipe."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Legacy OP: notes scrubbed",
                    detail: "Older QSOs with `OP: <name>` baked into "
                        + "their notes get a one-time cleanup pass on "
                        + "next launch, matching the going-forward fix "
                        + "from 1.90."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "Hunter Log sort affects everything",
                    detail: "Recent / Frequency / Needs now reorders "
                        + "the Club Members section too, not just the "
                        + "Other Spots list below it."
                ),
                WhatsNewItem(
                    kind: .fix,
                    title: "FT8 input warning",
                    detail: "Fixed four converging causes of the "
                        + "\"input too high\" banner getting stuck: "
                        + "an out-of-bounds decimator read, wide-band "
                        + "peak detection, missed audio route changes, "
                        + "and stale main-actor timestamps."
                ),
            ]
        ),
    ]

    private static func archiveDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }
}
