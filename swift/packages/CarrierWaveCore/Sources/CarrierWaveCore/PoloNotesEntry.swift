// Polo Notes Entry
//
// Shared data type for parsed Polo notes entries.
// Used by both Carrier Wave (iOS) and CW Sweep (macOS).

import CarrierWaveCwFfi
import Foundation

// MARK: - PoloNotesEntry

/// A parsed entry from a Polo notes list file
public struct PoloNotesEntry: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        callsign: String,
        emoji: String? = nil,
        name: String? = nil,
        note: String? = nil
    ) {
        self.callsign = callsign.uppercased()
        self.emoji = emoji
        self.name = name
        self.note = note
    }

    /// Build a Swift entry from the Rust-parsed FFI record.
    init(ffi: FfiPoloNotesEntry) {
        self.init(
            callsign: ffi.callsign,
            emoji: ffi.emoji,
            name: ffi.name,
            note: ffi.note
        )
    }

    // MARK: Public

    /// The callsign (always uppercase)
    public let callsign: String

    /// Leading emoji from the note text (e.g., "🌳")
    public let emoji: String?

    /// Operator name parsed from the note text
    public let name: String?

    /// Note text (everything after name, may contain markdown links)
    public let note: String?

    /// Parse a Polo notes entry from callsign and note text.
    /// Delegates the emoji / name / note split to the shared Rust core.
    public static func fromNoteText(callsign: String, noteText: String) -> PoloNotesEntry {
        PoloNotesEntry(ffi: poloNoteFromText(callsign: callsign, noteText: noteText))
    }
}
