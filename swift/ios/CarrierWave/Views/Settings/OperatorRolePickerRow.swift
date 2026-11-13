import CarrierWaveData
import SwiftUI

// MARK: - OperatorRolePickerRow

/// Inline picker for the operator's self-declared operating style.
/// Mirrors the onboarding role step so the choice is never locked in.
/// Role-aware defaults (Hunter Log landing, On Air card sections) react
/// immediately via their own `@AppStorage` readers on the shared key.
struct OperatorRolePickerRow: View {
    // MARK: Internal

    var body: some View {
        Picker("Operating Style", selection: $operatorRoleRaw) {
            Text("Not Set").tag("")
            ForEach(OperatorRole.allCases) { role in
                Text(role.displayName).tag(role.rawValue)
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: Private

    @AppStorage(OperatorRole.storageKey) private var operatorRoleRaw = ""
}
