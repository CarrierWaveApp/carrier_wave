// Additional TOTA scoring inputs surfaced in the start sheet:
// category (Standard/Mobile), winter override, and Personal Effort Factor.
// Lifted into their own extension so TOTAActivationFields stays under
// SwiftLint's 500-line cap.

import CarrierWaveData
import SwiftUI

extension TOTAActivationFields {
    var categoryRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Category")
                .font(.subheadline.weight(.medium))
            Picker("Category", selection: $category) {
                ForEach(TOTACategory.allCases, id: \.self) { value in
                    Label(value.displayName, systemImage: value.icon)
                        .tag(value)
                }
            }
            .pickerStyle(.segmented)
            Text(categoryHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Winter is auto-detected from coords + date. The toggle starts pre-set
    /// to the auto value; flipping it explicitly opts out / opts in.
    var winterRow: some View {
        Toggle(
            isOn: Binding(
                get: { winterOverride ?? autoDetectedWinter },
                set: { newValue in winterOverride = newValue }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Winter activation (+20 %)")
                    .font(.subheadline.weight(.medium))
                Text(winterHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var personalEffortRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(
                isOn: Binding(
                    get: { personalEffortFactor > 0 },
                    set: { isOn in
                        personalEffortFactor = isOn ? max(personalEffortFactor, 1) : 0
                    }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Personal Effort Factor")
                        .font(.subheadline.weight(.medium))
                    Text(
                        "Frozen onto this session. Affects only the Personal Effort "
                            + "leaderboard; Standard ranking is unchanged."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            if personalEffortFactor > 0 {
                Stepper(
                    "PEF: \(personalEffortFactor)",
                    value: $personalEffortFactor,
                    in: 1 ... 10
                )
                .font(.caption)
            }
        }
    }

    private var categoryHelpText: String {
        switch category {
        case .standard:
            "Standard: full formula (distance × QSOs + winter/ruck/elev/pets/kids)."
        case .mobile:
            "Mobile: separate leaderboard. QSOs × QRP + flat bonuses only — no "
                + "distance multiplier or percentage bonuses."
        }
    }

    private var winterHelpText: String {
        if winterOverride == nil {
            return "Auto-detected from your activation coordinate and the date."
        }
        return "Overridden — using your explicit choice."
    }
}
