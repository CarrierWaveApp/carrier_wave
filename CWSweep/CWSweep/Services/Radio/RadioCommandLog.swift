import Foundation

// MARK: - RadioCommandDirection

/// Direction of a radio command
enum RadioCommandDirection: Sendable {
    case tx // Sent to radio
    case rx // Received from radio
    case status // Connection lifecycle event
}

// MARK: - RadioCommandEntry

/// A single entry in the radio command log
struct RadioCommandEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let direction: RadioCommandDirection
    let text: String
}

// MARK: - RadioCommandLog

/// Observable ring-buffer log of radio commands for in-app visibility.
@MainActor
@Observable
final class RadioCommandLog {
    // MARK: Internal

    private(set) var entries: [RadioCommandEntry] = []

    /// Returns a @Sendable closure that hops to MainActor to append entries.
    /// Pass this to SerialRadioTransport at init time.
    func makeCallback() -> @Sendable (RadioCommandDirection, String) -> Void {
        { [weak self] direction, text in
            Task { @MainActor in
                self?.append(direction: direction, text: text)
            }
        }
    }

    func append(direction: RadioCommandDirection, text: String) {
        let entry = RadioCommandEntry(
            timestamp: Date(),
            direction: direction,
            text: text
        )
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }

    // MARK: Private

    private let maxEntries = 500
}
