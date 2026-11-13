import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - LoggerCommand Parsing (shared Rust grammar)

extension LoggerCommand {
    /// Parse input into a command. The command grammar (`FREQ`/`MODE`/`SPOT`/
    /// `RBN`/`HUNT`/… with all their aliases) lives in the shared Rust core
    /// (`cw_domain::logger_command`, via `parseLoggerCommand`), so it isn't
    /// reimplemented per platform. Returns nil when the input isn't a command
    /// (treat as a callsign). Only the mapping to this enum — and each command's
    /// native action/icon — stays in Swift.
    static func parse(_ input: String) -> LoggerCommand? {
        parseLoggerCommand(input: input).map(LoggerCommand.init(ffi:))
    }

    // Map the shared Rust `FfiLoggerCommand` into the app command enum — a flat
    // 1:1 case map; the complexity is inherent to the case count.
    // swiftlint:disable:next cyclomatic_complexity
    init(ffi: FfiLoggerCommand) {
        switch ffi {
        case let .frequency(mhz):
            self = .frequency(mhz)
        case let .mode(mode):
            self = .mode(mode)
        case let .spot(comment, repeatMinutes):
            self = .spot(comment: comment, repeatMinutes: repeatMinutes.map(Int.init))
        case .spotStop:
            self = .spotStop
        case let .rbn(callsign):
            self = .rbn(callsign: callsign)
        case .hunt:
            self = .hunt
        case let .huntLog(entry):
            self = .huntLog(CarrierWaveCore.QuickEntryParser.result(from: entry))
        case .p2p:
            self = .p2p
        case .s2s:
            self = .s2s
        case .solar:
            self = .solar
        case .weather:
            self = .weather
        case .map:
            self = .map
        case .hidden:
            self = .hidden
        case .help:
            self = .help
        case let .note(text):
            self = .note(text: text)
        case .manual:
            self = .manual
        case .websdr:
            self = .websdr
        case .band:
            self = .band
        case .rig:
            self = .rig
        case .checklist:
            self = .checklist
        case .radio:
            self = .radio
        case .replay:
            self = .replay
        case let .myCall(callsign):
            self = .myCall(callsign)
        case let .sessionMetadata(entry):
            self = .sessionMetadata(CarrierWaveCore.QuickEntryParser.metadata(from: entry))
        }
    }
}
