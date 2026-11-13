import UIKit

// MARK: - OperatorRole

/// The operator's self-declared operating style, chosen during onboarding
/// (or later in Settings → My Profile / Settings → Logger → Operating Style).
/// The app uses it to pick role-aware defaults — never to hide functionality:
///
/// - `.hunter` lands the Sessions tab on the Hunter Log and relabels it
///   "Hunter Log" (`SessionsTabView`, `ContentView`), and suppresses the
///   dashboard On Air card's duplicate spot sections (`OnAirCard`). Also
///   makes the "Same as Last Session" quick-start more prominent — hunters
///   want to log fast, not re-run a wizard they don't need.
/// - `.activator` keeps the intent grid first; the Activate intent opens the
///   program-led Activate wizard (`SessionOperationType.activation`), which
///   leads with the park / summit reference — the only field a portable op
///   mutates every session.
/// - `.newcomer` biases onboarding toward listening-first features
///   (Tune In, band plan) that deliver a first win before transmitting.
/// - `.mixed` (and unset) is the neutral default — current behavior.
///
/// Stored as a raw string under `storageKey` so `@AppStorage` call sites
/// stay cheap. An empty string means the user never chose; treat as `.mixed`.
enum OperatorRole: String, CaseIterable, Identifiable {
    case activator
    case hunter
    case mixed
    case newcomer

    // MARK: Internal

    /// Canonical UserDefaults key shared by every `@AppStorage` reader.
    static let storageKey = "operatorRole"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .activator: "Activator"
        case .hunter: "Hunter"
        case .mixed: "A Bit of Everything"
        case .newcomer: "New to Ham Radio"
        }
    }

    var icon: String {
        switch self {
        case .activator: "antenna.radiowaves.left.and.right"
        case .hunter: "binoculars"
        case .mixed: "dot.radiowaves.left.and.right"
        case .newcomer: "graduationcap"
        }
    }

    /// One-line pitch shown under the option in onboarding and Settings.
    var blurb: String {
        switch self {
        case .activator: "I head out to parks and summits and run sessions"
        case .hunter: "I chase parks, summits, and DX from home"
        case .mixed: "Ragchews, contests, hunting — depends on the day"
        case .newcomer: "Just licensed (or studying) and exploring"
        }
    }

    /// Whether the role implies the wizard is largely vestigial — the user
    /// just wants to log fast. Used by the "Same as Last Session" quick-start
    /// affordance to decide how prominent it should be.
    var prefersQuickStart: Bool {
        self == .hunter
    }

    /// The current persisted role, or `nil` if the user never chose one.
    static func current() -> OperatorRole? {
        guard let raw = UserDefaults.standard.string(forKey: storageKey) else {
            return nil
        }
        return OperatorRole(rawValue: raw)
    }

    /// Persist the chosen role to the canonical key.
    func persist() {
        UserDefaults.standard.set(rawValue, forKey: OperatorRole.storageKey)
    }
}
