import SwiftUI

// MARK: - FriendInviteConfirmSheet

struct FriendInviteConfirmSheet: View {
    let token: String
    @Binding var isProcessing: Bool

    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "person.badge.plus")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)

                Text("Friend Invite")
                    .font(.title)
                    .fontWeight(.bold)

                Text(
                    "Someone has invited you to connect on Carrier Wave. Accept to send them a friend request."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        onAccept()
                    } label: {
                        if isProcessing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Accept Invite")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isProcessing)

                    Button("Cancel", role: .cancel) {
                        onDismiss()
                    }
                    .disabled(isProcessing)
                }
                .padding()
            }
            .navigationTitle("Friend Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                        .disabled(isProcessing)
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium])
    }
}

#Preview {
    FriendInviteConfirmSheet(
        token: "test-token",
        isProcessing: .constant(false),
        onAccept: {},
        onDismiss: {}
    )
}
