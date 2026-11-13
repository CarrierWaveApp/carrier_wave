//
//  EnrichedLinkBuilder.swift
//  CarrierWaveCore
//
//  Builds enriched share URLs (universal links) from payloads. Handles
//  progressive truncation when an activation payload would exceed the
//  fragment size budget. See
//  docs/plans/2026-04-07-imessage-enriched-text-design.md.
//

import Foundation

// MARK: - EnrichedLinkBuilder

public enum EnrichedLinkBuilder {
    // MARK: Public

    /// Universal link host. Routes to the iOS app or CW Sweep when installed,
    /// falls through to the web landing page otherwise.
    public static let host = "carrierwave.app"

    /// Build a universal link URL for a callsign payload. Throws if the
    /// encoded fragment would exceed the size budget (very rare for
    /// callsign payloads).
    public static func url(for payload: CallsignPayload) throws -> URL {
        let token = identifier(payload.callsign)
        let fragment = try EnrichedLinkPayload.callsign(payload).encodeFragment()
        return try makeURL(kind: "call", token: token, fragment: fragment)
    }

    /// Build a universal link URL for a park payload.
    public static func url(for payload: ParkPayload) throws -> URL {
        let token = identifier(payload.reference)
        let fragment = try EnrichedLinkPayload.park(payload).encodeFragment()
        return try makeURL(kind: "park", token: token, fragment: fragment)
    }

    /// Build a universal link URL for a SOTA summit payload.
    public static func url(for payload: SummitPayload) throws -> URL {
        let token = identifier(payload.reference)
        let fragment = try EnrichedLinkPayload.summit(payload).encodeFragment()
        return try makeURL(kind: "sum", token: token, fragment: fragment)
    }

    /// Build a universal link URL for a QSO payload. The token is a
    /// short opaque random ID — the server never resolves it to data, it
    /// only exists so the URL is unique per share.
    public static func url(for payload: QSOPayload) throws -> URL {
        let token = randomToken()
        let fragment = try EnrichedLinkPayload.qso(payload).encodeFragment()
        return try makeURL(kind: "qso", token: token, fragment: fragment)
    }

    /// Build a universal link URL for an activation payload. Applies
    /// progressive truncation if the encoded payload exceeds the fragment
    /// budget. Truncation order:
    ///   1. Drop notes
    ///   2. Truncate bands/modes arrays to maxBandModeArrayLength
    ///   3. Drop dxccCount
    ///   4. Drop parkToParkCount
    ///   5. Drop endTime (keeps duration computable client-side from start)
    ///   6. Drop bands/modes entirely
    /// If still too large after step 6, throws `payloadTooLarge`.
    public static func url(for payload: ActivationPayload) throws -> URL {
        let token = randomToken()
        let truncated = try truncateToFit(payload)
        let fragment = try EnrichedLinkPayload.activation(truncated).encodeFragment()
        return try makeURL(kind: "act", token: token, fragment: fragment)
    }

    /// Decode an enriched link URL back into its payload. Returns nil if
    /// the URL is not a Carrier Wave enriched link or the fragment is
    /// missing/malformed.
    public static func decode(_ url: URL) -> EnrichedLinkPayload? {
        guard let components = URLComponents(
            url: url, resolvingAgainstBaseURL: false
        ),
            components.host == host,
            url.pathComponents.count >= 3,
            url.pathComponents[1] == "link"
        else {
            return nil
        }
        guard let fragment = components.fragment else {
            return nil
        }
        // Strip the "d=" prefix if present.
        let stripped = fragment.hasPrefix("d=")
            ? String(fragment.dropFirst(2))
            : fragment
        return try? EnrichedLinkPayload.decodeFragment(stripped)
    }

    /// Returns true if the URL is a Carrier Wave enriched link (regardless
    /// of whether the fragment is present or decodable). Used by the URL
    /// router to claim links before falling through to other handlers.
    public static func isEnrichedLink(_ url: URL) -> Bool {
        guard url.host == host,
              url.pathComponents.count >= 3,
              url.pathComponents[1] == "link"
        else {
            return false
        }
        let kind = url.pathComponents[2]
        return ["call", "park", "sum", "qso", "act"].contains(kind)
    }

    /// The kind segment of an enriched link URL, or nil if not enriched.
    public static func kind(of url: URL) -> String? {
        guard isEnrichedLink(url) else {
            return nil
        }
        return url.pathComponents[2]
    }

    /// The identifier segment (callsign / park ref / opaque token).
    public static func identifier(of url: URL) -> String? {
        guard isEnrichedLink(url), url.pathComponents.count >= 4 else {
            return nil
        }
        return url.pathComponents[3]
    }

    // MARK: Private

    private static func makeURL(kind: String, token: String, fragment: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/link/\(kind)/\(token)"
        components.fragment = "d=\(fragment)"
        guard let url = components.url else {
            throw EnrichedLinkPayloadError.invalidEncoding
        }
        if url.absoluteString.utf8.count > EnrichedLinkPayload.maxURLByteCount {
            throw EnrichedLinkPayloadError.payloadTooLarge(
                actual: url.absoluteString.utf8.count,
                limit: EnrichedLinkPayload.maxURLByteCount
            )
        }
        return url
    }

    /// URL-safe identifier derived from a callsign or park reference.
    /// Replaces `/` with `-` (e.g. `KD9LSV/P` → `KD9LSV-P`) so the URL
    /// path doesn't break.
    private static func identifier(_ raw: String) -> String {
        raw
            .uppercased()
            .replacingOccurrences(of: "/", with: "-")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? raw
    }

    /// Generate a random base62 token of length 10. Used for QSO and
    /// activation links where the path identifier is opaque.
    private static func randomToken() -> String {
        let alphabet = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        )
        var token = ""
        token.reserveCapacity(10)
        for _ in 0 ..< 10 {
            let idx = Int.random(in: 0 ..< alphabet.count)
            token.append(alphabet[idx])
        }
        return token
    }

    /// Apply progressive truncation to an activation payload until it fits
    /// within the fragment size budget. See `ActivationTruncation`.
    private static func truncateToFit(
        _ original: ActivationPayload
    ) throws -> ActivationPayload {
        for level in ActivationTruncation.allLevels {
            let candidate = ActivationTruncation.apply(level, to: original)
            if fits(candidate) {
                return candidate
            }
        }
        throw EnrichedLinkPayloadError.payloadTooLarge(
            actual: -1, limit: EnrichedLinkPayload.maxFragmentByteCount
        )
    }

    private static func fits(_ payload: ActivationPayload) -> Bool {
        guard let fragment = try? EnrichedLinkPayload
            .activation(payload).encodeFragment()
        else {
            return false
        }
        return fragment.utf8.count <= EnrichedLinkPayload.maxFragmentByteCount
    }
}
