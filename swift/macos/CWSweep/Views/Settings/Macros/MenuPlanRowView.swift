import CarrierWaveData
import SwiftUI

// MARK: - MenuPlanRowView

/// Render a `MenuPlanRow` in the same Terraform-style as `MacroPlanRow`:
/// gray for converged, green for delta with the prior value struck through,
/// orange when the current value couldn't be read (timeout → blind-apply
/// visual). Menu items live in their own section since they're sourced
/// from a different read path (one-shot via `MenuReader`).
struct MenuPlanRowView: View {
    // MARK: Internal

    let row: MenuPlanRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
                .font(.caption.weight(.semibold))
                .frame(width: 14)
            Text("\(row.label) (menu \(row.item))")
                .font(.callout.monospaced())
                .foregroundStyle(.primary)
                .frame(minWidth: 160, alignment: .leading)
            if let current = row.current {
                if current == row.desired {
                    Text(String(current))
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("no change")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(String(current))
                        .font(.callout.monospaced())
                        .foregroundStyle(.red)
                        .strikethrough()
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(row.desired))
                        .font(.callout.monospaced())
                        .foregroundStyle(.green)
                    Spacer()
                }
            } else {
                Text("→ \(row.desired)")
                    .font(.callout.monospaced())
                    .foregroundStyle(.orange)
                Spacer()
                Text("read failed")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Private

    private var iconName: String {
        if let current = row.current {
            current == row.desired ? "equal" : "arrow.triangle.2.circlepath"
        } else {
            "arrow.right.circle"
        }
    }

    private var tint: Color {
        if let current = row.current {
            current == row.desired ? .secondary : .green
        } else {
            .orange
        }
    }
}
