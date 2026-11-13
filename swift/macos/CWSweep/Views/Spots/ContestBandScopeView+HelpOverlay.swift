import SwiftUI

// MARK: - Help Overlay

extension ContestBandScopeView {
    func bandScopeHelpOverlay(dismiss: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            helpPanel
        }
    }

    private var helpPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Spacer()
                Button {
                    showHelp = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            Divider()

            HStack(alignment: .top, spacing: 24) {
                helpColumn(title: "Navigation", rows: [
                    ("j", "Next spot"),
                    ("k", "Previous spot"),
                    ("J", "Next mult"),
                    ("K", "Previous mult"),
                    ("⏎", "Tune to selected"),
                ])
                helpColumn(title: "Zoom & Pan", rows: [
                    ("+", "Zoom in"),
                    ("−", "Zoom out"),
                    ("0", "Fit to spots"),
                    ("h", "Pan up"),
                    ("l", "Pan down"),
                ])
                helpColumn(title: "Actions", rows: [
                    ("esc", "Close overlay"),
                    ("?", "Toggle help"),
                ])
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
        .frame(maxWidth: 520)
        .padding(40)
    }

    private func helpColumn(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(rows, id: \.0) { key, label in
                helpRow(key: key, label: label)
            }
        }
    }

    private func helpRow(key: String, label: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 18, alignment: .center)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                )
            Text(label)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}
