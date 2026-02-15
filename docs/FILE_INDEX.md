# File Index

This index maps files to their purpose. Use it to locate files by feature instead of scanning the codebase.

**Maintenance:** When adding, removing, or renaming files, update this index.

## CarrierWaveCore Package (`CarrierWaveCore/`)

Pure logic library that can be tested without iOS Simulator. Run tests with `make test-unit-core`.

| File | Purpose |
|------|---------|
| `Sources/CarrierWaveCore/ADIFParser.swift` | ADIF file format parsing |
| `Sources/CarrierWaveCore/BandUtilities.swift` | Band derivation from frequency |
| `Sources/CarrierWaveCore/CallsignDetector.swift` | Callsign regex detection, RST/grid/power parsing |
| `Sources/CarrierWaveCore/CWTextElement.swift` | CW text element types for transcript highlighting |
| `Sources/CarrierWaveCore/DeduplicationMatcher.swift` | Duplicate detection logic |
| `Sources/CarrierWaveCore/DetectedCallsign.swift` | Detected callsign with context |
| `Sources/CarrierWaveCore/FrequencyFormatter.swift` | Frequency formatting and parsing |
| `Sources/CarrierWaveCore/MaidenheadConverter.swift` | Grid square ↔ coordinate conversion |
| `Sources/CarrierWaveCore/ModeEquivalence.swift` | Mode family classification and equivalence |
| `Sources/CarrierWaveCore/MorseCode.swift` | Morse code tables and timing utilities |
| `Sources/CarrierWaveCore/MorseEditDistance.swift` | Levenshtein distance on morse patterns |
| `Sources/CarrierWaveCore/ParkReference.swift` | Park reference parsing and validation |
| `Sources/CarrierWaveCore/QSOSnapshot.swift` | Lightweight QSO representation for matching |
| `Sources/CarrierWaveCore/QuickEntryParser.swift` | Quick entry string parsing |
| `Sources/CarrierWaveCore/ServiceType.swift` | Sync service type enum (QRZ, POTA, LoFi, etc.) |
| `Sources/CarrierWaveCore/StreakCalculator.swift` | Streak calculation from date sets |
| `Sources/CarrierWaveCore/SuggestionCategory.swift` | CW suggestion category enum |
| `Sources/CarrierWaveCore/TwoferMatcher.swift` | Two-fer duplicate detection |
| `Sources/CarrierWaveCore/QueryLanguage/QueryToken.swift` | Query token types and field definitions |
| `Sources/CarrierWaveCore/QueryLanguage/QueryLexer.swift` | Query string tokenization |
| `Sources/CarrierWaveCore/QueryLanguage/QueryAST.swift` | Query AST types (expression, term, condition) |
| `Sources/CarrierWaveCore/QueryLanguage/QueryParser.swift` | Token stream to AST parsing |
| `Sources/CarrierWaveCore/QueryLanguage/QueryAnalyzer.swift` | Query performance analysis and warnings |
| `Sources/CarrierWaveCore/LoFi/LoFiCredentialStore.swift` | Protocol + key enum for credential storage |
| `Sources/CarrierWaveCore/LoFi/LoFiLogger.swift` | Protocol for logging |
| `Sources/CarrierWaveCore/LoFi/LoFiModels.swift` | LoFi API request/response models (operations, registration) |
| `Sources/CarrierWaveCore/LoFi/LoFiModels+QSO.swift` | LoFi QSO response models (QSOs, metadata) |
| `Sources/CarrierWaveCore/LoFi/LoFiClient.swift` | Ham2K LoFi sync client (core, config, setup) |
| `Sources/CarrierWaveCore/LoFi/LoFiClient+Fetch.swift` | LoFi fetch endpoints (operations, QSOs) |
| `Sources/CarrierWaveCore/LoFi/LoFiClient+Sync.swift` | LoFi sync orchestration (full download, progress) |
| `Sources/CarrierWaveCore/LoFi/LoFiClient+Helpers.swift` | LoFi helpers (token, secret gen, request, accumulator) |

## LoFi CLI (`Sources/LoFiCLI/`)

Standalone CLI tool for testing LoFi downloads without iOS Simulator. Run with `cd CarrierWaveCore && swift run lofi-cli`.

| File | Purpose |
|------|---------|
| `Sources/LoFiCLI/LoFiCLI.swift` | CLI entry point with register/link/download/status subcommands |
| `Sources/LoFiCLI/LoFiCLI+Pipeline.swift` | Sync report pipeline breakdown (skipped, two-fer, dupe analysis) |
| `Sources/LoFiCLI/FileCredentialStore.swift` | LoFiCredentialStore backed by ~/.config/lofi-cli/credentials.json |
| `Sources/LoFiCLI/ConsoleLogger.swift` | LoFiLogger that prints to stderr with level prefixes |

## Entry Points
| File | Purpose |
|------|---------|
| `CarrierWave/CarrierWaveApp.swift` | App entry point, SwiftData container setup |
| `CarrierWave/ContentView.swift` | Root TabView/NavigationSplitView for programmatic tab switching |
| `CarrierWave/TabConfiguration.swift` | AppTab enum, TabConfiguration manager, SettingsDestination |

## Models (`CarrierWave/Models/`)
| File | Purpose |
|------|---------|
| `QSO.swift` | Core contact record (callsign, band, mode, timestamps, grid, park ref) |
| `QSO+POTAPresence.swift` | Per-park POTA presence tracking for two-fer activations |
| `UploadDestination.swift` | Sync target configuration (enabled flag, last sync timestamp) |
| `POTAJob.swift` | POTA job tracking, status, details models (POTAJob, POTAJobDetails, POTAJobStatus) |
| `POTALogEntry.swift` | Individual POTA log entries |
| `POTAUploadAttempt.swift` | POTA upload attempt history and status |
| `ServicePresence.swift` | Service connection status tracking |
| `ActivationMetadata.swift` | Activation-level metadata storage |
| `ActivationStatistics.swift` | Pure stats computation for POTA activations (distance, timing, distribution, RST, entities) |
| `StatCategoryItem.swift` | Individual stat item for dashboard display |
| `StatCategoryType.swift` | Stat category enum (band, mode, DXCC, etc.) |
| `Types.swift` | Shared type definitions |
| `ChallengeDefinition.swift` | Challenge metadata and rules |
| `ChallengeParticipation.swift` | User's participation in a challenge |
| `ChallengeSource.swift` | Where challenge definitions come from |
| `ActiveStation.swift` | Unified on-air station model (POTA spots + RBN) |
| `ChallengeTypes.swift` | Challenge-related enums and types |
| `LeaderboardCache.swift` | Cached leaderboard data |
| `POTAActivation.swift` | POTA activation grouping view model |
| `TourState.swift` | UserDefaults-backed tour progress tracking |
| `StreakInfo.swift` | Streak data model and calculation utilities |
| `DashboardMetricType.swift` | Dashboard metric type enum, display properties, MetricDisplayValue |
| `ActivityType.swift` | Activity type enum with icons and display names |
| `Friendship.swift` | Friend connection model with status tracking |
| `FriendSuggestion.swift` | Friend suggestion models (DismissedSuggestion, FriendSuggestion, DTO) |
| `Club.swift` | Club model with Polo notes list membership |
| `ActivityItem.swift` | Activity feed item model |
| `CWConversation.swift` | CW conversation and message models for chat display |
| `CallsignInfo.swift` | Callsign lookup result with name, note, emoji, source |
| `LoggingSession.swift` | Logging session model with activation type, frequency, mode, equipment |
| `LoggingSession+Frequencies.swift` | Static frequency maps, band derivation, computed display properties |
| `LoggerCommand.swift` | Command enum for logger input (FREQ, BAND, MODE, SPOT, RBN, POTA, P2P, SOLAR, WEATHER, MAP, WEBSDR) |
| `WebSDRRecording.swift` | WebSDR recording metadata (host, file path, duration, session link) |
| `CallsignNotesSource.swift` | SwiftData model for user-configured callsign notes file sources |
| `BandPlan.swift` | US amateur radio band plan data with license class privileges |
| `BandPlan+Activities.swift` | Frequency activity data (QRP, SSTV, FT8, CWT, nets) and time windows |
| `UserProfile.swift` | User's amateur radio profile (callsign, name, QTH, grid, license) |
| `SessionSpot.swift` | Persisted RBN/POTA spot recorded during a logging session |
| `SpotRegion.swift` | Geographic region classification for spots (SpotRegion, EnrichedSpot, SpotSummary) |
| `ActivityLog.swift` | Activity log SwiftData model for persistent hunter workflow |
| `SDRParameterEvent.swift` | SDR parameter change event and recording segment types for tracking freq/mode changes |
| `StationProfile.swift` | Station profile struct and UserDefaults-backed storage |

## Services (`CarrierWave/Services/`)
| File | Purpose |
|------|---------|
| `QRZClient.swift` | QRZ.com API client (session auth) |
| `QRZClient+ADIF.swift` | QRZ ADIF upload extension |
| `QRZClient+Fetch.swift` | QRZ fetch helpers (request building, pagination, decoding) |
| `POTAClient.swift` | POTA API client (bearer token auth) |
| `POTAClient+Upload.swift` | POTA multipart ADIF upload |
| `POTAClient+ADIF.swift` | POTA ADIF formatting |
| `POTAClient+GridLookup.swift` | POTA grid square lookup |
| `POTAClient+Checkpoint.swift` | POTA resumable download checkpoints and incremental sync state |
| `POTAClient+Adaptive.swift` | POTA adaptive batch processing for rate limiting |
| `POTAClient+ParkDetail.swift` | Public POTA park stats, leaderboard, and activations API models + loader |
| `POTAParksCache.swift` | POTA park reference to name lookup cache |
| `POTAAuthService.swift` | POTA OAuth flow handling (main service) |
| `POTAAuthService+JavaScript.swift` | JavaScript helpers for POTA WebView auth |
| `POTAAuthService+HeadlessAuth.swift` | Headless authentication with stored credentials |
| `LoFiModels+QSOHelpers.swift` | LoFi QSO convenience properties (theirCall, timestamp, etc.) |
| `LoFi/KeychainCredentialStore.swift` | LoFiCredentialStore adapter wrapping KeychainHelper |
| `LoFi/SyncDebugLogAdapter.swift` | LoFiLogger adapter wrapping SyncDebugLog |
| `LoFi/LoFiClient+App.swift` | Convenience LoFiClient.appDefault() factory |
| `LoTWClient.swift` | LoTW API client (download-only, username/password auth) |
| `LoTWClient+Parsing.swift` | LoTW ADIF parsing methods |
| `LoTWClient+Adaptive.swift` | LoTW adaptive date windowing for rate limiting |
| `LoTWError.swift` | LoTW-specific errors |
| `HAMRSClient.swift` | HAMRS sync client |
| `HAMRSModels.swift` | HAMRS API models |
| `HAMRSError.swift` | HAMRS-specific errors |
| `ClubLogClient.swift` | Club Log API client (email/password + API key auth, bidirectional ADIF sync) |
| `ClubLogClient+Helpers.swift` | Club Log ADIF parsing/generation, network helpers, multipart body builder |
| `SyncService.swift` | Main sync orchestrator |
| `SyncService+SingleSync.swift` | Per-service sync methods (syncQRZ, syncPOTA, syncLoFi, etc.) |
| `SyncService+Upload.swift` | Upload logic for all services |
| `SyncService+Download.swift` | Download/import logic |
| `SyncService+ForceRedownload.swift` | Force re-download all QSOs from each service |
| `SyncService+Process.swift` | QSO processing during sync |
| `SyncService+Report.swift` | Per-service sync report building |
| `SyncService+Helpers.swift` | Sync helpers (reconciliation, uploads, data repair) |
| `SyncModels.swift` | Sync result types, progress tracking, service sync reports |
| `QSOProcessingActor.swift` | Background actor for QSO processing without blocking UI |
| `QSOProcessingActor+Merge.swift` | QSO merge, creation, and park reference extraction helpers |
| `QSOProcessingActor+OrphanRepair.swift` | Repair QSOs missing ServicePresence records |
| `QSOProcessingActor+POTAReconcile.swift` | Reconcile POTA ServicePresence against upload job log |
| `QSOProcessingActor+POTAGapRepair.swift` | Compare local QSOs against POTA remote data, flag missing for re-upload |
| `SyncDebugLog.swift` | Sync debugging utilities |
| `ImportService.swift` | ADIF parsing, deduplication, QSO creation |
| `ImportService+External.swift` | External file import handling |
| `ADIFParser.swift` | ADIF format parser |
| `ADIFExportService.swift` | Background ADIF generation for activation exports |
| `DeduplicationService.swift` | QSO deduplication logic |
| `ICloudMonitor.swift` | iCloud sync status monitoring |
| `DescriptionLookup.swift` | Human-readable descriptions for codes |
| `DescriptionLookup+DXCC.swift` | DXCC entity descriptions |
| `FetchedQSO.swift` | Intermediate QSO representation during fetch |
| `ActivitiesClient.swift` | Activities API client |
| `ActivitiesError.swift` | Activities-specific errors |
| `ActivitiesSyncService.swift` | Activities data synchronization (sources, fetching) |
| `ActivitiesSyncService+Participation.swift` | Activities participation, progress sync, leaderboards |
| `ChallengeProgressEngine.swift` | Challenge progress calculation |
| `ChallengeQSOMatcher.swift` | Match QSOs to challenge criteria |
| `BugReportService.swift` | Collects device/app info for bug reports |
| `CallsignAliasService.swift` | Manage current and previous callsigns for alias matching |
| `ActivitiesClient+Friends.swift` | Friend API endpoints extension |
| `ActivitiesClient+FriendSuggestions.swift` | Friend suggestion validation API (batch + fallback) |
| `FriendsSyncService.swift` | Friend data synchronization and actions |
| `FriendSuggestionActor.swift` | Background actor for counting QSOs per callsign |
| `ActivitiesClient+Clubs.swift` | Club API endpoints extension |
| `ClubsSyncService.swift` | Club data synchronization |
| `ActivityDetector.swift` | Detect notable activities from QSOs |
| `ActivityDetector+Detection.swift` | Activity detection methods (DXCC, bands, modes, DX, streaks) |
| `ActivitiesClient+Activities.swift` | Activity API endpoints (report, feed) |
| `ActivityReporter.swift` | Report detected activities to server |
| `SyncService+Activity.swift` | Hook activity detection into sync flow |
| `ActivityFeedSyncService.swift` | Sync activity feed from server |
| `POTAPresenceRepairService.swift` | Detect and fix incorrectly marked POTA service presence |
| `WPMBackfillService.swift` | One-time backfill of average WPM from stored spot comments into ActivationMetadata |
| `ConditionsBackfillService.swift` | One-time backfill parsing text solar/weather into structured ActivationMetadata fields |
| `TwoferDuplicateRepairService.swift` | Detect and merge duplicate QSOs from two-fer park reference mismatches |
| `CWError.swift` | CW transcription error types |
| `CWAudioCapture.swift` | AVAudioEngine microphone capture for CW decoding |
| `CWSignalProcessorProtocol.swift` | Protocol for signal processors, CWSignalResult struct |
| `GoertzelFilter.swift` | Goertzel algorithm for single-frequency detection |
| `GoertzelThreshold.swift` | Adaptive threshold for key state detection |
| `GoertzelSignalProcessor.swift` | Goertzel-based CW processor with adaptive frequency detection |
| `MorseCode.swift` | Morse code lookup table, timing constants, QSO abbreviations |
| `MorseDecoder.swift` | Timing state machine for dit/dah classification, adaptive WPM |
| `CWTranscriptionService.swift` | Coordinates audio capture, signal processing, and morse decoding |
| `CWConversationTracker.swift` | Track CW conversation turns via frequency and prosign analysis |
| `PoloNotesParser.swift` | Parse Ham2K Polo notes list files for callsign info |
| `CallsignLookupService.swift` | Two-tier callsign lookup (Polo notes cache, then QRZ API) |
| `CallsignNotesCache.swift` | Persistent cache for Polo notes (loads from disk, refreshes daily) |
| `CWSuggestionEngine.swift` | Word suggestion engine with dictionaries and settings |
| `LoggingSessionManager.swift` | Session lifecycle management (start, end, log QSO, hide QSO, photos) |
| `LoggingSessionManager+Conditions.swift` | Auto-record solar/weather conditions at POTA session start |
| `LoggingSessionManager+Spotting.swift` | POTA spot timer, posting, comments polling, monitoring |
| `RBNClient.swift` | Vail ReRBN API client for reverse beacon network spots |
| `NOAAClient.swift` | NOAA API client for solar conditions and weather |
| `POTAClient+Spot.swift` | POTA self-spotting extension |
| `POTAClient+Spots.swift` | POTA spots and spot comments API |
| `SpotsService.swift` | Combined RBN + POTA spots service |
| `P2PService.swift` | Park-to-park discovery via RBN skimmers near user's grid |
| `SpotCommentsService.swift` | Background polling for POTA spot comments |
| `SpotMonitoringService.swift` | Background RBN/POTA spot polling (activator + hunter modes) |
| `WorkedBeforeCache.swift` | Actor-based cache for worked-before spot checking |
| `BandPlanService.swift` | Validates frequency/mode against license class privileges |
| `FrequencyActivityService.swift` | Aggregates nearby frequency activity from RBN |
| `HamDBClient.swift` | HamDB.org API client for US callsign license class lookup |
| `UserProfileService.swift` | Persists and retrieves user profile data |
| `QuickEntryParser.swift` | Parses quick entry strings (e.g., "AJ7CM 579 WA US-0189") into structured data |
| `ActivityLogManager.swift` | Activity log lifecycle management (create, activate, log QSO, daily stats) |
| `EnvironmentalSnapshot.swift` | Sendable snapshot struct for environmental conditions charting |
| `EnvironmentalDataActor.swift` | Background actor for loading conditions from LoggingSession + ActivationMetadata |

## Services - WebSDR (`CarrierWave/Services/WebSDR/`)

| File | Purpose |
|------|---------|
| `AudioRingBuffer.swift` | Thread-safe circular buffer for audio jitter buffering between network and render threads |
| `KiwiSDRAudioEngine.swift` | AVAudioEngine-based live playback with adaptive rate from ring buffer |
| `KiwiSDRClient.swift` | KiwiSDR WebSocket client (connection, tuning, audio streaming) |
| `KiwiSDRTypes.swift` | KiwiSDRMode (mode mapping/passbands) and KiwiSDRError types |
| `KiwiSDRADPCM.swift` | IMA ADPCM decoder for KiwiSDR compressed audio |
| `WebSDRDirectory.swift` | KiwiSDR public directory fetch, cache, and proximity search |
| `WebSDRRecorder.swift` | Records KiwiSDR audio frames to compressed audio file |
| `WebSDRSession.swift` | Coordinates WebSDR connection, recording, playback, and resilient reconnects |
| `WebSDRSession+Internals.swift` | Internal helpers: audio stream processing, reconnect logic, recording lifecycle |
| `RecordingPlaybackEngine.swift` | @Observable AVAudioPlayer wrapper with seeking, speed control, amplitude envelope, QSO sync |
| `RecordingClipExporter.swift` | M4A clip export from recordings using AVAssetExportSession |

## Services - Query Language (`CarrierWave/Services/QueryLanguage/`)

Most Query Language types are now in CarrierWaveCore. Only the compiler remains in the main app.

| File | Purpose |
|------|---------|
| `QueryCompiler.swift` | Compiles AST to SwiftData predicates and filter closures |

## Views - Recording Player (`CarrierWave/Views/RecordingPlayer/`)
| File | Purpose |
|------|---------|
| `RecordingWaveformView.swift` | Reusable amplitude waveform with QSO markers, playback head, drag-to-seek |
| `CompactRecordingPlayer.swift` | Inline card for activation detail and sessions list |
| `RecordingPlayerView.swift` | Full-screen player with transport controls, speed picker, QSO list |
| `RecordingPlayerView+Actions.swift` | Share clip sheet with range selection and M4A export |

## Views - Sessions (`CarrierWave/Views/Sessions/`)
| File | Purpose |
|------|---------|
| `SessionsView.swift` | Unified sessions list merging POTA activations and all sessions, with rich content |
| `SessionsView+Actions.swift` | Data loading, POTA actions, session deletion, and helpers for SessionsView |
| `SessionsView+Share.swift` | Brag sheet generation and equipment list building for share cards |
| `SessionRow.swift` | Unified rich session row: timeline, conditions, badges, upload status |
| `SessionDetailView.swift` | Session detail with equipment, photos, notes, spots, QSO list, edit button |
| `SessionSpotsSection.swift` | Persisted spots display section for session detail (POTA highlighted, RBN collapsed) |
| `SessionMetadataEditSheet.swift` | Unified edit sheet for all session types (equipment, photos, notes) |
| `PhotoViewer.swift` | Full-screen photo viewer with pinch-to-zoom |

## Views - Conditions (`CarrierWave/Views/Conditions/`)
| File | Purpose |
|------|---------|
| `ConditionsCard.swift` | Dashboard card with sparkline and latest metrics, links to full history |
| `ConditionsHistoryView.swift` | Full-screen conditions history with timeline/location tabs and date range |
| `ConditionsHistoryChartView.swift` | Time-series line chart for solar/weather metrics with Swift Charts |
| `ConditionsByLocationView.swift` | Bar chart comparing conditions across grid squares |

## Views - Components (`CarrierWave/Views/Components/`)

| File | Purpose |
|------|---------|
| `ContactCountBadge.swift` | Tiered contact count badge (bronze/silver/gold at 10/25/50 QSOs) |
| `UnderConstructionBanner.swift` | Under-construction banner for incomplete features |

## Views - Logger (`CarrierWave/Views/Logger/`)
| File | Purpose |
|------|---------|
| `LoggerView.swift` | Main logger view with session header, callsign input, QSO form |
| `CallsignTextField.swift` | UITextField wrapper for callsign entry with proper cursor handling |
| `LoggerCallsignCard.swift` | Callsign info display card for logger |
| `SessionStartSheet.swift` | Session wizard for mode, frequency, activation type, equipment |
| `SessionStartSheet+Sections.swift` | Callsign and activation section views |
| `SessionStartSheet+Equipment.swift` | Equipment, attendees, and notes sections for session start |
| `EquipmentPickerSheet.swift` | Generic equipment picker (antenna, key, mic) with user-managed list |
| `SessionStartHelperViews.swift` | Helper views and validation for session start (CallsignBreakdown, ActivationSection, FrequencySuggestions) |
| `LiveActivitySuggestionsView.swift` | Unified FrequencyBandView: static band frequencies + live POTA spots + nestled clear-frequency recommendations |
| `BandPlanSheet.swift` | Interactive band plan reference with segments, license requirements, and activity frequencies |
| `RadioPickerSheet.swift` | Radio/rig picker sheet with user-managed list and RadioStorage helper |
| `SessionEquipmentEditSheet.swift` | Compact equipment editor (radio, antenna, key, mic) for active sessions |
| `ParkPickerSheet.swift` | Multi-select park search/nearby sheet for n-fer |
| `ParkEntryField.swift` | Multi-park entry with chips, search picker, and shorthand |
| `ParkDetailSheet.swift` | Park detail sheet with stats, leaderboard (top activators/hunters), and recent activations from POTA API |
| `LoggerSettingsView.swift` | (Deprecated) Logger settings moved to main SettingsView |
| `RBNPanelView.swift` | Combined RBN/POTA spots panel with mini-map |
| `SpotsMiniMapView.swift` | Map view showing spotter locations with arcs to target |
| `SpotCommentsSheet.swift` | POTA spot comments display sheet |
| `SolarPanelView.swift` | Solar conditions panel (K-index, SFI, propagation) |
| `WeatherPanelView.swift` | Weather conditions panel from NOAA |
| `FrequencyActivityView.swift` | Nearby frequency activity display with QRM assessment |
| `FrequencyWarningBanner.swift` | Unified frequency warning banner (license violations + activity warnings) |
| `LoggerToastView.swift` | Toast notification system for logger |
| `LoggerKeyboardAccessory.swift` | Number row and command buttons above keyboard |
| `KeyboardAccessoryBuilder.swift` | UIKit builder for keyboard accessory view |
| `POTASpotRow.swift` | Individual POTA spot row component |
| `POTASpotsView.swift` | POTA activator spots panel with filtering |
| `POTASpotsHelperViews.swift` | Helper views for POTA spots (filter sheet, loading, empty, error states) |
| `P2PPanelView.swift` | Park-to-park opportunities panel with SNR display |
| `SessionMapPanelView.swift` | Map panel showing session QSOs for MAP command |
| `POTAUploadPromptSheet.swift` | Post-session modal prompting POTA upload |
| `SpotFilters.swift` | Band and mode filter enums for spots |
| `QuickEntryPreview.swift` | Quick entry token display with color-coded badges |
| `SpotSummaryView.swift` | Compact spot monitoring summary with region breakdown |
| `WebSDRPanelView.swift` | WebSDR connection status, recording controls, level meter |
| `WebSDRPanelView+Subviews.swift` | Extension with level meter, buffer indicator, reconnecting/error views |
| `WebSDRPickerSheet.swift` | Nearby KiwiSDR receiver selection with distance/availability |

## Views - CW Transcription (`CarrierWave/Views/CWTranscription/`)
| File | Purpose |
|------|---------|
| `CWTranscriptionView.swift` | Main CW transcription container with controls |
| `CWSettingsMenu.swift` | Settings menu for WPM, frequency, and signal options |
| `CWWaveformView.swift` | Real-time audio waveform visualization, includes CWLevelMeter |
| `CWTranscriptView.swift` | Decoded text display with timestamps |
| `CWDetectedCallsignBar.swift` | Detected callsign display with "Use" button, highlighted text |
| `CWChatView.swift` | Chat-style conversation display with message bubbles |
| `CWMessageBubble.swift` | Individual message bubble for chat view |
| `CWCallsignInfoCard.swift` | Callsign info display card and chip components |

## Views - Dashboard (`CarrierWave/Views/Dashboard/`)
| File | Purpose |
|------|---------|
| `ActivityGridView.swift` | GitHub-style activity grid with horizontal scrolling |
| `DashboardView.swift` | Main dashboard with stats grid and services list |
| `DashboardView+Actions.swift` | Dashboard action handlers (sync, clear data) |
| `DashboardView+Services.swift` | Services list builder and detail sheet builders |
| `DashboardView+Stats.swift` | Stats grid and streak row components |
| `DashboardHelperViews.swift` | Reusable dashboard components (StatBox, StatBoxDeferred, ActivityGrid, StreaksCard) |
| `QSOStatistics.swift` | QSO statistics calculations (entities, grids, bands, parks, frequencies) |
| `QSOStatistics+Streaks.swift` | Streak calculation extensions for QSOStatistics |
| `AsyncQSOStatistics.swift` | Progressive stats computation wrapper with cooperative yielding |
| `AsyncServicePresenceCounts.swift` | Background computation of service presence counts |
| `StatsComputationActor.swift` | Background actor for QSO statistics computation |
| `StatsComputationActor+Extensions.swift` | Extensions for activations and favorites computation |
| `ServiceListView.swift` | Vertical stacked service list with status indicators |
| `ServiceDetailSheet.swift` | Service detail sheet for tap-through actions |
| `SyncReportViews.swift` | Sync report header, stat chips, status badge, step row |
| `SyncFunnelDetailView.swift` | Expandable sync funnel timeline, reconciliation, warnings |
| `StatDetailView.swift` | Drilldown view for stat categories |
| `StatItemRow.swift` | Individual stat row with expandable QSOs |
| `StreakDetailView.swift` | Streak statistics detail view with mode/band breakdowns |

## Views - Logs (`CarrierWave/Views/Logs/`)
| File | Purpose |
|------|---------|
| `LogsContainerView.swift` | Container with segmented picker for QSOs, POTA Activations, and Sessions |
| `LogsListView.swift` | Searchable/filterable QSO list content |
| `LogsListHelperViews.swift` | Helper views (QueryWarningBanner, QueryHelpSheet, QSORow, ServicePresenceBadge) |
| `QSODetailView.swift` | Read-only QSO detail view showing all metadata, sync status, and source info |

## Views - POTA Activations (`CarrierWave/Views/POTAActivations/`)
| File | Purpose |
|------|---------|
| `POTAActivationsView.swift` | POTA activations grouped by park with upload |
| `POTAActivationsView+Actions.swift` | Actions extension (upload, reject, share, subviews, helpers) |
| `POTAActivationsHelperViews.swift` | Helper views for POTA activations (ActivationRow, sheets) |
| `POTAActivationsBulkActions.swift` | Bulk action components (multi-select, upload/reject/export toolbar, progress banner) |
| `POTAActivationDetailView.swift` | Full activation detail view with upload, jobs, QSO list |
| `POTAActivationDetailView+Recording.swift` | Recording integration: lookup and compact player section |
| `POTAActivationLabel.swift` | Shared activation label view (date, park, status, metadata) |
| `POTAJobViews.swift` | POTA job display components (POTAJobRow, POTAJobDetailSheet) |
| `QSOTimelineView.swift` | Horizontal timeline bar showing QSO timing during activations (compact + share card variants) |
| `QSOTimelineLayout.swift` | Timeline layout engine: segments, gap detection, x-position computation, band colors |
| `POTALogEntryRow.swift` | Individual POTA log entry display (legacy) |
| `ActivationConditionsComponents.swift` | Compact solar gauge and weather badge components for activation rows |
| `ActivationConditionsSheet.swift` | Detail sheet showing full solar/weather conditions for an activation |
| `ActivationMetadataEditSheet.swift` | Thin wrapper bridging activation editing to SessionMetadataEditSheet |
| `ActivationShareCardView.swift` | Shareable activation card with map and stats |
| `ActivationShareCardComponents.swift` | Reusable component views for share cards (header, footer, stats, park info) |
| `ActivationSharePreviewSheet.swift` | Share preview sheet with ShareLink and Save to Photos |
| `ActivationShareRenderer.swift` | Render activation card to UIImage for sharing |
| `ShareCardStatisticianSection.swift` | Extra brag sheet section for Professional Statistician Mode (box plot, badges, distributions) |
| `ActivationStatsChartsView.swift` | Swift Charts for activation detail (band distribution, QSO rate, distance histogram) |
| `ActivationStatsSummaryView.swift` | Two-column stats summary grid for activation detail |
| `ADIFExportSheet.swift` | ADIF export sheet with share, save, copy options |
| `ActivationMapHelpers.swift` | Map utilities for activation share cards (region, geodesic paths) and activation stats helper |
| `ActivationMapView.swift` | Full-screen activation map with RST-based contact coloring |
| `ActivationMapComponents.swift` | RST coloring helpers, annotation/marker views, QSO callout |
| `ShareableImage.swift` | Transferable wrapper for UIImage sharing |

## Views - Challenges (`CarrierWave/Views/Challenges/`)
| File | Purpose |
|------|---------|
| `ChallengesView.swift` | Main challenges tab |
| `BrowseChallengesView.swift` | Browse available challenges |
| `ChallengeDetailView.swift` | Single challenge detail view (for joined challenges) |
| `ChallengePreviewDetailView.swift` | Challenge preview before joining |
| `ChallengeDetailHelperViews.swift` | Challenge detail components |
| `ChallengeProgressCard.swift` | Progress visualization card |
| `LeaderboardView.swift` | Challenge leaderboard display |

## Views - Activity Log (`CarrierWave/Views/ActivityLog/`)
| File | Purpose |
|------|---------|
| `ActivityLogView.swift` | Main activity log view (spots, quick log, recent QSOs) |
| `ActivityLogCard.swift` | Dashboard card component (setup prompt or active stats) |
| `ActivityLogHeader.swift` | Daily counter bar and station profile banner |
| `ActivityLogSetupSheet.swift` | Initial activity log setup sheet (name, callsign, profile) |
| `ActivityLogSettingsView.swift` | Activity log settings (profiles, upload, daily goal) |
| `ActivityLogSpotsList.swift` | Hunter spot list container with worked-before checking |
| `ActivityLogSpotRow.swift` | Individual spot row with frequency, callsign, badges |
| `SpotLogSheet.swift` | Half-sheet for logging a QSO from a tapped spot |
| `SpotFilterBar.swift` | Horizontal scrolling filter chips for spot list |
| `SpotFilterSheet.swift` | Full filter sheet (source, band, mode, toggles) |
| `QuickLogSection.swift` | Manual callsign entry section with quick entry parsing |
| `RecentQSOsSection.swift` | Recent QSOs list for today |
| `StationProfilePicker.swift` | Station profile selection sheet |
| `AddEditProfileSheet.swift` | Station profile add/edit form |
| `LocationChangeSheet.swift` | Grid change prompt (old grid → new grid with distance) |
| `BandTimelineView.swift` | Horizontal band timeline showing activity segments |
| `DailySummaryView.swift` | Full day activity with band timeline and QSO list |
| `ActivityShareCardView.swift` | Daily activity share card using ShareCardContent |

## Views - Activity (`CarrierWave/Views/Activity/`)
| File | Purpose |
|------|---------|
| `ActivityView.swift` | Main activity tab with challenges section and activity feed |
| `ActivityItemRow.swift` | Individual activity feed item display |
| `FilterBar.swift` | Feed filter chips (All/Friends/Clubs) |
| `FriendsListView.swift` | Friends list with pending requests, suggestions, and invite links |
| `FriendSuggestionsSection.swift` | Friend suggestion rows with Add/Dismiss actions |
| `FriendSearchView.swift` | Search and add friends |
| `FriendProfileView.swift` | Friend profile with activity and stats |
| `ClubsListView.swift` | List of clubs user belongs to |
| `ClubDetailView.swift` | Club details and member list |
| `CommunityFeaturesPromptSheet.swift` | One-time prompt for existing users to opt into community features |
| `ShareCardView.swift` | Branded share card templates |
| `ShareCardRenderer.swift` | Render share cards to UIImage |
| `SummaryCardSheet.swift` | Configure and generate summary cards |

## Views - Tour (`CarrierWave/Views/Tour/`)
| File | Purpose |
|------|---------|
| `TourSheetView.swift` | Reusable bottom sheet component for tour screens |
| `IntroTourView.swift` | Intro tour flow coordinator |
| `IntroTourStepViews.swift` | Individual step content views for intro tour |
| `MiniTourContent.swift` | Content definitions for all mini-tours |
| `MiniTourModifier.swift` | View modifier for easy mini-tour integration |
| `OnboardingView.swift` | Post-tour onboarding flow (callsign lookup, profile setup, service connections) |

## Views - Settings (`CarrierWave/Views/Settings/`)
| File | Purpose |
|------|---------|
| `SettingsView.swift` | Main settings navigation |
| `AboutMeView.swift` | User profile display and editing |
| `ServiceSettingsViews.swift` | QRZ/POTA/LoFi auth configuration |
| `CloudSettingsViews.swift` | iCloud sync settings |
| `HAMRSSettingsView.swift` | HAMRS connection settings |
| `LoTWSettingsView.swift` | LoTW login configuration |
| `ClubLogSettingsView.swift` | Club Log connection settings (email, app password, API key) |
| `ActivitiesSettingsView.swift` | Activities feature settings |
| `POTAAuthWebView.swift` | POTA OAuth WebView |
| `SyncDebugView.swift` | Sync debugging interface |
| `AttributionsView.swift` | Third-party attributions |
| `ExternalDataView.swift` | External data cache status and refresh (POTA parks) |
| `BugReportView.swift` | Bug report form with dpaste upload and Discord instructions |
| `CallsignAliasesSettingsView.swift` | Manage current and previous callsigns |
| `SettingsSections.swift` | Sync Sources section with service navigation links |
| `CallsignNotesSettingsView.swift` | Manage callsign notes file sources (URL + title) |
| `KeyboardRowSettingsView.swift` | Configure number row symbols above keyboard |
| `CommandRowSettingsView.swift` | Configure command row buttons above keyboard |
| `DashboardMetricsSettingsView.swift` | Configure which metrics appear on dashboard card |
| `WebSDRRecordingsView.swift` | List of all WebSDR recordings with delete, share, and details |

## Documentation (`docs/`)
| File | Purpose |
|------|---------|
| `design-language.md` | Visual and interaction design patterns specification |
| `kiwisdr-protocol.md` | KiwiSDR WebSocket protocol reference (from kiwiclient) |
| `features/callsign-filtering.md` | Primary callsign filtering requirements for syncs |
| `features/delete-confirmation.md` | Delete confirmation requirements and review checklist |
| `features/logger-requirements.md` | Logger requirements and compliance checklist |
| `features/sync.md` | QRZ, POTA, LoFi sync integration |
| `features/statistics.md` | Dashboard stats and drilldown views |
| `features/tour-requirements.md` | Feature tour rules and mini tour implementation guide |

## Views - Map (`CarrierWave/Views/Map/`)
| File | Purpose |
|------|---------|
| `QSOMapView.swift` | Main map view showing QSO locations |
| `QSOMapHelperViews.swift` | Map markers, filter sheet, callout views |
| `MapFilterState.swift` | Observable filter state for map |
| `QSOAnnotation.swift` | Annotation model for map markers and arcs |
| `MapDataLoadingActor.swift` | Background actor for loading map QSO data off main thread |

## Utilities (`CarrierWave/Utilities/`)
| File | Purpose |
|------|---------|
| `BandUtilities.swift` | Band derivation from frequency and band ordering |
| `FieldGuideLinker.swift` | Match radio names to CW Field Guide IDs and open deep links |
| `FrequencyFormatter.swift` | Frequency formatting with sub-kHz precision support |
| `KeychainHelper.swift` | Secure credential storage |
| `GridLocationService.swift` | One-shot GPS → 6-char Maidenhead grid square service |
| `MaidenheadConverter.swift` | Grid square to coordinate conversion (and reverse) |
| `SunlightMode.swift` | Sunlight mode environment key and view modifier for outdoor visibility |
| `UnitFormatter.swift` | Centralized imperial/metric unit formatting (distance, temperature, wind, watts/distance) |
| `EquipmentStorage.swift` | Generic UserDefaults-backed equipment list storage (antenna, key, mic) |
| `SessionPhotoManager.swift` | Session photo file save/load/delete (JPEG in Documents/SessionPhotos/) |

## Tests (`CarrierWaveTests/`)
| File | Purpose |
|------|---------|
| `CarrierWaveTests.swift` | Main test file placeholder |
| `ADIFParserTests.swift` | ADIF parsing tests |
| `DeduplicationServiceTests.swift` | QSO deduplication logic tests |
| `ImportServiceTests.swift` | Import service tests |
| `LoFiClientTests.swift` | LoFi client tests |
| `QRZClientTests.swift` | QRZ client tests |
| `LoggingSessionManagerTests.swift` | Session lifecycle, QSO logging, notes management tests |
| `LoggingSessionTests.swift` | LoggingSession model tests (state, band derivation, duration) |
| `ServicePresenceTests.swift` | Service presence and upload marking edge case tests |
| `MetadataModeTests.swift` | WEATHER/SOLAR/NOTE metadata mode filtering tests |
| `DXCCTests.swift` | DXCC extraction, QRZ import, and repair task tests |
| `QuickEntryParserTests.swift` | Quick entry parser unit tests (callsign, RST, park, grid, state detection) |
| `QuickEntryParserIntegrationTests.swift` | Quick entry parser integration tests (full parsing, token preview) |
| `WebSDRRecordingTests.swift` | WebSDR recording query helper tests |
| `SDRParameterTrackingTests.swift` | SDR parameter change tracking, segment computation, and persistence tests |
| `EquipmentStorageTests.swift` | Equipment storage CRUD and isolation tests |
| `SessionPhotoManagerTests.swift` | Session photo file management tests |
| `Helpers/QSOFactory.swift` | Synthetic QSO generator for testing (duplicates, metadata, edge cases) |
| `Helpers/TestModelContainer.swift` | Shared test infrastructure for SwiftData tests |
| `BandPlanServiceTests.swift` | Band plan validation tests (license class privileges) |
| `PerformanceTests/QSOStatisticsPerformanceTests.swift` | Performance regression tests (50k/500k QSOs) |
