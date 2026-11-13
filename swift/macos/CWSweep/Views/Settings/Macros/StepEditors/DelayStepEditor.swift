import CarrierWaveData
import SwiftUI

// MARK: - DelayStepEditor

/// Editor for `.delay(durationMs:)`. The verifier caps delays at
/// 30,000 ms; the editor surfaces the cap inline rather than waiting
/// for the verifier banner to complain.
struct DelayStepEditor: View {
    // MARK: Internal

    @Binding var durationMs: UInt64

    var body: some View {
        Form {
            Section("Duration") {
                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(durationMs) },
                            set: { durationMs = UInt64($0) }
                        ),
                        in: 0 ... 30_000,
                        step: 50
                    )
                    Text("\(durationMs) ms")
                        .font(.body.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                }
                TextField(
                    "Milliseconds",
                    value: Binding(
                        get: { durationMs },
                        set: { durationMs = min($0, 30_000) }
                    ),
                    formatter: NumberFormatter()
                )
                Text(secondsLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if durationMs == 30_000 {
                    Text("Capped at 30,000 ms (verifier limit).")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Section {
                ForEach(Self.suggestions, id: \.label) { suggestion in
                    Button {
                        durationMs = suggestion.ms
                    } label: {
                        HStack {
                            Text(suggestion.label)
                            Spacer()
                            Text("\(suggestion.ms) ms")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Common")
            }
        }
        .navigationTitle("Wait")
    }

    // MARK: Private

    private struct Suggestion {
        let label: String
        let ms: UInt64
    }

    private static let suggestions: [Suggestion] = [
        .init(label: "Quick (100 ms)", ms: 100),
        .init(label: "Settle (250 ms)", ms: 250),
        .init(label: "Brief (500 ms)", ms: 500),
        .init(label: "1 second", ms: 1_000),
        .init(label: "3 seconds", ms: 3_000),
        .init(label: "5 seconds", ms: 5_000),
    ]

    private var secondsLabel: String {
        String(format: "%.2f s", Double(durationMs) / 1_000)
    }
}
