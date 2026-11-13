// WWFF Reference Entry Field
//
// Thin wrapper around SingleReferenceEntryField configured for
// WWFF references. Preserves the existing call-site API.

import CarrierWaveData
import SwiftUI

// MARK: - WWFFReferenceEntryField

/// WWFF reference entry field with chip display, live name lookup, and search picker
struct WWFFReferenceEntryField: View {
    // MARK: Internal

    @Binding var wwffReference: String

    /// User's grid square for nearby references fallback
    var userGrid: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SingleReferenceEntryField(
                reference: $wwffReference,
                config: Self.wwffConfig,
                userGrid: userGrid
            ) { onSelect, onDismiss in
                WWFFReferencePickerSheet(
                    userGrid: userGrid,
                    onSelect: { ref in
                        onSelect(ref.reference, ref.name)
                    },
                    onDismiss: onDismiss
                )
            }

            NearbyWWFFSuggestions(
                userGrid: userGrid,
                currentReference: wwffReference,
                onSelect: { ref in
                    wwffReference = ref.reference
                }
            )
            .loadOnAppear()
            .padding(.top, 6)
        }
    }

    // MARK: Private

    private static let wwffConfig = ReferenceEntryConfig(
        label: "WWFF Reference",
        placeholder: "KFF-1234",
        accentColor: .mint,
        searchLabel: "Search WWFF references",
        lookupReference: { code in
            guard let ref = WWFFReferencesCache.shared.lookupReference(code) else {
                return nil
            }
            return (code: ref.reference, name: ref.name)
        },
        nameSync: { WWFFReferencesCache.shared.nameSync(for: $0) }
    )
}

// MARK: - Preview

#Preview("Empty") {
    VStack {
        WWFFReferenceEntryField(
            wwffReference: .constant(""),
            userGrid: "FN31"
        )
    }
    .padding()
}

#Preview("With Reference") {
    VStack {
        WWFFReferenceEntryField(
            wwffReference: .constant("KFF-1234"),
            userGrid: "FN31"
        )
    }
    .padding()
}
