import SwiftUI

// MARK: - VimHelpOverlay

struct VimHelpOverlay: View {
    // MARK: Internal

    let mode: VimMode

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Vim Mode Help — \(mode.rawValue)")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                helpContent
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                Text("Press any key to dismiss")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(40)
        }
    }

    // MARK: Private

    @ViewBuilder
    private var helpContent: some View {
        switch mode {
        case .normal:
            normalModeHelp
        case .entry:
            entryModeHelp
        case .command:
            commandModeHelp
        case .search:
            searchModeHelp
        }
    }

    private var normalModeHelp: some View {
        HStack(alignment: .top, spacing: 32) {
            helpColumn("Navigation", items: [
                ("j / k", "Move down / up"),
                ("J / K", "Band down / up"),
                ("gg / G", "Top / bottom"),
                ("Tab", "Cycle pane focus"),
                ("g1-g4", "Focus pane"),
                ("n / N", "Next / prev result"),
            ])

            helpColumn("Operators", items: [
                ("t", "Tune to selection"),
                ("i", "Enter Entry mode"),
                ("?", "Lookup callsign"),
                ("x", "Dismiss spot"),
                ("s", "Spot station"),
                ("u", "Undo"),
                (".", "Repeat last action"),
            ])

            helpColumn("Marks & Speed", items: [
                ("ma-mz", "Set frequency mark"),
                ("'a-'z", "Jump to mark"),
                ("''", "Jump to previous freq"),
                ("+ / -", "WPM speed up / down"),
                ("F1-F6", "Send CW memory"),
                ("Ctrl+C", "Abort CW"),
            ])

            helpColumn("Modes", items: [
                (":", "Command mode"),
                ("/", "Search mode"),
                ("Esc", "Return to Normal"),
            ])
        }
    }

    private var entryModeHelp: some View {
        helpColumn("Entry Mode", items: [
            ("Return", "Log QSO"),
            ("Escape", "Cancel and return"),
            ("Up / Down", "Entry history"),
            ("F1-F6", "Send CW memory"),
        ])
    }

    private var commandModeHelp: some View {
        HStack(alignment: .top, spacing: 32) {
            helpColumn("Radio", items: [
                ("freq <MHz|kHz>", "Tune (14.074 or 14074)"),
                ("mode <CW|SSB|…>", "Set operating mode"),
                ("connect <node>", "Connect cluster"),
                ("set wpm <n>", "Set CW speed"),
                ("split up/dn/off <n>", "Split control"),
            ])
            helpColumn("CW & Activation", items: [
                ("cq", "Send CQ"),
                ("send <n>", "Send memory 1-6"),
                ("park/summit <ref>", "Set reference"),
                ("spot [comment]", "Self-spot"),
                ("role <name>", "Switch role/layout"),
            ])
            helpColumn("Navigate", items: [
                ("logger / spots", "Show pane"),
                ("cluster / dashboard", "Show pane"),
                ("log / radio", "Show pane"),
                ("sync [now]", "Sync pane / sync now"),
                ("inspector", "Toggle inspector"),
            ])
            helpColumn("Info & Other", items: [
                ("find <call>", "QSOs with callsign"),
                ("last [n]", "Recent QSOs (5)"),
                ("count", "Session QSO count"),
                ("alert add <prefix>", "Add alert"),
                ("export/import", "ADIF I/O"),
                ("help", "Show this overlay"),
                ("Tab", "Auto-complete"),
            ])
        }
    }

    private var searchModeHelp: some View {
        helpColumn("Search Filters", items: [
            ("cw / ssb / ft8", "Filter by mode"),
            ("20m / 40m", "Filter by band"),
            ("pota / sota / rbn", "Filter by source"),
            ("new", "Needed entities only"),
            ("dupe", "Dupes only"),
            ("need:40m", "Needed on band"),
            ("call:cw", "Callsign prefix"),
            ("Return", "Lock filter"),
            ("Escape", "Clear filter"),
        ])
    }

    private func helpColumn(_ title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            ForEach(items, id: \.0) { key, desc in
                HStack(spacing: 8) {
                    Text(key)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.blue)
                        .frame(minWidth: 80, alignment: .trailing)
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
