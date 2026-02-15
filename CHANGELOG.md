# Changelog

All notable changes to Carrier Wave will be documented in this file.

## [1.32.0] - 2026-02-14

### Added
- Configurable dashboard metrics card — choose 1-2 metrics from streaks (On-Air, Activation, Hunter, CW, Phone, Digital) and counts (QSOs/activations/hunts per week/month/year, new DXCC)
- Hunter streak tracking — consecutive days working POTA activators
- Dashboard Metrics settings screen for metric selection
- Rename "Share Card" to "Brag Sheet" across all activation share actions
- Add equipment to brag sheet — antenna, key, mic, and extra equipment shown as badges when enabled
- Add "Include equipment on brag sheet" toggle in POTA settings (on by default)

### Fixed
- Hide sessions with zero QSOs from the Sessions list
- Fix build errors: static stored property in generic type, duplicate FlowLayout definition, ActivationShareRenderer instantiation
- Fix HAMRS incorrectly marked as supporting uploads, creating permanent phantom pending upload records that inflate sync counts
- Fix QRZ upload clearing needsUpload without confirmation, causing QSOs to get stuck in dead state (never uploaded, no recovery path)
- Add data repair steps to clean up existing bogus HAMRS upload flags and QRZ dead-state QSOs

## [1.31.0] - 2026-02-14

### Added
- Merge POTA Activations and Sessions into a single unified Sessions list — every session (POTA, SOTA, casual) now shows rich content including QSO timeline, upload status, conditions, and equipment badges
- Record solar/weather conditions at the start of every session type, not just POTA — conditions display on session cards when available
- Add multi-park (n-fer) support for POTA activations — park entry is now multi-select with removable chips, search picker supports adding multiple parks, and self-spots are posted to all parks simultaneously
- Add hunt-first session flow for POTA/SOTA — frequency is no longer required at session start, allowing activators to hunt first and set their run frequency later via BAND command or band picker
- Add BAND command to logger — opens band picker with live POTA/RBN spot data and recommended clear frequencies per band
- Add QSOs/hour rate to session detail and POTA activation detail views
- Add equipment (radio, antenna, key, mic) to map QSO callout popups
- Add swipe-to-delete on individual QSOs in POTA activation detail view with confirmation dialog
- Add expanded session metadata: antenna, CW key, microphone, attendees, photos, and extra equipment fields on logging sessions
- Add generic equipment picker with user-managed lists for antenna, key, and microphone
- Add unified session edit sheet replacing activation-only edit — works for all session types with equipment, photos, and notes editing
- Add photo attachment and viewing for sessions with full-screen pinch-to-zoom viewer
- Add equipment badges (antenna, key, mic) to POTA activation detail metadata row
- Add photo count badge to sessions list rows

### Fixed
- Fix hidden/deleted QSOs being uploaded during sync — `fetchQSOsNeedingUpload` now filters hidden QSOs, hiding a QSO clears its upload flags, POTA reconciliation skips hidden QSOs, and a data repair step cleans up pre-existing dirty state
- Fix social activity not appearing for live-logged QSOs — activity detection now triggers immediately when logging a QSO, not only during sync downloads
- Fix activity feed not auto-refreshing — feed now polls every 60 seconds while Activity tab is visible
- Fix third-party callsigns being sent to server for DX contact activities — workedCallsign is now only uploaded for worked-friend events where both parties are app users
- Fix unbounded QSO fetch in activity detection that could freeze UI for large datasets — capped at 10k most-recent QSOs
- Fix friend requests not appearing in Friends list — list now syncs from server on appear instead of only showing cached data

### Changed
- Remove "POTA Activations" segment from Logs tab — all activations now appear in the unified "Sessions" list
- Rename "Edit Metadata" to "Edit Info" in POTA activation detail toolbar menu
- Add imperial/metric unit system picker in Settings — affects distances, temperatures, wind speed, and watts-per-distance across all views
- Auto-populate grid square from GPS when station profile has "Use Current Location" enabled — works in profile setup, editing, and live activity log with location indicator icon
- Enhance park selector with GPS-based nearby parks, activation/QSO counts per park, and unified search by number or name
- Track SDR parameter changes (frequency/mode) during WebSDR recordings with timestamps and offsets, enabling accurate segment reconstruction for playback rendering
- Stitch WebSDR recordings across pause/resume and disconnect/reconnect — silence fills gaps to maintain accurate timeline, dormant state keeps recording alive for up to 30 minutes between connections
- Show station profile name and grid square dividers in Activity Log QSO lists — visual sections appear when station profile or grid changes between QSOs, stored per-QSO for historical accuracy

## [1.30.0] - 2026-02-13

### Added
- Add tap-to-edit and swipe-to-delete on QSO rows in Activity Log (Recent QSOs and Daily Summary) — tap opens QSOEditSheet, swipe left reveals Delete action, row height meets 44pt HIG minimum
- Add frequency and band pill display in Activity Log quick entry — typed frequencies (e.g., "W1AW 14.060") show as "14.060 MHz" and "20m" pills, and propagate to logged QSO
- Add band/mode indicator to Activity Log quick entry fields row — shows current band and mode so the user knows what the next QSO will be logged as
- Add number row keyboard accessory to Activity Log quick entry — shows digits 1-0, configurable symbols, and dismiss button above keyboard (shares settings with Logger)
- Add rich share card preview sheet with ShareLink (proper thumbnail in share sheet) and Save to Photos button
- Add sync report UI — structured per-service reports with visual funnel (fetched → validated → changes applied → uploaded), status badges, and reconciliation details; persisted across app launches via UserDefaults; populated by both normal sync and force re-download
- Add WebSDR tuning info display — show current frequency, mode, and filter bandwidth in WebSDR panel
- Add WebSDR browser link — open the connected KiwiSDR in Safari with current tuning settings
- Add WebSDR recording playback — play back recordings with seeking, speed control (0.5x-2x), and amplitude waveform visualization
- Add QSO-synced audio navigation — dynamically highlight the active QSO based on playback position with bidirectional sync (scrub highlights QSOs, tap QSO seeks audio)
- Add compact recording player in POTA activation detail — inline card with mini waveform that expands to full-screen player
- Add full-screen recording player — waveform scrubber with QSO markers, transport controls, speed picker, and scrollable QSO list with auto-scroll
- Add share clip feature — export time-range clips from recordings as M4A with adjustable range handles defaulting to active QSO window
- Add Sessions tab in Logs — browse all completed logging sessions grouped by month with recording indicators and navigation to player or session detail

### Fixed
- Fix Activity Log quick entry RST handling — single RST in quick entry (e.g., "W1AW 579") now applies to both sent and received instead of only received
- Fix Activity Log band/frequency not carrying over from spot logs — logging a spot now sets the frequency and mode for subsequent quick log entries
- Fix Activity Log quick entry not passing notes to QSO — parsed notes from multi-token input were silently dropped
- Fix POTA job matching showing jobs from unrelated activations on activation detail cards — nil-date jobs (from all-duplicate uploads) now match to the closest activation by submitted date instead of all activations for the same park
- Fix KiwiSDR redirect handling — follow server redirects during handshake (up to 3 hops) instead of showing an error; detect redirects during streaming to trigger immediate reconnect; cache effective host/port so reconnects go directly to the correct server
- Fix WebSDR CW tuning — apply CW pitch offset so the signal lands in the center of the audio passband instead of at 0 Hz (inaudible)
- Fix KiwiSDR false disconnect on `too_busy=0` — server sends `MSG too_busy=0` as an informational status (not busy), but string matching treated it as a disconnect causing 10-second reconnect cycles
- Fix WebSDR reconnect drops recording — keep recording timer running and write silence during reconnect gaps instead of pausing recorder
- Change CW filter passband from 200-1000 Hz to 300-800 Hz for tighter 500 Hz bandwidth
- Fix recording player amplitude waveform not displaying — use file's native audio format instead of mismatched custom format
- Fix recording player showing no QSOs when opened from Sessions tab — auto-load QSOs by session ID when none provided
- Add WebSDR session recording — record audio from a nearby KiwiSDR during logging sessions with WEBSDR command, auto-retune on frequency/mode changes, level meter, and lifecycle integration
- Add WebSDR live audio playback — hear the stream through speakers/headphones via jitter-buffered ring buffer with adaptive rate, mute toggle, and buffer health indicator
- Add WebSDR resilient reconnects — connection loss preserves the recording file, duration timer, and audio engine instead of resetting; exponential backoff with up to 5 retries
- Add persistent WebSDR recording badge — tappable mini badge in logger header shows duration when panel is closed, tap to reopen
- Add WebSDR recording file sharing — share button on active recording and in recordings list
- Add WebSDR Recordings settings screen — browse, share, and delete past recordings
- Add background audio mode — WebSDR recording and playback continue when app is backgrounded
- Add appearance mode picker in Settings (System/Light/Dark/Sunlight) to override system color scheme
- Add Sunlight appearance mode for outdoor visibility — forces light theme with boosted contrast for direct sunlight use
- Add tiered contact count badges (bronze/silver/gold at 10/25/50 QSOs) in log rows and logger card
- Extract LoFi client into CarrierWaveCore package for sharing between iOS app and CLI tool
- Add `lofi-cli` executable target for standalone LoFi download testing without iOS Simulator
- Add `LoFiCredentialStore` and `LoFiLogger` protocols to abstract app-specific dependencies
- Add visual condition gauges for POTA activations — compact solar gauge (3-segment red/yellow/green) and weather badge (icon + temperature) replace plain text labels
- Add tappable conditions detail sheet showing full solar metrics (K-index, SFI, sunspots) and weather details (temperature, wind, humidity)
- Add structured solar/weather fields to ActivationMetadata with one-time backfill from existing text data

### Fixed
- Fix WebSDR audio crash on device — render callback inherited @MainActor isolation, crashing on the audio I/O thread; extract as nonisolated static factory and mark AudioRingBuffer methods nonisolated
- Fix WebSDR buffer underrun — add 1-second pre-buffering phase before starting audio engine to absorb network jitter; increase ring buffer from 3s to 5s capacity
- Fix WebSDR audio silence — write audio frames to playback ring buffer before recorder file I/O, remove unnecessary actor hops and suspension points that starved the buffer
- Fix WebSDR directory fetch — correct URL from `/public/` to `/.public/`, rewrite parser to extract receiver data from HTML comments, add ATS exception for HTTP/WS connections
- Fix KiwiSDR connection — remove incorrect `/kiwi/` URL prefix, use seconds not milliseconds for timestamp, fix identity command (`SET ident_user=`), add `SET compression=1`, parse server error messages (auth failures, busy, down), use negotiated sample rate, and restore correct frequency/mode on reconnect
- Fix KiwiSDR binary frame handling — KiwiSDR sends MSG text as binary WebSocket frames; decode binary data as UTF-8 during handshake and in the receive loop to properly detect sample_rate and other server messages
- Fix POTA upload prompt sheet: buttons hidden below visible area on medium detent — pin buttons at bottom with scrollable content and allow expansion to large detent
- Fix POTA upload prompt falsely reporting "upload failed" when POTA returns empty adif_files on HTTP 200 (file queued for async processing, not rejected)
- Fix POTA upload prompt using wrong QSO marking method — use markSubmittedToPark (matches SyncService behavior) instead of markUploadedToPark
- Fix LoFi sync fetching every QSO twice (server ignores `deleted` param on QSO endpoint, causing 2x bandwidth)
- Fix two-fer park references lost during QSO merge — combine park references instead of "first wins" so both parks are preserved
- Add Step 4 (dedup key grouping) to CLI pipeline breakdown so QSO counts match the app

### Changed
- Display contact nickname (if available) instead of full name in logger session log and QSO log
- Show callsign notes emoji in QSO log rows
- Show total contact count in logger session log and QSO log rows
- Move LoFi models, client, and helpers from app to CarrierWaveCore package
- Replace `LoFiClient()` with `LoFiClient.appDefault()` at all call sites

## [1.29.0] - 2026-02-10

### Added
- Add dual-color activity grid on dashboard — green for activations, blue for activity log, diagonal split for days with both
- Add deep link to CW Field Guide radio manuals — book icon in radio picker and MANUAL command in logger open the matching manual

## [1.28.0] - 2026-02-10

### Added
- Add spot age filter — only spots ≤12 minutes old shown by default, configurable 5–30 min in Activity Log settings
- Add spot sort order — toggle between Recent (newest first) and Frequency (low to high)
- Add proximity filter — "Heard Nearby" toggle in filter sheet with configurable radius (100–2000 mi) in settings
- Wire up SpotFilters.apply() — spot list now applies source, band, mode, worked, age, and proximity filters
- Default spot filters: POTA source, 20m band, CW mode, Heard Nearby, and Hide Already Worked enabled out of the box
- Deduplicate spot list by callsign+band — combines POTA and RBN reports for same station into single row, preferring POTA source
- Add Activity Log feature for persistent hunter workflow — always-open daily QSO tracking without session start/stop (CAR-47, Phase 1)
- Add ActivityLog SwiftData model and ActivityLogManager service for log lifecycle and QSO creation
- Add StationProfile model with UserDefaults-backed storage for reusable station configurations
- Add Dashboard card showing activity log setup prompt or today's QSO stats
- Add main ActivityLogView with daily counter header, quick log section, and recent QSOs
- Add station profile picker and add/edit sheets for managing equipment profiles
- Add Activity Log settings section with profile management, upload service info, and daily goal
- Activity log QSOs upload to QRZ and LoFi only (never POTA — no operator park reference)
- Add mini tour for Activity Log (4 pages: overview, quick entry, daily tracking, uploads)
- Add hunter spot list showing POTA and RBN spots with worked-before badges (CAR-47, Phase 2)
- Add tap-to-log half-sheet pre-filled from spot data (callsign, frequency, mode, park)
- Add spot filtering by source (POTA/RBN), band, mode, and hide-worked toggle
- Add worked-before cache with dupe detection, today/historical band tracking
- Add hunter monitoring mode to SpotMonitoringService for all-spots polling
- Add daily summary view with band timeline visualization and day navigation (CAR-47, Phase 3)
- Add location change detection sheet with grid distance display and profile switching
- Add daily QSO goal tracking with alert notification on goal reached
- Add daily activity share card for sharing day's QSO stats (CAR-47, Phase 4)
- Add share button to daily summary view
- Add activity feed integration — activity log QSOs now trigger activity detection (new DXCC, new band, DX contacts, streaks)

### Fixed
- Add accessibility labels to all icon-only buttons across Activity Log views (VoiceOver compliance)
- Mark decorative images as accessibilityHidden (empty state icons, age dots)
- Increase touch targets to 44×44pt minimum on filter chips, RST fields, and icon buttons
- Use @ScaledMetric for fixed-width columns (time, frequency, RST) to scale with Dynamic Type
- Replace hardcoded .white with Color(.systemBackground) for dark mode adaptability (band timeline, DXCC badge)
- Use static DateFormatter instances instead of computed properties (DailySummaryView, RecentQSOsSection)
- Add haptic feedback on QSO logging actions (quick log, spot log)
- Wrap LocationChangeSheet in NavigationStack with title and dismiss button
- Add HIG compliance rules and expanded accessibility checklist to design language docs

## [1.27.2] - 2026-02-09

### Changed
- Move Log QSO button inline next to callsign input field, always visible regardless of keyboard state (CAR-59)
- Replace full-width Log QSO / Run Command buttons with compact LOG/RUN/SAVE button that stays fixed-width to prevent layout shifts
- Anchor End Session confirmation dialog to the END button instead of bottom of screen
- Move Delete Session sheet buttons above spacer so they remain visible when keyboard is open

### Fixed
- Fix callsign input field width shifting when clear button appears by always reserving space for it
- Fix command mode purple border causing layout width changes by using strokeBorder
- Fix End Session confirmation dialog hidden behind keyboard by dismissing keyboard first

## [1.27.1] - 2026-02-09

### Added
- Add QSO timeline bar to activation detail, activation list rows, and share cards showing when contacts occurred during an activation with band-colored ticks and collapsed gaps (1hr+) shown as zigzag breaks

## [1.27.0] - 2026-02-09

### Added
- Add radio (rig) selection to session start wizard with a growing user-managed list, saved as default, propagated to all QSOs, visible in QSO detail, and exported as MY_RIG in ADIF
- Add transmit power (watts) field to session start wizard with 1,500W US max validation, saved as default, and automatically applied to all QSOs logged in the session
- Add mode-aware frequency suggestions for all modes in session start wizard — FT8, FT4, RTTY, AM, and FM now show correct frequencies instead of defaulting to CW (CAR-56)
- Add live "Active Now" section in session start showing POTA spots filtered by mode and license class, with clear-frequency recommendations based on ARRL band plan usage zones
- Add band plan reference sheet accessible from session start frequency section, showing band segments, license requirements, and activity frequencies
- Add RTTY activity frequencies to band plan data
- Add VHF/UHF band support (6m, 2m, 70cm) in frequency suggestions for FM mode

### Changed
- Enhance activation share card with RST-based colored dots on map (green/yellow/red matching the activation map), distance stats (avg/max), power, watts/mile, and radio info
- Show radio/rig and power on activation detail view and activation map overlay
- Add radio/rig selector to activation metadata edit sheet, applied to all QSOs in the activation

### Fixed
- Fix LoTW first sync making 25+ unnecessary API requests by trying single request first, falling back to adaptive windowing only on rate limit (CAR-44)
- Fix bug report showing "Not configured" for QRZ, LoFi, LoTW, and HAMRS services

## [1.26.1] - 2026-02-09

### Changed
- Redesign POTA activation cards with navigation-based detail view replacing inline disclosure groups
- Add prominent upload button directly on activation cards (full-width, borderedProminent style)
- Move secondary actions (edit, map, export, share, reject) to context menu and detail view toolbar
- Add dedicated activation detail view showing park info, upload controls, POTA jobs, and QSO list

### Fixed
- Fix POTA job matching for uploads where API returns nil firstQSO (e.g., all-duplicate uploads) by fuzzy-matching on park + callsign
- Display actual upload error messages inline on activation cards instead of vague "tap for details" text

## [1.26.0] - 2026-02-08

### Added
- Auto-record solar and weather conditions when starting a POTA logging session, stored in activation metadata (CAR-55)
- Add QSO detail view — tap any QSO in the Logs tab to see all metadata, sync status, notes, and source info (CAR-53)
- Show activation WPM, solar conditions, and weather in map callouts when tapping pins with POTA activation data (CAR-54)
- Persist average CW speed (WPM) from RBN spots to activation metadata when ending a POTA session (CAR-54)
- One-time backfill of average WPM for existing sessions that have stored RBN spot data (CAR-54)
- Show average CW speed from RBN spots in spot comments sheet during POTA activations (CAR-51)
- Collapse consecutive RBN spots in spot comments list into expandable groups to keep human comments visible (CAR-52)
- Warn when ending a POTA session during maintenance window (2330-0400 UTC) that uploads are unavailable, and suggest uploading later from the POTA Activations tab (CAR-49)

### Changed
- iPad sidebar now respects tab visibility settings immediately without requiring a restart (CAR-39)
- Remove 4-tab limit on iPad — all tabs can be shown in the sidebar (CAR-39)
- iPad shows all tabs by default on first launch instead of hiding Logger and Activity (CAR-39)
- Replace "More" tab with dedicated Settings entry in iPad sidebar (CAR-39)
- Rename "Tab Bar" settings to "Sidebar" when running on iPad (CAR-39)

### Fixed
- Normalize POTA park references at all import and entry points — fixes malformed refs like "US1234" or bare numbers being stored instead of "US-1234" (CAR-50)
- Auto-uppercase QRZ Callbook username field since QRZ usernames are always callsigns (CAR-41)
- Suppress "operator nearby" frequency warning when the nearby spot is the station being worked (e.g., tapping a POTA spot to hunt)
- Fix activation type resetting to Casual when scrolling the session start sheet (CAR-46)
- Fix 10m band plan missing CW mode in phone segment (28.300-28.500 MHz) for Technician and General licenses (CAR-38)
- Support dot-separated frequency notation (e.g., 14.030.50) for sub-kHz precision entry (CAR-40)
- Fix screen going to sleep after pausing and resuming a logging session despite "Keep screen on" being enabled (CAR-43)
- Fix callsign field cursor jumping to end when inserting numbers at a mid-text position (CAR-42)
- Fix activity grid in landscape and iPad showing too few columns — now shows a full year of history to fill available width

## [1.25.4] - 2026-02-08

### Added
- Add bulk actions for POTA activations with multi-select (upload, reject, export)

### Fixed
- Fix POTA upload error "No valid operator or station_callsign" for QSOs imported from HAMRS with empty myCallsign — fall back to user's primary callsign and emit both STATION_CALLSIGN and OPERATOR fields
- Fix bulk reject build error from missing CarrierWaveCore import and private modelContext access

## [1.25.3] - 2026-02-07

### Fixed
- Fix POTA reconciliation treating duplicate jobs (status 7) as unmatched, causing infinite re-upload loops for already-accepted activations
- Fix POTA reconciliation resetting in-progress jobs (pending/processing) back to needsUpload, causing duplicate uploads while POTA is still processing — now waits up to 30 minutes before considering a job stale

### Changed
- Document canonical sync flow ordering and invariants in sync architecture docs

## [1.25.2] - 2026-02-07

### Fixed
- Fix POTA uploads silently rejected due to wrong location in upload request — use park's actual location from POTA parks cache instead of unreliable grid-to-state derivation
- Add warning log when operator grid square maps to a different state than the park's known location

## [1.25.1] - 2026-02-07

### Added
- Add "Worked Friend" activity event — detect and surface QSOs with accepted friends in the activity feed

### Fixed
- Fix POTA uploads silently failing — detect empty `adif_files` response as rejection instead of assuming success
- Fix POTA submitted QSOs getting stuck permanently when POTA silently drops the upload (no job created) — reconciliation now resets orphaned submitted QSOs back to pending
- Mark QSOs with invalid park references (e.g., bare "US") as rejected to stop infinite retry loops

## [1.25.0] - 2026-02-07

### Added
- Add friend request notifications: badge on Activity tab and Friends toolbar button showing pending incoming request count, plus a banner card in the Activity feed that links to the Friends list
- Add detailed logging throughout POTA upload flow — upload request/response at INFO level (HTTP status codes, response bodies, ADIF content, request URLs), per-park timing, content summaries (bands/modes/date range), and per-job status/QSO count breakdowns during reconciliation
- Add "Force Reupload" button to POTA activation rows when debug mode is enabled — resets all QSOs back to pending and immediately triggers the upload

### Fixed
- Fix friend requests not appearing by syncing friends from server on Activity tab load and refresh
- Fix invite link deep links not matching when URL uses `activities.carrierwave.app` subdomain

## [1.24.2] - 2026-02-07

### Added
- Add community features opt-in during onboarding — users can choose to register with the activities server for friend discovery, challenges, and activity feeds
- Add "Enable community features" toggle in Activities settings to control discoverability in friend search
- Auto-register with activities server during sync if opted in but token is missing
- Add one-time community features prompt for existing users on Activity tab

### Changed
- Rename Challenges* files and types to Activities* (ChallengesClient, ChallengesError, ChallengesSyncService, ChallengesSettingsView)

### Fixed
- Fix friend invite link sheet dismissing on error instead of showing error message inline

## [1.24.1] - 2026-02-07

### Fixed
- Reconcile POTA upload presence against job log during sync — if the DB says a QSO is uploaded to POTA but no completed upload job exists, reset it to needs-upload so it gets re-uploaded

## [1.24.0] - 2026-02-07

### Changed
- POTA uploads now show as "submitted" (blue clock icon) until accepted by POTA job log, instead of immediately showing as complete — refresh jobs to see accepted status or retry failed uploads
- Consolidate POTA activation row actions (Edit, Map, Export, Share, Reject) into a single ellipsis menu button
- Show park reference and name inside expanded activation rows instead of cramming into the label
- Auto-expand activation rows that have pending uploads

### Fixed
- Fix POTA upload button not responding to taps — move upload action inside disclosure content where button taps work reliably instead of in the DisclosureGroup label where SwiftUI swallows taps
- Fix completed POTA jobs not reconciling QSO upload status — now auto-reconciles on view load, not just on manual refresh
- Fix QSO status circles staying gray after POTA job completes — single-park activations now use park-aware presence checks consistently, matching how confirmUploadsFromJobs writes per-park records

## [1.23.0] - 2026-02-06

### Added
- Edit activation metadata after completion — title, park reference, and watts via edit button or swipe action on activation rows
- Display activation metadata (title, watts, weather, solar) in activation rows and share cards
- Show all-time previous QSO count for each callsign entered in the logger
- Suggest friends based on QSO history — callsigns with 3+ contacts who are Carrier Wave users appear in the Friends list with Add/Dismiss actions
- Add detailed POTA upload debug logging — auth state, token metadata, ADIF preview, request/response details, and response headers in sync debug log

### Fixed
- Fix activation duration counting gaps between sessions — now sums individual session durations instead of spanning first-to-last QSO across all sessions
- Fix POTA uploads silently succeeding without sending data for two-fer (multi-park) activations. Park reference matching now correctly handles comma-separated references like "US-1044, US-3791"
- Fix legacy POTA needsUpload flag not being cleared after per-park uploads complete, causing repeated upload attempts
- Fix 2-3 second UI hang when opening Activities tab (replaced @Query with bounded fetch)
- Fix duplicate activities appearing in feed (e.g., "Made first CW contact" shown twice) — add dedup on creation and one-time cleanup of existing duplicates
- Fix evaluateNewQSOs loading entire QSO table instead of using fetchLimit
- Fix "Invite Friend" failing to generate a link when tapped before view fully appeared

## [1.22.2] - 2026-02-06

### Added
- POTA Jobs tab in Sync Debug view — centralized view of all POTA upload jobs sorted by date

### Fixed
- LoFi import now returns all park references for two-fer activations instead of only the first park
- Malformed park references from upstream APIs are now sanitized on import (e.g., "US1849" → "US-1849", bare numbers like "3687" dropped)

## [1.22.1] - 2026-02-05

### Fixed
- POTA upload prompt not appearing when ending an activation (was checking a UserDefaults key that was never set instead of Keychain credentials)

## [1.22.0] - 2026-02-05

### Added
- Map stats: activation time span, QSO/hr rate, average/longest distance, watts per mile on both QSO map and POTA activation map
- **Force Re-download** button on service detail sheets - tap any service on the dashboard to access full re-download without needing debug mode

### Fixed
- Number row buttons in logger now insert at cursor position instead of always appending to end of callsign

## [1.21.0] - 2026-02-05

### Added
- **POTA Job Status Display** - View POTA upload job statuses directly in the Activations view
  - Jobs are automatically matched to activations by park, date, and callsign
  - Warning icon appears on activations with failed jobs
  - Expand any activation to see all matching POTA jobs with status badges
  - Tap a job to view full details including errors and warnings from POTA processing
- **Two-fer POTA Upload Support** - Activations with multiple park references (e.g., "US-1044, US-3791") now upload correctly
  - QSOs are automatically split and uploaded to each park separately
  - Per-park upload status tracking shows which parks succeeded or failed
  - Combined activation row in POTA Activations view with single upload button
  - Tappable error icon shows failed parks with error messages
- **Two-fer Duplicate Repair** - Detect and merge duplicate QSOs from multi-source imports
  - Automatically detects QSOs with partial/truncated park references alongside complete versions
  - Dashboard prompts to merge duplicates when detected
  - Merges preserve the complete park reference and combine service presence records
- **DXCC Repair** - Background task repairs missing DXCC entities from raw ADIF data during sync

### Fixed
- DXCC entity now populated correctly during QRZ import (was missing in import path)
- LoTW sync now properly handles HTTP 403/503 errors instead of silently failing

## [1.20.0] - 2026-02-04

### Added
- **Friend Profile View** - Tap any callsign in the activity feed to view their profile
  - Shows recent activity from that friend
  - Displays activity stats (total activities, activities this week)
  - Shows friendship start date for connected friends
- **Friend Invite Links** - Generate shareable links to invite friends
  - Access via Friends list menu (three dots) > "Invite Friend"
  - Share link via iOS share sheet or copy to clipboard
  - Recipients can tap the link to send you a friend request

## [1.19.3] - 2026-02-03

### Added
- LoTW sync now fetches QSOs for all configured callsigns (current + previous), ensuring complete stats and confirmation tracking across callsign changes

### Fixed
- DXCC entity now populated from QRZ sync (previously only came from LoTW confirmations)

## [1.19.2] - 2026-02-03

### Added
- Tap-to-edit callsigns in session log - tap any callsign to bring it back to the input field for quick correction without changing the QSO timestamp

### Fixed
- POTA spot timestamps now parse correctly, showing "spotted X ago" in nearby operator warnings
- Log QSO button now remains accessible when RBN/POTA/Solar/Weather/Map panels are open - scroll content adds padding to keep the button visible above panels

## [1.19.1] - 2026-02-03

### Added
- Action Required log level in Sync Debug with purple highlighting for issues needing user attention

### Fixed
- QSOs logged under previous callsigns no longer show as permanently pending
  - Upload counts now only include QSOs matching the current primary callsign
  - New fixer automatically clears needsUpload flags on QSOs that would never upload
  - Logs which callsigns had pending uploads cleared during sync
- QSOs with missing band/frequency are now skipped during upload with a warning
  - Sync log shows which QSOs need manual correction (edit in Logs to add band)
  - Prevents silent upload failures for incomplete QSOs
  - Uses new "ACTION" log level with purple highlighting to stand out

## [1.19.0] - 2026-02-03

### Added
- **Activation Share Cards** - Share POTA activation summaries as images
  - Swipe right on any activation in POTA Uploads to reveal Share action
  - Card shows map with QSO locations and geodesic arcs to your location
  - Displays park reference, name, date, and stats (QSOs, duration, bands, modes)
  - Branded Carrier Wave styling for social sharing
- **Sync Debug Logging** - Detailed logging for diagnosing permanently pending QSOs
  - Logs which QSOs are pending upload to QRZ and POTA with full details (callsign, timestamp, band, mode, park reference, myCallsign)
  - Shows ServicePresence state (isPresent, needsUpload, rejected) for each pending QSO
  - Logs upload results and any errors for each service
  - Warns about QSOs that need POTA upload but have no park reference
  - View logs in Settings > Sync Debug

### Changed
- CW decoder feature hidden and disabled from the app (code retained for future re-enablement)

### Fixed
- Metadata pseudo-modes (WEATHER, SOLAR, NOTE) are no longer marked for upload
  - These Ham2K PoLo activation metadata entries were incorrectly showing as "pending" for QRZ and POTA
  - Now filtered at the source: `ImportService` and `LoggingSessionManager` skip upload markers for metadata modes
  - Existing metadata QSOs with pending upload flags are automatically repaired during sync
- Reduced noisy LoFi sync logs when account has cutoff date restriction
  - "QSO MISMATCH" warnings now only appear when there's no cutoff date (indicating a real issue)
  - Per-operation mismatch warnings removed entirely (they were expected behavior with cutoff dates)
- POTA no longer shows "Not configured" when session token expires
  - Now uses stored credentials to determine configuration status
  - Auto-reauthenticates with saved credentials when token expires during sync
  - Dashboard, sync, and upload all work seamlessly after token expiry
- LoTW sync no longer triggers "Page Request Limit!" (503) errors
  - Increased delay between requests from 0.5s to 3s to respect LoTW rate limits

## [1.18.0] - 2026-02-02

### Fixed
- Log search now searches all QSOs instead of only the most recent 1,000
  - Field-specific queries like `band:6m` now use database predicates for efficient full-table search
  - Fixed case mismatch bug where band queries failed (bands stored lowercase, query used uppercase)
- LoFi sync progress bar now displays during parallel service downloads
- Fixed POTA presence repair service crash due to SwiftData predicate not supporting enum values
- Dashboard no longer freezes UI when loading statistics for large QSO databases
  - Statistics computation now runs entirely on a background thread
  - Progress bar shows loading progress under Activity card
  - UI remains responsive during computation
- Sync processing no longer freezes UI at the end of QSO loading
  - QSO deduplication and creation now runs on a background thread
  - UI stays responsive during the "Processing" phase of sync
- LoFi sync no longer freezes UI during operation downloads
  - Parallel downloads with adaptive concurrency (2-8 concurrent requests)
  - Automatic backoff and concurrency reduction on errors
  - UI remains responsive during large syncs
- QSO conversion after download now yields periodically
  - Prevents UI freeze when processing large batches of downloaded QSOs
- Processing phase now shows progress bar instead of indefinite spinner
  - Displays current phase (Grouping, Loading, Processing, Saving)

### Added
- Dynamic sync progress indicator shows QSO count as services complete
- LoFi sync shows progress bar with percentage based on total QSOs
- **Flexible frequency input** - Enter frequencies as kHz or MHz with optional unit suffixes
  - Type "14060" or "14060 kHz" for kHz input (auto-converted to MHz)
  - Type "14.060" or "14.060 MHz" for MHz input
  - Units are case-insensitive ("khz", "KHz", "kHz" all work)
- RBN spots map shows spotter locations via HamDB grid lookup with arcs to target station
- Spotter circles sized by signal strength (SNR)
- **Background Spot Monitoring** - Automatic RBN/POTA spot monitoring during logging sessions
  - Spots polled every 45 seconds while session is active
  - Compact summary banner shows spot count, region breakdown (NE, EU, etc.), and distance range
  - Tap to expand and see individual spots with SNR, distance, and time ago
  - POTA spots included for POTA activations only
  - Distance shown in miles or kilometers (user setting in Logger settings)
- Spot age color coding: green (<2m), blue (2-10m), orange (10-30m), gray (>30m)
- "SELF" badge on spots where the activator matches your callsign
- Auto-attach POTA spot comments to matching QSOs as notes
- QRT spot posted automatically when ending POTA session (if session was spotted)
- Setting to enable/disable QRT spotting (Settings → POTA Activations)
- **P2P command** - Find park-to-park opportunities during POTA activations
  - Type `P2P` in logger to discover other POTA activators heard by nearby RBN skimmers
  - Cross-references POTA spots with RBN data from skimmers within 500km of your grid
  - Shows SNR, frequency, park info, and age for each opportunity
  - Tap to auto-fill callsign, frequency, and P2P notes in logger

### Changed
- RBN spots now limited to last 10 minutes (was 6 hours)

### Fixed
- Fix LoFi sync failing when operations are missing `updatedAtMillis` field
- Fix Dashboard stats flashing during recomputation after sync
- Fix UI freeze when service detail sheet is open during stats recomputation
- Fix callsign suffix detection treating W1WC/CW as unconfigured alternate callsign
- Fix crash when deleting QSOs from Logs tab due to array index invalidation during SwiftUI list update
- Fix RBN spots not appearing in spot menu due to incorrect API response field mapping

## [1.17.0] - 2026-02-01

### Added
- **Quick Entry Mode** - Type complete QSOs in a single line for rapid logging
  - Type "AJ7CM 579 WA US-0189" to auto-fill callsign, RST, state, and park reference
  - Supports RST (2-3 digit), grid square (4-6 char), state/province codes, POTA park references
  - Color-coded token preview shows what each field will be populated with
  - Single RST applies to received; two consecutive RSTs become sent/received
  - Unrecognized tokens become QSO notes
- **Park Search and Nearby** - Enhanced park entry with name search and nearby parks
  - Search parks by name with full-text search picker
  - See nearby parks based on your grid square location
  - Park number shorthand: type "1234" to auto-expand to "US-1234"
- **State Entry Field** - Manual state entry/override in QSO logger
  - Appears in More Fields section (can be set to always visible)
  - Overrides QRZ lookup state when manually entered
- **Logger Layout Improvements** - Condensed QSO entry form
  - Removed magnifying glass icon from callsign input (only shows command icon when applicable)
  - Default fields: State, RST Sent, RST Received on single row
  - Chevron button expands to show Grid, Park, Operator, Notes
  - All text fields use consistent height and font size
- **POTA Spots Panel** - Dedicated view for active POTA activator spots
  - Filter by band and mode (defaults to session's current band/mode)
  - Grouped by band with section headers
  - Tap spot to tune to frequency
  - Access via `POTA` command in logger
- **Operator Field QRZ Hint** - Operator field now shows QRZ name as placeholder hint and logs it automatically if not overridden
- **Logs Tab Tour** - Added intro tour for the Logs tab explaining the query language
  - Overview of simple callsign search and wildcards
  - Field filter syntax (band, mode, state, park, grid)
  - Date filter examples (after:7d, date:today, before:)
  - Status filters (confirmed, synced, pending)
  - Combining filters with AND/OR/NOT
- **Log Search Query Language** - Powerful search for QSO logs with field-specific filters
  - Basic search: type callsigns, park references, or SOTA refs directly
  - Field filters: `band:20m`, `mode:CW`, `state:CA`, `park:K-*`, `grid:FN31`
  - Date filters: `date:today`, `after:7d`, `after:30d`, `date:2024-01`
  - Status filters: `confirmed:lotw`, `synced:pota`, `pending:yes`
  - Boolean logic: implicit AND, `|` for OR, `-` for NOT
  - Performance warnings for slow queries with suggestions to add filters
  - Quick filters menu for common searches
  - Help sheet with syntax reference

### Changed
- **QSO Deletion Confirmation** - Deleting a QSO in the logger now shows a confirmation dialog

### Fixed
- **QSO Deletion in Logger** - Fixed deleted QSOs not disappearing from session log until view refresh
  - QSO list now updates immediately when a QSO is deleted from the edit sheet
- **Quick Entry Notes Display** - Multi-word notes now display as a single combined badge instead of separate badges per word
- **Quick Entry Button Logging** - Fixed Log QSO button logging entire input string instead of parsed callsign in quick entry mode
- **Quick Entry Typing Crash** - Fixed crash when typing in quick entry mode caused by unstable SwiftUI identifiers
  - ParsedToken now uses position-based IDs instead of random UUIDs
  - Prevents view hierarchy rebuild during active text input
- **Sync Callsign Filtering** - QSOs from previous callsigns no longer appear in sync queues
  - Import now only creates upload markers for QSOs matching primary callsign
  - Sync fetch adds defense-in-depth filtering for legacy data
  - Prevents failed uploads to QRZ/POTA when user has changed callsigns

## [1.16.2] - 2026-02-01

### Fixed
- **Logger Text Input Lag** - Fixed multi-second input lag when typing in logger callsign field for users with large databases
  - Removed unbounded @Query from SessionMapPanelView (now uses passed session QSOs)
  - Removed unbounded @Query from HiddenQSOsSheet (now fetches by session ID)
  - Removed dead keyboard height tracking that triggered unnecessary re-renders
- **App-Wide Full Table Scan Elimination** - Replaced all unbounded @Query usages with paginated background fetching
  - DashboardView: stats and service counts now compute in background
  - QSOMapView: uses pagination with "Show All" option
  - LogsListView: uses "Load More" pagination
  - POTAActivationsView: loads park QSOs in batches
  - CallsignAliasesSettingsView: computes QSO counts in background
  - ChallengeDetailHelperViews: QualifyingQSOsView uses limited fetch
  - AllHiddenQSOsView: uses "Load More" pagination
- **Dashboard Build Error** - Fixed reference to non-existent property in sync time observer

## [1.16.1] - 2026-01-31

### Added
- **Persistent Callsign Notes Cache** - Polo notes now load instantly on app launch from disk cache, with background refresh

### Fixed
- **Session Delete Crash** - Fixed crash when deleting a logging session by properly ending the session before deletion
- **QRZ Name Display** - Now shows QRZ nickname instead of full formal name when available
- **False Callsign Detection** - Placeholder strings like "EVENT" are no longer incorrectly detected as unconfigured callsigns

## [1.16.0] - 2026-01-31

### Added
- **Hidden QSOs Management** - View and restore hidden (deleted) QSOs in Settings → Developer → Hidden QSOs
  - See all hidden QSOs across the app
  - Restore individual QSOs or all at once
  - Option to permanently delete hidden QSOs
- **Sub-kHz Frequency Precision** - Logger now supports entering and displaying frequencies with sub-kHz precision (e.g., 14.03050 MHz)
- **Auto-Focus Callsign Field** - Callsign field is automatically focused after logging a QSO for rapid contest-style entry
- **Background QSO Enrichment** - Grid, name, and other callsign data are now saved to QSOs even when logged before lookup completes

### Changed
- **Delete Session Confirmation** - Session deletion now requires typing "delete" to confirm, preventing accidental data loss
- **Onboarding Skip Button** - Button now shows "Next" instead of "Skip" when services have been connected, clarifying that connections are saved
- **iPad Sidebar Shows All Tabs** - iPad now shows all tabs in the sidebar by default (no 4-tab limit)
- **Technician Band Warning** - Clearer warning message for bands where Technicians have no privileges at all (e.g., "Technicians cannot operate in any mode within the 20m band")
- **RST Fields** - RST fields now start empty with placeholder hints (599/59) instead of pre-filled values
- **Removed Quick Log Mode** - Fast logging is now the default and only mode; setting removed from preferences

### Fixed
- **Settings Crash on Launch** - Fixed crash when navigating to service settings (QRZ, POTA, LoFi, etc.) due to missing SyncService environment object
- **Logger Submit Crash** - Fixed crash when pressing Return in logger callsign field while keyboard is dismissing
- **Technician CW Privileges** - Fixed incorrect warnings for Technicians operating CW on 80m (3.525-3.600), 40m (7.025-7.125), and 15m (21.025-21.200) bands
- **iPad Tab Settings** - Tab bar setting changes now take effect immediately on iPad without requiring app restart
- **Logger Submit Lag** - QSO logging is now instant with no visible delay
  - Replaced full-database @Query with session-scoped fetch
  - Cached service configuration to avoid Keychain reads per-QSO
  - Prevented redundant callsign lookups when QSO list re-renders
  - Disabled animations during form reset for immediate feedback

## [1.15.3] - 2026-01-31

### Fixed
- **Settings Crash on Launch** - Fixed crash when navigating to Settings before SyncService initialized
- **QSO Statistics Performance** - Major performance improvements for users with 15k+ QSOs
  - Refactored QSOStatistics to a class with cached computations (realQSOs, activation groups, category items, streaks)
  - Dashboard now computes stats asynchronously off the main thread
  - Cached activation grouping eliminates duplicate O(n) iterations for successful/attempted activations
  - Static DateFormatter in park grouping eliminates repeated allocation
  - FavoritesCard now defers item computation until navigation
  - LogsListView caches filtered QSOs and available bands/modes
  - QSOMapView caches filter options and stats (uniqueStates, uniqueDXCCEntities)
  - StatDetailView caches sorted items instead of resorting on every render

## [1.15.2] - 2026-01-31

### Fixed
- **Save as Defaults Button** - Now shows visual checkmark confirmation when tapped
- **Skip Wizard Setting** - "Skip wizard next time" now works correctly, auto-starting sessions with saved defaults
- **Save Defaults Completeness** - Activation type and park reference are now saved as defaults

## [1.15.1] - 2026-01-31

### Fixed
- **Tab Switching Performance** - Reduced lag when switching between tabs
  - Added lazy loading for Dashboard, Map, and Activity tabs (content deferred until visible)
  - Cached QSOStatistics in Dashboard to avoid recomputing on every render
  - Cached map annotations and arcs to avoid expensive coordinate conversions on every render
- **Logger Text Field Performance** - Fixed significant lag when typing callsigns
  - Cached DateFormatter instead of creating new instance on every render
  - Cached POTA duplicate status to avoid filtering all QSOs on every keystroke

## [1.15.0] - 2026-01-31

### Added
- **Tab Bar Configuration** - Customize which tabs appear and their order
  - Settings → Navigation → Tab Bar
  - All tabs (Dashboard, Logger, Logs, CW, Map, Activity) can be shown/hidden
  - Drag to reorder tabs in the tab bar
  - Hidden tabs appear in the More menu
  - Map and Activity start hidden by default, accessible from More
- **NOTE Command** - Add timestamped notes to the session log
  - Type `NOTE <text>` in logger input (e.g., `NOTE Band is noisy`)
  - Notes appear in the Session Log interleaved with QSOs
  - Notes are stored with UTC timestamp
- **Configurable Always-Visible Fields** - Toggle which QSO fields stay visible
  - Settings → Logger → Always visible fields
  - Options: Notes, Their Grid, Their Park, Operator
  - Configured fields appear without tapping "More"
  - Preferences persist across sessions
- **Delete Session** - Remove unwanted sessions before sync
  - Long-press or tap END button to access menu
  - "Delete Session" hides all QSOs and removes the session
  - Hidden QSOs won't sync to external services
- **Callsign Prefix/Suffix Support** - Construct callsigns for portable operations
  - Add country prefix when operating abroad (e.g., I/W6JSV)
  - Standard suffixes: /P (Portable), /M (Mobile), /MM (Maritime), /AM (Aeronautical)
  - Custom suffix option for regional indicators or other uses
  - Full callsign displayed prominently with color-coded breakdown

### Changed
- **Bare Mode Switching** - Enter mode name directly (CW, SSB, FT8, etc.) instead of requiring "MODE CW"
- **QSY Spot Confirmation** - Frequency and mode changes during POTA activations now prompt to post a QSY spot instead of auto-posting
- **Auto Mode Detection** - Changing frequency automatically switches to the appropriate mode for that segment (CW for CW/DATA segments, SSB for phone segments)
  - New setting "Auto-switch mode for frequency" to enable/disable this behavior

### Fixed
- **POTA Duplicate Blocking** - Same band/date duplicates are now blocked, not just warned
  - Log button is disabled when entering a duplicate callsign on the same band
  - Duplicate warning banner still shows to explain why logging is blocked
- **Hidden QSOs Excluded from All Views** - Hidden QSOs no longer appear in:
  - Dashboard statistics (total QSOs, QSLs, entities, grids, bands, parks, streaks)
  - Map view
  - POTA Activations view
  - Challenge progress
  - Callsign alias detection
- **License Class Persisted** - QSOs now save the contacted station's license class from QRZ lookup
- **Callsign Notes Ordering** - Emojis and source names from Polo notes now display in consistent alphabetical order by source title
- **Activity Grid Clipping on iPad** - Calendar activity view no longer cut off in landscape with navigation menu hidden
- **Callsign Lookup Error Feedback** - Logger now shows why callsign lookups fail
  - Displays actionable error when QRZ API key is missing
  - Shows authentication errors with recovery suggestions
  - Network errors displayed with helpful messages
  - Previously failed silently with no indication
- **QRZ Callbook Login Restored** - Re-added QRZ Callbook login in Settings → External Data
  - Uses proper username/password authentication (separate from Logbook API key)
  - Requires QRZ XML Logbook Data subscription for callsign lookups

### Removed
- **Feature Selection in Onboarding** - Removed now-redundant step for enabling/disabling Logger and CW Decoder
  - Tab visibility is now configured via Settings → Navigation → Tab Bar

## [1.14.0] - 2026-01-30

### Added
- **QSY Auto-Spotting** - Automatically post QSY spot to POTA when frequency changes during active POTA session
- **HIDDEN Command** - View and restore deleted QSOs from current session
  - Type `HIDDEN` or `DELETED` in logger input to show deleted QSOs
  - Restore button to un-delete individual QSOs

### Changed
- **Cleaner Logger UI** - Removed navigation bar title and top bar Start Session button

### Fixed
- **iPad Settings Navigation** - Changing sidebar tab now properly exits Settings submenus
- **QSO Count Accuracy** - Session QSO count now excludes deleted QSOs
- **Logs List Filter** - Hidden QSOs no longer appear in the Logs tab

### Added
- **Configurable Callsign Notes Files** - Add custom Polo-style notes files in Settings
  - Configure title and URL for each source
  - Sources fetched and cached, refreshed daily
  - Enable/disable individual sources
  - View entry count and last fetch status
- **Merged Callsign Notes Display** - When callsign appears in multiple notes sources
  - All emojis from matching sources shown together
  - Last source's note text used for display
  - Tracks which sources matched for reference
- **Notes Display Mode Toggle** - Choose how callsign notes are displayed
  - Emoji mode: Shows combined emoji from all matching sources
  - Source names mode: Shows source titles as chips
- **MAP Command** - View session QSOs on a map
  - Type `MAP` in the logger input to show session map panel
  - Displays QSO locations with geodesic paths from your location
  - Swipe-to-dismiss panel like RBN/Solar/Weather
- **Editable Session Title** - Tap the session title to customize it
  - Custom title persists across app restarts
  - Clear custom title to revert to default (callsign + activation type)
- **Navigate to Logs on Session End** - Automatically switch to Logs tab when ending a session with QSOs
- **RBN/POTA Spot Lookup** - View combined spots from RBN and POTA
  - `RBN` command shows your spots from both RBN and POTA
  - `RBN <callsign>` command to look up any callsign's spots
  - Unified spot display with source badges (RBN/POTA)
  - Mini-map view for RBN spotter locations
- **POTA Spot Comments** - Real-time hunter feedback during activations
  - Background polling for spot comments during active POTA sessions
  - Spot comments button in session header with new comment count badge
  - Comments sheet to view all hunter feedback
- **POTA Auto-Spotting** - Automatic self-spotting during POTA activations
  - Toggle in Logger Settings to enable auto-spotting every 10 minutes
  - Automatically posts initial spot when starting a POTA session
  - Timer pauses when session is paused and resumes with the session
- **User Onboarding Flow** - Profile setup after intro tour
  - Enter callsign and automatically fetch profile from HamDB.org
  - Displays name, QTH, grid square, license class, and expiration date
  - Pre-fills service credentials with callsign (username shown grayed out, just enter password)
  - Connect QRZ, LoTW, and POTA during onboarding
  - Profile stored securely and used throughout the app
- **About Me** - New profile section in Settings
  - View and edit your profile information
  - Refresh profile data from HamDB
  - Shows callsign, name, location, grid, and license class
- HamDB license class lookup in Logger Settings
  - Automatically look up license class from HamDB.org by tapping search icon
  - Works with US amateur radio callsigns (no authentication required)
  - Supports Extra, General, Technician, Advanced (mapped to Extra), and Novice (mapped to Technician)
- LoFi sync test script (`scripts/lofi-sync-test.swift`) for local testing

### Changed
- **Improved RST Labels** - Changed from "RST/S" and "RST/R" to "Sent" and "Rcvd" for clarity
- **RST Defaults by Mode** - RST defaults to 599 for CW/digital modes, 59 for phone modes
  - Automatically updates when changing modes during a session
  - Resets appropriately after logging each QSO
- **End Session Button** - Replaced 3-dot menu with a dedicated "End Session" button
  - Shows red "End Session" when session is active
  - Shows green "Start Session" when no session
  - Navigation title hidden during active sessions to save space
- Onboarding profile setup now skipped if callsign is already configured
- Add "Later" button to onboarding flow to defer profile setup

### Fixed
- Fix crash on iOS 26 when checking for existing profile during onboarding (actor isolation violation)
- LoFi sync pagination now fetches all operations (was stopping after first page of 50)
  - Server returns `next_updated_at_millis` when using `synced_since_millis` pagination
- LoFi QSOs with missing `startAtMillis` field no longer crash sync (field is now optional)
- **Logger Field Testing Fixes** - Multiple improvements from POTA activation feedback
  - Screen timeout prevention during active logging sessions (new "Keep screen on" setting, enabled by default)
  - Quick Log Mode setting to disable animations for faster pileup logging
  - UTC time display consistency - QSO list now shows UTC times with "Z" suffix
  - QRZ callsign lookup now works - implemented QRZ XML callbook API integration
  - Compact callsign info bar appears above keyboard when typing
  - SPOT command now accepts comments (e.g., `SPOT QRT`, `SPOT QSY 14.062`)
  - Map now shows activation QSOs - grid from callsign lookup is saved to QSO
  - State, country, and QTH from callsign lookup are now saved to logged QSOs

## [1.13.1] - 2026-01-29

### Fixed
- LoFi sync debug logging now appears in in-app sync logs and bug reports (was only going to system console)

## [1.13.0] - 2026-01-29

### Added
- **Under Construction Banner** - Dismissible warning for features still in development
  - Shows on Logger and CW Decoder tabs
  - Can be dismissed per-session or permanently hidden
- **Keyboard Number Row** - Quick frequency entry in Logger
  - Number row (0-9 and decimal) appears above keyboard when entering callsigns
  - Keyboard dismiss button to hide keyboard
- **Enhanced LoFi Sync Debugging** - Comprehensive logging for diagnosing sync issues
  - Logs account cutoff_date from registration response (explains limited data access)
  - Logs operation and QSO count mismatches with expected vs actual totals
  - Logs date ranges of operations and QSOs fetched
  - Logs pagination details (records_left, synced_until, synced_since)
  - Logs per-operation QSO count mismatches with POTA reference and date info
  - Warning when 0 QSOs returned for operations that should have data
  - Bug reports now include LoFi-specific details (linked status, callsign, last sync timestamp)
- **QSO Logger Tab** - Streamlined logging for activations and casual operating
  - Session-based logging with configurable wizard (mode, frequency, activation type)
  - Soft delete pattern - QSOs are hidden, never truly deleted (WAL durability)
  - Command input: type frequency (14.060), MODE, SPOT, RBN, SOLAR, WEATHER in callsign field
  - Callsign lookup integration (Polo notes + QRZ) with info card display
  - RST fields with expandable "More" section for notes, their park, operator
  - Recent QSOs list filtered by current session
- **RBN Integration** - Real-time Reverse Beacon Network spots
  - RBN panel showing your spots with signal strength and timing
  - Mini-map view showing spotter locations
  - Frequency activity monitoring (±2kHz) with QRM assessment
- **Solar & Weather Conditions** - NOAA data integration
  - Solar panel showing K-index, SFI, propagation forecast
  - HF band outlook based on current conditions
  - Weather panel from NOAA with outdoor/antenna/equipment advisories
- **Band Plan Validation** - License class privilege checking
  - Warning banner when operating outside license privileges
  - Technician/General/Extra class support
  - Mode validation (CW vs SSB segments)
- **POTA Self-Spotting** - Post spots directly from the logger
  - Integrates with existing POTA authentication
  - One-command spotting during activations
- **Toast Notifications** - Feedback for logger actions
  - QSO logged, spot posted, command executed confirmations
  - Friend spotted alerts when friends appear on RBN
- **CW Adaptive Frequency Detection** - Automatically detects CW tone frequency within a configurable range
  - Filter bank of Goertzel filters scans 400-900 Hz (default) with 50 Hz spacing
  - Locks onto detected frequency after confirmation, stays locked during gaps between elements
  - Three range presets: Wide (400-900 Hz), Normal (500-800 Hz), Narrow (550-700 Hz)
  - Toggle between adaptive and fixed frequency modes in settings menu
  - Detected frequency displayed in UI with auto-detect indicator
- **CW Chat Transcription** - View decoded CW as a conversation between stations
  - Chat/Raw toggle to switch between conversation bubbles and raw transcript
  - Turn detection using frequency changes and prosigns (DE, K, KN, BK)
  - Messages grouped by speaker with callsign attribution
  - Left/right aligned bubbles for other station vs. you
- **Enhanced CW Highlighting** - More intelligent text pattern detection
  - Grid squares highlighted (e.g., EM74)
  - Power levels highlighted (e.g., 100W)
  - Operator names highlighted after NAME/OP keywords
  - Signal reports highlighted with "UR" prefix context
- **Callsign Lookup** - Automatic callsign information from multiple sources
  - Polo notes lists checked first (local, fast, offline)
  - Name and emoji displayed in chat bubbles when available
  - Two-tier lookup architecture ready for QRZ XML API

## [1.12.0] - 2026-01-28

### Added
- **iPad Support** - Full iPad-optimized layouts following Apple HIG
  - Sidebar navigation on iPad (NavigationSplitView) instead of tab bar
  - Activity view uses side-by-side layout (challenges + feed columns)
  - Dashboard stats grid shows all 6 stats in one row on iPad
  - Activity grid dynamically shows 26-52 weeks based on screen width
  - iPhone retains existing TabView navigation (unchanged)

## [1.11.1] - 2026-01-28

### Fixed
- Crash during sync when evaluating challenge progress (SwiftData predicate used computed property instead of stored property)

## [1.11.0] - 2026-01-28

### Added
- **Activity tab** (renamed from Challenges)
  - Activity feed showing friend, club, and personal activities
  - Filter bar to show All, Friends only, or Clubs only
  - Activity detection for notable events (new DXCC, bands, modes, DX contacts, streaks)
  - Automatic activity reporting to server during sync
- **Friends**
  - Friends list showing accepted friends and pending requests
  - Friend search by callsign
  - Send, accept, and reject friend requests
- **Clubs**
  - Clubs list showing memberships (via Polo notes lists)
  - Club detail view with member list
- **Adaptive sync for rate limiting**
  - LoTW: Adaptive date windowing automatically shrinks time windows when hitting rate limits
  - POTA: Adaptive batch processing adjusts batch size on timeouts
  - Resumable downloads with checkpoints survive app restarts
- **Tour updates**
  - Activity tab added to intro tour
  - Expanded social mini-tour explaining friends and clubs
- "Ready to Upload" section in POTA Activations view
  - Pending activations pinned to top, sorted by date descending
  - Park reference shown in each row for easy identification

### Fixed
- POTA tour text changed from "AWS Cognito" to "External Logins (Google, Apple, etc.)" for clarity
- Map confirmed filter now includes QSOs confirmed by either QRZ or LoTW (union)
- Crash after device sleep when evaluating challenge progress
- Sync pagination handling improved

## [1.10.0] - 2026-01-28

### Added
- QSO Map view improvements:
  - States and DXCC counts in stats overlay
  - "Show Individual QSOs" toggle for small dot markers per QSO
  - Always-visible active filters display (dates, band, mode, park, confirmed)
  - Geodesic curve paths to contacted stations (renamed from "Show Arcs")
  - Performance limit (500 QSOs) with toggle to show all
- Streak statistics improvements:
  - POTA section showing valid/attempted activation counts
  - Best streak date ranges now include year
- Intro tour updates:
  - New Statistics step highlighting streaks and activity tracking
  - New Map step highlighting geodesic paths and filters

### Fixed
- Map date picker now defaults to earliest QSO date instead of invalid date
- Metadata modes (SOLAR, WEATHER, NOTE) filtered from map mode picker
- All streaks now use UTC consistently for date calculations
- Tour text alignment in Track Your Progress step
- Swift 6 concurrency warnings

## [1.9.0] - 2026-01-27

### Added
- Callsign Aliases feature for users who have changed callsigns over time
  - Configure current callsign and list of previous callsigns in Settings
  - Auto-detects multiple callsigns in QSO data and suggests adding as aliases
  - QRZ sync now properly matches QSOs logged under any user callsign
  - Current callsign auto-populated from QRZ on first connection

## [1.8.3] - 2026-01-27

### Added
- "Request a Feature" button in Settings linking to Discord

### Fixed
- Deduplication now treats equivalent modes as duplicates (PHONE/SSB/USB/LSB/AM/FM/DV, DATA/FT8/FT4/PSK31/RTTY)
- When merging duplicates, the more specific mode is preserved (e.g., SSB over PHONE)

## [1.8.2] - 2026-01-27

### Added
- Bug report feature with clipboard copy and Discord link in Settings
- Discord server link in Settings

### Fixed
- Configure button on dashboard service cards now navigates to settings instead of spinning indefinitely

## [1.8.0] - 2026-01-27

### Changed
- Redesigned dashboard services section as a compact vertical stacked list
  - Replaced 2x3 grid of large cards (~130pt each) with HIG-compliant list rows (~44pt each)
  - Each service shows status indicator, name, sync count, and optional secondary stats
  - Tapping a service opens a detail sheet with full stats and actions
- Consistent "Not configured" status text across all services

### Fixed
- Consider park reference when merging duplicate QSOs

## [1.7.0] - 2026-01-26

### Added
- POTA parks cache for displaying human-readable park names throughout the app

### Fixed
- Dashboard activation stats now match POTA activations view calculations
- Swift 6 concurrency warnings in POTAParksCache

## [1.6.0] - 2026-01-26

### Fixed
- Handle case where user hasn't finished POTA account setup
- POTA login and activation grouping improvements
- Show QSO rows in POTA uploads view

## [1.5.0] - 2026-01-25

### Added
- Force re-download debug buttons for all services (LoFi, HAMRS, LoTW, QRZ, POTA)
- Methods to force re-download and reprocess QSOs from any service

### Fixed
- POTA uploads reliability improvements
- DXCC entity handling

## [1.2.0] - 2026-01-25

### Added
- QRZ QSL confirmed count on dashboard
- POTA Activations view replacing POTA Uploads segment
  - QSOs grouped by park and date
  - Shows activation status (valid/incomplete)
- POTA maintenance window handling (0000-0400 UTC)
  - Countdown timer on dashboard
  - Uploads automatically skipped during maintenance
  - Developer bypass option in debug mode
- Connected status icons for all services

### Changed
- Reorganized POTA views into POTAActivations directory

### Fixed
- Remove logout/disconnect menus from dashboard service cards
- POTA sync button disabled during maintenance window
- WebView creation dispatched to main actor
- Handle POTA 403 errors same as 401

## [1.1.0] - 2026-01-25

### Added
- POTA maintenance window detection and handling
- LoTW integration for QSL confirmations
- QSLs stat card on dashboard (replacing Modes)

### Changed
- Various UI improvements following Apple HIG

## [1.0.0] - 2026-01-24

### Added
- Initial release
- QSO logging with SwiftData persistence
- Cloud sync to QRZ, POTA, Ham2K LoFi, HAMRS, and LoTW
- iCloud file monitoring for ADIF imports
- Dashboard with activity grid and statistics
- DXCC entity tracking
- Grid square tracking
- Band and mode statistics
