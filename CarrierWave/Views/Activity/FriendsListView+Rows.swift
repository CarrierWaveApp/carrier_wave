import SwiftUI
import UIKit

// MARK: - IncomingRequestRow

struct IncomingRequestRow: View {
    let friendship: Friendship
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack {
            Text(friendship.friendCallsign)
                .font(.headline)

            Spacer()

            Button("Accept") { onAccept() }
                .buttonStyle(.borderedProminent)

            Button("Decline") { onDecline() }
                .buttonStyle(.bordered)
                .tint(.red)
        }
    }
}

// MARK: - OutgoingRequestRow

struct OutgoingRequestRow: View {
    let friendship: Friendship

    var body: some View {
        HStack {
            Text(friendship.friendCallsign)
                .font(.headline)

            Spacer()

            Text("Pending...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - FriendRow

struct FriendRow: View {
    let friendship: Friendship

    var body: some View {
        HStack {
            Text(friendship.friendCallsign)
                .font(.headline)

            Spacer()

            if let acceptedAt = friendship.acceptedAt {
                Text(acceptedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - InviteLinkSheet

struct InviteLinkSheet: View {
    // MARK: Internal

    let inviteLink: InviteLinkDTO?
    let isGenerating: Bool
    let errorMessage: String?
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if isGenerating {
                    ProgressView("Generating invite link...")
                        .frame(maxHeight: .infinity)
                } else if let invite = inviteLink {
                    inviteContent(invite)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Unable to Generate Link",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    ContentUnavailableView(
                        "Unable to Generate Link",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Please try again later.")
                    )
                }
            }
            .padding()
            .navigationTitle("Invite Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Private

    private func inviteContent(_ invite: InviteLinkDTO) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            Text("Share this link with a friend")
                .font(.headline)

            Text(
                "When they tap the link, they'll be able to send you "
                    + "a friend request in Carrier Wave."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Text(invite.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if invite.expiresAt > Date() {
                Text("Expires \(invite.expiresAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            ShareLink(item: URL(string: invite.url)!) {
                Label("Share Link", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                UIPasteboard.general.string = invite.url
            } label: {
                Label("Copy to Clipboard", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}
