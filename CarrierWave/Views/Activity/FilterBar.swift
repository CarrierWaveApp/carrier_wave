import SwiftUI

// MARK: - FeedFilter

enum FeedFilter: Hashable {
    case all
    case friends
    case club(UUID)

    // MARK: Internal

    var displayName: String {
        switch self {
        case .all:
            "All"
        case .friends:
            "Friends"
        case .club:
            "" // Set externally based on club name
        }
    }
}

// MARK: - FilterBar

struct FilterBar: View {
    // MARK: Internal

    @Binding var selectedFilter: FeedFilter

    let clubs: [Club]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FeedFilterChip(
                    title: "All",
                    isSelected: selectedFilter == .all
                ) {
                    selectedFilter = .all
                }

                FeedFilterChip(
                    title: "Friends",
                    isSelected: selectedFilter == .friends
                ) {
                    selectedFilter = .friends
                }

                ForEach(clubs) { club in
                    FeedFilterChip(
                        title: club.name,
                        isSelected: isClubSelected(club)
                    ) {
                        selectedFilter = .club(club.serverId)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: Private

    private func isClubSelected(_ club: Club) -> Bool {
        if case let .club(id) = selectedFilter {
            return id == club.serverId
        }
        return false
    }
}

// MARK: - FeedFilterChip

struct FeedFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var filter: FeedFilter = .all

        var body: some View {
            VStack(spacing: 20) {
                FilterBar(selectedFilter: $filter, clubs: [])

                Text("Selected: \(String(describing: filter))")
                    .font(.caption)
            }
        }
    }

    return PreviewWrapper()
}
