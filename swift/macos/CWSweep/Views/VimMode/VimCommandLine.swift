import SwiftUI

struct VimCommandLine: View {
    // MARK: Internal

    var body: some View {
        HStack(spacing: 4) {
            Text(prefix)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            TextField("", text: textBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .focused($isFocused)
                .onSubmit {
                    vimEngine.handleLineReturn()
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .onAppear {
            isFocused = true
        }
        .onChange(of: vimEngine.mode) { _, newMode in
            if newMode == .command || newMode == .search {
                isFocused = true
            }
        }
    }

    // MARK: Private

    @Environment(VimEngine.self) private var vimEngine
    @FocusState private var isFocused: Bool

    private var prefix: String {
        vimEngine.mode == .command ? ":" : "/"
    }

    private var textBinding: Binding<String> {
        if vimEngine.mode == .command {
            Binding(
                get: { vimEngine.commandLineText },
                set: { vimEngine.commandLineText = $0 }
            )
        } else {
            Binding(
                get: { vimEngine.searchText },
                set: { vimEngine.searchText = $0 }
            )
        }
    }
}
