// Callsign Change Guide
//
// When the operator's callsign changes (manual edit, QRZ detection, or a new
// primary QRZ key), the app updates its own stores automatically — but every
// connected service still references the old callsign in some way. This
// service records the pending change and builds a per-service checklist so
// the user is walked through every location that needs attention.

import CarrierWaveData
import UIKit

// MARK: - PendingCallsignChange

/// A callsign change that has been applied locally but whose connected-service
/// checklist hasn't been completed or dismissed yet.
struct PendingCallsignChange: Codable, Equatable {
    let oldCallsign: String
    let newCallsign: String
    let startedAt: Date
    var completedStepIDs: Set<String>
}

// MARK: - CallsignChangeDestination

/// In-app settings screen a checklist step links to.
enum CallsignChangeDestination: String {
    case qrzLogbook
    case qrzLookup
    case lotw
    case eqsl
    case clublog
    case lofi
}

// MARK: - CallsignChangeStep

/// One connected-service item in the callsign change checklist.
struct CallsignChangeStep: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let destination: CallsignChangeDestination?
    let externalURL: URL?
    /// True when the app verified this step itself (e.g. the stored callsign
    /// already matches the new one). Auto-checked steps can't be un-checked.
    let autoChecked: Bool
}

// MARK: - CallsignChangeGuide

/// Records pending callsign changes and builds the connected-service
/// checklist. Steps only appear for services the user has configured, and
/// auto-verify where the app can read the stored value itself.
@MainActor
final class CallsignChangeGuide {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = CallsignChangeGuide()

    var pending: PendingCallsignChange? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else {
                return nil
            }
            return try? JSONDecoder().decode(PendingCallsignChange.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
                return
            }
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Record a freshly-applied callsign change so the checklist surfaces in
    /// Settings until the user works through it. Re-recording the same change
    /// preserves already-completed steps.
    func begin(oldCallsign: String, newCallsign: String) {
        let old = oldCallsign.uppercased()
        let new = newCallsign.uppercased()
        guard !old.isEmpty, !new.isEmpty, old != new else {
            return
        }
        if let existing = pending, existing.oldCallsign == old, existing.newCallsign == new {
            return
        }
        pending = PendingCallsignChange(
            oldCallsign: old,
            newCallsign: new,
            startedAt: Date(),
            completedStepIDs: []
        )
    }

    /// Whether a step counts as done (auto-verified or manually checked off).
    func isDone(_ step: CallsignChangeStep) -> Bool {
        step.autoChecked || pending?.completedStepIDs.contains(step.id) == true
    }

    /// Toggle a manual step's checked-off state.
    func toggleDone(_ step: CallsignChangeStep) {
        guard !step.autoChecked, var change = pending else {
            return
        }
        if change.completedStepIDs.contains(step.id) {
            change.completedStepIDs.remove(step.id)
        } else {
            change.completedStepIDs.insert(step.id)
        }
        pending = change
    }

    /// Clear the pending change (checklist finished or dismissed).
    func dismiss() {
        pending = nil
    }

    /// Build the checklist for the pending change. Only configured services
    /// produce steps; auto-checks re-evaluate on every call so returning to
    /// the checklist after fixing a service marks it done.
    func steps() -> [CallsignChangeStep] {
        guard let change = pending else {
            return []
        }
        return [
            qrzLogbookStep(change),
            qrzLookupStep(change),
            lotwStep(),
            eqslStep(change),
            clublogStep(change),
            potaStep(change),
            lofiStep(change),
            hamAlertStep(change),
        ].compactMap { $0 }
    }

    // MARK: Private

    private static let defaultsKey = "pendingCallsignChange"

    private func keychainString(_ key: String) -> String? {
        try? KeychainHelper.shared.readString(for: key)
    }

    private func qrzLogbookStep(_ change: PendingCallsignChange) -> CallsignChangeStep? {
        let client = QRZClient()
        let mappings = client.getCallsignMappings()
        guard !mappings.isEmpty else {
            return nil
        }
        let satisfied = client.getPrimaryMapping()?.callsign == change.newCallsign
        return CallsignChangeStep(
            id: "qrz-logbook",
            title: "QRZ Logbook Sync",
            detail: "Add a logbook API key for \(change.newCallsign) and set it as "
                + "primary. QSOs logged under \(change.newCallsign) won't sync until "
                + "its key is connected.",
            systemImage: "book.closed",
            destination: .qrzLogbook,
            externalURL: nil,
            autoChecked: satisfied
        )
    }

    private func qrzLookupStep(_ change: PendingCallsignChange) -> CallsignChangeStep? {
        guard let username = keychainString(KeychainHelper.Keys.qrzCallbookUsername),
              !username.isEmpty
        else {
            return nil
        }
        return CallsignChangeStep(
            id: "qrz-lookup",
            title: "QRZ Callsign Lookup",
            detail: "QRZ renames your account when your callsign changes, so the "
                + "saved login (\(username.uppercased())) may stop working. Sign in "
                + "again with \(change.newCallsign) if lookups show a failure banner.",
            systemImage: "person.text.rectangle",
            destination: .qrzLookup,
            externalURL: nil,
            autoChecked: username.uppercased() == change.newCallsign
        )
    }

    private func lotwStep() -> CallsignChangeStep? {
        guard keychainString(KeychainHelper.Keys.lotwUsername) != nil else {
            return nil
        }
        return CallsignChangeStep(
            id: "lotw",
            title: "Logbook of the World",
            detail: "Request a callsign certificate for your new callsign in TQSL "
                + "(your LoTW username stays the same). QSOs under the new callsign "
                + "won't upload until the certificate is issued.",
            systemImage: "checkmark.seal",
            destination: .lotw,
            externalURL: URL(string: "https://lotw.arrl.org/lotw-help/certificates/"),
            autoChecked: false
        )
    }

    private func eqslStep(_ change: PendingCallsignChange) -> CallsignChangeStep? {
        guard let username = keychainString(KeychainHelper.Keys.eqslUsername),
              !username.isEmpty
        else {
            return nil
        }
        return CallsignChangeStep(
            id: "eqsl",
            title: "eQSL",
            detail: "eQSL accounts are per-callsign. Register \(change.newCallsign) "
                + "at eQSL.cc, then sign in here with the new account.",
            systemImage: "envelope",
            destination: .eqsl,
            externalURL: URL(string: "https://www.eqsl.cc"),
            autoChecked: username.uppercased() == change.newCallsign
        )
    }

    private func clublogStep(_ change: PendingCallsignChange) -> CallsignChangeStep? {
        guard keychainString(KeychainHelper.Keys.clublogApiKey) != nil
            || keychainString(KeychainHelper.Keys.clublogCallsign) != nil
        else {
            return nil
        }
        let stored = keychainString(KeychainHelper.Keys.clublogCallsign)?.uppercased()
        return CallsignChangeStep(
            id: "clublog",
            title: "Club Log",
            detail: "Add \(change.newCallsign) to your Club Log account at "
                + "clublog.org, then update the callsign here.",
            systemImage: "chart.bar",
            destination: .clublog,
            externalURL: URL(string: "https://clublog.org"),
            autoChecked: stored == change.newCallsign
        )
    }

    private func potaStep(_ change: PendingCallsignChange) -> CallsignChangeStep? {
        guard keychainString(KeychainHelper.Keys.potaUsername) != nil
            || keychainString(KeychainHelper.Keys.potaIdToken) != nil
        else {
            return nil
        }
        return CallsignChangeStep(
            id: "pota",
            title: "Parks on the Air",
            detail: "Update the callsign on your POTA account profile at pota.app "
                + "so new activations credit \(change.newCallsign).",
            systemImage: "tree",
            destination: nil,
            externalURL: URL(string: "https://pota.app/user/stats"),
            autoChecked: false
        )
    }

    private func lofiStep(_ change: PendingCallsignChange) -> CallsignChangeStep? {
        guard keychainString(KeychainHelper.Keys.lofiCallsign) != nil
            || keychainString(KeychainHelper.Keys.lofiAuthToken) != nil
        else {
            return nil
        }
        let stored = keychainString(KeychainHelper.Keys.lofiCallsign)?.uppercased()
        return CallsignChangeStep(
            id: "lofi",
            title: "Ham2K LoFi",
            detail: "Update the callsign on your LoFi account so synced operations "
                + "use \(change.newCallsign).",
            systemImage: "antenna.radiowaves.left.and.right",
            destination: .lofi,
            externalURL: nil,
            autoChecked: stored == change.newCallsign
        )
    }

    private func hamAlertStep(_ change: PendingCallsignChange) -> CallsignChangeStep? {
        guard keychainString(KeychainHelper.Keys.hamAlertUsername) != nil else {
            return nil
        }
        return CallsignChangeStep(
            id: "hamalert",
            title: "HamAlert",
            detail: "Update any HamAlert triggers that reference "
                + "\(change.oldCallsign) so spots for \(change.newCallsign) still "
                + "reach you.",
            systemImage: "bell",
            destination: nil,
            externalURL: URL(string: "https://hamalert.org/triggers"),
            autoChecked: false
        )
    }
}
