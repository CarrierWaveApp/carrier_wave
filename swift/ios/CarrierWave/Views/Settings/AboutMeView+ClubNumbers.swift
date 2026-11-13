import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - AboutMeView + Club Numbers Card

extension AboutMeView {
    /// Card listing the clubs this callsign belongs to with editable
    /// member numbers, plus the derived SKCC number when present.
    @MainActor
    @ViewBuilder
    var clubNumbersCard: some View {
        if profile != nil {
            VStack(alignment: .leading, spacing: 12) {
                clubNumbersHeader
                clubNumbersBody
                clubNumbersFootnote
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    func loadClubNumbers() async {
        guard let callsign = profile?.callsign else {
            myClubMembers = []
            pendingNumbers = [:]
            skccBadgeForMyCallsign = nil
            return
        }
        let upper = callsign.uppercased()
        let previous = CallsignAliasService.shared.getPreviousCallsigns()
            .map { $0.uppercased() }
        let allCallsigns = Set([upper] + previous)

        var result: [FfiClubMember] = []
        for club in ClubsSyncService.shared.clubs {
            let members = await ClubsSyncService.shared.members(inClubId: club.id)
            let matching = members.filter { allCallsigns.contains($0.callsign.uppercased()) }
            result.append(contentsOf: matching)
        }

        myClubMembers = result.sorted {
            let nameA = ClubsSyncService.shared.club(id: $0.clubId)?.name ?? ""
            let nameB = ClubsSyncService.shared.club(id: $1.clubId)?.name ?? ""
            return nameA < nameB
        }

        pendingNumbers = Dictionary(
            uniqueKeysWithValues: myClubMembers.map {
                ("\($0.clubId):\($0.callsign)", $0.number ?? "")
            }
        )

        if let member = SKCCMembershipStore.shared.member(for: callsign) {
            skccBadgeForMyCallsign = "#\(member.badge)"
        } else {
            skccBadgeForMyCallsign = nil
        }
    }

    func saveAllClubNumbers() async {
        for member in myClubMembers {
            let key = "\(member.clubId):\(member.callsign)"
            let trimmed = (pendingNumbers[key] ?? "")
                .trimmingCharacters(in: .whitespaces)
            let newValue: String? = trimmed.isEmpty ? nil : trimmed
            guard member.number != newValue else {
                continue
            }
            await ClubsSyncService.shared.setMemberNumber(
                clubId: member.clubId,
                callsign: member.callsign,
                number: newValue
            )
        }
    }

    // MARK: Private

    private var clubNumbersHeader: some View {
        HStack {
            Text("Club Numbers")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if !myClubMembers.isEmpty {
                Text("\(myClubMembers.count) club\(myClubMembers.count == 1 ? "" : "s")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var clubNumbersBody: some View {
        if myClubMembers.isEmpty, skccBadgeForMyCallsign == nil {
            HStack(spacing: 10) {
                Image(systemName: "person.2")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text("No club memberships yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        } else {
            VStack(spacing: 0) {
                if let badge = skccBadgeForMyCallsign {
                    skccRow(badge: badge)
                    if !myClubMembers.isEmpty {
                        Divider().background(Color(.separator).opacity(0.6))
                    }
                }
                ForEach(Array(myClubMembers.enumerated()), id: \.offset) { index, member in
                    if index > 0 {
                        Divider().background(Color(.separator).opacity(0.6))
                    }
                    clubMemberRow(member)
                }
            }
        }
    }

    private var clubNumbersFootnote: some View {
        Text(
            "Stored locally. SKCC reads from the roster automatically."
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private func skccRow(badge: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "key.radiowaves.forward")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text("SKCC")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(badge)
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func clubMemberRow(_ member: FfiClubMember) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(ClubsSyncService.shared.club(id: member.clubId)?.name ?? "Club")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer()
            TextField("Number", text: bindingForMember(member))
                .font(.subheadline.monospaced())
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .frame(maxWidth: 120, minHeight: 32)
                .onSubmit { Task { await saveNumber(for: member) } }
        }
        .padding(.vertical, 6)
    }

    private func bindingForMember(_ member: FfiClubMember) -> Binding<String> {
        let key = "\(member.clubId):\(member.callsign)"
        return Binding(
            get: { pendingNumbers[key] ?? "" },
            set: { pendingNumbers[key] = $0 }
        )
    }

    private func saveNumber(for member: FfiClubMember) async {
        let key = "\(member.clubId):\(member.callsign)"
        let trimmed = (pendingNumbers[key] ?? "")
            .trimmingCharacters(in: .whitespaces)
        let newValue: String? = trimmed.isEmpty ? nil : trimmed
        guard member.number != newValue else {
            return
        }
        await ClubsSyncService.shared.setMemberNumber(
            clubId: member.clubId,
            callsign: member.callsign,
            number: newValue
        )
    }
}
