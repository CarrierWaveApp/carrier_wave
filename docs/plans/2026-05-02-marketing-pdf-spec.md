# Marketing PDF Spec — "What makes Carrier Wave different?"

**Audience:** Cowork (designers/marketers building a one-pager / informational PDF that an operator can hand to a curious ham, or that we can post in Discord when someone asks "why CW over PoLo / HAMRS / WRL?")

**Format:** Single PDF. Cover + 6–8 inside pages. Print-safe (US Letter / A4 both) and screen-readable. Provide a 2-page short variant ("hand-out") and a long variant ("mini-zine").

**Owner / voice:** Operator-to-operator. Humble, not aggressive. The other loggers are great — many of us came from them. The point of this PDF isn't to tear them down, it's to help an operator pick the one that fits their operating.

**Phone-competition scope:** World Radio League (WRL), HAMRS / HAMRS Pro, Ham2K PoLo. We are not positioning against Windows/Mac desktop loggers (HRD, N3FJP, Log4OM, RUMlog, MacLoggerDX) in this piece.

> Quick disambiguation for the writer: "Polo" in operator chat = **Ham2K PoLo** (KI2D, React Native, iOS+Android), **not** anything from HAMRS. Use "PoLo" consistently.

---

## 1. Brand & Visual System

Pull tokens from carrierwave.app — the marketing site is the source of truth.

### Palette (dark-first, matches site)

- Background primary: `#09090B`
- Background elevated: `#131316`
- Text primary: `#F0F0F2`; secondary `rgba(240,240,242,0.6)`; tertiary `rgba(240,240,242,0.35)`
- Subtle border: `rgba(255,255,255,0.06)`
- Brand accent (manual/wordmark): `#9B4DCA` purple, hot-pink edge `#C94BC4`
- Status accents: blue `#3B82F6`, green `#34D399`, orange `#F59E0B`, red `#EF4444`

A light-theme variant is acceptable for print; mirror the manual site (`#FFFFFF` bg, `#1D1D1F` text, same accents).

### Type

- Display / headlines: SF Pro Display (or DM Sans as web-safe fallback) — 700 weight, tight line-height (1.05–1.15), 48–80px hero.
- Body: DM Sans 300–400, 16/1.6.
- Tags, callsigns, frequencies: JetBrains Mono / SF Mono, uppercase, 11–13px, 0.04–0.15em tracking.

### Motifs

- Animated sine/wave background (still frame for print).
- Morse `· — · ·` style horizontal dividers between sections.
- Rounded-corner (12px) screenshot frames, 1px subtle border.
- 28×28px purple-gradient app icon in the wordmark lockup.

### Voice (from site copy — quote-worthy lines to honor)

- "Software and hardware that unifies the amateur radio experience."
- "If we wouldn't use it, we don't ship it."
- "The seams are on the inside."
- "We're amateur radio operators first and developers second."
- "Operator first."

Tone: terse, technical, confident-without-bragging. **Humble first.** No marketing fluff, no exclamation points, no "revolutionary," no "blows away." Sentences earn their length. Domain vocab (DXCC, P2P, QSY, RBN) used as naturally as a regular operator would. Treat the reader like another op at the bench.

---

## 2. The opening (cover + page 1)

**Cover line:** *"A logger built for the way you operate on iPhone."*

**Lead paragraph (set the tone — keep this exact framing):**

There are great ham radio loggers on the phone. PoLo is open source and works on Android too. HAMRS has the best desktop story. World Radio League turned a logbook into a community. We built Carrier Wave: Field because we wanted something that felt like an iPhone app — Live Activities while we operate, Apple Watch on the wrist, iCloud sync that respects the platform — and because we kept reaching for features that nobody had built yet. This PDF is a quick tour, not a take-down. Pick the one that fits your operating.

**Three-up cards (the things a CW user notices first):**

1. **Native iPhone, top to bottom.** Live Activities on the Lock Screen, Apple Watch complication, Spotlight indexing, Shortcuts, Widgets. Not a port — built in Swift on SwiftData with iCloud sync.
2. **Decoders in your pocket.** On-device CW (Morse) transcription from the mic with adaptive WPM. FT8 encode and decode in app. KiwiSDR/WebSDR streaming and recording with QSOs synced to the audio.
3. **Activations get a story.** Park boundaries on the map, rove stops, brag sheets with twenty-plus stat types, an MP4 highlight-reel exporter so you can share an activation in Discord without a screenshot collage.

---

## 3. Side-by-side comparison (page 2 — the headline page)

Four columns: **Carrier Wave: Field** vs **Ham2K PoLo** vs **HAMRS Pro** vs **World Radio League**. Use ✓ / ✗ / ◐ (partial). Accuracy first — always.

| Capability | CW: Field | PoLo | HAMRS Pro | WRL |
|---|---|---|---|---|
| Native iOS (Swift, no JS bridge) | ✓ | ✗ (RN) | ✗ (Electron-derived) | ✗ (RN/web) |
| Also on Android | ✗ | ✓ | ✓ | ✓ |
| Open source | ✗ | ✓ | ✗ | ✗ |
| Native desktop (macOS/Windows/Linux) | ◐ (CW Sweep, Mac) | ◐ (Win in dev) | ✓ | ✗ |
| Apple Watch app + complications | ✓ | ✗ | ✗ | ✗ |
| Live Activities / Lock Screen | ✓ | ✗ | ✗ | ✗ |
| Widgets, Shortcuts, Spotlight | ✓ | ✗ | ✗ | ✗ |
| iCloud / CloudKit sync (no account) | ✓ | ◐ (paid Log Filer) | ◐ (paid cloud) | ✗ (cloud-required) |
| Works fully offline | ✓ | ✓ | ✓ | ◐ |
| Append-only ADIF safety ledger | ✓ | ✗ | ✗ | ✗ |
| Database recovery mode | ✓ | ✗ | ✗ | ✗ |
| Quick-entry command bar (FREQ / MODE / HUNT / SPOT / RBN / SOLAR / WX / NOTE …) | ✓ | ◐ | ◐ | ◐ |
| Log query language (typed search) | ✓ | ◐ | ◐ | ◐ |
| Equipment management (rigs / antennas / station profiles) | ✓ | ✓ | ✓ | ◐ |
| Per-QSO equipment from active station profile | ✓ | ✓ | ✓ | ◐ |
| Friends + clubs + activity feed | ✓ | ◐ | ✗ | ✓ |
| Real-time global leaderboards / live contesting | ✗ | ✗ | ✗ | ✓ |
| Auto-generated QSL cards per QSO | ✗ | ✗ | ✗ | ✓ |
| Auto-spotting to POTA on a timer | ◐ (manual & via command bar) | ✓ | ◐ | ✓ |
| Spot comment polling during activation | ✓ | ✓ | ✗ | ◐ |
| RBN spots + needs matching + grid enrichment | ✓ | ◐ | ✗ | ◐ |
| POTA park boundaries on map (US + several countries) | ✓ | ✓ | ✗ | ✗ |
| QSO grid map (Maidenhead heatmap) | ✓ | ✓ | ✗ | ◐ |
| Azimuthal spot map centered on QTH | ✓ | ✗ | ✗ | ✗ |
| POTA N-fer ADIF split (one file per park) | ✓ | ✓ | ✗ (manual workaround) | ◐ (multi-ref logging, split unclear) |
| On-device CW (Morse) transcription | ✓ | ✗ | ✗ | ✗ |
| FT8 full encode/decode in app | ✓ | ✗ | ✗ | ✗ |
| KiwiSDR / WebSDR streaming + recording | ✓ | ✗ | ✗ | ✗ |
| SDR clip export with QSO sync | ✓ | ✗ | ✗ | ✗ |
| Video export of activation (MP4) | ✓ | ✗ | ✗ | ✗ |
| Brag sheet (20+ stats, presets) | ✓ | ◐ | ◐ | ◐ |
| Contest calendar + Cabrillo | ✓ | ✗ | ✗ | ◐ (own format) |
| Log scanning (camera → OCR → QSOs) | ✓ | ✗ | ✗ | ✗ |
| Pricing | one-time | free + opt-in $2.99/mo cloud | $4.99 + $2/mo cloud | freemium subscription |

> Designer note: Use ◐ generously. If we can't link a screenshot or doc, mark partial. Operators will check and we lose more by overclaiming than by underclaiming.

---

## 4. Eight "what's different" stories (pages 3–6, photo-led)

Each story = roughly half a page: a screenshot or photo, a short headline, a 2–4 sentence body in operator voice. **Tone rule:** describe what we built; do not say "competitors don't have this." The matrix already did that work.

### Story 1 — "The log can't lose itself."

Every QSO is also written to monthly append-only ADIF and JSONL files in your Documents folder. If SwiftData ever fails to open, Recovery Mode preserves the broken store and offers Restore from backup, Send diagnostics, or a typed-confirmation Reset. We built it because operators in our Discord told us about every logger they'd ever lost data to. Yours, ours, all of them.

### Story 2 — "Decoders in your pocket."

CW (Morse) is decoded from the phone's mic in real time with a Goertzel detector and an adaptive-WPM timing state machine. FT8 is fully encoded and decoded inside the app. Point the phone at a speaker on a park bench and the callsigns appear on screen — no laptop, no SignaLink, no soundcard.

### Story 3 — "A command bar instead of a tap stack."

Type `14.060` to QSY. Type `MODE CW`. Type `SPOT QRP REPEAT 10` to self-spot every ten minutes. Type `HUNT W6JY 14067 CW` to log a one-off off-frequency QSO without disturbing the active session. Type `RBN K0PIR` to look someone up, `SOLAR` for current conditions, `NOTE wind picked up at the picnic table`. Some operators never touch the command bar; some live in it.

### Story 4 — "POTA without the workarounds."

Park boundaries render on the map for US parks and several supported countries, cached for thirty days. N-fer activations export as one ADIF per park with `MY_POTA_REF` set correctly — drop them all on pota.app/user/logs and you're done. Sessions auto-split at UTC midnight. Rove stops know which QSOs belong to which park. Auto-recorded solar and weather conditions per session.

### Story 5 — "Two maps you'll keep coming back to."

A Maidenhead grid heatmap of every grid you've worked, tappable down to the contact. An azimuthal-equidistant map centered on your QTH that shows live spots on the projection your antenna actually sees — bearing and distance read straight off the page. Both are built in native MapKit-and-Canvas code so they scroll at 120 Hz.

### Story 6 — "Equipment that follows you."

Carrier Wave keeps station profiles — Home, Mobile, QRP Portable, Field Day — each with rig, antenna, power, key, mic. The active profile stamps every QSO with the gear you used. Edit a profile, and it backfills cleanly without rewriting history. The brag sheet then breaks out QSOs by rig and by antenna, so you can see what your end-fed actually does on 20 m.

### Story 7 — "The log talks to your friends, the radio talks to RBN."

A friends list, club rosters with O(1) member lookup on spots, an activity feed of friend QSOs, and a friend-spot toast when one of them shows up on RBN. SKCC member numbers and award tier render right on the spot row. Park-to-Park discovery suggests nearby activators while you're on the air. None of this requires a Carrier Wave account — friends sync through the services you already use (QRZ, POTA).

### Story 8 — "An activation gets a story."

Twenty-plus brag-sheet stats, curated presets (DXer, QRP, Activator, Hunter, Field Day, Contest), session map with antimeridian-aware viewport and day/night terminator. Plus an MP4 highlight-reel exporter that overlays the map and a HUD on real-time or compressed audio — drop it in Discord, post it to Reddit, send it to Mom. KiwiSDR/WebSDR recordings sync to your QSOs so you can replay the actual contact later.

### Story 9 — "Search the log like you'd search anything else."

A typed query language with field filters: `band:20m mode:cw state:CA after:2026-01-01` resolves down to a SwiftData fetch with proper indexes; complex predicates fall back to in-memory filtering. Pair it with Spotlight indexing and "K0PIR Yosemite" finds a four-month-old contact from your Home Screen.

---

## 5. The "what they do better" page (page 7 — earn trust)

A full page, equal billing, no asterisks. This is the page that sells operators because it's the page we'd want to read.

### What Ham2K PoLo does that we don't

- **Fully open source** under github.com/ham2k/app-polo. You can fork it, audit it, ship a patch.
- **Cross-platform.** iOS, Android, and Windows in development. If half your shack runs Android, CW doesn't help.
- **Self-spotting on a timer** to POTA / SOTA / WWFF, dialed in over years of activator feedback.
- **Per-service export templates** with customizable filename, notes, and comment fields.
- **Free, donation-supported** by KI2D and a small group of contributors. We respect the model.

### What HAMRS Pro does that we don't

- **The strongest desktop story.** Real native-feeling Electron apps for macOS, Windows, Linux, and Raspberry Pi.
- **One-click QRZ logbook upload** baked into the workflow.
- **FLRig-based CAT** on the desktop, which beats anything we can do over BLE for fixed-station ops.
- **A genuinely cheap entry point** at $4.99 plus $2/mo for sync.
- **User-shareable templates** for contests and special events.

### What World Radio League does that we don't

- **Real-time global leaderboards** by mode. If gamification is what gets you on the air, WRL is unmatched.
- **Live contesting platform** with real-time scoring, a worldwide live-contacts map, and built-in analytics.
- **Auto-generated QSL cards** per contact, with shareable QSO maps.
- **A real community layer** — an active Discourse forum, livestreamed feature demos, Founding Member program.
- **Cloud-first data model** that means your log is on every device you log into, not just your iCloud-paired ones.

### And honestly, what we are not

- **Not on Android.** Not coming. We're an iOS-native shop and we'd rather do that one thing well than do two things passably.
- **Not a cloud platform.** No Carrier Wave server holds your log. No global leaderboard, no profile page, no public scoreboard. WRL does that better, by design.
- **Not free.** PoLo is, and that's a legitimate reason to pick it.
- **Not a contest super-station replacement.** N1MM still wins on a Windows multi-op.
- **Sync is iCloud, not a Carrier Wave server.** Faster, more reliable, and works without an account — but you can't share a log with an Android friend.

---

## 6. Footer / call-to-action

- App Store badge → Carrier Wave: Field
- carrierwave.app
- Wordmark + "Operator First" lockup
- Small print: "Carrier Wave is built by operators. If we wouldn't use it, we don't ship it."

---

## 7. Asset list cowork will need from us

1. Hero screenshot: live session with Live Activity visible on Lock Screen.
2. Apple Watch screenshot of complication + new-spot toast.
3. CW decode view (waterfall + decoded text).
4. Brag sheet export — long form + the MP4 still frame for video-export proof.
5. POTA N-fer ADIF split UI.
6. Recovery mode screen (the *unique* trust artifact).
7. Quick-entry command bar with autocomplete dropdown visible.
8. Equipment / station-profile editor with multiple profiles selectable.
9. Friends + activity feed + friend-spot toast.
10. POTA park boundary rendered on the activation map.
11. QSO grid heatmap (full screen).
12. Azimuthal spot map centered on QTH with antenna pattern overlay.
13. SDR recording playback view with timeline + transcript.
14. Log query language search results, ideally `band:20m mode:cw` style query visible.
15. Comparison table as editable Figma frame so the legend can update as competitors ship.
16. App icon SVG; wordmark SVG; color tokens as a Figma library or CSS file from the website.
17. Two short voice samples (≤140 chars) per feature so the designer can A/B headline length.

---

## 8. Variants

- **2-page hand-out:** cover + comparison page only. The "post in Discord when asked" SKU.
- **8-page mini-zine:** the full doc above. The "I built this and want to talk about it" SKU.
- **Square 1080×1080 social cards:** one per story (9), pulled from §4. Same dark theme, same Morse divider.

---

## 9. Don'ts (tape this above the designer's monitor)

- **Humility first.** Every other logger has people who love it for good reasons. Don't write a sentence that wouldn't survive being read by KI2D, the HAMRS team, or N0WRL.
- No exclamation points. No "revolutionary." No "game-changing." No "blows away."
- No emoji in the deck (we don't ship them in product copy either).
- Don't write "PoLo doesn't have X" or "WRL can't do Y." The matrix shows it; the prose stays about what we built.
- Don't invent features. If you can't link to a screenshot, the line doesn't go in.
- Don't use stock ham photography. Field photos from real operators only — ask Discord.

---

## Appendix A — Source notes for fact-checking

### Carrier Wave: Field — feature → file

- **Quick-entry command bar:** `swift/ios/CarrierWave/Models/LoggerCommand.swift`, `LoggerCommand+Parsing.swift`, `LoggerCommand+Suggestions.swift`. Commands include FREQ, BAND, MODE, SPOT (w/ REPEAT), RBN, HUNT, P2P, SOLAR, WEATHER, MAP, MANUAL, CHECKLIST, WEBSDR, RADIO, REPLAY, MYCALL, NOTE.
- **Equipment / station profiles:** `swift/ios/CarrierWave/Models/StationProfile.swift`, `Services/EquipmentUsageReporter.swift`, `Services/CustomEquipmentSubmitter.swift`.
- **Friends / clubs / activity feed:** `Services/FriendsSyncService.swift`, `ClubsSyncService.swift`, `ActivityFeedSyncService.swift`, `FriendSpotNotifier.swift`.
- **Spot comment polling:** `Services/SpotCommentsService.swift`, `Models/LoggingSession+Types.swift` (POTASpotComment).
- **Log query language:** `Services/QueryLanguage/QueryCompiler.swift` (+ `+StringFields`, `+NumericFields`, `+DateStatusFields`, `+Predicates`).
- **POTA park boundaries:** `Models/ParkBoundary.swift`, `ParkBoundary+Geometry.swift`, `ParkBoundary+Merging.swift`, `Services/ParkBoundaryCache.swift`, `Services/ActivitiesClient+ParkBoundaries.swift`. 30-day TTL file cache.
- **QSO grid map:** `Views/Dashboard/GridTrackerCard.swift`, `GridTrackerDetailView.swift`, `GridHeatmapView.swift`.
- **Azimuthal spot map:** `Views/Map/AzimuthalMapView.swift`, `AzimuthalContainerView.swift`, `AzimuthalStandaloneView.swift`, `AzimuthalDataProvider.swift`, `AzimuthalTileRenderer.swift`, `AzimuthalMapRenderer.swift`.
- **Video export:** `Services/VideoExport/VideoExportActor.swift`, `VideoWriter.swift`, `VideoEventSequencer.swift`, `VideoOverlayRenderer.swift`, `VideoFrameCompositor.swift`, `VideoAudioMixer.swift`. Views: `Views/Sessions/VideoExportSheet.swift`, `VideoExportButton.swift`.
- **CW transcription:** `Services/GoertzelFilter.swift`, `CWAudioCapture.swift`, `MorseDecoder.swift`, `CWTranscriptionService.swift` (+ `+Decoder`, `+SDR`).
- **SDR recording:** `Services/WebSDR/KiwiSDRClient.swift`, `WebSDRSession.swift`, `WebSDRRecorder.swift`, `SDRReplayEngine.swift`, `RecordingClipExporter.swift`. Views in `Views/RecordingPlayer/`.
- **FT8 codec:** `Services/FT8SessionManager.swift`, `Services/FT8AudioEngine.swift`. Shared CFT8 C library.
- **Safety ledger / recovery:** `Services/BackupService.swift`, `CarrierWaveApp+ContainerSetup.swift`, `Services/DiagnosticsCollector.swift`.
- **Brag sheet:** `Models/BragSheet/`, `Models/BragSheetPreset.swift`.
- **Contest calendar / scoring:** `Services/ContestEnrichmentService.swift`, `Services/ContestCalendarClient.swift`.
- **Log scanning OCR:** `Services/LogScanning/LogPageScanner.swift`.

### Competitor fact-check sources

- **Ham2K PoLo:** [polo.ham2k.com](https://polo.ham2k.com/), [exports docs](https://polo.ham2k.com/docs/polo-features/exports/) (confirms N-fer split: "two POTA logs for the two parks"), [spotting docs](https://polo.ham2k.com/docs/polo-features/spotting/), [github.com/ham2k/app-polo](https://github.com/ham2k/app-polo), forum thread [Log uploads with multiple parks](https://forums.ham2k.com/t/log-uploads-with-multiple-parks/1343).
- **HAMRS / HAMRS Pro:** [hamrs.app](https://hamrs.app/), [pricing](https://hamrs.app/pricing), [community: two or more parks same time](https://community.hamrs.app/t/two-or-more-parks-same-time/359) (confirms manual workaround for N-fer), [community: POTA self-uploader](https://community.hamrs.app/t/pota-self-uploader/2413).
- **World Radio League:** [worldradioleague.com](https://worldradioleague.com/), [mobile-apps](https://worldradioleague.com/mobile-apps/), [contesting docs](https://worldradioleague.com/docs/contesting/), [how-to-use-wrl-for-pota](https://worldradioleague.com/docs/how-to-use-wrl-for-pota/), [export-an-adif](https://worldradioleague.com/docs/export-an-adif/), [community.worldradioleague.com](https://community.worldradioleague.com/).

### Corrections from previous draft

- PoLo **does** support N-fer ADIF split (per official docs); table updated to ✓.
- HAMRS Pro N-fer is a manual station-profile workaround, not a true split; table marked ✗.
- WRL accepts up to 5 park refs per QSO; per-park split output is not clearly documented; table marked ◐ pending verification.
- None of the three currently support direct API submission to pota.app for log upload (POTA has not published that API).
