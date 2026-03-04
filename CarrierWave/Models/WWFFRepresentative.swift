// WWFF Representative
//
// Data model for WWFF national program coordinators/representatives.
// Used for looking up the appropriate contact for log submissions,
// award claims, and program inquiries based on country or reference prefix.

import Foundation

// MARK: - WWFFRepresentative

struct WWFFRepresentative: Identifiable, Sendable {
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

    // MARK: - Email Composition

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
        """
        Dear \(programCode) Coordinator,

        I would like to submit my WWFF activation log for review.

        Callsign: \(callsign)
        WWFF Reference: \(reference)
        Date of Activation: \(date)
        Number of QSOs: \(qsoCount)

        Please find the ADIF log attached.

        73,
        \(callsign)
        """
    }

    /// Compose a mailto URL for contacting a representative.
    static func mailtoURL(
        representative: WWFFRepresentative,
        subject: String,
        body: String
    ) -> URL? {
        guard let email = representative.email else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
