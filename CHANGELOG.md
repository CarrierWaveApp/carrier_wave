# Changelog

All notable changes to Carrier Wave will be documented in this file.

## [Unreleased]

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
