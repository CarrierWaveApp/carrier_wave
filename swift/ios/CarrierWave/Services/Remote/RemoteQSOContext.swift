import CarrierWaveCore
import SwiftData
import UIKit

// MARK: - RemoteQSOContext

//
// Operator-supplied state for the Remote-tab CW keyer pane. Mirrors the
// macro vocabulary in `RemoteCWMacros`: callsign, looked-up first name,
// RST, serial, and contest exchange. Tap a slot button → the pane reads
// `asContext` and ships it as `PlayCWSlotCommand.context` over the wire.
//
// Lookup happens on Field (rather than Sweep) because Field already holds
// the iOS keychain credentials for QRZ/HamDB — Sweep just runs the
// substitution against whatever name we resolve here.

@MainActor
@Observable
final class RemoteQSOContext {
    // MARK: Lifecycle

    init(modelContext: ModelContext? = nil) {
        myCall = UserDefaults.standard.string(forKey: "loggerDefaultCallsign") ?? ""
        exchange = UserDefaults.standard.string(forKey: "contestExchange") ?? ""
        rstSent = "599"
        serial = 1
        callsign = ""
        lookup = CallsignLookupService(modelContext: modelContext)
    }

    // MARK: Internal

    var myCall: String
    var rstSent: String
    var serial: Int
    var exchange: String

    /// Most recent lookup result for `callsign` (nil when no callsign or
    /// nothing came back). Set after the debounced lookup task resolves.
    private(set) var lookupResult: CallsignInfo?

    /// True while a lookup task is in flight for the current callsign.
    private(set) var isLookingUp = false

    var callsign: String {
        didSet {
            let normalized = callsign.uppercased()
            if normalized != callsign {
                callsign = normalized
                return
            }
            if normalized != lastLookedUp {
                lookupResult = nil
                scheduleLookup(for: normalized)
            }
        }
    }

    /// First name to substitute for `{NAME}`. Pulls from QRZ's first-name
    /// field, then falls back to the first space-separated word of `name`.
    var name: String {
        if let info = lookupResult {
            if let first = info.firstName, !first.isEmpty {
                return first.uppercased()
            }
            if let full = info.name?.split(separator: " ").first, !full.isEmpty {
                return String(full).uppercased()
            }
        }
        return ""
    }

    /// Wire-format context dict consumed by `coordinator.cwPlaySlot(...)`.
    /// Keys match `RemoteCWMacros.known`; missing fields are simply absent
    /// so Sweep's `missingMacros(in:context:)` flags them and rejects rather
    /// than transmitting a half-rendered message.
    var asContext: [String: String] {
        var out: [String: String] = [:]
        if !callsign.isEmpty {
            let upper = callsign.uppercased()
            out["CALL"] = upper
            out["HISCALL"] = upper
        }
        if !myCall.isEmpty {
            out["MYCALL"] = myCall.uppercased()
        }
        if !name.isEmpty {
            out["NAME"] = name
        }
        if !rstSent.isEmpty {
            out["RST"] = rstSent
        }
        if serial > 0 {
            let padded = String(format: "%03d", serial)
            out["NR"] = padded
            out["SERIAL"] = padded
        }
        if !exchange.isEmpty {
            out["EXCH"] = exchange
        }
        return out
    }

    /// Increments the contest serial — call after a confirmed QSO is sent.
    func bumpSerial() {
        serial += 1
    }

    // MARK: Private

    private let lookup: CallsignLookupService
    private var lookupTask: Task<Void, Never>?
    private var lastLookedUp: String?

    private func scheduleLookup(for normalized: String) {
        lookupTask?.cancel()
        guard normalized.count >= 3 else {
            // Too short to be a meaningful prefix; clear in-flight state.
            isLookingUp = false
            lastLookedUp = nil
            return
        }
        lastLookedUp = normalized
        isLookingUp = true
        lookupTask = Task { [weak self] in
            // CallsignLookupService already debounces internally (~500 ms),
            // so we don't add another sleep here.
            guard let info = await self?.lookup.lookup(normalized) else {
                await MainActor.run { [weak self] in
                    guard let self, lastLookedUp == normalized else {
                        return
                    }
                    isLookingUp = false
                }
                return
            }
            await MainActor.run { [weak self] in
                guard let self, lastLookedUp == normalized else {
                    return
                }
                lookupResult = info
                isLookingUp = false
            }
        }
    }
}
