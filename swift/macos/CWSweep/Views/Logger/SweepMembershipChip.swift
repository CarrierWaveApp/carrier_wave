// Sweep Membership Chip
//
// Single-row chip rendering one organisation membership for a callsign
// (e.g. "🎹 CWops #1532") in the QSO entry popup callsign-info bar.
// Mirrors the iOS MembershipChip; lives here because Sweep's chip styling
// is more compact (smaller padding, monospaced number).

import CarrierWaveData
import SwiftUI

struct SweepMembershipChip: View {
    // MARK: Internal

    let membership: CallsignEnrichmentMembership

    var body: some View {
        HStack(spacing: 3) {
            if let emoji = membership.emoji {
                Text(emoji)
            }
            Text(label)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: Private

    private var label: String {
        if let number = membership.memberNumber, !number.isEmpty {
            return "\(membership.sourceName) #\(number)"
        }
        return membership.sourceName
    }
}
