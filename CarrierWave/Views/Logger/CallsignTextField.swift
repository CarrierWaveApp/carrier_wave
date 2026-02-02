// Callsign Text Field
//
// A UITextField wrapper that properly handles cursor position
// when entering mixed letters and numbers with auto-capitalization.

import SwiftUI
import UIKit

// MARK: - CallsignTextField

/// A text field optimized for callsign entry that maintains cursor position
/// when typing numbers (works around iOS bug with textInputAutocapitalization)
struct CallsignTextField: UIViewRepresentable {
    // MARK: Lifecycle

    init(
        _ placeholder: String,
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        onSubmit: @escaping () -> Void
    ) {
        self.placeholder = placeholder
        _text = text
        self.isFocused = isFocused
        self.onSubmit = onSubmit
    }

    // MARK: Internal

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextFieldDelegate {
        // MARK: Lifecycle

        init(_ parent: CallsignTextField) {
            self.parent = parent
        }

        // MARK: Internal

        var parent: CallsignTextField

        /// Track whether we're currently processing a user edit
        /// to avoid re-entrant updates from SwiftUI
        var isUpdatingFromUIKit = false

        @objc
        func textFieldDidChange(_ textField: UITextField) {
            isUpdatingFromUIKit = true
            parent.text = textField.text ?? ""
            isUpdatingFromUIKit = false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused.wrappedValue = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused.wrappedValue = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return true
        }
    }

    @Binding var text: String

    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.font = UIFont.monospacedSystemFont(ofSize: 20, weight: .regular)
        textField.autocapitalizationType = .allCharacters
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.returnKeyType = .done
        textField.clearButtonMode = .never
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textFieldDidChange(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        // Skip updates that originated from user typing to preserve cursor position
        // Only update for programmatic changes (e.g., clearing field after logging)
        if !context.coordinator.isUpdatingFromUIKit, uiView.text != text {
            // Save cursor position relative to end of text
            let cursorOffsetFromEnd: Int
            if let selectedRange = uiView.selectedTextRange {
                let cursorPosition = uiView.offset(
                    from: uiView.endOfDocument, to: selectedRange.end
                )
                cursorOffsetFromEnd = cursorPosition
            } else {
                cursorOffsetFromEnd = 0
            }

            uiView.text = text

            // Restore cursor position relative to end of text
            // This handles cases where text length changed
            if let newPosition = uiView.position(
                from: uiView.endOfDocument,
                offset: cursorOffsetFromEnd
            ) {
                uiView.selectedTextRange = uiView.textRange(from: newPosition, to: newPosition)
            }
        }

        // Handle focus state changes from SwiftUI
        // Skip during active editing to prevent focus loss
        if !context.coordinator.isUpdatingFromUIKit {
            DispatchQueue.main.async {
                if isFocused.wrappedValue, !uiView.isFirstResponder {
                    uiView.becomeFirstResponder()
                } else if !isFocused.wrappedValue, uiView.isFirstResponder {
                    uiView.resignFirstResponder()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}
