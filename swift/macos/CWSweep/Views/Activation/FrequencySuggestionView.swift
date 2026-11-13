import CarrierWaveCore
import SwiftUI

// MARK: - FrequencySuggestionView

/// Card displaying the recommended frequency from FrequencySuggestionEngine.
struct FrequencySuggestionView: View {
    let suggestion: FrequencySuggestion?

    var body: some View {
        if let suggestion {
            VStack(alignment: .leading, spacing: 4) {
                Text("SUGGESTED FREQUENCY")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .tracking(0.5)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(FrequencyFormatter.format(suggestion.frequencyMHz))
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                    Text("MHz")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.green.opacity(0.2)))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
