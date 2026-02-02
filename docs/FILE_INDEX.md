# File Index

This index maps files to their purpose. Use it to locate files by feature instead of scanning the codebase.

**Maintenance:** When adding, removing, or renaming files, update this index.

## Entry Points
| File | Purpose |
|------|---------|
| `CarrierWave/CarrierWaveApp.swift` | App entry point, SwiftData container setup |
| `CarrierWave/ContentView.swift` | Root TabView with AppTab enum for programmatic tab switching |

## Models (`CarrierWave/Models/`)
| File | Purpose |
|------|---------|
| `QSO.swift` | Core contact record (callsign, band, mode, timestamps, grid, park ref) |
| `UploadDestination.swift` | Sync target configuration (enabled flag, last sync timestamp) |
| `POTAJob.swift` | POTA activation job tracking |
| `POTALogEntry.swift` | Individual POTA log entries |
| `POTAUploadAttempt.swift` | POTA upload attempt history and status |
| `ServicePresence.swift` | Service connection status tracking |
| `ActivationMetadata.swift` | Activation-level metadata storage |
| `StatCategoryItem.swift` | Individual stat item for dashboard display |
| `StatCategoryType.swift` | Stat category enum (band, mode, DXCC, etc.) |
| `Types.swift` | Shared type definitions |
| `ChallengeDefinition.swift` | Challenge metadata and rules |
| `ChallengeParticipation.swift` | User's participation in a challenge |
| `ChallengeSource.swift` | Where challenge definitions come from |
| `ChallengeTypes.swift` | Challenge-related enums and types |
| `LeaderboardCache.swift` | Cached leaderboard data |
| `POTAActivation.swift` | POTA activation grouping view model |
| `TourState.swift` | UserDefaults-backed tour progress tracking |
| `StreakInfo.swift` | Streak data model and calculation utilities |
| `ActivityType.swift` | Activity type enum with icons and display names |
| `Friendship.swift` | Friend connection model with status tracking |
| `Club.swift` | Club model with Polo notes list membership |
| `ActivityItem.swift` | Activity feed item model |
| `CWConversation.swift` | CW conversation and message models for chat display |
| `CallsignInfo.swift` | Callsign lookup result with name, note, emoji, source |
| `LoggingSession.swift` | Logging session model with activation type, frequency, mode |
| `LoggerCommand.swift` | Command enum for logger input (FREQ, MODE, SPOT, RBN, POTA, P2P, SOLAR, WEATHER, MAP) |
| `CallsignNotesSource.swift` | SwiftData model for user-configured callsign notes file sources |
| `BandPlan.swift` | US amateur radio band plan data with license class privileges |
| `UserProfile.swift` | User's amateur radio profile (callsign, name, QTH, grid, license) |
| `SpotRegion.swift` | Geographic region classification for spots (SpotRegion, EnrichedSpot, SpotSummary) |

## Services (`CarrierWave/Services/`)
| File | Purpose |
|------|---------|
| `QRZClient.swift` | QRZ.com API client (session auth) |
| `QRZClient+ADIF.swift` | QRZ ADIF upload extension |
| `POTAClient.swift` | POTA API client (bearer token auth) |
| `POTAClient+Upload.swift` | POTA multipart ADIF upload |
| `POTAClient+ADIF.swift` | POTA ADIF formatting |
| `POTAClient+GridLookup.swift` | POTA grid square lookup |
| `POTAClient+Checkpoint.swift` | POTA resumable download checkpoints |
| `POTAClient+Adaptive.swift` | POTA adaptive batch processing for rate limiting |
| `POTAParksCache.swift` | POTA park reference to name lookup cache |
| `POTAAuthService.swift` | POTA OAuth flow handling (main service) |
| `POTAAuthService+JavaScript.swift` | JavaScript helpers for POTA WebView auth |
| `POTAAuthService+HeadlessAuth.swift` | Headless authentication with stored credentials |
| `LoFiClient.swift` | Ham2K LoFi sync client |
| `LoFiClient+Helpers.swift` | LoFi helper methods |
| `LoFiModels.swift` | LoFi API response models |
| `LoTWClient.swift` | LoTW API client (download-only, username/password auth) |
| `LoTWClient+Parsing.swift` | LoTW ADIF parsing methods |
| `LoTWClient+Adaptive.swift` | LoTW adaptive date windowing for rate limiting |
| `LoTWError.swift` | LoTW-specific errors |
| `HAMRSClient.swift` | HAMRS sync client |
| `HAMRSModels.swift` | HAMRS API models |
| `HAMRSError.swift` | HAMRS-specific errors |
| `SyncService.swift` | Main sync orchestrator |
| `SyncService+Upload.swift` | Upload logic for all services |
| `SyncService+Download.swift` | Download/import logic |
| `SyncService+Process.swift` | QSO processing during sync |
| `SyncDebugLog.swift` | Sync debugging utilities |
| `ImportService.swift` | ADIF parsing, deduplication, QSO creation |
| `ImportService+External.swift` | External file import handling |
| `ADIFParser.swift` | ADIF format parser |
| `DeduplicationService.swift` | QSO deduplication logic |
| `ICloudMonitor.swift` | iCloud sync status monitoring |
| `DescriptionLookup.swift` | Human-readable descriptions for codes |
| `DescriptionLookup+DXCC.swift` | DXCC entity descriptions |
| `FetchedQSO.swift` | Intermediate QSO representation during fetch |
| `ChallengesClient.swift` | Challenges API client |
| `ChallengesError.swift` | Challenges-specific errors |
| `ChallengesSyncService.swift` | Challenge data synchronization (sources, fetching) |
| `ChallengesSyncService+Participation.swift` | Challenge participation, progress sync, leaderboards |
| `ChallengeProgressEngine.swift` | Challenge progress calculation |
| `ChallengeQSOMatcher.swift` | Match QSOs to challenge criteria |
| `BugReportService.swift` | Collects device/app info for bug reports |
| `CallsignAliasService.swift` | Manage current and previous callsigns for alias matching |
| `ChallengesClient+Friends.swift` | Friend API endpoints extension |
| `FriendsSyncService.swift` | Friend data synchronization and actions |
| `ChallengesClient+Clubs.swift` | Club API endpoints extension |
| `ClubsSyncService.swift` | Club data synchronization |
| `ActivityDetector.swift` | Detect notable activities from QSOs |
| `ActivityDetector+Detection.swift` | Activity detection methods (DXCC, bands, modes, DX, streaks) |
| `ChallengesClient+Activities.swift` | Activity API endpoints (report, feed) |
| `ActivityReporter.swift` | Report detected activities to server |
| `SyncService+Activity.swift` | Hook activity detection into sync flow |
| `ActivityFeedSyncService.swift` | Sync activity feed from server |
| `POTAPresenceRepairService.swift` | Detect and fix incorrectly marked POTA service presence |
| `CWError.swift` | CW transcription error types |
| `CWAudioCapture.swift` | AVAudioEngine microphone capture for CW decoding |
| `CWSignalProcessorProtocol.swift` | Protocol for signal processors, CWSignalResult struct |
| `GoertzelFilter.swift` | Goertzel algorithm for single-frequency detection |
| `GoertzelThreshold.swift` | Adaptive threshold for key state detection |
| `GoertzelSignalProcessor.swift` | Goertzel-based CW processor with adaptive frequency detection |
| `MorseCode.swift` | Morse code lookup table, timing constants, QSO abbreviations |
| `MorseDecoder.swift` | Timing state machine for dit/dah classification, adaptive WPM |
| `CWTranscriptionService.swift` | Coordinates audio capture, signal processing, and morse decoding |
| `CallsignDetector.swift` | Callsign regex detection, context analysis, text element parsing |
| `CWConversationTracker.swift` | Track CW conversation turns via frequency and prosign analysis |
| `PoloNotesParser.swift` | Parse Ham2K Polo notes list files for callsign info |
| `CallsignLookupService.swift` | Two-tier callsign lookup (Polo notes cache, then QRZ API) |
| `CallsignNotesCache.swift` | Persistent cache for Polo notes (loads from disk, refreshes daily) |
| `MorseEditDistance.swift` | Levenshtein distance on morse patterns for word suggestions |
| `CWSuggestionEngine.swift` | Word suggestion engine with dictionaries and settings |
| `LoggingSessionManager.swift` | Session lifecycle management (start, end, log QSO, hide QSO) |
| `RBNClient.swift` | Vail ReRBN API client for reverse beacon network spots |
| `NOAAClient.swift` | NOAA API client for solar conditions and weather |
| `POTAClient+Spot.swift` | POTA self-spotting extension |
| `POTAClient+Spots.swift` | POTA spots and spot comments API |
| `SpotsService.swift` | Combined RBN + POTA spots service |
| `P2PService.swift` | Park-to-park discovery via RBN skimmers near user's grid |
| `SpotCommentsService.swift` | Background polling for POTA spot comments |
| `SpotMonitoringService.swift` | Background RBN/POTA spot polling during logging sessions |
| `BandPlanService.swift` | Validates frequency/mode against license class privileges |
| `FrequencyActivityService.swift` | Aggregates nearby frequency activity from RBN |
| `HamDBClient.swift` | HamDB.org API client for US callsign license class lookup |
| `UserProfileService.swift` | Persists and retrieves user profile data |
| `QuickEntryParser.swift` | Parses quick entry strings (e.g., "AJ7CM 579 WA US-0189") into structured data |

## Services - Query Language (`CarrierWave/Services/QueryLanguage/`)
| File | Purpose |
|------|---------|
| `QueryToken.swift` | Token types and field definitions for query lexer |
| `QueryLexer.swift` | Tokenizes query strings, handles field:value syntax |
| `QueryAST.swift` | Abstract syntax tree nodes for parsed queries |
| `QueryParser.swift` | Parses tokens into AST with boolean logic support |
| `QueryAnalyzer.swift` | Performance analysis and slow query warnings |
| `QueryCompiler.swift` | Compiles AST to SwiftData predicates and filter closures |

## Views - Logger (`CarrierWave/Views/Logger/`)
| File | Purpose |
|------|---------|
| `LoggerView.swift` | Main logger view with session header, callsign input, QSO form |
| `LoggerCallsignCard.swift` | Callsign info display card for logger |
| `SessionStartSheet.swift` | Session wizard for mode, frequency, activation type |
| `ParkPickerSheet.swift` | Park search and nearby selection sheet |
| `ParkEntryField.swift` | Enhanced park entry with search picker and shorthand |
| `LoggerSettingsView.swift` | (Deprecated) Logger settings moved to main SettingsView |
| `RBNPanelView.swift` | Combined RBN/POTA spots panel with mini-map |
| `SpotsMiniMapView.swift` | Map view showing spotter locations with arcs to target |
| `SpotCommentsSheet.swift` | POTA spot comments display sheet |
| `SolarPanelView.swift` | Solar conditions panel (K-index, SFI, propagation) |
| `WeatherPanelView.swift` | Weather conditions panel from NOAA |
| `FrequencyActivityView.swift` | Nearby frequency activity display with QRM assessment |
| `LicenseWarningBanner.swift` | Band plan violation warning banner |
| `LoggerToastView.swift` | Toast notification system for logger |
| `LoggerKeyboardAccessory.swift` | Number row and command buttons above keyboard |
| `POTASpotRow.swift` | Individual POTA spot row component |
| `POTASpotsView.swift` | POTA activator spots panel with filtering |
| `P2PPanelView.swift` | Park-to-park opportunities panel with SNR display |
| `SessionMapPanelView.swift` | Map panel showing session QSOs for MAP command |
| `SpotFilters.swift` | Band and mode filter enums for spots |
| `QuickEntryPreview.swift` | Quick entry token display with color-coded badges |
| `SpotSummaryView.swift` | Compact spot monitoring summary with region breakdown |

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
| `ServiceListView.swift` | Vertical stacked service list with status indicators |
| `ServiceDetailSheet.swift` | Service detail sheet for tap-through actions |
| `StatDetailView.swift` | Drilldown view for stat categories |
| `StatItemRow.swift` | Individual stat row with expandable QSOs |
| `StreakDetailView.swift` | Streak statistics detail view with mode/band breakdowns |

## Views - Logs (`CarrierWave/Views/Logs/`)
| File | Purpose |
|------|---------|
| `LogsContainerView.swift` | Container with segmented picker for QSOs and POTA Uploads |
| `LogsListView.swift` | Searchable/filterable QSO list content |

## Views - POTA Activations (`CarrierWave/Views/POTAActivations/`)
| File | Purpose |
|------|---------|
| `POTAActivationsView.swift` | POTA activations grouped by park with upload |
| `POTAActivationsHelperViews.swift` | Helper views for POTA activations (rows, sheets) |
| `POTALogEntryRow.swift` | Individual POTA log entry display (legacy) |

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

## Views - Activity (`CarrierWave/Views/Activity/`)
| File | Purpose |
|------|---------|
| `ActivityView.swift` | Main activity tab with challenges section and activity feed |
| `ActivityItemRow.swift` | Individual activity feed item display |
| `FilterBar.swift` | Feed filter chips (All/Friends/Clubs) |
| `FriendsListView.swift` | Friends list with pending requests |
| `FriendSearchView.swift` | Search and add friends |
| `ClubsListView.swift` | List of clubs user belongs to |
| `ClubDetailView.swift` | Club details and member list |
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
| `ChallengesSettingsView.swift` | Challenges feature settings |
| `POTAAuthWebView.swift` | POTA OAuth WebView |
| `SyncDebugView.swift` | Sync debugging interface |
| `AttributionsView.swift` | Third-party attributions |
| `ExternalDataView.swift` | External data cache status and refresh (POTA parks) |
| `BugReportView.swift` | Bug report form with dpaste upload and Discord instructions |
| `CallsignAliasesSettingsView.swift` | Manage current and previous callsigns |
| `SettingsSections.swift` | Sync Sources section with service navigation links |
| `CallsignNotesSettingsView.swift` | Manage callsign notes file sources (URL + title) |

## Documentation (`docs/`)
| File | Purpose |
|------|---------|
| `design-language.md` | Visual and interaction design patterns specification |
| `features/callsign-filtering.md` | Primary callsign filtering requirements for syncs |
| `features/logger-requirements.md` | Logger requirements and compliance checklist |
| `features/sync.md` | QRZ, POTA, LoFi sync integration |
| `features/statistics.md` | Dashboard stats and drilldown views |

## Views - Map (`CarrierWave/Views/Map/`)
| File | Purpose |
|------|---------|
| `QSOMapView.swift` | Main map view showing QSO locations |
| `QSOMapHelperViews.swift` | Map markers, filter sheet, callout views |
| `MapFilterState.swift` | Observable filter state for map |
| `QSOAnnotation.swift` | Annotation model for map markers and arcs |

## Utilities (`CarrierWave/Utilities/`)
| File | Purpose |
|------|---------|
| `BandUtilities.swift` | Band derivation from frequency and band ordering |
| `FrequencyFormatter.swift` | Frequency formatting with sub-kHz precision support |
| `KeychainHelper.swift` | Secure credential storage |
| `MaidenheadConverter.swift` | Grid square to coordinate conversion |

## Tests (`CarrierWaveTests/`)
| File | Purpose |
|------|---------|
| `CarrierWaveTests.swift` | Main test file placeholder |
| `ADIFParserTests.swift` | ADIF parsing tests |
| `DeduplicationServiceTests.swift` | QSO deduplication logic tests |
| `ImportServiceTests.swift` | Import service tests |
| `LoFiClientTests.swift` | LoFi client tests |
| `QRZClientTests.swift` | QRZ client tests |
| `Helpers/QSOFactory.swift` | Synthetic QSO generator for performance testing |
| `PerformanceTests/QSOStatisticsPerformanceTests.swift` | Performance regression tests (50k/500k QSOs) |
| `QuickEntryParserTests.swift` | Quick entry parser unit tests (callsign, RST, park, grid, state detection) |
| `QuickEntryParserIntegrationTests.swift` | Quick entry parser integration tests (full parsing, token preview) |
