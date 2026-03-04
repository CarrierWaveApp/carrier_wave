// Frequency Warning Banner
//
// Unified warning display for frequency/mode issues including license violations
// and activity warnings (QRP, SSTV, CWT, etc.)

import CarrierWaveData
import SwiftUI

// MARK: - FrequencyWarningBanner

struct FrequencyWarningBanner: View {
    // MARK: Lifecycle

    init(warning: FrequencyWarning, onDismiss: (() -> Void)? = nil) {
        self.warning = warning
        self.onDismiss = onDismiss
    }

    // MARK: Internal

    let warning: FrequencyWarning
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(warning.message)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let suggestion = warning.suggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    // MARK: Private

    // MARK: - Styling

    private var icon: String {
        switch warning.type {
        case .noPrivileges: "exclamationmark.triangle.fill"
        case .wrongMode: "xmark.circle.fill"
        case .outOfBand: "antenna.radiowaves.left.and.right.slash"
        case .activityConflict: "waveform.badge.exclamationmark"
        case .activityCrowded: "clock.badge.exclamationmark"
        case .spotNearby: "person.wave.2.fill"
        case .unusualFrequency: "info.circle.fill"
        case .activityInfo: "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch warning.type {
        case .noPrivileges: .orange
        case .wrongMode,
             .outOfBand:
            .red
        case .activityConflict,
             .activityCrowded,
             .spotNearby:
            .yellow
        case .unusualFrequency,
             .activityInfo:
            .blue
        }
    }

    private var backgroundColor: Color {
        switch warning.type {
        case .noPrivileges: Color.orange.opacity(0.1)
        case .wrongMode,
             .outOfBand:
            Color.red.opacity(0.1)
        case .activityConflict,
             .activityCrowded,
             .spotNearby:
            Color.yellow.opacity(0.1)
        case .unusualFrequency,
             .activityInfo:
            Color.blue.opacity(0.1)
        }
    }

    private var borderColor: Color {
        switch warning.type {
        case .noPrivileges: Color.orange.opacity(0.3)
        case .wrongMode,
             .outOfBand:
            Color.red.opacity(0.3)
        case .activityConflict,
             .activityCrowded,
             .spotNearby:
            Color.yellow.opacity(0.3)
        case .unusualFrequency,
             .activityInfo:
            Color.blue.opacity(0.3)
        }
    }
}

// MARK: - FrequencyWarningBannerContainer

/// Container that conditionally shows a FrequencyWarningBanner
/// Used to properly handle optional warnings with animations
struct FrequencyWarningBannerContainer: View {
    let warning: FrequencyWarning?
    let onDismiss: (String) -> Void

    var body: some View {
        if let warning {
            FrequencyWarningBanner(warning: warning) {
                onDismiss(warning.message)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - LicenseWarningBanner

/// Displays a warning when the user is operating outside their license privileges.
/// - Note: Deprecated. Use `FrequencyWarningBanner` with `FrequencyWarning` instead.
struct LicenseWarningBanner: View {
    // MARK: Lifecycle

    init(violation: BandPlanViolation, onDismiss: (() -> Void)? = nil) {
        self.violation = violation
        self.onDismiss = onDismiss
    }

    // MARK: Internal

    let violation: BandPlanViolation
    let onDismiss: (() -> Void)?

    var body: some View {
        FrequencyWarningBanner(
            warning: violation.asFrequencyWarning,
            onDismiss: onDismiss
        )
    }
}

// MARK: - FrequencyWarningModifier

/// View modifier to add frequency warning banner when needed
struct FrequencyWarningModifier: ViewModifier {
    // MARK: Internal

    let frequencyMHz: Double?
    let mode: String?
    let license: LicenseClass

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if let warning, !isDismissed {
                FrequencyWarningBanner(warning: warning) {
                    withAnimation {
                        isDismissed = true
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            content
        }
        .onChange(of: frequencyMHz) { _, _ in
            checkWarnings()
        }
        .onChange(of: mode) { _, _ in
            checkWarnings()
        }
        .onAppear {
            checkWarnings()
        }
    }

    // MARK: Private

    @State private var warning: FrequencyWarning?
    @State private var isDismissed = false

    private func checkWarnings() {
        guard let freq = frequencyMHz, let mode, !mode.isEmpty else {
            warning = nil
            return
        }

        let warnings = BandPlanService.validateFrequency(
            frequencyMHz: freq,
            mode: mode,
            license: license
        )

        // Get the highest priority warning
        let newWarning = warnings.first

        if newWarning?.message != warning?.message {
            withAnimation {
                warning = newWarning
                isDismissed = false
            }
        }
    }
}

// MARK: - LicenseWarningModifier

/// View modifier to add license warning banner when needed
/// - Note: Deprecated. Use `FrequencyWarningModifier` instead.
struct LicenseWarningModifier: ViewModifier {
    let frequencyMHz: Double?
    let mode: String?
    let license: LicenseClass

    func body(content: Content) -> some View {
        content.modifier(
            FrequencyWarningModifier(
                frequencyMHz: frequencyMHz,
                mode: mode,
                license: license
            )
        )
    }
}

extension View {
    /// Add frequency warning banner when operating on special frequencies or outside privileges
    func frequencyWarning(
        frequencyMHz: Double?,
        mode: String?,
        license: LicenseClass
    ) -> some View {
        modifier(
            FrequencyWarningModifier(
                frequencyMHz: frequencyMHz,
                mode: mode,
                license: license
            )
        )
    }

    /// Add license warning banner when operating outside privileges
    /// - Note: Deprecated. Use `frequencyWarning` instead.
    func licenseWarning(
        frequencyMHz: Double?,
        mode: String?,
        license: LicenseClass
    ) -> some View {
        modifier(
            LicenseWarningModifier(
                frequencyMHz: frequencyMHz,
                mode: mode,
                license: license
            )
        )
    }
}

// MARK: - Previews

#Preview("No Privileges") {
    FrequencyWarningBanner(
        warning: FrequencyWarning(
            type: .noPrivileges,
            message: "Technician license cannot operate CW at 7.025 MHz",
            suggestion: "Requires General or higher"
        )
    )
    .padding()
}

#Preview("Wrong Mode") {
    FrequencyWarningBanner(
        warning: FrequencyWarning(
            type: .wrongMode,
            message: "SSB is not allowed at 7.030 MHz",
            suggestion: "Try: CW, DATA"
        )
    )
    .padding()
}

#Preview("Out of Band") {
    FrequencyWarningBanner(
        warning: FrequencyWarning(
            type: .outOfBand,
            message: "Frequency 14.400 MHz is outside amateur bands",
            suggestion: "Nearest band: 20m"
        )
    )
    .padding()
}

#Preview("Activity Conflict") {
    FrequencyWarningBanner(
        warning: FrequencyWarning(
            type: .activityConflict,
            message: "14.230 MHz is the SSTV calling frequency",
            suggestion: "Expected mode: USB, you're in CW",
            activity: .sstv
        )
    )
    .padding()
}

#Preview("Activity Crowded (CWT)") {
    FrequencyWarningBanner(
        warning: FrequencyWarning(
            type: .activityCrowded,
            message: "CWOps CWT is active",
            suggestion: "Expect heavy CW traffic 7.028-7.045 MHz",
            activity: .cwtContest
        )
    )
    .padding()
}

#Preview("Activity Info (QRP)") {
    FrequencyWarningBanner(
        warning: FrequencyWarning(
            type: .activityInfo,
            message: "14.060 MHz is the QRP CW calling frequency",
            suggestion: nil,
            activity: .qrpCW
        )
    )
    .padding()
}
