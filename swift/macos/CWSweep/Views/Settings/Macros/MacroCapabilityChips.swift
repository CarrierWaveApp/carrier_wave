import CarrierWaveData
import SwiftUI

// MARK: - MacroCapabilityChipsCompact

/// Tiny capability chip strip used in list rows. Only renders chips for
/// flags that are set, so safe (read-only) macros render no chips at all.
/// Reusable from both library + detail surfaces; the detail view uses
/// `MacroCapabilityChipsFull` for the wider presentation.
struct MacroCapabilityChipsCompact: View {
    // MARK: Internal

    let capabilities: RadioMacroCapabilities

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                ForEach(items, id: \.label) { item in
                    Text(item.label)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(item.color.opacity(0.18), in: Capsule())
                        .foregroundStyle(item.color)
                }
            }
        }
    }

    // MARK: Private

    private var items: [MacroCapabilityChipItem] {
        MacroCapabilityChipItem.items(for: capabilities)
    }
}

// MARK: - MacroCapabilityChipsFull

struct MacroCapabilityChipsFull: View {
    // MARK: Internal

    let capabilities: RadioMacroCapabilities

    var body: some View {
        if items.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(.green)
                Text("Read-only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            MacroCapabilityChipStrip(items: items)
        }
    }

    // MARK: Private

    private var items: [MacroCapabilityChipItem] {
        MacroCapabilityChipItem.items(for: capabilities)
    }
}

// MARK: - MacroCapabilityChipItem

struct MacroCapabilityChipItem {
    let label: String
    let color: Color

    static func items(for capabilities: RadioMacroCapabilities) -> [MacroCapabilityChipItem] {
        var items: [MacroCapabilityChipItem] = []
        if capabilities.transmits {
            items.append(MacroCapabilityChipItem(label: "TX", color: .red))
        }
        if capabilities.usesRawBytes {
            items.append(MacroCapabilityChipItem(label: "RAW", color: .orange))
        }
        if capabilities.changesFrequency {
            items.append(MacroCapabilityChipItem(label: "FREQ", color: .blue))
        }
        if capabilities.changesMode {
            items.append(MacroCapabilityChipItem(label: "MODE", color: .teal))
        }
        if capabilities.changesPower {
            items.append(MacroCapabilityChipItem(label: "PWR", color: .purple))
        }
        return items
    }
}

// MARK: - MacroCapabilityChipStrip

private struct MacroCapabilityChipStrip: View {
    let items: [MacroCapabilityChipItem]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.label) { item in
                Text(item.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(item.color.opacity(0.18), in: Capsule())
                    .foregroundStyle(item.color)
            }
        }
    }
}
