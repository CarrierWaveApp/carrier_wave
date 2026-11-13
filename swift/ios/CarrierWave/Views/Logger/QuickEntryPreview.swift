//
//  QuickEntryPreview.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI

// MARK: - TokenType Extension

extension TokenType {
    /// Color for UI display of this token type
    var color: Color {
        switch self {
        case .callsign:
            .green
        case .rstSent,
             .rstReceived:
            .blue
        case .state:
            .orange
        case .park:
            .green
        case .grid:
            .purple
        case .frequency:
            .teal
        case .band:
            .indigo
        case .mode:
            .green
        case .notes:
            .secondary
        case .time:
            .mint
        case .rstConflict:
            .red
        }
    }

    /// Short label for UI display below token badge
    var label: String {
        switch self {
        case .callsign:
            "call"
        case .rstSent:
            "sent"
        case .rstReceived:
            "rcvd"
        case .rstConflict:
            "rst?"
        case .state:
            "state"
        case .park:
            "park"
        case .grid:
            "grid"
        case .frequency:
            "freq"
        case .band:
            "band"
        case .mode:
            "mode"
        case .time:
            "utc"
        case .notes:
            "note"
        }
    }
}

// MARK: - QuickEntryPreview

/// Displays parsed quick entry tokens with color coding
struct QuickEntryPreview: View {
    // MARK: Internal

    let tokens: [ParsedToken]
    /// Park reference from a matched POTA spot, shown when not already in tokens
    var spotPark: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(displayTokens) { token in
                    TokenBadge(token: token)
                }
                ForEach(spotTokens) { token in
                    SpotTokenBadge(token: token)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Private

    /// Tokens with consecutive notes combined into a single token
    private var displayTokens: [ParsedToken] {
        var result: [ParsedToken] = []
        var noteTexts: [String] = []
        var noteStartIndex: Int?

        for token in tokens {
            if token.type == .notes {
                if noteStartIndex == nil {
                    noteStartIndex = token.index
                }
                noteTexts.append(token.text)
            } else {
                // Flush accumulated notes before adding this token
                if !noteTexts.isEmpty, let startIndex = noteStartIndex {
                    result.append(
                        ParsedToken(
                            index: startIndex,
                            text: noteTexts.joined(separator: " "),
                            type: .notes
                        )
                    )
                    noteTexts = []
                    noteStartIndex = nil
                }
                result.append(token)
            }
        }

        // Flush any remaining notes at the end
        if !noteTexts.isEmpty, let startIndex = noteStartIndex {
            result.append(
                ParsedToken(
                    index: startIndex,
                    text: noteTexts.joined(separator: " "),
                    type: .notes
                )
            )
        }

        return result
    }

    /// Tokens from matched POTA spots (park not already in quick entry)
    private var spotTokens: [ParsedToken] {
        let hasPark = tokens.contains { $0.type == .park }
        guard !hasPark, let park = spotPark else {
            return []
        }
        let nextIndex = (displayTokens.last?.index ?? tokens.count) + 1
        return [ParsedToken(index: nextIndex, text: park, type: .park)]
    }
}

// MARK: - TokenBadge

/// Individual token badge with text and label
private struct TokenBadge: View {
    let token: ParsedToken

    var body: some View {
        VStack(spacing: 2) {
            Text(token.text)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(token.type.color.opacity(0.2))
                .foregroundStyle(token.type.color)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(token.type.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - SpotTokenBadge

/// Token badge for spot-sourced values, with antenna icon to indicate source
private struct SpotTokenBadge: View {
    let token: ParsedToken

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption2)
                Text(token.text)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(token.type.color.opacity(0.2))
            .foregroundStyle(token.type.color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(token.type.color.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )

            Text(token.type.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview("Quick Entry Tokens") {
    VStack(spacing: 20) {
        // Full example with all token types
        QuickEntryPreview(tokens: [
            ParsedToken(index: 0, text: "AJ7CM", type: .callsign),
            ParsedToken(index: 1, text: "579", type: .rstSent),
            ParsedToken(index: 2, text: "559", type: .rstReceived),
            ParsedToken(index: 3, text: "WA", type: .state),
            ParsedToken(index: 4, text: "US-0189", type: .park),
            ParsedToken(index: 5, text: "CN87", type: .grid),
            ParsedToken(index: 6, text: "SOTA", type: .notes),
        ])

        Divider()

        // Simple example
        QuickEntryPreview(tokens: [
            ParsedToken(index: 0, text: "W1AW", type: .callsign),
            ParsedToken(index: 1, text: "59", type: .rstReceived),
        ])

        Divider()

        // POTA example
        QuickEntryPreview(tokens: [
            ParsedToken(index: 0, text: "K3LR", type: .callsign),
            ParsedToken(index: 1, text: "US-1234", type: .park),
            ParsedToken(index: 2, text: "PA", type: .state),
        ])

        Divider()

        // Example with multi-word notes (should combine into single badge)
        QuickEntryPreview(tokens: [
            ParsedToken(index: 0, text: "W1AW", type: .callsign),
            ParsedToken(index: 1, text: "59", type: .rstReceived),
            ParsedToken(index: 2, text: "GREAT", type: .notes),
            ParsedToken(index: 3, text: "SIGNAL", type: .notes),
            ParsedToken(index: 4, text: "TODAY", type: .notes),
        ])
    }
    .padding()
}
