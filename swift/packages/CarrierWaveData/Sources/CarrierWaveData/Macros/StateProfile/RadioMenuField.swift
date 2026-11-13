import Foundation

// MARK: - RadioMenuField

/// One readable Elecraft K-line menu item. The read sequence is
/// `MN<item>;MP;MN255;` — select the menu page, query its parameter,
/// exit menu mode — driven through `RadioSession.sendQuery`.
///
/// Distinct from `RadioStateField` because the codec layer is fundamentally
/// different: menu reads cost a round-trip through menu mode (the front
/// panel briefly shows the menu page), so they can't ride the continuous
/// poll loop the way `FA;`/`MD;`/`PC;` do. Menu snapshots happen on
/// demand — once per intent invocation, before computing the plan.
public struct RadioMenuField: Sendable, Equatable, Identifiable {
    // MARK: Lifecycle

    public init(item: UInt16, label: String) {
        self.item = item
        self.label = label
    }

    // MARK: Public

    public let item: UInt16
    public let label: String

    public var id: UInt16 {
        item
    }

    /// `MN128;` etc. Always 3-digit zero-padded per the Elecraft Programmer's
    /// Reference (MN takes 3 decimal digits).
    public var preamble: String {
        String(format: "MN%03d;", item)
    }

    /// `MP;` — query the parameter of the currently-selected menu page.
    public var query: String {
        "MP;"
    }

    /// `MN255;` — exit menu mode and return to operating display.
    public var postamble: String {
        "MN255;"
    }
}

// MARK: - KX2 menu catalog

public extension RadioMenuField {
    /// KX2 menu items the `RadioIntent` system asserts. Labels match the
    /// human-readable names from the KX2 Owner's Manual menu summary so the
    /// Plan section shows "AGC MD" rather than "menu 128".
    static let kx2Canonical: [RadioMenuField] = [
        RadioMenuField(item: 82, label: "MIC BTN"),
        RadioMenuField(item: 128, label: "AGC MD"),
        RadioMenuField(item: 135, label: "MIC BIAS"),
    ]
}

// MARK: - MenuPlanRow

/// One diff row for the Plan section, the menu-item counterpart to
/// `RadioStatePlanAction`. `current == nil` means the read timed out so
/// the row degrades to a blind-apply visual.
public struct MenuPlanRow: Sendable, Equatable, Identifiable {
    // MARK: Lifecycle

    public init(item: UInt16, label: String, current: UInt16?, desired: UInt16) {
        self.item = item
        self.label = label
        self.current = current
        self.desired = desired
    }

    // MARK: Public

    public let item: UInt16
    public let label: String
    public let current: UInt16?
    public let desired: UInt16

    public var id: UInt16 {
        item
    }

    public var converged: Bool {
        current == desired
    }
}

// MARK: - MenuReader

/// One-shot batch read of KX2/K3 menu values. Issues `MN<item>;MP;MN255;`
/// per item through `RadioSession.sendQuery`, parses the `MP<value>;`
/// response, and returns a dictionary keyed by menu number. Items that
/// time out are omitted (caller treats them as "unknown current value").
@MainActor
public enum MenuReader {
    // MARK: Public

    public static func snapshot(
        items: [RadioMenuField],
        session: RadioSession,
        perItemTimeout: Duration = .milliseconds(500)
    ) async -> [UInt16: UInt16] {
        var result: [UInt16: UInt16] = [:]
        for field in items {
            guard let value = await readOne(field: field, session: session, timeout: perItemTimeout) else {
                continue
            }
            result[field.item] = value
        }
        return result
    }

    // MARK: Private

    private static func readOne(
        field: RadioMenuField,
        session: RadioSession,
        timeout: Duration
    ) async -> UInt16? {
        let response = await session.sendQuery(
            command: field.query,
            expectedPrefix: "MP",
            preamble: field.preamble,
            postamble: field.postamble,
            timeout: timeout
        )
        guard let response else {
            return nil
        }
        // `MP<digits>;` — strip prefix + trailing semicolon, parse the body.
        let body = response.dropFirst(2).dropLast()
        guard body.allSatisfy(\.isNumber) else {
            return nil
        }
        return UInt16(body)
    }
}
