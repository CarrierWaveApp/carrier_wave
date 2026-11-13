import SwiftUI

// MARK: - SessionHistoryPopover

/// Popover wrapping PastActivationsListView with a header.
/// Triggered by a toolbar icon in ActivationHeader.
struct SessionHistoryPopover: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Past Activations")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            PastActivationsListView(onParkSelected: nil)
        }
        .frame(width: 340, height: 400)
    }
}
