import Foundation

// MARK: - FrequencyMark

struct FrequencyMark: Equatable {
    let frequencyMHz: Double
    let mode: String
}

// MARK: - VimMarkStore

@MainActor
final class VimMarkStore {
    // MARK: Internal

    private(set) var previousFrequency: FrequencyMark?

    func set(_ register: Character, frequency: Double, mode: String) {
        guard register >= "a", register <= "z" else {
            return
        }
        marks[register] = FrequencyMark(frequencyMHz: frequency, mode: mode)
    }

    func get(_ register: Character) -> FrequencyMark? {
        marks[register]
    }

    func updatePrevious(frequency: Double, mode: String) {
        previousFrequency = FrequencyMark(frequencyMHz: frequency, mode: mode)
    }

    // MARK: Private

    private var marks: [Character: FrequencyMark] = [:]
}
