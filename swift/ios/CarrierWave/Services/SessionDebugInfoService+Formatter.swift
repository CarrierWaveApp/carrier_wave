import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - SessionDebugInfoService.Formatter

extension SessionDebugInfoService {
    enum Formatter {
        // MARK: Internal

        static func filenameStem(session: LoggingSession) -> String {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd"
            let date = formatter.string(from: session.startedAt)
            let callsign = (session.stationCallsign ?? session.myCallsign)
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: " ", with: "_")
            let suffix = String(session.id.uuidString.prefix(8))
            let park = session.parkReference.map { "_\($0.replacingOccurrences(of: "/", with: "-"))" } ?? ""
            return "debug_\(callsign)\(park)_\(date)_\(suffix)"
        }

        // swiftlint:disable:next function_parameter_count
        static func format(
            session: LoggingSession,
            qsos: [QSO],
            qsoServiceRows: [QSOServiceRow],
            spots: [SessionSpot],
            metadata: ActivationMetadata?,
            logs: [SyncDebugLog.LogEntry],
            deviceInfo: DeviceInfoSnapshot,
            callsignInfo: (current: String?, previous: [String])
        ) -> String {
            var out: [String] = []
            out.append(headerBlock(session: session, deviceInfo: deviceInfo, callsignInfo: callsignInfo))
            out.append(sessionBlock(session: session))
            if let metadata {
                out.append(metadataBlock(metadata))
            }
            out.append(qsosBlock(qsos: qsos, serviceRows: qsoServiceRows))
            out.append(spotsBlock(spots))
            out.append(syncLogBlock(logs))
            return out.joined(separator: "\n\n")
        }

        // MARK: Private

        // MARK: - Section builders

        private static func headerBlock(
            session: LoggingSession,
            deviceInfo: DeviceInfoSnapshot,
            callsignInfo: (current: String?, previous: [String])
        ) -> String {
            let generatedAt = iso8601(Date())
            let previous = callsignInfo.previous.isEmpty
                ? "(none)"
                : callsignInfo.previous.joined(separator: ", ")
            return """
            SESSION DEBUG REPORT
            ====================
            Generated: \(generatedAt)
            Session ID: \(session.id.uuidString)

            DEVICE / APP
            ------------
            App Version: \(deviceInfo.appVersion) (\(deviceInfo.buildNumber))
            iOS: \(deviceInfo.iosVersion)
            Device: \(deviceInfo.deviceModel)
            Locale: \(deviceInfo.locale)
            Time Zone: \(deviceInfo.timeZone)

            OPERATOR
            --------
            Current Callsign: \(callsignInfo.current ?? "(none)")
            Previous Callsigns: \(previous)
            """
        }

        private static func sessionBlock(session: LoggingSession) -> String {
            var lines: [String] = []
            lines.append("SESSION")
            lines.append("-------")
            lines.append("Title: \(session.customTitle ?? "(none)")")
            lines.append("Status: \(session.status.rawValue)")
            lines.append("Started: \(iso8601(session.startedAt))")
            lines.append("Ended: \(session.endedAt.map { iso8601($0) } ?? "(still active)")")
            lines.append("Duration: \(formatDuration(session.duration))")
            lines.append("Activation Type: \(session.activationType.rawValue)")
            lines.append("Programs: \(session.programs.sorted().joined(separator: ", "))")
            lines.append("My Callsign: \(session.myCallsign)")
            lines.append("Station Callsign: \(session.stationCallsign ?? "(same as operator)")")
            lines.append("Operators: \(session.operatorCallsignsRawValue)")
            lines.append("Mode: \(session.mode)")
            lines.append("Frequency: \(session.frequency.map { String(format: "%.3f MHz", $0) } ?? "(none)")")
            lines.append("Grid: \(session.myGrid ?? "(none)")")
            lines.append("Power: \(session.power.map { "\($0) W" } ?? "(none)")")
            lines.append("Park Reference: \(session.parkReference ?? "(none)")")
            lines.append("SOTA Reference: \(session.sotaReference ?? "(none)")")
            lines.append("WWFF Reference: \(session.wwffReference ?? "(none)")")
            lines.append("Mission Reference: \(session.missionReference ?? "(none)")")
            lines.append("QSO Count (stored): \(session.qsoCount)")
            lines.append(
                "Is Rove: \(session.isRove) (stops: \(session.roveStopCount),"
                    + " unique parks: \(session.uniqueParkCount))"
            )
            lines.append("Is Contest: \(session.isContest)")
            if session.isContest {
                lines.append("Contest ID: \(session.contestId ?? "?")")
                lines.append("Contest Category: \(session.contestCategory ?? "?")")
                lines.append("Contest Overlay: \(session.contestOverlayCategory ?? "?")")
                lines.append("Contest Power: \(session.contestPower ?? "?")")
                lines.append("Contest Bands: \(session.contestBands ?? "?")")
                lines.append("Contest Operator: \(session.contestOperator ?? "?")")
            }
            lines.append("Rig: \(session.myRig ?? "(none)")")
            lines.append("Antenna: \(session.myAntenna ?? "(none)")")
            lines.append("Key: \(session.myKey ?? "(none)")")
            lines.append("Mic: \(session.myMic ?? "(none)")")
            lines.append("Extra Equipment: \(session.extraEquipment ?? "(none)")")
            lines.append("Attendees: \(session.attendees ?? "(none)")")
            lines.append("Photo Count: \(session.photoFilenames.count)")
            lines.append("Cloud Dirty Flag: \(session.cloudDirtyFlag)")
            if let notes = session.notes, !notes.isEmpty {
                lines.append("")
                lines.append("Notes:")
                lines.append(notes)
            }
            return lines.joined(separator: "\n")
        }

        private static func metadataBlock(_ metadata: ActivationMetadata) -> String {
            var lines: [String] = []
            lines.append("ACTIVATION METADATA")
            lines.append("-------------------")
            lines.append("Park: \(metadata.parkReference)")
            lines.append("Date: \(iso8601(metadata.date))")
            lines.append("Title: \(metadata.title ?? "(none)")")
            lines.append("Watts: \(metadata.watts.map(String.init) ?? "(none)")")
            lines.append("Weather: \(metadata.weather ?? "(none)")")
            lines.append("Solar: \(metadata.solarConditions ?? "(none)")")
            lines.append("Average WPM: \(metadata.averageWPM.map(String.init) ?? "(none)")")
            lines.append("Cloud Dirty Flag: \(metadata.cloudDirtyFlag)")
            return lines.joined(separator: "\n")
        }

        private static func qsosBlock(qsos: [QSO], serviceRows: [QSOServiceRow]) -> String {
            var lines: [String] = []
            lines.append("QSOs (\(qsos.count))")
            lines.append(String(repeating: "-", count: 40))
            let rowsByID = Dictionary(uniqueKeysWithValues: serviceRows.map { ($0.id, $0) })
            let sorted = qsos.sorted(by: { $0.timestamp < $1.timestamp })
            for (index, qso) in sorted.enumerated() {
                lines.append("")
                lines.append(contentsOf: qsoLines(qso: qso, index: index, row: rowsByID[qso.id]))
            }
            return lines.joined(separator: "\n")
        }

        private static func qsoLines(qso: QSO, index: Int, row: QSOServiceRow?) -> [String] {
            var lines: [String] = []
            let short = qso.id.uuidString.prefix(8)
            lines.append("#\(index + 1) [\(short)] \(qso.callsign) @ \(iso8601(qso.timestamp))")
            let freq = qso.frequency.map { String(format: "%.3f", $0) } ?? "-"
            lines.append("  band=\(qso.band) mode=\(qso.mode) freq=\(freq)")
            lines.append("  rst rx=\(qso.rstReceived ?? "-") tx=\(qso.rstSent ?? "-")")
            let station = qso.stationCallsign ?? "-"
            lines.append("  my=\(qso.myCallsign) station=\(station) grid=\(qso.myGrid ?? "-")")
            let dxcc = qso.dxcc.map(String.init) ?? "-"
            lines.append(
                "  their grid=\(qso.theirGrid ?? "-") dxcc=\(dxcc)"
                    + " state=\(qso.state ?? "-") country=\(qso.country ?? "-")"
            )
            lines.append(
                "  park=\(qso.parkReference ?? "-") their park=\(qso.theirParkReference ?? "-")"
                    + " sota=\(qso.sotaRef ?? "-") wwff=\(qso.wwffRef ?? "-")"
            )
            let modified = qso.modifiedAt.map { iso8601($0) } ?? "-"
            lines.append(
                "  source=\(qso.importSource.rawValue)"
                    + " importedAt=\(iso8601(qso.importedAt)) modifiedAt=\(modified)"
            )
            lines.append(
                "  hidden=\(qso.isHidden) activityLog=\(qso.isActivityLogQSO)"
                    + " cloudDirty=\(qso.cloudDirtyFlag)"
            )
            let lotwDate = qso.lotwConfirmedDate.map { iso8601($0) } ?? "-"
            lines.append(
                "  qrzConfirmed=\(qso.qrzConfirmed)"
                    + " lotwConfirmed=\(qso.lotwConfirmed) lotwConfDate=\(lotwDate)"
            )
            if let row, !row.presence.isEmpty {
                lines.append("  presence:")
                lines.append(contentsOf: row.presence.map { presenceLine($0) })
            }
            if let notes = qso.notes, !notes.isEmpty {
                lines.append("  notes: \(notes)")
            }
            if let raw = qso.rawADIF, !raw.isEmpty {
                lines.append("  rawADIF: \(raw)")
            }
            return lines
        }

        private static func presenceLine(_ presence: ServicePresenceRow) -> String {
            let lastConfirmed = presence.lastConfirmedAt.map { iso8601($0) } ?? "-"
            return "    \(presence.service.rawValue):"
                + " present=\(presence.isPresent) needsUpload=\(presence.needsUpload)"
                + " rejected=\(presence.uploadRejected) submitted=\(presence.isSubmitted)"
                + " lastConfirmed=\(lastConfirmed)"
        }

        private static func spotsBlock(_ spots: [SessionSpot]) -> String {
            var lines: [String] = []
            lines.append("SESSION SPOTS (\(spots.count))")
            lines.append(String(repeating: "-", count: 40))
            if spots.isEmpty {
                lines.append("(none)")
                return lines.joined(separator: "\n")
            }
            for spot in spots.prefix(200) {
                let snr = spot.snr.map { String($0) } ?? "-"
                let wpm = spot.wpm.map { String($0) } ?? "-"
                lines.append(
                    "\(iso8601(spot.timestamp)) \(spot.callsign) \(String(format: "%.1f", spot.frequencyKHz)) kHz " +
                        "mode=\(spot.mode) src=\(spot.source) snr=\(snr) wpm=\(wpm) " +
                        "spotter=\(spot.spotter ?? "-") park=\(spot.parkRef ?? "-") region=\(spot.region)"
                )
            }
            if spots.count > 200 {
                lines.append("... (truncated, \(spots.count - 200) more)")
            }
            return lines.joined(separator: "\n")
        }

        private static func syncLogBlock(_ entries: [SyncDebugLog.LogEntry]) -> String {
            var lines: [String] = []
            lines.append("SYNC DEBUG LOGS (\(entries.count))")
            lines.append(String(repeating: "-", count: 40))
            if entries.isEmpty {
                lines.append("(no log entries available)")
                return lines.joined(separator: "\n")
            }
            let sorted = entries.sorted { $0.timestamp < $1.timestamp }
            for entry in sorted {
                let service = entry.service?.displayName ?? "General"
                lines.append("[\(iso8601(entry.timestamp))] [\(entry.level.rawValue)] [\(service)] \(entry.message)")
            }
            return lines.joined(separator: "\n")
        }

        // MARK: - Helpers

        private static func iso8601(_ date: Date) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: date)
        }

        private static func formatDuration(_ seconds: TimeInterval) -> String {
            let total = Int(seconds)
            let hours = total / 3_600
            let minutes = (total % 3_600) / 60
            let secs = total % 60
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
    }
}
