## CarrierWaveCore Package (`swift/packages/CarrierWaveCore/`)

Pure logic library that can be tested without iOS Simulator. Run tests with `make test-unit-core`.

| File | Purpose |
|------|---------|
| `Sources/CarrierWaveCore/ADIFParser.swift` | ADIF file format parsing |
| `Sources/CarrierWaveCore/ADIFFieldValidator.swift` | ADIF 3.1.7 per-field validator (length, format, allowed enums) for export sanitization |
| `Sources/CarrierWaveCore/AzimuthalProjection.swift` | Azimuthal equidistant projection math and great circle paths |
| `Sources/CarrierWaveCore/BandUtilities.swift` | Band derivation from frequency |
| `Sources/CarrierWaveCore/CallsignDetector.swift` | Callsign regex detection, RST/grid/power parsing |
| `Sources/CarrierWaveCore/CIVProtocol.swift` | CI-V protocol: frame building/parsing, BCD frequency encoding, mode mapping |
| `Sources/CarrierWaveCore/CIVScope.swift` | Icom `0x27` spectrum scope: `27 00` waveform frame parser, Main/Sub accumulator (USB 11-division + LAN single-frame), command encoders |
| `Sources/CarrierWaveCore/CIVDuplex.swift` | IC-9700 Main/Sub band select (`07 D0/D1/D2`), satellite mode (`16 5A`), PTT read (`1C 00`): encoders, reply parsers, ack/nak checks |
| `Sources/CarrierWaveCore/CoastlineData.swift` | Natural Earth 110m land polygon index (~5K points, public domain) |
| `Sources/CarrierWaveCore/CoastlineData+Part1..6.swift` | Land polygon coordinate data split across 6 files |
| `Sources/CarrierWaveCore/KenwoodProtocol.swift` | Kenwood/Elecraft K3 text command building/parsing, mode mapping |
| `Sources/CarrierWaveCore/TextProtocolParser.swift` | Shared `;`-terminated response extraction for text-based radio protocols |
| `Sources/CarrierWaveCore/YaesuProtocol.swift` | Yaesu CAT text command building/parsing, IF response parsing, mode mapping |
| `Sources/CarrierWaveCore/CallsignEditDistance.swift` | Levenshtein edit distance for callsign comparison |
| `Sources/CarrierWaveCore/SCPDatabase.swift` | Super Check Partial in-memory database (partial match, exact lookup, near-miss) |
| `Sources/CarrierWaveCore/CWTextElement.swift` | CW text element types for transcript highlighting |
| `Sources/CarrierWaveCore/DeduplicationMatcher.swift` | Duplicate detection logic |
| `Sources/CarrierWaveCore/DetectedCallsign.swift` | Detected callsign with context |
| `Sources/CarrierWaveCore/FrequencyFormatter.swift` | Frequency formatting and parsing |
| `Sources/CarrierWaveCore/Ham365Models.swift` | Ham365 DXpedition data model |
| `Sources/CarrierWaveCore/Ham365Parser.swift` | Ham365.net HTML calendar parser |
| `Sources/CarrierWaveCore/MaidenheadConverter.swift` | Grid square ↔ coordinate conversion, haversine distance, bearing, 6-char tile bounds |
| `Sources/CarrierWaveCore/MaidenheadConverter+Rust.swift` | UniFFI bridge: `coordinateViaRust`/`gridViaRust`/`distanceKmViaRust`/`bearingViaRust`/`isValidViaRust` forward to `cw-domain::maidenhead` |
| `Sources/CarrierWaveCore/FieldStore+Observation.swift` | UniFFI bridge: `FieldStore.changes(for:)` adapts the Rust `StoreObserver` callback into an `AsyncStream<FfiStoreChange>` (the `@Query`-reactivity replacement); auto-registers/removes the observer over the stream's lifetime |
| `Sources/CarrierWaveCore/CwFfiExports.swift` | `@_exported import CarrierWaveCwFfi` — re-exports the FFI surface (`FieldStore`, `Ffi*`, `StoreObserver`) so downstream packages see it via `import CarrierWaveCore` |
| `Sources/CarrierWaveCore/TOTAScoringEngine.swift` | Pure TOTA scoring formula (Standard + Mobile), 4-tier ledger output |
| `Sources/CarrierWaveCore/TOTATileDetector.swift` | QSO-anchored multi-tile detection from track samples |
| `Sources/CarrierWaveCore/TOTAT3Correlator.swift` | T3 candidate matcher: TOTA spots ↔ QSOs with 6h preceding window |
| `Sources/CarrierWaveCore/TOTAWinterDetector.swift` | Hemisphere-aware winter bonus eligibility |
| `Sources/CarrierWaveCore/ModeEquivalence.swift` | Mode family classification and equivalence |
| `Sources/CarrierWaveCore/MorseCode.swift` | Morse code tables and timing utilities |
| `Sources/CarrierWaveCore/MorseEditDistance.swift` | Levenshtein distance on morse patterns |
| `Sources/CarrierWaveCore/NATOPhonetics.swift` | NATO/ITU phonetic alphabet spelling for callsign readback |
| `Sources/CarrierWaveCore/ParkReference.swift` | Park reference parsing and validation |
| `Sources/CarrierWaveCore/QSOSnapshot.swift` | Lightweight QSO representation for matching |
| `Sources/CarrierWaveCore/Sharing/EnrichedLinkPayload.swift` | Enriched share link payload schema (callsign + park + dispatcher) |
| `Sources/CarrierWaveCore/Sharing/EnrichedLinkPayload+QSO.swift` | Enriched share link payload schema (QSO + activation) |
| `Sources/CarrierWaveCore/Sharing/EnrichedLinkBuilder.swift` | Builds universal-link URLs from enriched payloads, handles truncation |
| `Sources/CarrierWaveCore/Sharing/ActivationTruncation.swift` | Progressive truncation levels for activation payloads |
| `Sources/CarrierWaveCore/Sharing/PlatformImage.swift` | Cross-platform UIImage/NSImage typealias for sharing |
| `Sources/CarrierWaveCore/Sharing/LinkPreviewCardView.swift` | Cross-platform SwiftUI card views for LPLinkMetadata previews |
| `Sources/CarrierWaveCore/Sharing/LinkPreviewCardRenderer.swift` | Renders LinkPreviewCardView to a PlatformImage via ImageRenderer |
| `Sources/CarrierWaveCore/QuickEntryParser.swift` | Quick entry public types + API; delegates parsing to `cw_domain::quick_entry` via UniFFI (grammar shared with Android) |
| `Sources/CarrierWaveCore/RadioBandDefaults.swift` | Band frequency defaults table (CW, SSB, FT8, FT4 per band) |
| `Sources/CarrierWaveCore/BandPlan.swift` | US amateur radio band plan data with license class privileges and frequency dicts |
| `Sources/CarrierWaveCore/BandPlan+Activities.swift` | Frequency activity data (QRP, SSTV, FT8, CWT, nets) and time windows |
| `Sources/CarrierWaveCore/BandPlan+Frequencies.swift` | Common calling and activity frequencies by band |
| `Sources/CarrierWaveCore/RadioCommandParser.swift` | Radio command palette parser (frequency, mode, band shortcuts, split directives, named commands) |
| `Sources/CarrierWaveCore/ServiceType.swift` | Sync service type enum (QRZ, POTA, LoFi, etc.) |
| `Sources/CarrierWaveCore/StreakCalculator.swift` | Streak calculation from date sets |
| `Sources/CarrierWaveCore/SuggestionCategory.swift` | CW suggestion category enum |
| `Sources/CarrierWaveCore/TwoferMatcher.swift` | Two-fer duplicate detection |
| `Sources/CarrierWaveCore/AntennaDescriptionParser.swift` | KiwiSDR antenna description parser (type, bands, directionality) |
| `Sources/CarrierWaveCore/AntennaPattern.swift` | Parametric 2D azimuthal radiation patterns for common antenna types |
| `Sources/CarrierWaveCore/AzimuthalProjection.swift` | Azimuthal equidistant projection math, sector binning for polar map |
| `Sources/CarrierWaveCore/CallsignNotesSourceConfig.swift` | Codable config for callsign notes file sources (synced via iCloud KVS) |
| `Sources/CarrierWaveCore/PoloNotesEntry.swift` | Parsed Polo notes entry (callsign, emoji, name, note) with text parsing |
| `Sources/CarrierWaveCore/PoloNotesParser.swift` | Parse Ham2K Polo notes list files into PoloNotesEntry objects |
| `Sources/CarrierWaveCore/QSYURIParser.swift` | QSY URI scheme parser (qsy://spot, tune, lookup, import, log) |
| `Sources/CarrierWaveCore/QueryLanguage/QueryToken.swift` | Query token types and field definitions |
| `Sources/CarrierWaveCore/QueryLanguage/QueryLexer.swift` | Query string tokenization |
| `Sources/CarrierWaveCore/QueryLanguage/QueryAST.swift` | Query AST types (expression, term, condition) |
| `Sources/CarrierWaveCore/QueryLanguage/QueryParser.swift` | Token stream to AST parsing (core struct, expression/group parsing) |
| `Sources/CarrierWaveCore/QueryLanguage/QueryParser+FieldTerms.swift` | Field term and bare term parsing |
| `Sources/CarrierWaveCore/QueryLanguage/QueryParser+Conditions.swift` | Condition building (date, numeric, status, source, wildcards) |
| `Sources/CarrierWaveCore/QueryLanguage/QueryAnalyzer.swift` | Query performance analysis and warnings |
| `Sources/CarrierWaveCore/QueryLanguage/QueryAnalyzer+Rust.swift` | UniFFI bridge: `analyzeViaRust`/`validateViaRust` forward to `cw-domain` and lift result into Swift `QueryAnalysis` |
| `Sources/CarrierWaveCwFfi/CwFfi+Generated.swift` | UniFFI-generated Swift bindings for `cw-ffi` (do not hand-edit; `rust/cw-core/scripts/build-xcframework.sh` regenerates) |
| `Vendored/CwFfi.xcframework` | Built XCFramework (gitignored — produced by `rust/cw-core/scripts/build-xcframework.sh`) |
| `Sources/CFT8/` | Vendored ft8_lib C library (MIT license) — FT8 encode/decode with KISS FFT and LDPC codec |
| `Sources/CarrierWaveCore/FT8Constants.swift` | FT8 dial frequencies, supported bands, timing constants |
| `Sources/CarrierWaveCore/FT8Message.swift` | FT8 message types (CQ, directed, signal report, RR73) and decode result |
| `Sources/CarrierWaveCore/FT8Decoder.swift` | Swift wrapper over ft8_lib C decoder |
| `Sources/CarrierWaveCore/FT8EnrichedDecode.swift` | Enriched FT8 decode with DXCC, state, distance, worked-before flags, section classification |
| `Sources/CarrierWaveCore/SOTASpot.swift` | SOTAwatch API spot model (activator, summit, frequency, mode, timestamp) |
| `Sources/CarrierWaveCore/SOTAClient.swift` | SOTAwatch API actor — fetches active spots and posts self-spots to api2.sota.org.uk |
| `Sources/CarrierWaveCore/WWFFSpot.swift` | WWFF Spotline API spot model (activator, reference, frequency, mode, timestamp) |
| `Sources/CarrierWaveCore/WWFFAgendaItem.swift` | WWFF Spotline agenda model for scheduled upcoming activations |
| `Sources/CarrierWaveCore/WWFFClient.swift` | WWFF Spotline API actor for fetching spots and agenda from spots.wwff.co |
| `Sources/CarrierWaveCore/POTAShift.swift` | POTA early/late shift calculation based on park longitude |
| `Sources/CarrierWaveCore/POTASpot.swift` | POTA spot model (activator, park, frequency, mode, timestamp) |
| `Sources/CarrierWaveCore/RBNSpot.swift` | Reverse Beacon Network spot model with band derivation via BandUtilities |
| `Sources/CarrierWaveCore/PSKReporterSpot.swift` | PSK Reporter reception report model (sender/receiver callsign, locator, frequency, SNR) |
| `Sources/CarrierWaveCore/PSKReporterClient.swift` | PSK Reporter HTTP query API actor with XML parsing (5-min rate limit, FT8/FT4 spots) |
| `Sources/CarrierWaveCore/DONKIClient.swift` | NASA DONKI space weather API actor — geomagnetic storms, solar flares, CMEs with 30-min cache |
| `Sources/CarrierWaveCore/HamQSLClient.swift` | HamQSL solar XML API actor with 15-min cache (solar indices + per-band day/night conditions) |
| `Sources/CarrierWaveCore/PropagationEstimator.swift` | Empirical HF band propagation estimator from SFI, K-index, and UTC hour (MUF model + per-band quality) |
| `Sources/CarrierWaveCore/Ham365Client.swift` | Ham365.net DXpedition calendar API actor |
| `Sources/CarrierWaveCore/FT8Encoder.swift` | FT8 GFSK tone synthesis for transmission |
| `Sources/CarrierWaveCore/FT8QSOStateMachine.swift` | Pure-logic state machine for FT8 QSO exchanges (CQ and S&P modes) |
| `Sources/CarrierWaveCore/LoFi/LoFiCredentialStore.swift` | Protocol + key enum for credential storage |
| `Sources/CarrierWaveCore/LoFi/LoFiLogger.swift` | Protocol for logging |
| `Sources/CarrierWaveCore/LoFi/LoFiModels.swift` | LoFi API request/response models (operations, registration) |
| `Sources/CarrierWaveCore/LoFi/LoFiModels+QSO.swift` | LoFi QSO response models (QSOs, metadata) |
| `Sources/CarrierWaveCore/LoFi/LoFiClient.swift` | Ham2K LoFi sync client (core, config, setup) |
| `Sources/CarrierWaveCore/LoFi/LoFiClient+Fetch.swift` | LoFi fetch endpoints (operations, QSOs) |
| `Sources/CarrierWaveCore/LoFi/LoFiClient+Sync.swift` | LoFi sync orchestration (full download, progress) |
| `Sources/CarrierWaveCore/LoFi/LoFiClient+Helpers.swift` | LoFi helpers (token, secret gen, request, accumulator) |
| `Sources/CarrierWaveCore/CTYParser.swift` | CTY.dat parser — builds CTYDatabase with longest-prefix-match DXCC entity lookup |
| `Sources/CarrierWaveCore/DescriptionLookup.swift` | Human-readable descriptions for codes (DXCCEntityRef type) |
| `Sources/CarrierWaveCore/DescriptionLookup+DXCC.swift` | DXCC lookup entry point and combined entity list |
| `Sources/CarrierWaveCore/DescriptionLookup+DXCC+Americas.swift` | DXCC entities: US, Canada, Mexico, South/Central America, Caribbean |
| `Sources/CarrierWaveCore/DescriptionLookup+DXCC+Europe.swift` | DXCC entities: Europe, Russia, Caucasus, Central Asia |
| `Sources/CarrierWaveCore/DescriptionLookup+DXCC+AsiaOceania.swift` | DXCC entities: Middle East, South/East/SE Asia, Oceania |
| `Sources/CarrierWaveCore/DescriptionLookup+DXCC+AfricaOther.swift` | DXCC entities: Africa, Indian/Atlantic Ocean, special entities |
| `Sources/CarrierWaveCore/DescriptionLookup+DXCC+Descriptions.swift` | Simple prefix-to-country name lookup table |
| `Sources/CarrierWaveCore/LocationPrefixLookup.swift` | Location-based call sign prefix lookup (GPS → nearest DXCC entity, callsign → home country) |
| `Sources/CarrierWaveCore/LocationPrefixLookup+Countries.swift` | Prefix country data: Americas |
| `Sources/CarrierWaveCore/LocationPrefixLookup+Europe.swift` | Prefix country data: Europe |
| `Sources/CarrierWaveCore/LocationPrefixLookup+AsiaOceania.swift` | Prefix country data: Asia & Oceania |
| `Sources/CarrierWaveCore/LocationPrefixLookup+Africa.swift` | Prefix country data: Africa + combined country list |
| `Sources/CarrierWaveCore/DescriptionLookup+Grid.swift` | Maidenhead grid field to approximate region name lookup |
| `Sources/CarrierWaveCore/GridSquareStatus.swift` | Grid square status enum, GridSquareData, GridTrackerSummary types |
| `Sources/CarrierWaveCore/UnitFormatter.swift` | Centralized imperial/metric unit formatting (distance, temperature, wind, watts/distance) |
| `Sources/CarrierWaveCore/FT8DecodeEnricher.swift` | Enriches raw FT8 decodes with DXCC entity, distance, bearing, worked-before flags |
| `Sources/CarrierWaveCore/FT8Models.swift` | FT8 operating mode, TX event/state, channel recommendation types |
| `Sources/CarrierWaveCore/FT8WaterfallData.swift` | Observable waterfall magnitude data for FT8 spectrum display |
| `Sources/CarrierWaveCore/RemoteOp/RemoteOpTransport.swift` | `RemoteOpTransport` byte-pipe protocol — one decoded JSON frame per `incoming()` element |
| `Sources/CarrierWaveCore/RemoteOp/NWConnectionTransport.swift` | LAN TCP adapter for `RemoteOpTransport`; owns the newline-delimited framing |
| `Sources/CarrierWaveCore/RemoteOp/MultipeerTransport.swift` | MultipeerConnectivity adapter for `RemoteOpTransport`; off-LAN transport for iOS↔macOS |

## LoFi CLI (`Sources/LoFiCLI/`)

Standalone CLI tool for testing LoFi downloads without iOS Simulator. Run with `cd CarrierWaveCore && swift run lofi-cli`.

| File | Purpose |
|------|---------|
| `Sources/LoFiCLI/LoFiCLI.swift` | CLI entry point with register/link/download/status subcommands |
| `Sources/LoFiCLI/LoFiCLI+Pipeline.swift` | Sync report pipeline breakdown (skipped, two-fer, dupe analysis) |
| `Sources/LoFiCLI/FileCredentialStore.swift` | LoFiCredentialStore backed by ~/.config/lofi-cli/credentials.json |
| `Sources/LoFiCLI/ConsoleLogger.swift` | LoFiLogger that prints to stderr with level prefixes |


## CarrierWaveCore Tests (`swift/packages/CarrierWaveCore/Tests/CarrierWaveCoreTests/`)
| File | Purpose |
|------|---------|
| `FT8ConstantsTests.swift` | FT8 constants tests (dial frequencies, supported bands) |
| `FT8MessageTests.swift` | FT8 message parsing and classification tests |
| `FT8DecoderTests.swift` | FT8 decoder tests (WAV sample decoding) |
| `FT8EncoderTests.swift` | FT8 encoder tests (tone generation, round-trip) |
| `FT8EnrichedDecodeTests.swift` | FT8 enriched decode tests (section classification, sort priority, SNR tier) |
| `FT8QSOStateMachineTests.swift` | FT8 QSO state machine tests (S&P, CQ, timeout, duplicate) |
| `AntennaDescriptionParserTests.swift` | Antenna description parsing tests (models, bands, direction) |
| `AzimuthalProjectionInverseTests.swift` | Inverse azimuthal projection round-trip and edge case tests |
| `Ham365ParserTests.swift` | Ham365 DXpedition calendar HTML parser tests |
| `RemoteOpWaterfallFramesTests.swift` | `WaterfallLineEvent` quantize/dequantize round-trip + JSON framing round-trip for the `radio.waterfall` topic |
| `QueryLanguage/QueryAnalyzerRustParityTests.swift` | Parity vectors: Swift vs Rust analyzer agree on `usesIndex`, `estimatedCost`, `requiresConfirmation`, `shouldWarn` |
| `MaidenheadRustParityTests.swift` | Parity: Swift vs Rust Maidenhead agree on coordinate (1e-9), grid string (exact), distance/bearing (0.01), validity |
| `FieldStoreObservationTests.swift` | End-to-end: `FieldStore.changes(for:)` yields an `FfiStoreChange` on QSO upsert; re-fetch from the consumer sees the committed write (no deadlock) |

