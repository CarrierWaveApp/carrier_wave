// Spot Comments Sheet
//
// Displays POTA spot comments received during an activation,
// allowing activators to see hunter feedback. Consecutive RBN
// (automated) spots are collapsed into expandable summary rows
// to keep human comments visible.

import CarrierWaveData
import SwiftUI

// MARK: - CommentGroup

/// A group of comments — either a single human comment or a batch of consecutive RBN spots
enum CommentGroup: Identifiable {
    case human(POTASpotComment)
    case rbnGroup(index: Int, comments: [POTASpotComment])

    // MARK: Internal

    var id: String {
        switch self {
        case let .human(comment):
            "human-\(comment.spotId)"
        case let .rbnGroup(index, _):
            "rbn-group-\(index)"
        }
    }

    /// Average WPM across RBN spots in this group (nil if no WPM data)
    var averageWPM: Int? {
        guard case let .rbnGroup(_, comments) = self else {
            return nil
        }
        let wpms = comments.compactMap(\.wpm)
        guard !wpms.isEmpty else {
            return nil
        }
        return wpms.reduce(0, +) / wpms.count
    }
}

// MARK: - SpotCommentsSheet

struct SpotCommentsSheet: View {
    // MARK: Internal

    let comments: [POTASpotComment]
    let parkRef: String
    let onDismiss: () -> Void
    let onMarkRead: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if comments.isEmpty {
                    emptyView
                } else {
                    commentsList
                }
            }
            .navigationTitle("Spot Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onMarkRead()
                        onDismiss()
                    }
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    @State private var expandedGroups: Set<String> = []

    /// All RBN comments across the entire list
    private var allRBNComments: [POTASpotComment] {
        comments.filter(\.isAutomatedSpot)
    }

    /// Overall average CW speed from all RBN spots
    private var overallAverageWPM: Int? {
        let wpms = allRBNComments.compactMap(\.wpm)
        guard !wpms.isEmpty else {
            return nil
        }
        return wpms.reduce(0, +) / wpms.count
    }

    /// Group consecutive RBN spots together, keeping human comments individual
    private var groupedComments: [CommentGroup] {
        groupComments(comments)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Comments Yet", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Hunters can leave comments when they spot you on POTA.")
        }
    }

    private var commentsList: some View {
        List {
            // Average CW speed header (if RBN spots with WPM exist)
            if let avgWPM = overallAverageWPM {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "metronome")
                            .foregroundStyle(.blue)
                        Text("Avg CW Speed: \(avgWPM) WPM")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("from \(allRBNComments.count) RBN spots")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ForEach(groupedComments) { group in
                    switch group {
                    case let .human(comment):
                        commentRow(comment)
                    case let .rbnGroup(_, comments):
                        rbnGroupView(group: group, comments: comments)
                    }
                }
            } header: {
                Text(parkRef)
            } footer: {
                Text("Comments from hunters spotting your activation on pota.app")
            }
        }
    }

    private func rbnGroupView(
        group: CommentGroup,
        comments: [POTASpotComment]
    ) -> some View {
        let isExpanded = expandedGroups.contains(group.id)

        return DisclosureGroup(
            isExpanded: Binding(
                get: { expandedGroups.contains(group.id) },
                set: { newValue in
                    if newValue {
                        expandedGroups.insert(group.id)
                    } else {
                        expandedGroups.remove(group.id)
                    }
                }
            )
        ) {
            ForEach(comments) { comment in
                commentRow(comment)
            }
        } label: {
            rbnGroupLabel(
                count: comments.count, averageWPM: group.averageWPM, isExpanded: isExpanded
            )
        }
    }

    private func rbnGroupLabel(count: Int, averageWPM: Int?, isExpanded: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.blue)

            Text("\(count) RBN spot\(count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let wpm = averageWPM {
                Text("\(wpm) WPM avg")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
            }

            Spacer()
        }
    }

    private func commentRow(_ comment: POTASpotComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.spotter)
                    .font(.subheadline.weight(.semibold).monospaced())
                    .foregroundStyle(comment.isAutomatedSpot ? .blue : .green)

                if comment.isAutomatedSpot {
                    Text("RBN")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Spacer()

                Text(comment.timeAgo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let commentText = comment.comments, !commentText.isEmpty {
                Text(commentText)
                    .font(.body)
            } else {
                Text("Spotted you")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            if let source = comment.source, !source.isEmpty, !comment.isAutomatedSpot {
                Text("via \(source)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Group consecutive RBN spots together between human comments
    private func groupComments(_ comments: [POTASpotComment]) -> [CommentGroup] {
        var groups: [CommentGroup] = []
        var currentRBNBatch: [POTASpotComment] = []
        var rbnGroupIndex = 0

        for comment in comments {
            if comment.isAutomatedSpot {
                currentRBNBatch.append(comment)
            } else {
                // Flush any accumulated RBN batch
                if !currentRBNBatch.isEmpty {
                    groups.append(.rbnGroup(index: rbnGroupIndex, comments: currentRBNBatch))
                    rbnGroupIndex += 1
                    currentRBNBatch = []
                }
                groups.append(.human(comment))
            }
        }

        // Flush trailing RBN batch
        if !currentRBNBatch.isEmpty {
            groups.append(.rbnGroup(index: rbnGroupIndex, comments: currentRBNBatch))
        }

        return groups
    }
}

// MARK: - SpotCommentsBadge

/// A badge showing the number of new spot comments
struct SpotCommentsBadge: View {
    let commentCount: Int

    var body: some View {
        if commentCount > 0 {
            Text("\(commentCount)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green)
                .clipShape(Capsule())
        }
    }
}

// MARK: - SpotCommentsButton

/// A button that shows spot comments count and opens the sheet
struct SpotCommentsButton: View {
    // MARK: Internal

    let comments: [POTASpotComment]
    let newCount: Int
    let parkRef: String
    let onMarkRead: () -> Void

    var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 14))

                if newCount > 0 {
                    Text("\(newCount)")
                        .font(.caption.weight(.bold))
                }
            }
            .foregroundStyle(newCount > 0 ? .green : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                newCount > 0
                    ? Color.green.opacity(0.1)
                    : Color(.tertiarySystemBackground)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            SpotCommentsSheet(
                comments: comments,
                parkRef: parkRef,
                onDismiss: { showSheet = false },
                onMarkRead: onMarkRead
            )
        }
    }

    // MARK: Private

    @State private var showSheet = false
}

#Preview("With Mixed Comments") {
    SpotCommentsSheet(
        comments: [
            POTASpotComment(
                spotId: 1,
                spotter: "K3ABC",
                comments: "Strong signal, 599!",
                spotTime: "2025-01-15T14:30:00Z",
                source: "web"
            ),
            POTASpotComment(
                spotId: 10,
                spotter: "VE3RBN",
                comments: "14 dB 22 WPM CQ",
                spotTime: "2025-01-15T14:29:00Z",
                source: "RBN"
            ),
            POTASpotComment(
                spotId: 11,
                spotter: "W3LPL",
                comments: "18 dB 20 WPM CQ",
                spotTime: "2025-01-15T14:28:30Z",
                source: "RBN"
            ),
            POTASpotComment(
                spotId: 12,
                spotter: "K1TTT",
                comments: "10 dB 22 WPM CQ",
                spotTime: "2025-01-15T14:28:00Z",
                source: "RBN"
            ),
            POTASpotComment(
                spotId: 2,
                spotter: "W1XYZ",
                comments: "Thanks for the park!",
                spotTime: "2025-01-15T14:25:00Z",
                source: "app"
            ),
            POTASpotComment(
                spotId: 13,
                spotter: "N2FOC",
                comments: "20 dB 24 WPM CQ",
                spotTime: "2025-01-15T14:24:00Z",
                source: "RBN"
            ),
            POTASpotComment(
                spotId: 14,
                spotter: "KM3T",
                comments: "12 dB 18 WPM CQ",
                spotTime: "2025-01-15T14:23:00Z",
                source: "RBN"
            ),
        ],
        parkRef: "K-1234",
        onDismiss: {},
        onMarkRead: {}
    )
}

#Preview("Human Only") {
    SpotCommentsSheet(
        comments: [
            POTASpotComment(
                spotId: 1,
                spotter: "K3ABC",
                comments: "Strong signal, 599!",
                spotTime: "2025-01-15T14:30:00Z",
                source: "web"
            ),
            POTASpotComment(
                spotId: 2,
                spotter: "W1XYZ",
                comments: nil,
                spotTime: "2025-01-15T14:25:00Z",
                source: "app"
            ),
        ],
        parkRef: "K-1234",
        onDismiss: {},
        onMarkRead: {}
    )
}

#Preview("Empty") {
    SpotCommentsSheet(
        comments: [],
        parkRef: "K-1234",
        onDismiss: {},
        onMarkRead: {}
    )
}
