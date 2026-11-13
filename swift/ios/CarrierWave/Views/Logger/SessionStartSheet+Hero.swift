import SwiftUI

// MARK: - SessionStartSheet Callsign Hero

extension SessionStartSheet {
    /// The identity block — first thing the user sees: a standard form section
    /// (header icon + "Operator" title, matching Programs / Radio / Gear)
    /// showing the callsign and grid at full size. No bespoke compact bar.
    var identitySection: some View {
        Section {
            callsignHeroCard
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.purple)
                    .accessibilityHidden(true)
                Text("Operator")
            }
        }
        .headerProminence(.increased)
    }

    @ViewBuilder
    private var callsignHeroCard: some View {
        if defaultCallsign.isEmpty {
            emptyCallsignHero
        } else {
            HStack(alignment: .center, spacing: 12) {
                callsignHeroDisplay
                Spacer(minLength: 8)
                gridHeroPanel
            }
        }
    }

    private var emptyCallsignHero: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Set your callsign")
                    .font(.subheadline.weight(.semibold))
                Text("Settings → About Me")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var callsignHeroDisplay: some View {
        if isClubStation {
            VStack(alignment: .leading, spacing: 2) {
                Text(clubStationCallsign ?? "—")
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("op  \(defaultCallsign.uppercased())")
                    .font(.caption.monospaced().weight(.medium))
                    .foregroundStyle(Color.purple)
                    .tracking(0.5)
            }
        } else {
            Text(fullCallsign)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
    }

    private var gridHeroPanel: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("GRID")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.purple)
            if myGrid.isEmpty,
               sessionManager?.locationService.isMonitoring == true,
               sessionManager?.locationService.locationError == nil
            {
                ProgressView()
                    .controlSize(.mini)
            } else {
                TextField("—", text: Binding(
                    get: { myGrid },
                    set: { newValue in
                        myGrid = newValue
                        gridManuallyEdited = true
                    }
                ))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { dismissKeyboard() }
                .font(.subheadline.monospaced().weight(.semibold))
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
                .foregroundStyle(
                    myGrid.isEmpty && sessionManager?.locationService.locationError != nil
                        ? Color.orange
                        : Color.primary
                )
            }
        }
    }
}
