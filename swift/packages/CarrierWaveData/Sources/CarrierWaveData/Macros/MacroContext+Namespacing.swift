import Foundation

extension MacroContext {
    /// Returns the namespaced (lowercased) ctx token map suitable for
    /// seeding the strict `MacroTemplateEngine`. Mirrors the legacy
    /// `value(forToken:)` accessors but in `ctx.*` form (with the
    /// `ctx.` prefix applied by the executor at seed time).
    func namespacedTokens() -> [String: String] {
        var out: [String: String] = [:]
        if let myCall {
            out["myCall"] = myCall
        }
        if let myName {
            out["myName"] = myName
        }
        if let myGrid {
            out["myGrid"] = myGrid
        }
        if let contactCall {
            out["call"] = contactCall
        }
        if let contactName {
            out["name"] = contactName
        }
        if let rstSent {
            out["rst"] = rstSent
        }
        if let rstReceived {
            out["rstr"] = rstReceived
        }
        if let serial {
            out["nr"] = String(format: "%03d", serial)
        }
        if let exchange {
            out["exch"] = exchange
        }
        if let currentFreqHz {
            out["freq"] = String(currentFreqHz)
        }
        if let currentMode {
            out["mode"] = currentMode
        }
        if let park {
            out["park"] = park
        }
        if let sotaRef {
            out["sotaRef"] = sotaRef
        }
        if let wwffRef {
            out["wwffRef"] = wwffRef
        }
        return out
    }
}
