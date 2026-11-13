import Foundation

// MARK: - CWTextElement

/// A segment of decoded CW text with optional highlighting
public enum CWTextElement: Identifiable, Equatable, Sendable {
    case text(String)
    case callsign(String, role: CallsignRole)
    case prosign(String)
    case signalReport(String)
    case grid(String) // Grid square (e.g., EM74)
    case power(String) // Power level (e.g., 100W)
    case name(String) // Operator name
    case suggestion(original: String, suggested: String, category: SuggestionCategory)

    // MARK: Public

    /// Role of the callsign in the QSO
    public enum CallsignRole: Equatable, Sendable {
        case caller // Station calling (after CQ or before DE)
        case callee // Station being called (after DE)
        case unknown
    }

    public var id: String {
        switch self {
        case let .text(str): "text-\(str)"
        case let .callsign(str, _): "call-\(str)"
        case let .prosign(str): "pro-\(str)"
        case let .signalReport(str): "rst-\(str)"
        case let .grid(str): "grid-\(str)"
        case let .power(str): "pwr-\(str)"
        case let .name(str): "name-\(str)"
        case let .suggestion(orig, sugg, _): "sug-\(orig)-\(sugg)"
        }
    }
}
