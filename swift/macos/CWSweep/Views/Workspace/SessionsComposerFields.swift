import SwiftUI

// MARK: - SectionLabel

/// Small-caps section header used inside the composer to group fields.
/// Matches the dense Linear/Raycast aesthetic — secondary color, narrow,
/// generous tracking. Pairs with the field rows below.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

// MARK: - MonoTextField

/// Monospaced text field with an inline small-caps label, used for callsign /
/// grid / manual references where radio data deserves a fixed-width readout.
struct MonoTextField: View {
    let label: String
    @Binding var text: String

    var width: CGFloat = 140
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body.monospaced())
                .textCase(.uppercase)
                .autocorrectionDisabled()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(width: width, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }
}

// MARK: - ManualRefField

/// Compact secondary reference field for SOTA / WWFF when the operator
/// isn't using the POTA typeahead. Same chrome as MonoTextField but slightly
/// narrower; lives inline beneath the park search.
struct ManualRefField: View {
    let label: String
    let placeholder: String

    @Binding var text: String

    var body: some View {
        MonoTextField(label: label, text: $text, width: 160, placeholder: placeholder)
    }
}

// MARK: - FrequencyReadout

/// Frequency display + manual entry. When the radio is supplying a value
/// (`fromRadio == true`), shows it in green monospace with a subtle
/// "from radio" badge — and remains editable so the operator can override.
struct FrequencyReadout: View {
    // MARK: Internal

    @Binding var frequency: Double?

    let fromRadio: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("FREQ")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                if fromRadio {
                    FromRadioBadge()
                }
            }
            TextField("14.025", text: textBinding)
                .textFieldStyle(.plain)
                .font(.title3.monospaced().weight(.semibold))
                .foregroundStyle(fromRadio ? Color.green : Color.primary)
                .frame(width: 140, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }

    // MARK: Private

    private static let formatter: NumberFormatter = {
        let fmt = NumberFormatter()
        fmt.minimumFractionDigits = 3
        fmt.maximumFractionDigits = 6
        return fmt
    }()

    @State private var rawText: String = ""

    private var textBinding: Binding<String> {
        Binding(
            get: {
                if !rawText.isEmpty {
                    return rawText
                }
                if let freq = frequency, freq > 0 {
                    return Self.formatter.string(from: NSNumber(value: freq)) ?? ""
                }
                return ""
            },
            set: { value in
                rawText = value
                let cleaned = value.trimmingCharacters(in: .whitespaces)
                frequency = cleaned.isEmpty ? nil : Double(cleaned)
            }
        )
    }
}

// MARK: - ModeReadout

/// Mode picker. Mirrors the FrequencyReadout style — small-caps label, optional
/// "from radio" badge, monospaced display. The picker itself is a borderless
/// menu so it visually nests with the other inputs instead of looking like a
/// Settings sheet control.
struct ModeReadout: View {
    // MARK: Internal

    @Binding var mode: String

    let fromRadio: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("MODE")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                if fromRadio {
                    FromRadioBadge()
                }
            }
            Menu {
                ForEach(modes, id: \.self) { entry in
                    Button(entry) { mode = entry }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(mode.isEmpty ? "CW" : mode)
                        .font(.title3.monospaced().weight(.semibold))
                        .foregroundStyle(fromRadio ? Color.green : Color.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(width: 100, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    // MARK: Private

    private let modes = ["CW", "SSB", "USB", "LSB", "FT8", "FT4", "RTTY", "JTTY", "FM", "AM", "DIGI"]
}

// MARK: - PowerField

struct PowerField: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("POWER")
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                TextField("5", text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3.monospaced().weight(.semibold))
                    .frame(width: 60, alignment: .leading)
                Text("W")
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: 100, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

// MARK: - FromRadioBadge

/// Tiny "from radio" badge that appears next to FREQ/MODE labels when the
/// value was pulled from a connected RadioSession. Tactile signal that the
/// composer is in sync with the hardware.
struct FromRadioBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 8, weight: .semibold))
            Text("RADIO")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Color.green.opacity(0.12), in: Capsule())
    }
}

// MARK: - RadioStatusChip

/// Footer chip showing the connected radio. Green dot + monospaced name,
/// matching the LIVE chip in ContestPickerView so the visual language stays
/// consistent across the app.
struct RadioStatusChip: View {
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor), in: Capsule())
        .overlay(
            Capsule().stroke(Color.green.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - NoRadioChip

struct NoRadioChip: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 6, height: 6)
            Text("No radio connected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor), in: Capsule())
        .overlay(
            Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - RecentChipStrip

/// Horizontal scrollable chip list for recents (parks, contests, etc.).
/// Tapping a chip fires `onSelect`. Used by the composer to surface
/// last-used references without making the operator retype anything.
struct RecentChipStrip<Item: Identifiable>: View {
    let items: [Item]
    let label: (Item) -> String
    let onSelect: (Item) -> Void

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            Text(label(item))
                                .font(.caption.monospaced().weight(.medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor), in: Capsule())
                                .overlay(
                                    Capsule().stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
