import CarrierWaveData
import SwiftData
import SwiftUI

extension QSOEditSheet {
    /// Load read-only fields that come from the parent `LoggingSession`
    /// rather than the QSO itself. Today this is just the operator's own
    /// summit reference (`MY_SOTA_REF` at ADIF-export time), used to make
    /// the S2S vs. self-summit distinction visible in the edit sheet.
    func loadParentSessionContext() {
        guard let sessionId = qso.loggingSessionId else {
            return
        }
        var desc = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.id == sessionId }
        )
        desc.fetchLimit = 1
        guard let session = try? modelContext.fetch(desc).first else {
            return
        }
        mySotaReference = session.sotaReference ?? ""
    }

    func save() {
        let trimmedCallsign = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let trimmedMyCallsign = myCallsign.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmedCallsign.isEmpty, !trimmedMyCallsign.isEmpty else {
            return
        }

        let callsignChanged = trimmedCallsign != originalCallsign

        applyContactFields(trimmedCallsign: trimmedCallsign)
        applyMyStationFields(trimmedMyCallsign: trimmedMyCallsign)
        applySignalFields()
        applyTheirLocationFields()
        applyReferenceFields()
        applyContestFields()
        applySatelliteFields()
        applyNotesField()

        qso.cloudDirtyFlag = true
        qso.modifiedAt = Date()

        do {
            try QSOWriteSink.commitUpsert(qso, in: modelContext)
        } catch {
            modelContext.rollback()
            CwStoreWriteLog.shared.record("Edit QSO failed: \(error.localizedDescription)")
            return
        }

        if callsignChanged {
            refreshCallsignLookup(trimmedCallsign: trimmedCallsign)
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        NotificationCenter.default.post(name: .didLogQSO, object: nil)
        onSave()
        dismiss()
    }

    private func applyContactFields(trimmedCallsign: String) {
        // Preserve the very-first contact callsign so download-merge can match
        // against the pre-edit value. See CAR-245.
        if qso.originalCallsign == nil, qso.callsign != trimmedCallsign,
           !qso.callsign.trimmingCharacters(in: .whitespaces).isEmpty
        {
            qso.originalCallsign = qso.callsign
        }
        qso.callsign = trimmedCallsign
        qso.band = band
        qso.mode = mode
        qso.frequency = FrequencyFormatter.parse(frequencyText)
        qso.timestamp = timestamp
        qso.name = name.trimmingCharacters(in: .whitespaces).nonEmpty
    }

    private func applyMyStationFields(trimmedMyCallsign: String) {
        qso.myCallsign = trimmedMyCallsign
        qso.stationCallsign = stationCallsign.trimmingCharacters(in: .whitespaces)
            .uppercased().nonEmpty
        qso.myRig = myRig.trimmingCharacters(in: .whitespaces).nonEmpty
        qso.stationProfileName = stationProfileName.trimmingCharacters(in: .whitespaces).nonEmpty
        qso.myGrid = myGrid.trimmingCharacters(in: .whitespaces).uppercased().nonEmpty
        qso.power = Int(powerText.trimmingCharacters(in: .whitespaces))
    }

    private func applySignalFields() {
        qso.rstSent = rstSent.trimmingCharacters(in: .whitespaces).nonEmpty
        qso.rstReceived = rstReceived.trimmingCharacters(in: .whitespaces).nonEmpty
    }

    private func applyTheirLocationFields() {
        qso.theirGrid = theirGrid.trimmingCharacters(in: .whitespaces).uppercased().nonEmpty
        qso.qth = qth.trimmingCharacters(in: .whitespaces).nonEmpty
        qso.state = state.trimmingCharacters(in: .whitespaces).uppercased().nonEmpty
        qso.country = country.trimmingCharacters(in: .whitespaces).nonEmpty
        qso.dxcc = Int(dxccText.trimmingCharacters(in: .whitespaces))
        qso.theirLicenseClass = licenseClass.trimmingCharacters(in: .whitespaces).nonEmpty
    }

    private func applyReferenceFields() {
        qso.parkReference = parkReference.trimmingCharacters(in: .whitespaces)
            .uppercased().nonEmpty
        qso.theirParkReference = theirParkReference.trimmingCharacters(in: .whitespaces)
            .uppercased().nonEmpty
        qso.sotaRef = sotaRef.trimmingCharacters(in: .whitespaces).uppercased().nonEmpty
        qso.wwffRef = wwffRef.trimmingCharacters(in: .whitespaces).uppercased().nonEmpty
        qso.aoaCode = aoaCode.trimmingCharacters(in: .whitespaces).uppercased().nonEmpty
    }

    private func applyContestFields() {
        qso.contestName = contestName.trimmingCharacters(in: .whitespaces).nonEmpty
        qso.contestSerialSent = Int(contestSerialSent.trimmingCharacters(in: .whitespaces))
        qso.contestSerialReceived = Int(contestSerialReceived.trimmingCharacters(in: .whitespaces))
        qso.contestExchangeSent = contestExchangeSent.trimmingCharacters(in: .whitespaces).nonEmpty
        qso.contestExchangeReceived = contestExchangeReceived.trimmingCharacters(in: .whitespaces)
            .nonEmpty
    }

    private func applySatelliteFields() {
        qso.satName = satName.trimmingCharacters(in: .whitespaces).uppercased().nonEmpty
        qso.propMode = propMode.trimmingCharacters(in: .whitespaces).uppercased().nonEmpty
    }

    private func applyNotesField() {
        let trimmed = notes.trimmingCharacters(in: .whitespaces).nonEmpty
        qso.notes = trimmed
        // User edited the notes in the QSO edit sheet — tag as user-authored. CAR-243.
        if trimmed != nil {
            qso.notesUserAuthored = true
        }
    }

    private func refreshCallsignLookup(trimmedCallsign: String) {
        let context = modelContext
        Task {
            let service = CallsignLookupService(modelContext: context)
            guard let info = await service.lookup(trimmedCallsign) else {
                return
            }
            qso.name = info.name
            qso.theirGrid = info.grid
            qso.state = info.state
            qso.country = info.country
            qso.qth = info.qth
            qso.theirLicenseClass = info.licenseClass
            qso.callsignChangeNote = info.callsignChangeNote
            try? context.save()
        }
    }
}
