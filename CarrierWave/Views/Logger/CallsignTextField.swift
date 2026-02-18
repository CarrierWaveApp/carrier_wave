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
        fontSize: CGFloat = 20,
        showCommands: Bool = true,
        onSubmit: @escaping () -> Void,
        onCommand: @escaping (LoggerCommand) -> Void = { _ in }
    ) {
        self.placeholder = placeholder
        _text = text
        self.isFocused = isFocused
        self.fontSize = fontSize
        self.showCommands = showCommands
        self.onSubmit = onSubmit
        self.onCommand = onCommand
    }

    // MARK: Internal

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextFieldDelegate {
        // MARK: Lifecycle

        init(_ parent: CallsignTextField) {
            self.parent = parent
        }

        deinit {
            // Remove all observers for this object
            NotificationCenter.default.removeObserver(self)
        }

        // MARK: Internal

        var parent: CallsignTextField

        /// Track whether we're currently processing a user edit
        /// to avoid re-entrant updates from SwiftUI.
        /// Uses a counter instead of a bool to handle rapid typing where
        /// multiple edits can overlap before the async reset fires.
        var uiKitEditCounter = 0
        var lastProcessedEditCounter = 0

        /// Reference to the text field for explicit dismiss
        weak var textField: UITextField?

        /// Whether a UIKit-originated edit is still being processed by SwiftUI
        var isUpdatingFromUIKit: Bool {
            uiKitEditCounter != lastProcessedEditCounter
        }

        @objc
        func textFieldDidChange(_ textField: UITextField) {
            uiKitEditCounter += 1
            let editId = uiKitEditCounter
            parent.text = textField.text ?? ""
            // Delay resetting until after SwiftUI has processed the update
            DispatchQueue.main.async { [weak self] in
                self?.lastProcessedEditCounter = editId
            }
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

        // MARK: - Number Row Actions

        @objc
        func numberButtonTapped(_ sender: UIButton) {
            guard let char = sender.titleLabel?.text,
                  let textField
            else {
                return
            }

            // Insert at cursor position instead of appending to end
            if let selectedRange = textField.selectedTextRange {
                textField.replace(selectedRange, withText: char)
            } else {
                // Fallback: append if no cursor position available
                parent.text.append(char)
            }
        }

        @objc
        func commandButtonTapped(_ sender: UIButton) {
            guard let commandKey = sender.accessibilityIdentifier,
                  let item = CommandRowItem(rawValue: commandKey)
            else {
                return
            }
            parent.onCommand(item.command)
        }

        @objc
        func dismissKeyboard(_ sender: UIButton) {
            // Explicitly resign first responder, then update SwiftUI state
            textField?.resignFirstResponder()
            parent.isFocused.wrappedValue = false
        }

        func startObservingConfigurationChanges() {
            keyboardConfigObserver = NotificationCenter.default.addObserver(
                forName: .keyboardRowConfigurationChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.rebuildAccessoryView()
                }
            }
            commandConfigObserver = NotificationCenter.default.addObserver(
                forName: .commandRowConfigurationChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.rebuildAccessoryView()
                }
            }
        }

        func stopObservingConfigurationChanges() {
            if let observer = keyboardConfigObserver {
                NotificationCenter.default.removeObserver(observer)
                keyboardConfigObserver = nil
            }
            if let observer = commandConfigObserver {
                NotificationCenter.default.removeObserver(observer)
                commandConfigObserver = nil
            }
        }

        // MARK: Private

        /// Observer for keyboard row configuration changes
        private var keyboardConfigObserver: NSObjectProtocol?
        /// Observer for command row configuration changes
        private var commandConfigObserver: NSObjectProtocol?

        private func rebuildAccessoryView() {
            guard let textField else {
                return
            }
            textField.inputAccessoryView = parent.createInputAccessoryView(coordinator: self)
            // Force layout update if keyboard is visible
            textField.reloadInputViews()
        }
    }

    @Binding var text: String

    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    let fontSize: CGFloat
    let showCommands: Bool
    let onSubmit: () -> Void
    let onCommand: (LoggerCommand) -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textField.autocapitalizationType = .allCharacters
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.returnKeyType = .done
        textField.clearButtonMode = .never
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textFieldDidChange(_:)),
            for: .editingChanged
        )

        // Store reference for explicit dismiss and start observing config changes
        context.coordinator.textField = textField
        context.coordinator.startObservingConfigurationChanges()

        // Add input accessory view with number row
        textField.inputAccessoryView = createInputAccessoryView(coordinator: context.coordinator)

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
        // Only becomeFirstResponder if SwiftUI wants focus and we don't have it
        // Only resignFirstResponder if SwiftUI doesn't want focus AND we're not actively editing
        // The isEditing check prevents focus loss during typing
        if isFocused.wrappedValue, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused.wrappedValue, uiView.isFirstResponder, !uiView.isEditing {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Input Accessory View

    func createInputAccessoryView(coordinator: Coordinator) -> UIView {
        KeyboardAccessoryBuilder.createAccessoryView(
            numberButtonAction: #selector(Coordinator.numberButtonTapped(_:)),
            commandButtonAction: #selector(Coordinator.commandButtonTapped(_:)),
            dismissAction: #selector(Coordinator.dismissKeyboard(_:)),
            target: coordinator,
            includeCommands: showCommands
        )
    }
}
