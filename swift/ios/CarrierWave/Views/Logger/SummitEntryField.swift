// Summit Entry Field
//
// Thin wrapper around SingleReferenceEntryField configured for
// SOTA summit references. Preserves the existing call-site API.

import CarrierWaveData
import SwiftUI

// MARK: - SummitEntryField

/// Summit entry field with chip display, live name lookup, and search picker
struct SummitEntryField: View {
    // MARK: Internal

    @Binding var sotaReference: String

    /// User's grid square for nearby summits fallback
    var userGrid: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SingleReferenceEntryField(
                reference: $sotaReference,
                config: Self.summitConfig,
                userGrid: userGrid
            ) { onSelect, onDismiss in
                SummitPickerSheet(
                    userGrid: userGrid,
                    onSelect: { summit in
                        onSelect(summit.code, summit.name)
                    },
                    onDismiss: onDismiss
                )
            }

            NearbySummitSuggestions(
                userGrid: userGrid,
                currentReference: sotaReference,
                onSelect: { summit in
                    sotaReference = summit.code
                }
            )
            .loadOnAppear()
            .padding(.top, 6)
        }
    }

    // MARK: Private

    private static let summitConfig = ReferenceEntryConfig(
        label: "Summit",
        placeholder: "W4C/CM-001",
        accentColor: .green,
        searchLabel: "Search summits",
        lookupReference: { code in
            guard let summit = SOTASummitsCache.shared.lookupSummit(code) else {
                return nil
            }
            return (code: summit.code, name: summit.name)
        },
        nameSync: { SOTASummitsCache.shared.nameSync(for: $0) }
    )
}

// MARK: - Preview

#Preview("Empty") {
    VStack {
        SummitEntryField(
            sotaReference: .constant(""),
            userGrid: "FN31"
        )
    }
    .padding()
}

#Preview("With Reference") {
    VStack {
        SummitEntryField(
            sotaReference: .constant("W4C/CM-001"),
            userGrid: "FN31"
        )
    }
    .padding()
}
