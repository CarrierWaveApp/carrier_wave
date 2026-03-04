import CarrierWaveData
import SwiftUI

// MARK: - SpotContactMismatchBanner

/// Banner showing potential callsign mismatches between session spots and logged QSOs.
/// Appears at the top of the session and can be permanently dismissed.
struct SpotContactMismatchBanner: View {
    // MARK: Internal

    let mismatches: [SpotContactMismatch]
    let onDismiss: () -> Void
    let onTapMismatch: (SpotContactMismatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.diamond.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.yellow)

                Text(headerText)
                    .font(.subheadline.weight(.medium))

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ForEach(mismatches.prefix(3)) { mismatch in
                Button {
                    onTapMismatch(mismatch)
                } label: {
                    mismatchRow(mismatch)
                }
                .buttonStyle(.plain)
            }

            if mismatches.count > 3 {
                Text("+\(mismatches.count - 3) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: Private

    private var headerText: String {
        if mismatches.count == 1 {
            return "Possible mislog from spot"
        }
        return "\(mismatches.count) possible mislogs from spots"
    }

    private func mismatchRow(_ mismatch: SpotContactMismatch) -> some View {
        HStack(spacing: 6) {
            Text("Logged")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(mismatch.qsoCallsign)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.orange)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Spotted")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(mismatch.spotCallsign)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.green)
            Spacer()
            Image(systemName: "pencil.circle")
                .font(.caption)
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - SpotContactMismatchBannerContainer

/// Container that conditionally shows the mismatch banner with animation.
struct SpotContactMismatchBannerContainer: View {
    let mismatches: [SpotContactMismatch]
    let onDismiss: () -> Void
    let onTapMismatch: (SpotContactMismatch) -> Void

    var body: some View {
        if !mismatches.isEmpty {
            SpotContactMismatchBanner(
                mismatches: mismatches,
                onDismiss: onDismiss,
                onTapMismatch: onTapMismatch
            )
            .padding(.horizontal)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
