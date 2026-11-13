import SwiftUI

/// Inline editor for serial port nicknames. Shows the display name with a pencil button;
/// tapping reveals a TextField for renaming.
struct PortNicknameEditor: View {
    // MARK: Internal

    let port: SerialPortMonitor.SerialPortInfo

    var body: some View {
        if isEditing {
            HStack(spacing: 4) {
                TextField("Nickname", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(maxWidth: 140)
                    .onSubmit { save() }
                    .onExitCommand { cancel() }

                Button {
                    save()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)

                Button {
                    cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: 4) {
                Text(portMonitor.displayName(for: port))
                    .fontWeight(.medium)

                Button {
                    draft = portMonitor.nickname(for: port) ?? ""
                    isEditing = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Rename this port")
            }
        }
    }

    // MARK: Private

    @Environment(SerialPortMonitor.self) private var portMonitor
    @State private var isEditing = false
    @State private var draft = ""

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        portMonitor.setNickname(trimmed.isEmpty ? nil : trimmed, for: port)
        isEditing = false
    }

    private func cancel() {
        isEditing = false
    }
}
