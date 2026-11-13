import AppKit
import SwiftUI

// MARK: - SQLTextEditor

/// SwiftUI wrapper around `NSTextView` that adds two code-editor
/// behaviors `TextEditor` doesn't offer:
///
/// 1. **Tab inserts four spaces.** A bare Tab keypress (without
///    modifiers) replaces the current selection with `"    "` instead
///    of jumping focus.
/// 2. **Backspace unindents an aligned indent.** When the caret sits
///    at a column that is a multiple of 4 *and* the four characters
///    immediately before it are all spaces *and* the line up to that
///    column is whitespace-only (i.e. the user is in the indent area,
///    not deleting trailing whitespace mid-statement), Backspace
///    removes all four spaces in one keystroke. Otherwise it falls
///    through to the normal one-character delete.
///
/// `Shift+Tab` (insertBacktab) is also handled — it removes up to four
/// leading spaces from the current line so users can dedent without
/// reaching for the mouse.
struct SQLTextEditor: NSViewRepresentable {
    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        // MARK: Lifecycle

        init(_ parent: SQLTextEditor) {
            self.parent = parent
        }

        // MARK: Internal

        weak var textView: NSTextView?

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else {
                return
            }
            parent.text = view.string
        }

        /// AppKit funnels Tab / Shift-Tab / Backspace through
        /// `doCommand(by:)` *before* applying the default action, so
        /// we can intercept here without subclassing NSTextView.
        /// Returning `true` tells AppKit we handled the command.
        func textView(
            _ textView: NSTextView,
            doCommandBy selector: Selector
        ) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                insertSpaces(in: textView)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                unindentLine(in: textView)
                return true
            case #selector(NSResponder.deleteBackward(_:)):
                return tryUnindentBackspace(in: textView)
            default:
                return false
            }
        }

        // MARK: Private

        private static let indentWidth = 4

        private let parent: SQLTextEditor

        /// Tab → insert `"    "` at the caret (or replace selection).
        /// `insertText:replacementRange:` integrates with NSTextView's
        /// undo stack so ⌘Z reverses the indent in one step.
        private func insertSpaces(in textView: NSTextView) {
            let spaces = String(repeating: " ", count: Self.indentWidth)
            textView.insertText(spaces, replacementRange: textView.selectedRange())
        }

        /// Shift-Tab → drop up to four leading spaces from the line
        /// containing the caret. No-op if the line has no leading
        /// whitespace.
        private func unindentLine(in textView: NSTextView) {
            let nsString = textView.string as NSString
            let selection = textView.selectedRange()
            let lineRange = nsString.lineRange(for: NSRange(location: selection.location, length: 0))
            let lineString = nsString.substring(with: lineRange)
            var leadingSpaces = 0
            for char in lineString {
                if char == " ", leadingSpaces < Self.indentWidth {
                    leadingSpaces += 1
                } else {
                    break
                }
            }
            guard leadingSpaces > 0 else {
                return
            }
            let removeRange = NSRange(location: lineRange.location, length: leadingSpaces)
            if textView.shouldChangeText(in: removeRange, replacementString: "") {
                textView.replaceCharacters(in: removeRange, with: "")
                textView.didChangeText()
                // Keep caret in roughly the same column position.
                let newLocation = max(lineRange.location, selection.location - leadingSpaces)
                textView.setSelectedRange(NSRange(location: newLocation, length: 0))
            }
        }

        /// Returns `true` if we consumed a backspace by removing four
        /// aligned indent spaces. Returns `false` to let AppKit
        /// perform the normal one-character delete.
        private func tryUnindentBackspace(in textView: NSTextView) -> Bool {
            let selection = textView.selectedRange()
            // Only fire on collapsed selection — range deletion goes
            // through the standard path.
            guard selection.length == 0, selection.location > 0 else {
                return false
            }
            let nsString = textView.string as NSString
            let lineStart = nsString.lineRange(
                for: NSRange(location: selection.location, length: 0)
            ).location
            let column = selection.location - lineStart
            // Caret must sit on an indent boundary.
            guard column >= Self.indentWidth, column.isMultiple(of: Self.indentWidth) else {
                return false
            }
            // Everything from the line start up to the caret must be
            // whitespace — we don't want to nuke real content that
            // happens to end on a column boundary.
            let prefix = nsString.substring(
                with: NSRange(location: lineStart, length: column)
            )
            guard prefix.allSatisfy({ $0 == " " }) else {
                return false
            }
            let removeRange = NSRange(
                location: selection.location - Self.indentWidth,
                length: Self.indentWidth
            )
            if textView.shouldChangeText(in: removeRange, replacementString: "") {
                textView.replaceCharacters(in: removeRange, with: "")
                textView.didChangeText()
                return true
            }
            return false
        }
    }

    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else {
            return scroll
        }
        textView.delegate = context.coordinator
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.string = text
        // Hand the existing NSTextView's behaviors over to our subclass.
        // We can't substitute the class easily after creation, so we
        // route key events through the coordinator's swizzle-free
        // delegate-style hook by overriding `doCommand(by:)`.
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else {
            return
        }
        if textView.string != text {
            // Preserve selection across external state updates so
            // SwiftUI re-renders don't yank the caret to the start.
            let selection = textView.selectedRange()
            textView.string = text
            let clamped = NSRange(
                location: min(selection.location, textView.string.count),
                length: 0
            )
            textView.setSelectedRange(clamped)
        }
        context.coordinator.textView = textView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}
