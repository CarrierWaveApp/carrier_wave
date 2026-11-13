import SwiftUI

// MARK: - SatellitePassSidebarView

/// Upcoming-pass list (next 6 h above the elevation floor). In-progress
/// passes come first with a LOS countdown; the selected pass carries the
/// indigo selection. Also owns the loading / error / empty states.
struct SatellitePassSidebarView: View {
    // MARK: Internal

    let model: SatellitePassModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(SatelliteTheme.hairline)
                .frame(height: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SatelliteTheme.panel)
    }

    // MARK: Private

    private var minimumElevation: Binding<Double> {
        Binding(
            get: { model.minimumPeakElevationDeg },
            set: { model.minimumPeakElevationDeg = $0 }
        )
    }

    private var header: some View {
        HStack {
            Text("UPCOMING PASSES")
                .font(SatelliteTheme.label(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(SatelliteTheme.textTertiary)
            Spacer()
            if !model.upcoming.isEmpty {
                Text("\(model.upcoming.count)")
                    .font(SatelliteTheme.mono(10, weight: .semibold))
                    .foregroundStyle(SatelliteTheme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(SatelliteTheme.panelRaised))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle,
             .loading:
            placeholder {
                ProgressView()
                    .controlSize(.small)
                Text("Loading satellites…")
            }
        case let .failed(message):
            placeholder {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 20))
                    .foregroundStyle(SatelliteTheme.tx)
                Text(message)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await model.reload() }
                }
                .controlSize(.small)
            }
        case .loaded:
            if model.observerGrid == nil {
                placeholder {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 20))
                        .foregroundStyle(SatelliteTheme.textTertiary)
                    Text("Set your grid in Settings → General")
                        .multilineTextAlignment(.center)
                }
            } else if model.upcoming.isEmpty {
                noPasses
            } else {
                passList
            }
        }
    }

    private var noPasses: some View {
        placeholder {
            Image(systemName: "moon.stars")
                .font(.system(size: 20))
                .foregroundStyle(SatelliteTheme.textTertiary)
            Text("No passes above \(Int(model.minimumPeakElevationDeg))° in the next 6 h")
                .multilineTextAlignment(.center)
            Stepper(
                value: minimumElevation,
                in: 0 ... 45,
                step: 5
            ) {
                Text("Min. elevation \(Int(model.minimumPeakElevationDeg))°")
                    .font(SatelliteTheme.mono(11))
            }
            .controlSize(.small)
        }
    }

    private var passList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 4) {
                ForEach(model.upcoming) { pass in
                    SatellitePassRow(
                        pass: pass,
                        now: model.frame.now,
                        isSelected: model.selectedPass?.id == pass.id
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { model.select(pass) }
                }
            }
            .padding(8)
        }
        .scrollIndicators(.automatic)
    }

    private func placeholder(@ViewBuilder _ body: () -> some View) -> some View {
        VStack(spacing: 10) {
            body()
        }
        .font(SatelliteTheme.label(12, weight: .regular))
        .foregroundStyle(SatelliteTheme.textSecondary)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SatellitePassRow

struct SatellitePassRow: View {
    // MARK: Internal

    let pass: SweepPass
    let now: Date
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(pass.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SatelliteTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(SatellitePassFormat.degrees(pass.peakElevationDeg, decimals: 0))
                    .font(SatelliteTheme.mono(13, weight: .semibold))
                    .foregroundStyle(elevationColor)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(SatellitePassFormat.utcHHmm(pass.aos)) UTC · \(SatellitePassFormat.duration(pass.duration))")
                    .font(SatelliteTheme.mono(11))
                    .foregroundStyle(SatelliteTheme.textSecondary)
                Spacer(minLength: 6)
                if let countdown = SatellitePassFormat.sidebarCountdown(for: pass, at: now) {
                    Text(countdown)
                        .font(SatelliteTheme.mono(11, weight: .medium))
                        .foregroundStyle(isActive ? SatelliteTheme.satellite : SatelliteTheme.accent)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? SatelliteTheme.accent : .clear, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(SatelliteTheme.satellite)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: Private

    private var isActive: Bool {
        pass.isActive(at: now)
    }

    private var backgroundFill: Color {
        if isSelected {
            return SatelliteTheme.accent.opacity(0.22)
        }
        if isActive {
            return SatelliteTheme.accent.opacity(0.12)
        }
        return SatelliteTheme.panelRaised.opacity(0.6)
    }

    private var elevationColor: Color {
        if pass.peakElevationDeg >= 45 {
            return SatelliteTheme.rx
        }
        if pass.peakElevationDeg >= 20 {
            return SatelliteTheme.textPrimary
        }
        return SatelliteTheme.textSecondary
    }
}
