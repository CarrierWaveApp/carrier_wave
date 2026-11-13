import SwiftUI

// MARK: - IntentGrid

/// 2×2 grid of intent cards. All cards route into existing sheets; the grid
/// itself owns no state beyond the closures passed in.
///
/// Lives in its own file so `SessionsIntentView.swift` stays under SwiftLint's
/// 500-line cap as more header sections (role prompt, quick-start card) land
/// above the grid.
struct IntentGrid: View {
    let onActivate: () -> Void
    let onHunt: () -> Void
    let onCasual: () -> Void
    let onContest: () -> Void
    let activateSubtitle: String

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                IntentCard(
                    title: "Activate",
                    subtitle: activateSubtitle,
                    systemImage: "antenna.radiowaves.left.and.right",
                    tint: .blue,
                    action: onActivate
                )
                IntentCard(
                    title: "Hunt",
                    subtitle: "Chase parks, summits, DX",
                    systemImage: "binoculars",
                    tint: .orange,
                    action: onHunt
                )
            }
            HStack(spacing: 12) {
                IntentCard(
                    title: "Casual",
                    subtitle: "Ragchew & random QSOs",
                    systemImage: "dot.radiowaves.left.and.right",
                    tint: .green,
                    action: onCasual
                )
                IntentCard(
                    title: "Contest",
                    subtitle: "Score & exchange",
                    systemImage: "trophy",
                    tint: .purple,
                    action: onContest
                )
            }
        }
    }
}

// MARK: - IntentCard

/// A single large, tappable intent tile. Designed for the 2×2 grid —
/// prominent SF Symbol, verb title, short subtitle. Matches Apple HIG
/// guidance for a clearly primary action: big target, icon + verb, soft
/// material background tinted by role.
struct IntentCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
            // Constrain the tap region to the visible card so taps on
            // adjacent List rows (e.g. the `NavigationLink` session rows
            // below) don't bleed into this button.
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        // `.borderless` (not `.plain`) gives each card an independent hit
        // target. With `.plain`, the four cards share one row inside the
        // same `List` as the session `NavigationLink`s, and SwiftUI routes
        // stray taps to a grid button — surfacing the New Session wizard
        // when the user meant to open a session's detail (CAR-276 PR2
        // regression).
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}
