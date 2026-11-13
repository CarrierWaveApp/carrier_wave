// Session-aware ADIF export — supports POTA, SOTA, dual POTA+SOTA, and casual
// sessions where the activation-keyed `generateADIF(for:parkReference:...)`
// path doesn't apply (POTA path is preserved as-is for back-compat with the
// activation-centric POTA upload flow).
//
// Split out of `ADIFExportService.swift` to keep that actor under SwiftLint's
// 500-line / 300-statement-line type-body limits.

import CarrierWaveData
import Foundation

extension ADIFExportService {
    /// Bundle of optional program references that apply to every QSO record
    /// in a session export. Lets the session-aware ADIF generator stay under
    /// SwiftLint's 5-parameter limit while still expressing POTA / SOTA / WWFF
    /// activation context.
    struct SessionReferences {
        // MARK: Lifecycle

        init(
            parkReference: String? = nil,
            parkName: String? = nil,
            sotaReference: String? = nil,
            summitName: String? = nil,
            wwffReference: String? = nil
        ) {
            self.parkReference = parkReference
            self.parkName = parkName
            self.sotaReference = sotaReference
            self.summitName = summitName
            self.wwffReference = wwffReference
        }

        // MARK: Internal

        let parkReference: String?
        let parkName: String?
        let sotaReference: String?
        let summitName: String?
        let wwffReference: String?
    }

    /// Generate ADIF content for a logging session with arbitrary program
    /// references (POTA, SOTA, both, or neither). Mirrors `generateADIF(for:
    /// parkReference:parkName:activatorCallsign:)` but supports SOTA-only
    /// sessions where there is no park reference at all.
    ///
    /// - Parameters:
    ///   - snapshots: QSO snapshots to export.
    ///   - activatorCallsign: Operator callsign for the header comment.
    ///   - references: Per-session program references applied to every QSO.
    func generateSessionADIF(
        for snapshots: [QSOExportSnapshot],
        activatorCallsign: String,
        references: SessionReferences,
        mySigOverride: LogSubmissionFlavor? = nil
    ) async -> String {
        var lines: [String] = []
        lines.append(
            contentsOf: buildSessionHeader(
                snapshots: snapshots,
                activatorCallsign: activatorCallsign,
                references: references
            )
        )
        lines.append("<EOH>")
        lines.append("")

        for snapshot in snapshots.sorted(by: { $0.timestamp < $1.timestamp }) {
            lines.append(
                buildSessionQSORecord(
                    snapshot,
                    references: references,
                    mySigOverride: mySigOverride
                )
            )
            lines.append("")
            await Task.yield()
        }

        return lines.joined(separator: "\n")
    }

    /// Generate a program-flavored ADIF + filename for one specific submission
    /// portal. The body is identical to `generateSessionADIF` but `MY_SIG` is
    /// pinned to the flavor (so POTA portals see `MY_SIG=POTA`, WWFF portals
    /// see `MY_SIG=WWFF`) and the filename follows that program's convention.
    func generateFlavoredSessionADIF(
        for snapshots: [QSOExportSnapshot],
        activatorCallsign: String,
        references: SessionReferences,
        flavor: LogSubmissionFlavor,
        date: Date
    ) async -> ADIFExportResult? {
        guard let reference = mySigInfo(for: flavor, references: references)
        else {
            return nil
        }
        let content = await generateSessionADIF(
            for: snapshots,
            activatorCallsign: activatorCallsign,
            references: references,
            mySigOverride: flavor
        )
        let filename = flavor.filename(
            activatorCallsign: activatorCallsign,
            reference: reference,
            date: date
        )
        return ADIFExportResult(
            content: content,
            filename: filename,
            qsoCount: snapshots.count
        )
    }

    /// Generate a filename for a session ADIF export. Picks the SOTA reference
    /// when present (it's program-distinct), otherwise falls back to the POTA
    /// reference, otherwise just the callsign + date.
    func generateSessionFilename(
        activatorCallsign: String,
        parkReference: String?,
        sotaReference: String?,
        date: Date
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = dateFormatter.string(from: date)

        let safeCallsign =
            activatorCallsign
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: " ", with: "_")

        let referenceTag = sotaReference ?? parkReference
        let safeRef = referenceTag.map {
            $0.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: " ", with: "_")
        }
        if let safeRef {
            return "\(safeCallsign)_\(safeRef)_\(dateStr).adi"
        }
        return "\(safeCallsign)_\(dateStr).adi"
    }

    /// Per-QSO program fields for the session-aware export. POTA, SOTA, and
    /// WWFF each get their canonical ADIF tags when the corresponding session
    /// reference is set. MY_SIG can only hold one value, so we use the
    /// `mySigOverride` if supplied (program-flavored exports), otherwise pick
    /// POTA → WWFF → SOTA in priority order to match the most common
    /// upload-portal expectations for the combined archive.
    func appendSessionRefFields(
        to fields: inout [String],
        snapshot: QSOExportSnapshot,
        references: SessionReferences,
        mySigOverride: LogSubmissionFlavor? = nil
    ) {
        appendMyProgramFields(
            to: &fields,
            references: references,
            mySigOverride: mySigOverride
        )
        appendTheirProgramFields(to: &fields, snapshot: snapshot)
        appendQSLMessage(
            to: &fields,
            snapshot: snapshot,
            references: references
        )
    }

    private func appendMyProgramFields(
        to fields: inout [String],
        references: SessionReferences,
        mySigOverride: LogSubmissionFlavor?
    ) {
        let parkReference = references.parkReference?.nonEmpty
        let sotaReference = references.sotaReference?.nonEmpty
        let wwffReference = references.wwffReference?.nonEmpty

        let mySigFlavor = mySigOverride ?? defaultMySigFlavor(
            parkReference: parkReference,
            wwffReference: wwffReference,
            sotaReference: sotaReference
        )
        if let flavor = mySigFlavor,
           let mySigInfo = mySigInfo(for: flavor, references: references)
        {
            fields.append(formatField("MY_SIG", flavor.mySig))
            fields.append(formatField("MY_SIG_INFO", mySigInfo))
        }

        if let parkReference {
            fields.append(formatField("MY_POTA_REF", parkReference))
        }
        if let wwffReference {
            fields.append(formatField("MY_WWFF_REF", wwffReference))
        }
        if let sotaReference {
            fields.append(formatField("MY_SOTA_REF", sotaReference))
        }
    }

    private func appendTheirProgramFields(
        to fields: inout [String],
        snapshot: QSOExportSnapshot
    ) {
        if let theirPark = snapshot.theirParkReference, !theirPark.isEmpty {
            fields.append(formatField("SIG", "POTA"))
            fields.append(formatField("SIG_INFO", theirPark))
            fields.append(formatField("POTA_REF", theirPark))
        }
        if let theirSota = snapshot.sotaRef, !theirSota.isEmpty {
            fields.append(formatField("SOTA_REF", theirSota))
        }
    }

    private func appendQSLMessage(
        to fields: inout [String],
        snapshot: QSOExportSnapshot,
        references: SessionReferences
    ) {
        var qslParts: [String] = []
        if let parkReference = references.parkReference?.nonEmpty {
            qslParts.append("POTA \(parkReference)")
        }
        if let wwffReference = references.wwffReference?.nonEmpty {
            qslParts.append("WWFF \(wwffReference)")
        }
        if let sotaReference = references.sotaReference?.nonEmpty {
            qslParts.append("SOTA \(sotaReference)")
        }
        if let theirPark = snapshot.theirParkReference, !theirPark.isEmpty {
            qslParts.append("P2P \(theirPark)")
        }
        if let theirSota = snapshot.sotaRef, !theirSota.isEmpty {
            qslParts.append("S2S \(theirSota)")
        }
        if !qslParts.isEmpty {
            fields.append(formatField("QSLMSG", qslParts.joined(separator: " ")))
        }
    }

    private func defaultMySigFlavor(
        parkReference: String?,
        wwffReference: String?,
        sotaReference: String?
    ) -> LogSubmissionFlavor? {
        if parkReference != nil {
            return .pota
        }
        if wwffReference != nil {
            return .wwff
        }
        if sotaReference != nil {
            return nil
        } // SOTA flavor not yet supported
        return nil
    }

    private func mySigInfo(
        for flavor: LogSubmissionFlavor,
        references: SessionReferences
    ) -> String? {
        switch flavor {
        case .pota: references.parkReference?.nonEmpty
        case .wwff: references.wwffReference?.nonEmpty
        case .sota: references.sotaReference?.nonEmpty
        }
    }

    func buildSessionHeader(
        snapshots: [QSOExportSnapshot],
        activatorCallsign: String,
        references: SessionReferences
    ) -> [String] {
        var lines: [String] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = snapshots.first.map { dateFormatter.string(from: $0.timestamp) } ?? "unknown"

        var headerComment = "ADIF export for \(activatorCallsign):"
        var hasProgram = false
        if let parkReference = references.parkReference {
            headerComment += " POTA \(parkReference)"
            if let parkName = references.parkName {
                headerComment += " (\(parkName))"
            }
            hasProgram = true
        }
        if let wwffReference = references.wwffReference {
            if hasProgram {
                headerComment += " +"
            }
            headerComment += " WWFF \(wwffReference)"
            hasProgram = true
        }
        if let sotaReference = references.sotaReference {
            if hasProgram {
                headerComment += " +"
            }
            headerComment += " SOTA \(sotaReference)"
            if let summitName = references.summitName {
                headerComment += " (\(summitName))"
            }
            hasProgram = true
        }
        if !hasProgram {
            headerComment += " session"
        }
        headerComment += " on \(dateStr)"
        lines.append(headerComment)
        lines.append("")

        lines.append(formatField("ADIF_VER", "3.1.7"))
        lines.append(formatField("PROGRAMID", "CarrierWave"))
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        lines.append(formatField("PROGRAMVERSION", version))

        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyyMMdd HHmmss"
        timestampFormatter.timeZone = TimeZone(identifier: "UTC")
        lines.append(formatField("CREATED_TIMESTAMP", timestampFormatter.string(from: Date())))

        return lines
    }

    func buildSessionQSORecord(
        _ snapshot: QSOExportSnapshot,
        references: SessionReferences,
        mySigOverride: LogSubmissionFlavor? = nil
    ) -> String {
        var fields: [String] = []
        appendCoreFields(to: &fields, snapshot: snapshot)
        appendStationFields(to: &fields, snapshot: snapshot)
        appendContactFields(to: &fields, snapshot: snapshot)
        appendSessionRefFields(
            to: &fields,
            snapshot: snapshot,
            references: references,
            mySigOverride: mySigOverride
        )
        appendConfirmationFields(to: &fields, snapshot: snapshot)
        appendContestFields(to: &fields, snapshot: snapshot)

        if let notes = snapshot.notes, !notes.isEmpty {
            let cleaned = ParkReference.stripFromFreeText(notes) ?? notes
            fields.append(formatField("COMMENT", cleaned))
        }

        return fields.joined() + "<EOR>"
    }
}
