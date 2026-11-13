import SwiftUI

// MARK: - CallsignNotesSection

/// Displays Polo notes and user annotations for a callsign.
struct CallsignNotesSection: View {
    let callsign: String
    let callsignInfo: CallsignInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Notes")
                    .font(.headline)
                Spacer()
            }

            if let note = callsignInfo?.note, !note.isEmpty {
                Text(CallsignInfo.parseNoteMarkdown(note))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No notes for this callsign")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            if let previousCall = callsignInfo?.previousCallsign {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.up.left")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Previously \(previousCall)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let changeNote = callsignInfo?.callsignChangeNote {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(changeNote)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let sources = callsignInfo?.matchingSources, !sources.isEmpty {
                HStack(spacing: 4) {
                    ForEach(sources, id: \.self) { src in
                        Text(src)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
