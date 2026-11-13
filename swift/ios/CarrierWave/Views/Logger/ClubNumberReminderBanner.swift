import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - ClubNumberReminderBanner

/// Dismissible banner shown inside the contest exchange section that
/// reminds the operator of any club numbers (local `ClubMember.number`
/// values plus the auto-derived SKCC badge) they should include in the
/// sent exchange. Dismissal is persisted per contest id.
struct ClubNumberReminderBanner: View {
    // MARK: Internal

    let contestId: String
    let myCallsign: String

    var body: some View {
        if !isDismissed, !numbers.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "number.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Club numbers to send")
                        .font(.caption.weight(.semibold))
                    ForEach(numbers, id: \.club) { entry in
                        HStack(spacing: 6) {
                            Text(entry.club)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text("#\(entry.number)")
                                .font(.caption.monospaced().weight(.semibold))
                        }
                    }
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss reminder")
            }
            .padding(10)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .task(id: myCallsign) { await reload() }
        }
    }

    // MARK: Private

    private struct Entry: Equatable {
        let club: String
        let number: String
    }

    @AppStorage("dismissedClubNumberReminders") private var dismissedRaw = ""

    @State private var numbers: [Entry] = []

    private var isDismissed: Bool {
        dismissedRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .contains(contestId)
    }

    private func dismiss() {
        var ids = dismissedRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !ids.contains(contestId) {
            ids.append(contestId)
        }
        dismissedRaw = ids.joined(separator: ",")
    }

    private func reload() async {
        let upper = myCallsign.uppercased()
        guard !upper.isEmpty else {
            numbers = []
            return
        }

        var collected: [Entry] = []

        for club in ClubsSyncService.shared.clubs {
            let members = await ClubsSyncService.shared.members(inClubId: club.id)
            for member in members where member.callsign.uppercased() == upper {
                guard let raw = member.number?.trimmingCharacters(in: .whitespaces),
                      !raw.isEmpty
                else {
                    continue
                }
                let clubName = ClubsSyncService.shared.club(id: member.clubId)?.name ?? "Club"
                collected.append(Entry(club: clubName, number: raw))
            }
        }

        if let skcc = SKCCMembershipStore.shared.member(for: upper),
           !collected.contains(where: { $0.club.uppercased() == "SKCC" })
        {
            collected.append(Entry(club: "SKCC", number: skcc.badge))
        }

        numbers = collected.sorted { $0.club.lowercased() < $1.club.lowercased() }
    }
}
