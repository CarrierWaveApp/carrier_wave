import Foundation

// MARK: - Multi-Operator Support

public extension LoggingSession {
    /// Additional operator callsigns for multi-op sessions (excludes session owner)
    var operatorCallsigns: [String] {
        get {
            guard !operatorCallsignsRawValue.isEmpty,
                  operatorCallsignsRawValue != "[]",
                  let data = operatorCallsignsRawValue.data(using: .utf8),
                  let calls = try? JSONDecoder().decode([String].self, from: data)
            else {
                return []
            }
            return calls
        }
        set {
            let cleaned = newValue.map { $0.uppercased().trimmingCharacters(in: .whitespaces) }
            let unique = cleaned.reduce(into: [String]()) { result, call in
                if !call.isEmpty, !result.contains(call) {
                    result.append(call)
                }
            }
            if let data = try? JSONEncoder().encode(unique) {
                operatorCallsignsRawValue = String(data: data, encoding: .utf8) ?? "[]"
            }
            cloudDirtyFlag = true
        }
    }

    /// Whether this session has additional operators beyond the session owner
    var isMultiOp: Bool {
        !operatorCallsigns.isEmpty
    }

    /// All operator callsigns including the session owner
    var allOperatorCallsigns: [String] {
        [myCallsign] + operatorCallsigns
    }
}
