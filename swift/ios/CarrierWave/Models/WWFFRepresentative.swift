// WWFF Representative
//
// Data model for WWFF national program coordinators/representatives.
// Used for looking up the appropriate contact for log submissions,
// award claims, and program inquiries based on country or reference prefix.

import Foundation

// MARK: - WWFFRepresentative

struct WWFFRepresentative: Identifiable {
    let id: String // Program code, e.g., "KFF"
    let programCode: String // e.g., "KFF"
    let country: String // e.g., "United States"
    let coordinatorCallsign: String // e.g., "N9MM"
    let coordinatorName: String? // e.g., "Norm"
    let email: String? // Contact email if publicly available
    let website: String? // National program website
    let logManagerCallsign: String? // Log manager if different
    let awardManagerCallsign: String? // Award manager if different
}

// MARK: - WWFFRepresentativeDirectory

/// Directory of WWFF national program representatives.
/// Provides lookup by program code (extracted from WWFF reference prefix)
/// and by DXCC entity number.
enum WWFFRepresentativeDirectory {
    // MARK: - Email Composition

    /// WWFF-required minimum QSO count for a valid activator credit.
    static let minimumValidQSOs = 44

    // MARK: - Non-Program Fallback

    /// Global WWFF log inbox for DXCC entities without a national program.
    /// Per the WWFF FAQ, logs for these areas are emailed to Manfred (DF6EX).
    static let nonProgramFallbackEmail = "wwfflogs@winqsl.de"
    static let nonProgramFallbackCallsign = "DF6EX"
    static let nonProgramFallbackName = "Manfred"

    /// Synthetic representative used when a reference's DXCC has no
    /// national program. Pretends to be a program named "WWFF Global"
    /// so the existing UI flow can compose an email without special-casing.
    static let nonProgramFallbackRepresentative = WWFFRepresentative(
        id: "WWFF",
        programCode: "WWFF",
        country: "Non-Program Areas",
        coordinatorCallsign: nonProgramFallbackCallsign,
        coordinatorName: nonProgramFallbackName,
        email: nonProgramFallbackEmail,
        website: "https://wwff.co",
        logManagerCallsign: nil,
        awardManagerCallsign: nil
    )

    /// All representatives sorted by country name.
    static var allRepresentatives: [WWFFRepresentative] {
        representatives.sorted { $0.country < $1.country }
    }

    // MARK: - Lookup Methods

    /// Look up a representative by WWFF program code (e.g., "KFF", "VKFF").
    static func representative(forProgram code: String) -> WWFFRepresentative? {
        let upper = code.uppercased()
        return representatives.first { $0.programCode == upper }
    }

    /// Look up a representative from a full WWFF reference (e.g., "KFF-1234").
    static func representative(forReference reference: String) -> WWFFRepresentative? {
        let programCode = extractProgramCode(from: reference)
        return representative(forProgram: programCode)
    }

    /// Look up a representative by DXCC entity number.
    static func representative(forDXCC dxcc: Int) -> WWFFRepresentative? {
        guard let code = dxccToProgramCode[dxcc] else {
            return nil
        }
        return representative(forProgram: code)
    }

    /// Search representatives by country name or program code.
    static func search(_ query: String) -> [WWFFRepresentative] {
        let lower = query.lowercased()
        return representatives.filter {
            $0.country.lowercased().contains(lower)
                || $0.programCode.lowercased().contains(lower)
                || $0.coordinatorCallsign.lowercased().contains(lower)
        }.sorted { $0.country < $1.country }
    }

    /// Extract program code from a WWFF reference (e.g., "KFF-1234" -> "KFF").
    static func extractProgramCode(from reference: String) -> String {
        let upper = reference.uppercased()
        if let dashIndex = upper.firstIndex(of: "-") {
            return String(upper[..<dashIndex])
        }
        return upper
    }

    /// WWFF-compliant ADIF filename for an activation log.
    /// Per WWFF Global Rules: `<callsign> @ <reference> YYYYMMDD.adi` —
    /// spaces around the `@` are part of the spec (see the official
    /// example `M0YMA-P @ GFF-0354 20240511.ADI`). Forward slashes in
    /// portable calls are replaced with hyphens so the filename is
    /// filesystem-safe. For multi-day activations use the date of the
    /// first day.
    nonisolated static func logFilename(
        reference: String,
        callsign: String,
        dateYYYYMMDD: String
    ) -> String {
        let safeCall = callsign.uppercased()
            .replacingOccurrences(of: "/", with: "-")
        let safeRef = reference.uppercased()
        return "\(safeCall) @ \(safeRef) \(dateYYYYMMDD).adi"
    }

    /// Convert a `YYYY-MM-DD` date string to the WWFF `YYYYMMDD` form used
    /// in filenames. Returns the input unchanged if it doesn't match.
    static func compactDate(_ date: String) -> String {
        date.replacingOccurrences(of: "-", with: "")
    }

    /// Compose an email subject for a log submission.
    static func logSubmissionSubject(
        reference: String,
        callsign: String,
        date: String
    ) -> String {
        "WWFF Log Submission: \(callsign) at \(reference) on \(date)"
    }

    /// Compose an email body for a log submission.
    static func logSubmissionBody(
        reference: String,
        callsign: String,
        date: String,
        qsoCount: Int,
        programCode: String
    ) -> String {
        let filename = logFilename(
            reference: reference,
            callsign: callsign,
            dateYYYYMMDD: compactDate(date)
        )
        let qsoLine = qsoCount > 0
            ? "Number of QSOs: \(qsoCount)"
            : "Number of QSOs: (see attached log)"
        return """
        Dear \(programCode) Log Manager,

        Please find my WWFF activation log attached for processing.

        Callsign: \(callsign)
        WWFF Reference: \(reference)
        Date of Activation: \(date)
        \(qsoLine)

        ADIF file: \(filename)

        Per WWFF Global Rules, the attached log uses the required filename
        format "<callsign> @ <reference> YYYYMMDD.<ext>" (ADI or CSV) and
        includes MY_SIG=WWFF with MY_SIG_INFO set to the reference. For
        multi-day activations the filename uses the first day's date. A
        minimum of \(minimumValidQSOs) valid QSOs is required for activator
        credit. Proof-of-activity photos (location/GPS, park sign, and
        station setup) can be supplied on request.

        73,
        \(callsign)
        """
    }

    /// Resolve the primary recipient for a log submission.
    /// WWFF rules: send to the log manager if listed, otherwise the
    /// coordinator. The coordinator is CC'd when distinct from the manager.
    static func logSubmissionRecipients(
        for representative: WWFFRepresentative
    ) -> (to: String, cc: String?)? {
        guard let coordinatorEmail = representative.email else {
            return nil
        }
        return (to: coordinatorEmail, cc: nil)
    }

    /// Compose a mailto URL for contacting a representative.
    /// Routes to the WWFF-preferred recipient and CCs the coordinator when
    /// a separate log manager is configured.
    static func mailtoURL(
        representative: WWFFRepresentative,
        subject: String,
        body: String
    ) -> URL? {
        guard let recipients = logSubmissionRecipients(for: representative)
        else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipients.to
        var items = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        if let cc = recipients.cc {
            items.append(URLQueryItem(name: "cc", value: cc))
        }
        components.queryItems = items
        return components.url
    }
}
