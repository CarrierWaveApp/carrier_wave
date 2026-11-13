import SwiftUI

struct VimStatusBadge: View {
    // MARK: Internal

    let mode: VimMode
    let pendingKeys: String
    let lastEcho: String

    var body: some View {
        HStack(spacing: 6) {
            Text(mode.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(modeColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(modeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))

            if !pendingKeys.isEmpty {
                Text(pendingKeys + "_")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if !lastEcho.isEmpty {
                Text(lastEcho)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Private

    private var modeColor: Color {
        switch mode {
        case .normal: .green
        case .entry: .yellow
        case .command: .blue
        case .search: .purple
        }
    }
}
