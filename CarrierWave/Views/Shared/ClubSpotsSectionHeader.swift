import SwiftUI

/// Sticky section header for club member spots.
struct ClubSpotsSectionHeader: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.3.fill")
                .font(.caption)
                .foregroundStyle(.blue)
            Text("Club Members")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }
}
