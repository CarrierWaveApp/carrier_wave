import CarrierWaveCore
import SwiftUI

// MARK: - RemoteCWEntryStrip

//
// Compact "current QSO" strip that drives the Remote CW keyer pane's macro
// substitutions. Owner is `RemoteSweepCWPane` — this view binds straight to
// a shared `RemoteQSOContext` so changes propagate to the slot buttons'
// enable/disable logic in real time.

struct RemoteCWEntryStrip: View {
    // MARK: Internal

    @Bindable var context: RemoteQSOContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            callsignRow
            HStack(spacing: 8) {
                rstField
                serialField
                exchangeField
            }
            lookupChip
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemBackground))
    }

    // MARK: Private

    private var callsignRow: some View {
        HStack(spacing: 8) {
            TextField("Callsign", text: $context.callsign)
                .font(.system(.title3, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .submitLabel(.done)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            if context.isLookingUp {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var rstField: some View {
        labeledField("RST") {
            TextField("599", text: $context.rstSent)
                .keyboardType(.numberPad)
                .frame(width: 56)
        }
    }

    private var serialField: some View {
        labeledField("NR") {
            TextField(
                "1",
                value: $context.serial,
                format: .number
            )
            .keyboardType(.numberPad)
            .frame(width: 56)
        }
    }

    private var exchangeField: some View {
        labeledField("EXCH") {
            TextField("Exchange", text: $context.exchange)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
        }
    }

    @ViewBuilder
    private var lookupChip: some View {
        if !context.callsign.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !context.name.isEmpty {
                    Text(context.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    if let qth = context.lookupResult?.qth, !qth.isEmpty {
                        Text("· \(qth)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if context.isLookingUp {
                    Text("Looking up…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No name found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func labeledField(_ label: String, @ViewBuilder field: () -> some View) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            field()
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
