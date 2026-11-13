import Foundation

// MARK: - VimMotion

/// Represents a navigation motion in vim normal mode.
/// Motions describe *where* to move — they are the "noun" in the vim grammar.
enum VimMotion: Equatable {
    case down(Int) // j with optional count prefix
    case up(Int) // k with optional count prefix
    case bandDown // J — move to next band
    case bandUp // K — move to previous band
    case top // gg — jump to first row
    case bottom // G — jump to last row
    case nextResult // n — next search result
    case prevResult // N — previous search result
    case cycleFocus // Tab — cycle keyboard focus between panes
    case focusPane(FocusedPane) // g + panel name — focus a specific pane
    case focusPaneByIndex(Int) // g1–g9 — focus Nth pane in layout order
}
