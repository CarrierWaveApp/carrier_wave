import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - StationSuggestion

nonisolated struct StationSuggestion: Identifiable, Equatable {
    let callsign: String
    let isFriend: Bool

    var id: String {
        callsign
    }
}

// MARK: - Station autocomplete

/// The "Them" field's autocomplete: friends first (friend-colored), then
/// distinct callsigns from the QSO log, plus the per-station mode-history
/// ordering both share. Split from MutualPassPlannerSheet.swift for file
/// size limits.
extension MutualPassPlannerSheet {
    var acceptedFriends: [Friendship] {
        FriendsSyncService.shared.acceptedFriends
    }

    static var maxSuggestions: Int {
        12
    }

    /// Autocomplete row: borderless chips (a Menu inside a List row swallows
    /// item taps), matching friends first in the friend color, then
    /// callsigns from the QSO log.
    var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions) { suggestion in
                    suggestionChip(suggestion)
                }
            }
        }
    }

    func suggestionChip(_ suggestion: StationSuggestion) -> some View {
        let isSelected = stationBInput.uppercased() == suggestion.callsign
        let tint: Color = suggestion.isFriend ? .yellow : Color(.systemGray)
        return Button {
            stationBInput = suggestion.callsign
            resolvedB = nil
        } label: {
            HStack(spacing: 4) {
                if suggestion.isFriend {
                    Image(systemName: "person.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                }
                Text(suggestion.callsign)
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.25) : tint.opacity(suggestion.isFriend ? 0.22 : 0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Use \(suggestion.callsign)\(suggestion.isFriend ? ", friend," : "") as the other station"
        )
    }

    /// Debounced rebuild of the autocomplete row: friends matching the
    /// input first (prefix beats substring), then distinct recent callsigns
    /// from the log. Empty input shows friends + recently worked.
    func refreshSuggestions() {
        suggestionTask?.cancel()
        suggestionTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else {
                return
            }
            suggestions = buildSuggestions()
        }
    }

    func buildSuggestions() -> [StationSuggestion] {
        let query = stationBInput.trimmingCharacters(in: .whitespaces).uppercased()
        // A parseable grid isn't a callsign — hide the row.
        if !query.isEmpty, MaidenheadConverter.coordinate(from: query) != nil {
            return []
        }
        let friendCalls = acceptedFriends.map { $0.friendCallsign.uppercased() }
        let prefixFriends = friendCalls.filter { query.isEmpty || $0.hasPrefix(query) }.sorted()
        let substringFriends = friendCalls
            .filter { !query.isEmpty && !$0.hasPrefix(query) && $0.contains(query) }
            .sorted()
        let friends = prefixFriends + substringFriends
        let friendSet = Set(friends)
        var result = friends.map { StationSuggestion(callsign: $0, isFriend: true) }
        for callsign in loggedCallsigns(matching: query) where !friendSet.contains(callsign) {
            result.append(StationSuggestion(callsign: callsign, isFriend: false))
            if result.count >= Self.maxSuggestions {
                break
            }
        }
        // Exact match already typed — nothing left to complete.
        if result.count == 1, result[0].callsign == query {
            return []
        }
        return result
    }

    /// Distinct callsigns from the log matching the prefix, most recently
    /// worked first (bounded fetch per the performance rules).
    func loggedCallsigns(matching query: String) -> [String] {
        var descriptor = if query.isEmpty {
            FetchDescriptor<QSO>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        } else {
            FetchDescriptor<QSO>(
                predicate: #Predicate { $0.callsign.starts(with: query) },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        }
        descriptor.fetchLimit = 200
        let qsos = (try? modelContext.fetch(descriptor)) ?? []
        var seen = Set<String>()
        var ordered = [String]()
        for qso in qsos {
            let call = qso.callsign.uppercased()
            guard !call.isEmpty, seen.insert(call).inserted else {
                continue
            }
            ordered.append(call)
        }
        return ordered
    }
}
