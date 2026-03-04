//
//  QuickEntryParser.swift
//  CarrierWave
//
//  Thin wrapper around CarrierWaveCore's QuickEntryParser that integrates
//  with the app's LoggerCommand for command detection.
//

@_exported import CarrierWaveCore
import CarrierWaveData
import Foundation

// Re-export types from CarrierWaveCore for app compatibility
typealias TokenType = CarrierWaveCore.TokenType
typealias ParsedToken = CarrierWaveCore.ParsedToken
typealias QuickEntryResult = CarrierWaveCore.QuickEntryResult

// MARK: - QuickEntryParser

/// App-level wrapper that connects CarrierWaveCore's QuickEntryParser with LoggerCommand
enum QuickEntryParser {
    // MARK: Internal

    /// Parse a quick entry string into structured result
    /// Returns nil if input is not valid quick entry (single callsign or command)
    static func parse(_ input: String) -> QuickEntryResult? {
        CarrierWaveCore.QuickEntryParser.parse(input, isCommand: isLoggerCommand)
    }

    /// Parse a quick entry string into tokens with types for UI preview (color-coding)
    /// Returns empty array if input is not valid quick entry (single callsign or command)
    static func parseTokens(_ input: String) -> [ParsedToken] {
        CarrierWaveCore.QuickEntryParser.parseTokens(input, isCommand: isLoggerCommand)
    }

    /// Check if a string is a valid RST report
    static func isRST(_ string: String) -> Bool {
        CarrierWaveCore.QuickEntryParser.isRST(string)
    }

    /// Check if a string looks like a valid amateur radio callsign
    static func isCallsign(_ string: String) -> Bool {
        CarrierWaveCore.QuickEntryParser.isCallsign(string)
    }

    /// Check if a string is a valid POTA/WWFF park reference
    static func isParkReference(_ string: String) -> Bool {
        CarrierWaveCore.QuickEntryParser.isParkReference(string)
    }

    /// Check if a string is a valid Maidenhead grid square
    static func isGridSquare(_ string: String) -> Bool {
        CarrierWaveCore.QuickEntryParser.isGridSquare(string)
    }

    /// Check if a string is a valid US state, Canadian province, or DX region code
    static func isStateOrRegion(_ string: String) -> Bool {
        CarrierWaveCore.QuickEntryParser.isStateOrRegion(string)
    }

    // MARK: Private

    /// Check if a token is a LoggerCommand (used to prevent quick entry on commands)
    private static func isLoggerCommand(_ token: String) -> Bool {
        LoggerCommand.parse(token) != nil
    }
}
